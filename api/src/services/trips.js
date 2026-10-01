/**
 * Freedom Supercars - Trip Service (Guide 10.1 & 10.2)
 *
 * Implements:
 * - 10.1: Trip Creation, Showroom-to-Showroom Custody, Odometer Logging
 * - 10.2: Trip Settlement, Actual Duration, Overage Mileage, and Point Charges
 * - Addendum A: Decision D-01 (staff miles on member tab), C-21 (referential ordering), E-10 (actual trip timestamps)
 * - Condition and signature capture at checkout and checkin
 * - Fuel replenishment fee calculation with plan markup and automated member charges
 */

import { query } from '../db.js';
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
  condition = 'excellent',
  conditionSignature = null,
  preExistingDamage = null,
  photosUrl = null,
  notes = null,
  handledByStaff = null,
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

  // Must be in confirmed or tentative state (allow pickup to complete checkout)
  if (reservation.status !== 'confirmed' && reservation.status !== 'tentative' && reservation.status !== 'picked_up') {
    throw new HttpError(409, `Cannot checkout reservation in status '${reservation.status}'; must be 'confirmed' or 'tentative'`);
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

  // 5. Create core VEHICLE_TRIP (10.1-C01, 10.1-C06) with condition signatures
  let trip;
  try {
    const tripInsert = await client.query(
      `INSERT INTO fs.vehicle_trip (
         vehicle_reservation_id,
         trip_type_code,
         vehicle_id,
         start_time_actual,
         odometer_start_id,
         fuel_start_percent,
         miles_driven,
         pay_vop_use,
         condition_signature_url,
         condition_snapshot
       ) VALUES (
         $1, 'member', $2, $3, $4, $5, 0, 'Earning', $6, $7
       ) RETURNING *`,
      [
        reservationId,
        reservation.vehicle_id,
        departureTime,
        odometerStartId,
        Math.round(Number(fuelStartPercent)),
        conditionSignature || null,
        condition || 'excellent'
      ]
    );
    trip = tripInsert.rows[0];
  } catch (_err) {
    // Fallback if condition columns do not exist yet on vehicle_trip
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
    trip = tripInsert.rows[0];
  }

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

  // 7. Insert into fs.reservation_pickups_returns for Stage 1 / inspection log compatibility
  try {
    await client.query(
      `INSERT INTO fs.reservation_pickups_returns (
         reservation_id, event_type, mileage, fuel_level_pct, condition,
         pre_existing_damage, handled_by_staff, member_signature_url, photos_url, notes
       ) VALUES ($1, 'pickup', $2, $3, $4, $5, $6, $7, $8, $9)`,
      [
        reservationId,
        Math.round(Number(startingOdometer)),
        Math.round(Number(fuelStartPercent)),
        condition || 'excellent',
        preExistingDamage || null,
        handledByStaff || null,
        conditionSignature || null,
        photosUrl || null,
        notes || null
      ]
    );
  } catch (_e) {
    // Tolerant if table is missing or constrained
  }

  // 8. Update reservation status to 'checked_out' (10.1-C04)
  await client.query(
    `UPDATE fs.reservations
        SET status = 'checked_out',
            updated_at = now()
      WHERE id = $1`,
    [reservationId]
  );

  // 9. Update vehicle status to 'in_use' (10.1-C04)
  await client.query(
    `UPDATE fs.vehicles
        SET status = 'in_use',
            current_mileage = $1,
            updated_at = now()
      WHERE id = $2`,
    [Math.round(Number(startingOdometer)), reservation.vehicle_id]
  );

  return {
    trip_id: trip.vehicle_trip_id,
    reservation_id: reservationId,
    vehicle_id: reservation.vehicle_id,
    start_time_actual: trip.start_time_actual,
    starting_odometer: Number(startingOdometer),
    fuel_start_percent: trip.fuel_start_percent,
    start_type: companion.start_type,
    condition: condition || 'excellent',
    condition_signature: conditionSignature || null,
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
  condition = 'good',
  conditionSignature = null,
  newDamage = null,
  photosUrl = null,
  notes = null,
  handledByStaff = null,
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
  const adjustmentMiles = trip.miles_member_adjustment || 0;
  const milesMember = Math.max(0, milesDriven - adjustmentMiles);

  // 4. Compute overage miles (Guide 10.2-C08)
  const includedMiles = trip.included_miles_snapshot || 0;
  const overageMiles = Math.max(0, milesMember - includedMiles);

  // 5. Compute extra mileage points (Guide 7.6 & 10.2-C11)
  const extraMileRate = Number(trip.extra_mile_point_value_snapshot) || 0;
  const extraMileagePoints = Math.round(overageMiles * extraMileRate);
  const totalPoints = (trip.base_points || 0) + extraMileagePoints;

  // 6. Fuel replenishment fee computation (Guide 10.2 Rule 14)
  const fuelStartPercent = trip.fuel_start_percent != null ? Number(trip.fuel_start_percent) : 100;
  const fuelEndPercentVal = Math.round(Number(fuelEndPercent));
  const fuelDeficitPercent = Math.max(0, fuelStartPercent - fuelEndPercentVal);

  let tankCapacity = 18.0; // standard supercar fuel tank size in gallons
  try {
    const descRes = await query(
      `SELECT fuel_tank_size FROM fs.vehicle_description WHERE vehicle_id = $1 LIMIT 1`,
      [trip.vehicle_id]
    );
    if (descRes.rowCount > 0 && descRes.rows[0].fuel_tank_size) {
      tankCapacity = Number(descRes.rows[0].fuel_tank_size);
    }
  } catch (_e) {}

  const gallonsReplenished = Math.round(((fuelDeficitPercent / 100) * tankCapacity) * 100) / 100;
  const pricePerGallon = 5.50; // market standard 93 Octane Premium
  const fuelBaseCost = Math.round((gallonsReplenished * pricePerGallon) * 100) / 100;

  let fuelMarkupPercent = 10.0; // default 10.00% markup
  try {
    const markupRes = await query(
      `SELECT mlp.fuel_markup_percent
         FROM fs.member m
         JOIN fs.membership_level_pricing mlp ON mlp.membership_level_id = m.membership_level_id
        WHERE m.member_id = $1 AND mlp.fuel_markup_percent IS NOT NULL
        ORDER BY mlp.effective_from DESC NULLS LAST
        LIMIT 1`,
      [trip.member_id]
    );
    if (markupRes.rowCount > 0 && markupRes.rows[0].fuel_markup_percent != null) {
      fuelMarkupPercent = Number(markupRes.rows[0].fuel_markup_percent);
    }
  } catch (_e) {}

  const fuelReplenishmentFee = fuelDeficitPercent > 0
    ? Math.round((fuelBaseCost * (1 + fuelMarkupPercent / 100)) * 100) / 100
    : 0.00;

  let fuelChargeId = null;
  if (fuelReplenishmentFee > 0) {
    try {
      await client.query('SAVEPOINT sp_fuel_charge');
      const chargeRes = await client.query(
        `INSERT INTO fs.member_charge (
           member_id, vehicle_trip_id, reservation_id, vehicle_id,
           charge_type_code, charge_style, charge_amount, description, payment_status, created_at, updated_at
         ) VALUES (
           (SELECT member_id FROM fs.member WHERE member_id = $1),
           $2,
           (SELECT vehicle_reservation_id FROM fs.vehicle_reservation WHERE vehicle_reservation_id = $3),
           (SELECT vehicle_id FROM fs.vehicle WHERE vehicle_id = $4),
           'FUEL',
           'Dollars'::fs.member_charge_charge_style_enum,
           $5,
           $6,
           'Pending'::fs.member_charge_payment_status_enum,
           now(),
           now()
         ) RETURNING member_charge_id`,
        [
          trip.member_id,
          tripId,
          trip.vehicle_reservation_id,
          trip.vehicle_id,
          fuelReplenishmentFee,
          `Fuel replenishment fee: ${fuelDeficitPercent}% consumed (${gallonsReplenished} gal @ $${pricePerGallon}/gal + ${fuelMarkupPercent}% markup)`
        ]
      );
      if (chargeRes.rowCount > 0) {
        fuelChargeId = chargeRes.rows[0].member_charge_id;
      }
      await client.query('RELEASE SAVEPOINT sp_fuel_charge');
    } catch (_e) {
      await client.query('ROLLBACK TO SAVEPOINT sp_fuel_charge').catch(() => {});
    }

    try {
      await client.query('SAVEPOINT sp_fuel_payment');
      await client.query(
        `INSERT INTO fs.payments (
           member_id, reservation_id, amount, currency, description, category, status, created_at
         ) VALUES (
           (SELECT id FROM fs.members WHERE id = $1),
           (SELECT id FROM fs.reservations WHERE id = $2),
           $3,
           'USD',
           $4,
           'fuel',
           'pending'::fs.payment_status,
           now()
         )`,
        [
          trip.member_id,
          trip.vehicle_reservation_id,
          fuelReplenishmentFee,
          `Fuel replenishment fee for reservation ${trip.confirmation_code || tripId}`
        ]
      );
      await client.query('RELEASE SAVEPOINT sp_fuel_payment');
    } catch (_e) {
      await client.query('ROLLBACK TO SAVEPOINT sp_fuel_payment').catch(() => {});
    }
  }

  // 7. Insert into fs.reservation_pickups_returns for Stage 1 / inspection log compatibility
  if (trip.vehicle_reservation_id) {
    try {
      await client.query('SAVEPOINT sp_return_inspection');
      await client.query(
        `INSERT INTO fs.reservation_pickups_returns (
           reservation_id, event_type, mileage, fuel_level_pct, condition,
           new_damage, handled_by_staff, member_signature_url, photos_url, notes
         ) VALUES (
           (SELECT id FROM fs.reservations WHERE id = $1),
           'return',
           $2,
           $3,
           ($4)::fs.vehicle_condition,
           $5,
           $6,
           $7,
           $8,
           $9
         )`,
        [
          trip.vehicle_reservation_id,
          Math.round(Number(endOdometer)),
          fuelEndPercentVal,
          condition || 'good',
          newDamage || null,
          handledByStaff || null,
          conditionSignature || null,
          photosUrl ? (Array.isArray(photosUrl) ? photosUrl : [photosUrl]) : null,
          notes || null
        ]
      );
      await client.query('RELEASE SAVEPOINT sp_return_inspection');
    } catch (_e) {
      await client.query('ROLLBACK TO SAVEPOINT sp_return_inspection').catch(() => {});
    }
  }

  // 8. Working calculation trace (Guide 10.2-C18, 10.2-C19)
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
    fuel_start_percent: fuelStartPercent,
    fuel_end_percent: fuelEndPercentVal,
    fuel_deficit_percent: fuelDeficitPercent,
    fuel_replenishment_fee: fuelReplenishmentFee,
    fuel_breakdown: {
      fuel_consumed_percent: fuelDeficitPercent,
      tank_capacity_gallons: tankCapacity,
      gallons_replenished: gallonsReplenished,
      price_per_gallon: pricePerGallon,
      fuel_base_cost: fuelBaseCost,
      fuel_markup_percent: fuelMarkupPercent,
      fuel_replenishment_fee: fuelReplenishmentFee,
      charge_id: fuelChargeId
    },
    condition: condition || 'good',
    condition_signature: conditionSignature || null
  };

  // 9. Update core VEHICLE_TRIP (10.1-C09, 10.1-C10)
  await client.query(
    `UPDATE fs.vehicle_trip
        SET end_time_actual = $1,
            odometer_end_id = $2,
            miles_driven = $3,
            fuel_end_percent = $4,
            extra_miles = $5,
            extra_miles_reason = $6,
            condition_return_signature_url = $7,
            condition_return_snapshot = $8,
            updated_at = now()
      WHERE vehicle_trip_id = $9`,
    [
      returnTime,
      odometerEndId,
      milesDriven,
      fuelEndPercentVal,
      Math.round(Number(extraMiles) || 0),
      extraMiles ? (extraMilesReason === 'Fuel' ? 'Fuel' : 'Delivery') : null,
      conditionSignature || null,
      condition || 'good',
      tripId
    ]
  );

  // 10. Update companion VEHICLE_TRIP_MEMBER (10.2-C01 to 10.2-C20)
  await client.query(
    `UPDATE fs.vehicle_trip_member
        SET end_time_actual = $1,
            return_type = ($2)::fs.vehicle_trip_member_return_type_enum,
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

  // 11. Debit ledger if overage points occurred (Guide 10.2-C14)
  if (extraMileagePoints > 0) {
    try {
      await client.query('SAVEPOINT sp_points_ledger');
      await client.query(
        `INSERT INTO fs.member_points_ledger (
           member_id, vehicle_trip_id, reservation_id, points_change, source, description, entry_type, occurred_at
         ) VALUES (
           (SELECT member_id FROM fs.member WHERE member_id = $1),
           $2,
           (SELECT vehicle_reservation_id FROM fs.vehicle_reservation WHERE vehicle_reservation_id = $3),
           $4,
           'Reservation',
           $5,
           'Charge Reservation'::fs.member_points_ledger_entry_type_enum,
           now()
         )`,
        [
          trip.member_id,
          tripId,
          trip.vehicle_reservation_id,
          -extraMileagePoints,
          `Trip settlement: ${overageMiles} overage miles for reservation ${trip.confirmation_code || tripId}`
        ]
      );
      await client.query('RELEASE SAVEPOINT sp_points_ledger');
    } catch (_e) {
      await client.query('ROLLBACK TO SAVEPOINT sp_points_ledger').catch(() => {});
    }
  }

  // 12. Update reservation to completed
  if (trip.vehicle_reservation_id) {
    await client.query(
      `UPDATE fs.reservations
          SET status = 'completed',
              updated_at = now()
        WHERE id = $1`,
      [trip.vehicle_reservation_id]
    );
  }

  // 13. Update vehicle to turnaround prep / detailing and update current mileage (10.1-C04)
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
    starting_odometer: startOdometer,
    closing_odometer: endOdometer,
    miles_driven: milesDriven,
    miles_member: milesMember,
    included_miles: includedMiles,
    overage_miles: overageMiles,
    extra_mile_rate: extraMileRate,
    extra_mileage_points: extraMileagePoints,
    base_points: trip.base_points,
    total_points: totalPoints,
    fuel_start_percent: fuelStartPercent,
    fuel_end_percent: fuelEndPercentVal,
    fuel_deficit_percent: fuelDeficitPercent,
    fuel_replenishment_fee: fuelReplenishmentFee,
    fuel_breakdown: {
      fuel_consumed_percent: fuelDeficitPercent,
      tank_capacity_gallons: tankCapacity,
      gallons_replenished: gallonsReplenished,
      price_per_gallon: pricePerGallon,
      fuel_base_cost: fuelBaseCost,
      fuel_markup_percent: fuelMarkupPercent,
      fuel_replenishment_fee: fuelReplenishmentFee,
      charge_id: fuelChargeId
    },
    condition: condition || 'good',
    condition_signature: conditionSignature || null,
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

/**
 * ============================================================================
 * GUIDE 10.3: TRIP STORIES
 * ============================================================================
 */

/**
 * Retrieve active story prompts ordered by sort_order
 */
export async function getStoryPrompts(client) {
  const res = await client.query(
    `SELECT member_trip_story_prompt_id AS prompt_id,
            prompt_code,
            prompt_text,
            help_text,
            sort_order
       FROM fs.member_trip_story_prompt
      WHERE is_active = TRUE
      ORDER BY sort_order ASC, created_at ASC`
  );
  return res.rows;
}

/**
 * Retrieve the story and answers for a specific trip
 */
export async function getTripStory(client, { tripId, memberId = null, isStaff = false }) {
  if (!tripId) throw new HttpError(400, 'tripId is required');

  const storyRes = await client.query(
    `SELECT s.*, 
            t.vehicle_id, 
            t.vehicle_reservation_id,
            t.end_time_actual
       FROM fs.member_trip_story s
       JOIN fs.vehicle_trip t ON t.vehicle_trip_id = s.vehicle_trip_id
      WHERE s.vehicle_trip_id = $1`,
    [tripId]
  );

  if (storyRes.rowCount === 0) {
    return null;
  }

  const story = storyRes.rows[0];

  // Privacy rule: private stories are accessible only by author and staff
  if (story.visibility === 'private' && !isStaff && memberId && story.member_id !== memberId) {
    throw new HttpError(403, 'This trip story is private to the author');
  }

  const answersRes = await client.query(
    `SELECT a.member_trip_story_answer_id AS answer_id,
            a.member_trip_story_prompt_id AS prompt_id,
            p.prompt_code,
            p.prompt_text,
            a.answer_text,
            a.assisted_text,
            a.assisted_at,
            a.uses_assisted,
            a.updated_at
       FROM fs.member_trip_story_answer a
       JOIN fs.member_trip_story_prompt p ON p.member_trip_story_prompt_id = a.member_trip_story_prompt_id
      WHERE a.member_trip_story_id = $1
      ORDER BY p.sort_order ASC, a.created_at ASC`,
    [story.member_trip_story_id]
  );

  return {
    ...story,
    answers: answersRes.rows,
  };
}

/**
 * Create or update a trip story header and answers (Guide 10.3)
 */
export async function upsertTripStory(client, {
  tripId,
  storyTitle = null,
  introduction = null,
  coverDocumentId = null,
  coverPhotoUrl = null,
  visibility = 'members',
  answers = [],
  memberId = null,
  actorUserId = null
}) {
  if (!tripId) throw new HttpError(400, 'tripId is required');

  // 1. Verify trip exists and is completed (Guide 10.3 Step 1)
  const tripRes = await client.query(
    `SELECT t.vehicle_trip_id, t.vehicle_reservation_id, t.end_time_actual, tm.member_id AS trip_member_id
       FROM fs.vehicle_trip t
       LEFT JOIN fs.vehicle_trip_member tm ON tm.vehicle_trip_id = t.vehicle_trip_id
      WHERE t.vehicle_trip_id = $1`,
    [tripId]
  );

  if (tripRes.rowCount === 0) throw new HttpError(404, `Trip ${tripId} not found`);
  const trip = tripRes.rows[0];

  if (!trip.end_time_actual) {
    throw new HttpError(400, 'Trip is not completed yet; stories can only be recorded for closed trips (Guide 10.3 Step 1)');
  }

  const authorMemberId = memberId || trip.trip_member_id || null;
  const now = new Date();

  // 2. Check if story already exists (Enforce 1 story per trip)
  const existingStory = await client.query(
    `SELECT member_trip_story_id FROM fs.member_trip_story WHERE vehicle_trip_id = $1`,
    [tripId]
  );

  let storyId;
  if (existingStory.rowCount > 0) {
    storyId = existingStory.rows[0].member_trip_story_id;
    await client.query(
      `UPDATE fs.member_trip_story
          SET story_title = COALESCE($1, story_title),
              introduction = COALESCE($2, introduction),
              cover_document_id = COALESCE($3, cover_document_id),
              cover_photo_url = COALESCE($4, cover_photo_url),
              visibility = COALESCE($5, visibility),
              last_saved_at = $6,
              updated_at = $6,
              updated_by_user_id = $7
        WHERE member_trip_story_id = $8`,
      [
        storyTitle,
        introduction,
        coverDocumentId,
        coverPhotoUrl,
        visibility,
        now,
        actorUserId,
        storyId
      ]
    );
  } else {
    const insertStory = await client.query(
      `INSERT INTO fs.member_trip_story (
         vehicle_trip_id,
         member_id,
         story_title,
         introduction,
         cover_document_id,
         cover_photo_url,
         visibility,
         started_at,
         last_saved_at,
         created_by_user_id,
         updated_by_user_id
       ) VALUES (
         $1, 
         (SELECT member_id FROM fs.member WHERE member_id = $2),
         $3, $4, $5, $6, $7, $8, $8, $9, $9
       ) RETURNING member_trip_story_id`,
      [
        tripId,
        authorMemberId,
        storyTitle,
        introduction,
        coverDocumentId,
        coverPhotoUrl,
        visibility || 'members',
        now,
        actorUserId
      ]
    );
    storyId = insertStory.rows[0].member_trip_story_id;
  }

  // 3. Upsert answers if provided
  if (Array.isArray(answers) && answers.length > 0) {
    for (const ans of answers) {
      const promptId = ans.prompt_id || ans.promptId;
      if (!promptId) continue;

      await client.query(
        `INSERT INTO fs.member_trip_story_answer (
           member_trip_story_id,
           member_trip_story_prompt_id,
           answer_text,
           assisted_text,
           uses_assisted,
           created_by_user_id,
           updated_by_user_id
         ) VALUES (
           $1, $2, $3, $4, $5, $6, $6
         )
         ON CONFLICT (member_trip_story_id, member_trip_story_prompt_id) DO UPDATE
         SET answer_text = COALESCE(EXCLUDED.answer_text, fs.member_trip_story_answer.answer_text),
             assisted_text = COALESCE(EXCLUDED.assisted_text, fs.member_trip_story_answer.assisted_text),
             uses_assisted = COALESCE(EXCLUDED.uses_assisted, fs.member_trip_story_answer.uses_assisted),
             updated_at = now(),
             updated_by_user_id = EXCLUDED.updated_by_user_id`,
        [
          storyId,
          promptId,
          ans.answer_text ?? ans.answerText ?? null,
          ans.assisted_text ?? ans.assistedText ?? null,
          ans.uses_assisted ?? ans.usesAssisted ?? false,
          actorUserId
        ]
      );
    }
  }

  return await getTripStory(client, { tripId, memberId: authorMemberId, isStaff: true });
}

/**
 * Autosave individual or batch story answers (Guide 10.3 Step 3)
 */
export async function saveStoryAnswers(client, {
  tripId,
  answers = [],
  memberId = null,
  actorUserId = null
}) {
  if (!tripId) throw new HttpError(400, 'tripId is required');

  // Verify trip exists and is completed
  const tripRes = await client.query(
    `SELECT t.vehicle_trip_id, t.end_time_actual, tm.member_id AS trip_member_id
       FROM fs.vehicle_trip t
       LEFT JOIN fs.vehicle_trip_member tm ON tm.vehicle_trip_id = t.vehicle_trip_id
      WHERE t.vehicle_trip_id = $1`,
    [tripId]
  );
  if (tripRes.rowCount === 0) throw new HttpError(404, `Trip ${tripId} not found`);
  const trip = tripRes.rows[0];

  if (!trip.end_time_actual) {
    throw new HttpError(400, 'Trip is not completed yet; stories can only be recorded for closed trips (Guide 10.3)');
  }

  const authorMemberId = memberId || trip.trip_member_id || null;
  const now = new Date();

  // Find or create story record
  let storyId;
  const existingStory = await client.query(
    `SELECT member_trip_story_id FROM fs.member_trip_story WHERE vehicle_trip_id = $1`,
    [tripId]
  );

  if (existingStory.rowCount > 0) {
    storyId = existingStory.rows[0].member_trip_story_id;
  } else {
    const insertStory = await client.query(
      `INSERT INTO fs.member_trip_story (
         vehicle_trip_id,
         member_id,
         visibility,
         started_at,
         last_saved_at,
         created_by_user_id,
         updated_by_user_id
       ) VALUES (
         $1, 
         (SELECT member_id FROM fs.member WHERE member_id = $2),
         'members', $3, $3, $4, $4
       ) RETURNING member_trip_story_id`,
      [tripId, authorMemberId, now, actorUserId]
    );
    storyId = insertStory.rows[0].member_trip_story_id;
  }

  const answerList = Array.isArray(answers) ? answers : [answers];
  let savedCount = 0;

  for (const ans of answerList) {
    const promptId = ans.prompt_id || ans.promptId;
    if (!promptId) continue;

    await client.query(
      `INSERT INTO fs.member_trip_story_answer (
         member_trip_story_id,
         member_trip_story_prompt_id,
         answer_text,
         assisted_text,
         uses_assisted,
         created_by_user_id,
         updated_by_user_id
       ) VALUES (
         $1, $2, $3, $4, $5, $6, $6
       )
       ON CONFLICT (member_trip_story_id, member_trip_story_prompt_id) DO UPDATE
       SET answer_text = COALESCE(EXCLUDED.answer_text, fs.member_trip_story_answer.answer_text),
           assisted_text = COALESCE(EXCLUDED.assisted_text, fs.member_trip_story_answer.assisted_text),
           uses_assisted = COALESCE(EXCLUDED.uses_assisted, fs.member_trip_story_answer.uses_assisted),
           updated_at = now(),
           updated_by_user_id = EXCLUDED.updated_by_user_id`,
      [
        storyId,
        promptId,
        ans.answer_text ?? ans.answerText ?? null,
        ans.assisted_text ?? ans.assistedText ?? null,
        ans.uses_assisted ?? ans.usesAssisted ?? false,
        actorUserId
      ]
    );
    savedCount++;
  }

  // Stamp last_saved_at on the story
  await client.query(
    `UPDATE fs.member_trip_story
        SET last_saved_at = $1,
            updated_at = $1,
            updated_by_user_id = $2
      WHERE member_trip_story_id = $3`,
    [now, actorUserId, storyId]
  );

  return {
    saved: true,
    trip_id: tripId,
    story_id: storyId,
    answers_saved: savedCount,
    last_saved_at: now
  };
}

/**
 * ============================================================================
 * GUIDE 10.4: SERVICE TRIPS
 * ============================================================================
 */

/**
 * Checkout a Service Trip (Guide 10.4 Step 1)
 */
export async function checkoutServiceTrip(client, {
  vehicleId,
  vendorId = null,
  startingOdometer,
  serviceCategoryCode = 'maintenance',
  serviceTypeCode = 'scheduled',
  serviceReasonCode = 'oil_change',
  serviceNotes = null,
  fuelStartPercent = 100,
  startTimeActual = null,
  actorUserId = null
}) {
  if (!vehicleId) throw new HttpError(400, 'vehicleId is required');
  if (startingOdometer == null || isNaN(startingOdometer) || Number(startingOdometer) < 0) {
    throw new HttpError(400, 'Valid startingOdometer is required');
  }

  const departureTime = startTimeActual ? new Date(startTimeActual) : new Date();

  // 1. Verify vehicle exists
  const vehRes = await client.query(
    `SELECT id, status, current_mileage, location_id FROM fs.vehicles WHERE id = $1`,
    [vehicleId]
  );
  if (vehRes.rowCount === 0) throw new HttpError(404, `Vehicle ${vehicleId} not found`);

  // 2. Prevent concurrent open trips for this vehicle
  const openTrip = await client.query(
    `SELECT vehicle_trip_id FROM fs.vehicle_trip WHERE vehicle_id = $1 AND end_time_actual IS NULL`,
    [vehicleId]
  );
  if (openTrip.rowCount > 0) {
    throw new HttpError(409, 'An open trip is already in progress for this vehicle');
  }

  // 3. Resolve vendor ID: if none provided, pick first active vendor
  let resolvedVendorId = vendorId;
  if (!resolvedVendorId) {
    const defaultVendor = await client.query(
      `SELECT vendor_id FROM fs.vendor WHERE is_active = TRUE ORDER BY created_at ASC LIMIT 1`
    );
    if (defaultVendor.rowCount > 0) resolvedVendorId = defaultVendor.rows[0].vendor_id;
  }

  // 4. Log starting odometer into fs.vehicle_odometer_log (Rule 10.4-R09)
  const odoRes = await client.query(
    `INSERT INTO fs.vehicle_odometer_log (
       vehicle_id, odometer_value, captured_at, effective_at, quality_flag, is_estimated
     ) VALUES (
       $1, $2, $3, $3, 'Good', FALSE
     ) RETURNING vehicle_odometer_id, odometer_value`,
    [vehicleId, Math.round(Number(startingOdometer)), departureTime]
  );
  const odometerStartId = odoRes.rows[0].vehicle_odometer_id;

  // 5. Insert core VEHICLE_TRIP with trip_type_code = 'service'
  const tripRes = await client.query(
    `INSERT INTO fs.vehicle_trip (
       trip_type_code,
       vehicle_id,
       start_time_actual,
       odometer_start_id,
       fuel_start_percent,
       miles_driven,
       pay_vop_use,
       condition_snapshot
     ) VALUES (
       'service', $1, $2, $3, $4, 0, 'Not Earning', 'service_dispatch'
     ) RETURNING *`,
    [
      vehicleId,
      departureTime,
      odometerStartId,
      Math.round(Number(fuelStartPercent))
    ]
  );
  const trip = tripRes.rows[0];

  // 6. Insert companion fs.vehicle_trip_service (Rule 10.4-R01, 10.4-R03)
  const serviceRes = await client.query(
    `INSERT INTO fs.vehicle_trip_service (
       vehicle_trip_id,
       vendor_id,
       service_category_code,
       service_type_code,
       service_reason_code,
       service_notes,
       created_by_user_id,
       updated_by_user_id
     ) VALUES (
       $1, $2, $3, $4, $5, $6, $7, $7
     ) RETURNING *`,
    [
      trip.vehicle_trip_id,
      resolvedVendorId,
      serviceCategoryCode,
      serviceTypeCode,
      serviceReasonCode,
      serviceNotes,
      actorUserId
    ]
  );

  // 7. Update vehicle status to 'maintenance'
  await client.query(
    `UPDATE fs.vehicles SET status = 'maintenance', updated_at = now() WHERE id = $1`,
    [vehicleId]
  );

  return {
    ...trip,
    service: serviceRes.rows[0],
    starting_odometer: Math.round(Number(startingOdometer))
  };
}

/**
 * Checkin a Service Trip (Guide 10.4 Step 1 & 2)
 */
export async function checkinServiceTrip(client, {
  tripId,
  closingOdometer,
  fuelEndPercent = 100,
  endTimeActual = null,
  serviceCost = null,
  warrantyClaimReference = null,
  serviceNotes = null,
  actorUserId = null
}) {
  if (!tripId) throw new HttpError(400, 'tripId is required');
  if (closingOdometer == null || isNaN(closingOdometer) || Number(closingOdometer) < 0) {
    throw new HttpError(400, 'Valid closingOdometer is required');
  }

  const returnTime = endTimeActual ? new Date(endTimeActual) : new Date();

  // 1. Fetch service trip
  const tripRes = await client.query(
    `SELECT t.*, ts.vendor_id, ts.service_cost
       FROM fs.vehicle_trip t
       JOIN fs.vehicle_trip_service ts ON ts.vehicle_trip_id = t.vehicle_trip_id
      WHERE t.vehicle_trip_id = $1`,
    [tripId]
  );

  if (tripRes.rowCount === 0) throw new HttpError(404, `Service trip ${tripId} not found`);
  const trip = tripRes.rows[0];

  if (trip.end_time_actual) {
    throw new HttpError(409, 'Service trip is already closed');
  }

  // 2. Lookup starting odometer
  let startOdo = 0;
  if (trip.odometer_start_id) {
    const odoStart = await client.query(
      `SELECT odometer_value FROM fs.vehicle_odometer_log WHERE vehicle_odometer_id = $1`,
      [trip.odometer_start_id]
    );
    if (odoStart.rowCount > 0) startOdo = Number(odoStart.rows[0].odometer_value);
  }

  const closingOdoNum = Math.round(Number(closingOdometer));
  if (closingOdoNum < startOdo) {
    throw new HttpError(400, `Closing odometer (${closingOdoNum}) cannot be less than starting odometer (${startOdo})`);
  }

  const milesDriven = closingOdoNum - startOdo;

  // 3. Log closing odometer
  const odoEnd = await client.query(
    `INSERT INTO fs.vehicle_odometer_log (
       vehicle_id, odometer_value, captured_at, effective_at, quality_flag, is_estimated
     ) VALUES (
       $1, $2, $3, $3, 'Good', FALSE
     ) RETURNING vehicle_odometer_id`,
    [trip.vehicle_id, closingOdoNum, returnTime]
  );
  const odometerEndId = odoEnd.rows[0].vehicle_odometer_id;

  // 4. Update core VEHICLE_TRIP (Miles logged, NO member points/allowance touched)
  await client.query(
    `UPDATE fs.vehicle_trip
        SET end_time_actual = $1,
            odometer_end_id = $2,
            fuel_end_percent = $3,
            miles_driven = $4,
            updated_at = now()
      WHERE vehicle_trip_id = $5`,
    [returnTime, odometerEndId, Math.round(Number(fuelEndPercent)), milesDriven, tripId]
  );

  // 5. Update VEHICLE_TRIP_SERVICE details
  await client.query(
    `UPDATE fs.vehicle_trip_service
        SET service_cost = COALESCE($1, service_cost),
            warranty_claim_reference = COALESCE($2, warranty_claim_reference),
            service_notes = CASE 
              WHEN $3::text IS NOT NULL THEN COALESCE(service_notes || E'\n', '') || $3::text 
              ELSE service_notes 
            END,
            updated_at = now(),
            updated_by_user_id = $4
      WHERE vehicle_trip_id = $5`,
    [
      serviceCost != null ? Number(serviceCost) : null,
      warrantyClaimReference || null,
      serviceNotes || null,
      actorUserId,
      tripId
    ]
  );

  // 6. Return vehicle to 'available' status with updated mileage
  await client.query(
    `UPDATE fs.vehicles
        SET status = 'available',
            current_mileage = $1,
            updated_at = now()
      WHERE id = $2`,
    [closingOdoNum, trip.vehicle_id]
  );

  // Fetch updated service trip details
  const updatedRes = await client.query(
    `SELECT t.*, ts.*
       FROM fs.vehicle_trip t
       JOIN fs.vehicle_trip_service ts ON ts.vehicle_trip_id = t.vehicle_trip_id
      WHERE t.vehicle_trip_id = $1`,
    [tripId]
  );

  return {
    ...updatedRes.rows[0],
    starting_odometer: startOdo,
    closing_odometer: closingOdoNum,
    miles_driven: milesDriven
  };
}

/**
 * Record/Update Service Trip Cost and Split/Partner Billing (Guide 10.4 Steps 2 & 3)
 */
export async function updateServiceTripCost(client, {
  tripId,
  serviceCost = null,
  warrantyClaimReference = null,
  billedMemberId = null,
  billedVehiclePartnerId = null,
  billedAmount = null,
  serviceNotes = null,
  actorUserId = null
}) {
  if (!tripId) throw new HttpError(400, 'tripId is required');

  // ENFORCE RULE 10.4-R07: Never bill both a member and a vehicle partner
  if (billedMemberId && billedVehiclePartnerId) {
    throw new HttpError(400, 'Rule 10.4-R07 Violation: A cost is never billed to both a member and a vehicle partner.');
  }

  // 1. Fetch service trip
  const tripRes = await client.query(
    `SELECT t.vehicle_id, ts.*
       FROM fs.vehicle_trip t
       JOIN fs.vehicle_trip_service ts ON ts.vehicle_trip_id = t.vehicle_trip_id
      WHERE t.vehicle_trip_id = $1`,
    [tripId]
  );

  if (tripRes.rowCount === 0) throw new HttpError(404, `Service trip ${tripId} not found`);
  const serviceTrip = tripRes.rows[0];

  const costNum = serviceCost != null ? Number(serviceCost) : serviceTrip.service_cost;
  const billedNum = billedAmount != null ? Number(billedAmount) : (billedMemberId || billedVehiclePartnerId ? costNum : null);

  // 2. Update fs.vehicle_trip_service
  await client.query(
    `UPDATE fs.vehicle_trip_service
        SET service_cost = COALESCE($1, service_cost),
            warranty_claim_reference = COALESCE($2, warranty_claim_reference),
            billed_member_id = $3,
            billed_vehicle_partner_id = $4,
            billed_amount = $5,
            service_notes = CASE 
              WHEN $6::text IS NOT NULL THEN COALESCE(service_notes || E'\n', '') || $6::text 
              ELSE service_notes 
            END,
            updated_at = now(),
            updated_by_user_id = $7
      WHERE vehicle_trip_id = $8`,
    [
      costNum,
      warrantyClaimReference || null,
      billedMemberId || null,
      billedVehiclePartnerId || null,
      billedNum,
      serviceNotes || null,
      actorUserId,
      tripId
    ]
  );

  let raisedCharge = null;

  // 3. If billed to member, raise member charge in fs.member_charge (Guide 10.4 Step 3.2)
  if (billedMemberId) {
    await client.query('SAVEPOINT sp_service_charge');
    try {
      const chargeRes = await client.query(
        `INSERT INTO fs.member_charge (
           member_id,
           vehicle_id,
           service_trip_id,
           charge_type_code,
           charge_style,
           charge_amount,
           description,
           payment_status,
           created_by_user_id
         ) VALUES (
           (SELECT member_id FROM fs.member WHERE member_id = $1),
           (SELECT vehicle_id FROM fs.vehicle WHERE vehicle_id = $2),
           $3,
           'DAMAGE',
           'DEBIT'::fs.member_charge_charge_style_enum,
           $4,
           $5,
           'PENDING'::fs.member_charge_payment_status_enum,
           $6
         ) RETURNING member_charge_id, charge_amount, description, payment_status`,
        [
          billedMemberId,
          serviceTrip.vehicle_id,
          tripId,
          billedNum,
          `Service / Repair Recharge for Trip ${tripId.slice(0, 8)}`,
          actorUserId
        ]
      );
      raisedCharge = chargeRes.rows[0];
      await client.query('RELEASE SAVEPOINT sp_service_charge');
    } catch (_err) {
      await client.query('ROLLBACK TO SAVEPOINT sp_service_charge').catch(() => {});
    }
  }

  // 4. If billed to vehicle partner, log entry in fs.vop_payout_log (Guide 10.4 Step 3.3)
  if (billedVehiclePartnerId) {
    await client.query('SAVEPOINT sp_vop_log');
    try {
      await client.query(
        `INSERT INTO fs.vop_payout_log (
           vehicle_id,
           vehicle_partner_id,
           vehicle_trip_id,
           source_table,
           source_record_id,
           entry_type,
           entry_direction,
           entry_value,
           description,
           processed_flag,
           entry_date,
           created_by_user_id
         ) VALUES (
           $1, $2, $3, 'fs.vehicle_trip_service', $3,
           'VOP Service'::fs.vop_payout_log_entry_type_enum,
           'Charge'::fs.vop_payout_log_entry_direction_enum,
           $4, $5, FALSE, CURRENT_DATE, $6
         )`,
        [
          serviceTrip.vehicle_id,
          billedVehiclePartnerId,
          tripId,
          billedNum,
          `Service/maintenance expense recharged to partner for trip ${tripId.slice(0, 8)}`,
          actorUserId
        ]
      );
      await client.query('RELEASE SAVEPOINT sp_vop_log');
    } catch (_err) {
      await client.query('ROLLBACK TO SAVEPOINT sp_vop_log').catch(() => {});
    }
  }

  const updatedService = await client.query(
    `SELECT t.*, ts.*, v.license_plate, vm.model_name
       FROM fs.vehicle_trip t
       JOIN fs.vehicle_trip_service ts ON ts.vehicle_trip_id = t.vehicle_trip_id
       LEFT JOIN fs.vehicles v ON v.id = t.vehicle_id
       LEFT JOIN fs.vehicle_models vm ON vm.id = v.model_id
      WHERE t.vehicle_trip_id = $1`,
    [tripId]
  );

  return {
    ...updatedService.rows[0],
    raised_member_charge: raisedCharge
  };
}

/**
 * List Service Trips (Guide 10.4)
 */
export async function listServiceTrips(client, {
  vehicleId = null,
  vendorId = null,
  status = null,
  limit = 50,
  offset = 0
} = {}) {
  const conditions = ["t.trip_type_code = 'service'"];
  const params = [];
  let paramIdx = 1;

  if (vehicleId) {
    conditions.push(`t.vehicle_id = $${paramIdx++}`);
    params.push(vehicleId);
  }
  if (vendorId) {
    conditions.push(`ts.vendor_id = $${paramIdx++}`);
    params.push(vendorId);
  }
  if (status === 'open') {
    conditions.push('t.end_time_actual IS NULL');
  } else if (status === 'completed') {
    conditions.push('t.end_time_actual IS NOT NULL');
  }

  const whereClause = `WHERE ${conditions.join(' AND ')}`;
  params.push(Math.min(100, Math.max(1, Number(limit))));
  const limitIdx = paramIdx++;
  params.push(Math.max(0, Number(offset)));
  const offsetIdx = paramIdx++;

  const res = await client.query(
    `SELECT t.*,
            ts.vendor_id,
            vdr.name AS vendor_name,
            ts.service_category_code,
            ts.service_type_code,
            ts.service_reason_code,
            ts.service_cost,
            ts.billed_member_id,
            ts.billed_vehicle_partner_id,
            ts.billed_amount,
            ts.warranty_claim_reference,
            ts.service_notes,
            v.license_plate,
            vm.model_name AS vehicle_model
       FROM fs.vehicle_trip t
       JOIN fs.vehicle_trip_service ts ON ts.vehicle_trip_id = t.vehicle_trip_id
       LEFT JOIN fs.vendor vdr ON vdr.vendor_id = ts.vendor_id
       LEFT JOIN fs.vehicles v ON v.id = t.vehicle_id
       LEFT JOIN fs.vehicle_models vm ON vm.id = v.model_id
      ${whereClause}
      ORDER BY t.start_time_actual DESC
      LIMIT $${limitIdx} OFFSET $${offsetIdx}`,
    params
  );

  return {
    service_trips: res.rows,
    count: res.rowCount
  };
}

