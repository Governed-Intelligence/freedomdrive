/**
 * Freedom Supercars - Trip Service (Guide 10.1 & 10.2)
 *
 * Implements:
 * - 10.1: Trip Creation, Showroom-to-Showroom Custody, Odometer Logging
 * - 10.2: Trip Settlement, Actual Duration, Overage Mileage, and Point Charges
 * - Addendum A: Decision D-01 (staff miles on member tab), C-21 (referential ordering), E-10 (actual trip timestamps)
 */

import { HttpError } from '../middleware/errorHandler.js';

/**
 * Open a Trip at Checkout (Guide 10.1-C01 through 10.1-C06)
 */
export async function checkoutTrip(client, {
  reservationId,
  startingOdometer,
  fuelStartPercent = 100,
  startTimeActual,
  startType = 'Pickup',
  actorUserId = null
}) {
  if (!reservationId) throw new HttpError(400, 'reservationId is required');
  if (startingOdometer == null || isNaN(startingOdometer) || Number(startingOdometer) < 0) {
    throw new HttpError(400, 'Valid startingOdometer is required');
  }

  const departureTime = startTimeActual ? new Date(startTimeActual) : new Date();

  // 1. Fetch reservation
  const resQuery = await client.query(
    `SELECT r.*, vm.model_name as model, m.name as manufacturer, v.tier_id, v.location_id,
            t.name as tier_name, ('TIER_' || v.tier_id) as tier_code
       FROM fs.reservations r
       JOIN fs.vehicles v ON v.id = r.vehicle_id
       JOIN fs.vehicle_models vm ON vm.id = v.model_id
       LEFT JOIN fs.manufacturers m ON m.id = vm.manufacturer_id
       LEFT JOIN fs.tiers t ON t.id = v.tier_id
      WHERE r.id = $1`,
    [reservationId]
  );

  if (resQuery.rowCount === 0) {
    throw new HttpError(404, `Reservation ${reservationId} not found`);
  }

  const reservation = resQuery.rows[0];

  // Must be in confirmed state
  if (reservation.status !== 'confirmed') {
    throw new HttpError(409, `Cannot checkout reservation in status '${reservation.status}'; must be 'confirmed'`);
  }

  // 2. Check no existing open trip
  const existingTrip = await client.query(
    `SELECT vehicle_trip_id FROM fs.vehicle_trip 
      WHERE vehicle_reservation_id = $1 AND end_time_actual IS NULL`,
    [reservationId]
  );
  if (existingTrip.rowCount > 0) {
    throw new HttpError(409, 'An open trip already exists for this reservation');
  }

  // 3. Snapshot rate card pricing (Guide 10.1-C03)
  // Fallbacks from tier / reservation quote
  let weekdayRate = reservation.weekday_points || 0;
  let weekendRate = reservation.weekend_points || 0;
  let extraMileRate = 1.250; // standard default
  let includedMiles = reservation.days_booked ? reservation.days_booked * 100 : 300;

  // Try fetching exact rate card placement if available
  try {
    if (reservation.rate_card_id) {
      const rcRate = await client.query(
        `SELECT rcr.weekday_point_value, rcr.weekend_point_value, rcr.extra_mile_point_value
           FROM fs.rate_card_rate rcr
           JOIN fs.vehicle_tier vt ON vt.vehicle_tier_id = rcr.vehicle_tier_id
          WHERE rcr.rate_card_id = $1 AND vt.vehicle_tier = ('TIER_' || $2)
          LIMIT 1`,
        [reservation.rate_card_id, reservation.tier_id]
      );
      if (rcRate.rowCount > 0) {
        if (rcRate.rows[0].weekday_point_value) weekdayRate = rcRate.rows[0].weekday_point_value;
        if (rcRate.rows[0].weekend_point_value) weekendRate = rcRate.rows[0].weekend_point_value;
        if (rcRate.rows[0].extra_mile_point_value) extraMileRate = Number(rcRate.rows[0].extra_mile_point_value);
      }
    } else {
      const rcRate = await client.query(
        `SELECT rcr.weekday_point_value, rcr.weekend_point_value, rcr.extra_mile_point_value
           FROM fs.rate_card_placement rcp
           JOIN fs.rate_card_rate rcr ON rcr.rate_card_id = rcp.rate_card_id AND rcr.vehicle_tier_id = rcp.vehicle_tier_id
          WHERE rcp.vehicle_id = $1
          LIMIT 1`,
        [reservation.vehicle_id]
      );
      if (rcRate.rowCount > 0) {
        if (rcRate.rows[0].weekday_point_value) weekdayRate = rcRate.rows[0].weekday_point_value;
        if (rcRate.rows[0].weekend_point_value) weekendRate = rcRate.rows[0].weekend_point_value;
        if (rcRate.rows[0].extra_mile_point_value) extraMileRate = Number(rcRate.rows[0].extra_mile_point_value);
      }
    }
  } catch (_e) {
    // Fallback to reservation points and default extra mile rate
  }

  // 4. Create starting odometer log (10.1-C02, 10.1-C18)
  const odoStart = await client.query(
    `INSERT INTO fs.vehicle_odometer_log (
       vehicle_id, odometer_value, captured_at, effective_at, quality_flag, is_estimated
     ) VALUES (
       $1, $2, $3, $3, 'Good', FALSE
     ) RETURNING vehicle_odometer_id, odometer_value`,
    [reservation.vehicle_id, Math.round(Number(startingOdometer)), departureTime]
  );
  const odometerStartId = odoStart.rows[0].vehicle_odometer_id;

  // 5. Create core VEHICLE_TRIP (10.1-C01, 10.1-C06)
  const tripInsert = await client.query(
    `INSERT INTO fs.vehicle_trip (
       vehicle_reservation_id,
       trip_type_code,
       vehicle_id,
       start_time_actual,
       odometer_start_id,
       fuel_start_percent,
       miles_driven,
       pay_vop_use
     ) VALUES (
       $1, 'member', $2, $3, $4, $5, 0, 'Earning'
     ) RETURNING *`,
    [
      reservationId,
      reservation.vehicle_id,
      departureTime,
      odometerStartId,
      Math.round(Number(fuelStartPercent))
    ]
  );
  const trip = tripInsert.rows[0];

  // 6. Create companion VEHICLE_TRIP_MEMBER (10.1-C03, 10.1-C05, 10.1-C06)
  const memberInsert = await client.query(
    `INSERT INTO fs.vehicle_trip_member (
       vehicle_trip_id,
       member_id,
       member_package_id,
       branch_id,
       start_time_actual,
       start_type,
       vehicle_tier_snapshot,
       weekday_point_value_snapshot,
       weekend_point_value_snapshot,
       extra_mile_point_value_snapshot,
       included_miles_snapshot,
       base_points,
       total_points,
       miles_member,
       miles_member_adjustment
     ) VALUES (
       $1, $2,
       (SELECT member_package_id FROM fs.member_package WHERE member_package_id = $3),
       (SELECT branch_id FROM fs.branch WHERE branch_id = $4),
       $5, $6, $7, $8, $9, $10, $11, $12, $12, 0, 0
     ) RETURNING *`,
    [
      trip.vehicle_trip_id,
      reservation.member_id,
      reservation.subscription_id,
      reservation.location_id,
      departureTime,
      startType === 'Delivery' ? 'Delivery' : 'Pickup',
      reservation.tier_code || ('TIER_' + reservation.tier_id) || 'TIER_1',
      weekdayRate,
      weekendRate,
      extraMileRate,
      includedMiles,
      reservation.total_points_cost || 0
    ]
  );
  const companion = memberInsert.rows[0];

  // 7. Update reservation status to 'checked_out' (10.1-C04)
  await client.query(
    `UPDATE fs.reservations
        SET status = 'checked_out',
            updated_at = now()
      WHERE id = $1`,
    [reservationId]
  );

  // 8. Update vehicle status to 'in_use' (10.1-C04)
  await client.query(
    `UPDATE fs.vehicles
        SET status = 'in_use',
            updated_at = now()
      WHERE id = $1`,
    [reservation.vehicle_id]
  );

  return {
    trip_id: trip.vehicle_trip_id,
    reservation_id: reservationId,
    vehicle_id: reservation.vehicle_id,
    start_time_actual: trip.start_time_actual,
    starting_odometer: Number(startingOdometer),
    fuel_start_percent: trip.fuel_start_percent,
    start_type: companion.start_type,
    pricing_snapshot: {
      tier: companion.vehicle_tier_snapshot,
      weekday_points: companion.weekday_point_value_snapshot,
      weekend_points: companion.weekend_point_value_snapshot,
      extra_mile_rate: companion.extra_mile_point_value_snapshot,
      included_miles: companion.included_miles_snapshot,
      base_points: companion.base_points
    }
  };
}

/**
 * Close Trip at Check-In & Compute Settlement (Guide 10.1-C09 to 10.1-C14, Guide 10.2)
 */
export async function checkinTrip(client, {
  tripId,
  closingOdometer,
  fuelEndPercent = 100,
  endTimeActual,
  extraMiles = 0,
  extraMilesReason = 'Delivery',
  returnType = 'Return',
  actorUserId = null
}) {
  if (!tripId) throw new HttpError(400, 'tripId is required');
  if (closingOdometer == null || isNaN(closingOdometer) || Number(closingOdometer) < 0) {
    throw new HttpError(400, 'Valid closingOdometer is required');
  }

  const returnTime = endTimeActual ? new Date(endTimeActual) : new Date();

  // 1. Fetch trip and companion
  const tripRes = await client.query(
    `SELECT t.*, m.*, o.odometer_value as start_odometer, r.confirmation_code
       FROM fs.vehicle_trip t
       JOIN fs.vehicle_trip_member m ON m.vehicle_trip_id = t.vehicle_trip_id
       LEFT JOIN fs.vehicle_odometer_log o ON o.vehicle_odometer_id = t.odometer_start_id
       LEFT JOIN fs.reservations r ON r.id = t.vehicle_reservation_id
      WHERE t.vehicle_trip_id = $1`,
    [tripId]
  );

  if (tripRes.rowCount === 0) {
    throw new HttpError(404, `Trip ${tripId} not found`);
  }

  const trip = tripRes.rows[0];

  if (trip.end_time_actual != null) {
    throw new HttpError(409, `Trip ${tripId} has already been checked in and settled`);
  }

  const startOdometer = trip.start_odometer || 0;
  const endOdometer = Math.round(Number(closingOdometer));

  if (endOdometer < startOdometer) {
    throw new HttpError(400, `Closing odometer (${endOdometer}) cannot be less than starting odometer (${startOdometer})`);
  }

  // 10.1-C10: miles_driven = difference between the two odometer readings
  const milesDriven = endOdometer - startOdometer;

  // 2. Insert closing odometer log (10.1-C18)
  const odoEnd = await client.query(
    `INSERT INTO fs.vehicle_odometer_log (
       vehicle_id, odometer_value, captured_at, effective_at, quality_flag, is_estimated
     ) VALUES (
       $1, $2, $3, $3, 'Good', FALSE
     ) RETURNING vehicle_odometer_id`,
    [trip.vehicle_id, endOdometer, returnTime]
  );
  const odometerEndId = odoEnd.rows[0].vehicle_odometer_id;

  // 3. Decision D-01 & 10.1-C14: extra_miles (staff legs) are on member's tab and do NOT subtract from miles_member
  // miles_member = miles_driven - miles_member_adjustment
  const adjustmentMiles = trip.miles_member_adjustment || 0;
  const milesMember = Math.max(0, milesDriven - adjustmentMiles);

  // 4. Compute overage miles (Guide 10.2-C08)
  const includedMiles = trip.included_miles_snapshot || 0;
  const overageMiles = Math.max(0, milesMember - includedMiles);

  // 5. Compute extra mileage points (Guide 10.2-C11)
  const extraMileRate = Number(trip.extra_mile_point_value_snapshot) || 0;
  const extraMileagePoints = Math.round(overageMiles * extraMileRate);
  const totalPoints = trip.base_points + extraMileagePoints;

  // 6. Working calculation (Guide 10.2-C18, 10.2-C19)
  const calculationWorking = {
    start_time_actual: trip.start_time_actual,
    end_time_actual: returnTime,
    start_odometer: startOdometer,
    closing_odometer: endOdometer,
    miles_driven: milesDriven,
    staff_extra_miles: Number(extraMiles) || 0,
    miles_member_adjustment: adjustmentMiles,
    miles_member: milesMember,
    included_miles: includedMiles,
    overage_miles: overageMiles,
    extra_mile_rate: extraMileRate,
    extra_mileage_points: extraMileagePoints,
    base_points: trip.base_points,
    total_points: totalPoints,
    fuel_start_percent: trip.fuel_start_percent,
    fuel_end_percent: Math.round(Number(fuelEndPercent))
  };

  // 7. Update core VEHICLE_TRIP (10.1-C09, 10.1-C10)
  await client.query(
    `UPDATE fs.vehicle_trip
        SET end_time_actual = $1,
            odometer_end_id = $2,
            miles_driven = $3,
            fuel_end_percent = $4,
            extra_miles = $5,
            extra_miles_reason = $6,
            updated_at = now()
      WHERE vehicle_trip_id = $7`,
    [
      returnTime,
      odometerEndId,
      milesDriven,
      Math.round(Number(fuelEndPercent)),
      Math.round(Number(extraMiles) || 0),
      extraMiles ? (extraMilesReason === 'Fuel' ? 'Fuel' : 'Delivery') : null,
      tripId
    ]
  );

  // 8. Update companion VEHICLE_TRIP_MEMBER (10.2-C01 to 10.2-C20)
  await client.query(
    `UPDATE fs.vehicle_trip_member
        SET end_time_actual = $1,
            return_type = $2,
            miles_member = $3,
            overage_miles_snapshot = $4,
            extra_mileage_points = $5,
            total_points = $6,
            calculation_version = 'v1.0',
            calculation_detail = $7,
            updated_at = now()
      WHERE vehicle_trip_id = $8`,
    [
      returnTime,
      returnType === 'Collection' ? 'Collection' : 'Return',
      milesMember,
      overageMiles,
      extraMileagePoints,
      totalPoints,
      JSON.stringify(calculationWorking),
      tripId
    ]
  );

  // 9. Debit ledger if overage points occurred (Guide 10.2-C14)
  if (extraMileagePoints > 0) {
    await client.query(
      `INSERT INTO fs.member_points_ledger (
         member_id, vehicle_trip_id, reservation_id, points_change, source, description, entry_type, occurred_at
       ) VALUES (
         $1, $2, $3, $4, 'Reservation', $5, 'Charge Reservation', now()
       )`,
      [
        trip.member_id,
        tripId,
        trip.vehicle_reservation_id,
        -extraMileagePoints,
        `Trip settlement: ${overageMiles} overage miles for reservation ${trip.confirmation_code || tripId}`
      ]
    );
  }

  // 10. Update reservation to completed
  if (trip.vehicle_reservation_id) {
    await client.query(
      `UPDATE fs.reservations
          SET status = 'completed',
              updated_at = now()
        WHERE id = $1`,
      [trip.vehicle_reservation_id]
    );
  }

  // 11. Update vehicle to turnaround prep / detailing and update current mileage (10.1-C04)
  await client.query(
    `UPDATE fs.vehicles
        SET status = 'detailing',
            current_mileage = $1,
            updated_at = now()
      WHERE id = $2`,
    [endOdometer, trip.vehicle_id]
  );

  return {
    trip_id: tripId,
    reservation_id: trip.vehicle_reservation_id,
    vehicle_id: trip.vehicle_id,
    start_time_actual: trip.start_time_actual,
    end_time_actual: returnTime,
    miles_driven: milesDriven,
    miles_member: milesMember,
    overage_miles: overageMiles,
    extra_mileage_points: extraMileagePoints,
    base_points: trip.base_points,
    total_points: totalPoints,
    fuel_end_percent: Math.round(Number(fuelEndPercent)),
    settled: true,
    calculation_version: 'v1.0',
    calculation_working: calculationWorking
  };
}

/**
 * Goodwill Member Mileage Adjustment (Guide 10.1-C15, 10.1-C21)
 */
export async function adjustTripMiles(client, {
  tripId,
  adjustmentMiles,
  adjustmentReason,
  actorUserId = null
}) {
  if (!tripId) throw new HttpError(400, 'tripId is required');
  if (adjustmentMiles == null || isNaN(adjustmentMiles)) {
    throw new HttpError(400, 'Valid adjustmentMiles is required');
  }
  if (!adjustmentReason) {
    throw new HttpError(400, 'A valid adjustmentReason is mandatory (10.1-C21)');
  }

  const tripRes = await client.query(
    `SELECT t.miles_driven, m.*
       FROM fs.vehicle_trip t
       JOIN fs.vehicle_trip_member m ON m.vehicle_trip_id = t.vehicle_trip_id
      WHERE t.vehicle_trip_id = $1`,
    [tripId]
  );

  if (tripRes.rowCount === 0) {
    throw new HttpError(404, `Trip ${tripId} not found`);
  }

  const trip = tripRes.rows[0];
  const adj = Math.round(Number(adjustmentMiles));
  const newMilesMember = Math.max(0, (trip.miles_driven || 0) - adj);

  await client.query(
    `UPDATE fs.vehicle_trip_member
        SET miles_member_adjustment = $1,
            miles_member_adjustment_reason = $2,
            miles_member = $3
      WHERE vehicle_trip_id = $4`,
    [adj, adjustmentReason, newMilesMember, tripId]
  );

  return {
    trip_id: tripId,
    miles_driven: trip.miles_driven,
    miles_member_adjustment: adj,
    miles_member_adjustment_reason: adjustmentReason,
    miles_member: newMilesMember
  };
}
