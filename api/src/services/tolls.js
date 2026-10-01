/**
 * Freedom Supercars - Toll Transactions Service (Guide 10.5)
 *
 * Implements:
 * - Batch import of toll authority files with deduplication on (authority, tag, timestamp)
 * - Matching of unmatched tolls against actual trip windows (actual times, never reservation times)
 * - Service trip tolls marked as club cost (matched, no member charge)
 * - Member trip tolls aggregated into a single member charge at billing time
 * - Unmatched toll working queue (fleet diagnostic & anomaly detection)
 * - Toll disputes and exclusions management
 */

import { HttpError } from '../middleware/errorHandler.js';

/**
 * Import batch of toll transactions with deduplication (Guide 10.5 Steps 1 & 2)
 */
export async function importTolls(client, {
  batchId = null,
  source = 'import',
  tolls = [],
  actorUserId = null
}) {
  if (!Array.isArray(tolls) || tolls.length === 0) {
    throw new HttpError(400, 'tolls array is required and must not be empty');
  }

  const effectiveBatchId = batchId || `TOLL-BATCH-${Date.now()}`;
  let importedCount = 0;
  let duplicateCount = 0;
  const importedRecords = [];

  for (const item of tolls) {
    const tollTag = (item.toll_tag || item.tag || '').trim();
    const transactionAt = item.transaction_at || item.timestamp;
    const authorityCode = (item.toll_authority_code || item.authority || 'OTHER').trim();
    const amount = Number(item.amount);
    const location = item.location || item.gantry || null;
    const notes = item.notes || null;

    if (!tollTag) throw new HttpError(400, 'toll_tag is required for every toll');
    if (!transactionAt) throw new HttpError(400, 'transaction_at is required for every toll');
    if (isNaN(amount) || amount <= 0) throw new HttpError(400, `Valid positive amount required for toll on tag ${tollTag}`);

    // Resolve vehicle_id from toll_tag, license_plate, or stock_number
    let vehicleId = null;
    const vehQuery = await client.query(
      `SELECT vehicle_id FROM (
         SELECT vehicle_id FROM fs.vehicle_registration_warranty WHERE LOWER(toll_tag) = LOWER($1) OR LOWER(license_plate) = LOWER($1)
         UNION
         SELECT id as vehicle_id FROM fs.vehicles WHERE LOWER(license_plate) = LOWER($1) OR LOWER(stock_number) = LOWER($1)
         UNION
         SELECT vehicle_id FROM fs.vehicle WHERE LOWER(license_plate) = LOWER($1) OR LOWER(stock_number) = LOWER($1)
       ) sub LIMIT 1`,
      [tollTag]
    );

    if (vehQuery.rowCount > 0) {
      vehicleId = vehQuery.rows[0].vehicle_id;
    }

    // Insert with ON CONFLICT DO NOTHING for deduplication (Guide 10.5 Developer Note 2)
    const insertRes = await client.query(
      `INSERT INTO fs.vehicle_toll_transaction (
         vehicle_id,
         toll_tag,
         transaction_at,
         toll_authority_code,
         location,
         amount,
         import_source,
         import_batch_id,
         match_status,
         notes,
         created_by_user_id
       ) VALUES (
         $1, $2, $3, $4, $5, $6, $7, $8, 
         'Unmatched'::fs.vehicle_toll_transaction_match_status_enum,
         $9, $10
       )
       ON CONFLICT (toll_authority_code, toll_tag, transaction_at) DO NOTHING
       RETURNING vehicle_toll_transaction_id, vehicle_id, toll_tag, amount, match_status`,
      [
        vehicleId,
        tollTag,
        new Date(transactionAt),
        authorityCode,
        location,
        amount,
        source,
        effectiveBatchId,
        notes,
        actorUserId
      ]
    );

    if (insertRes.rowCount > 0) {
      importedCount++;
      importedRecords.push(insertRes.rows[0]);
    } else {
      duplicateCount++;
    }
  }

  return {
    batch_id: effectiveBatchId,
    total_submitted: tolls.length,
    imported_count: importedCount,
    duplicate_count: duplicateCount,
    records: importedRecords
  };
}

/**
 * Match Unmatched Tolls against Actual Trip Windows (Guide 10.5 Step 2)
 *
 * Match condition:
 * Vehicle ID matches AND start_time_actual <= transaction_at <= (end_time_actual OR now())
 */
export async function matchTolls(client, { actorUserId = null } = {}) {
  // 1. Fetch all unmatched tolls that have a resolved vehicle_id
  const unmatchedRes = await client.query(
    `SELECT vehicle_toll_transaction_id, vehicle_id, transaction_at, amount
       FROM fs.vehicle_toll_transaction
      WHERE match_status = 'Unmatched'::fs.vehicle_toll_transaction_match_status_enum
        AND vehicle_id IS NOT NULL`
  );

  let matchedCount = 0;
  const matchedList = [];

  for (const toll of unmatchedRes.rows) {
    // Find matching trip by vehicle and actual trip window
    const tripMatch = await client.query(
      `SELECT t.vehicle_trip_id, t.trip_type_code, tm.member_id
         FROM fs.vehicle_trip t
         LEFT JOIN fs.vehicle_trip_member tm ON tm.vehicle_trip_id = t.vehicle_trip_id
        WHERE t.vehicle_id = $1
          AND t.start_time_actual <= $2
          AND ($2 <= COALESCE(t.end_time_actual, now()))
        ORDER BY t.start_time_actual DESC
        LIMIT 1`,
      [toll.vehicle_id, toll.transaction_at]
    );

    if (tripMatch.rowCount > 0) {
      const trip = tripMatch.rows[0];
      await client.query(
        `UPDATE fs.vehicle_toll_transaction
            SET vehicle_trip_id = $1,
                match_status = 'Matched'::fs.vehicle_toll_transaction_match_status_enum,
                updated_at = now(),
                updated_by_user_id = $2
          WHERE vehicle_toll_transaction_id = $3`,
        [trip.vehicle_trip_id, actorUserId, toll.vehicle_toll_transaction_id]
      );

      matchedCount++;
      matchedList.push({
        toll_id: toll.vehicle_toll_transaction_id,
        trip_id: trip.vehicle_trip_id,
        trip_type: trip.trip_type_code,
        member_id: trip.member_id || null,
        amount: Number(toll.amount)
      });
    }
  }

  // Get current remaining count
  const remainingRes = await client.query(
    `SELECT count(*) FROM fs.vehicle_toll_transaction
      WHERE match_status = 'Unmatched'::fs.vehicle_toll_transaction_match_status_enum`
  );
  const remainingCount = parseInt(remainingRes.rows[0].count, 10);

  return {
    matched_count: matchedCount,
    remaining_unmatched_count: remainingCount,
    matched_tolls: matchedList
  };
}

/**
 * Bill All Matched Tolls for a Trip in Aggregate (Guide 10.5 Step 3)
 *
 * Captures individually, bills in aggregate:
 * 1. Sums all Matched tolls for the trip where member_charge_id IS NULL
 * 2. Excludes Disputed and Excluded tolls
 * 3. Creates ONE member charge for the sum
 * 4. Updates all those tolls with member_charge_id pointing at that charge
 */
export async function billTripTolls(client, {
  tripId,
  actorUserId = null
}) {
  if (!tripId) throw new HttpError(400, 'tripId is required');

  // 1. Fetch trip and member details
  const tripRes = await client.query(
    `SELECT t.vehicle_trip_id, t.vehicle_reservation_id, t.vehicle_id, t.trip_type_code,
            tm.member_id, r.confirmation_code
       FROM fs.vehicle_trip t
       LEFT JOIN fs.vehicle_trip_member tm ON tm.vehicle_trip_id = t.vehicle_trip_id
       LEFT JOIN fs.reservations r ON r.id = t.vehicle_reservation_id
      WHERE t.vehicle_trip_id = $1`,
    [tripId]
  );

  if (tripRes.rowCount === 0) {
    throw new HttpError(404, `Trip ${tripId} not found`);
  }

  const trip = tripRes.rows[0];

  // If service or internal trip: tolls are club cost, matched but no member charge (Guide 10.5 Step 2.4)
  if (trip.trip_type_code === 'service' || trip.trip_type_code === 'internal' || !trip.member_id) {
    return {
      billed: false,
      is_club_cost: true,
      trip_type: trip.trip_type_code,
      message: 'Tolls on service or internal trips are absorbed as club costs per Guide 10.5; no member charge posted.'
    };
  }

  // 2. Fetch all matched, unbilled tolls for this trip
  const tollsRes = await client.query(
    `SELECT vehicle_toll_transaction_id, amount, toll_authority_code, location, transaction_at
       FROM fs.vehicle_toll_transaction
      WHERE vehicle_trip_id = $1
        AND match_status = 'Matched'::fs.vehicle_toll_transaction_match_status_enum
        AND member_charge_id IS NULL
      ORDER BY transaction_at ASC`,
    [tripId]
  );

  if (tollsRes.rowCount === 0) {
    return {
      billed: false,
      message: `No unbilled matched tolls found for trip ${tripId}`
    };
  }

  const tolls = tollsRes.rows;
  const totalAmount = tolls.reduce((sum, t) => sum + Number(t.amount), 0);
  const roundedTotal = Math.round(totalAmount * 100) / 100;
  const tollIds = tolls.map((t) => t.vehicle_toll_transaction_id);

  // 3. Post a single aggregated member charge (Guide 10.5 Step 3.2)
  const description = `Toll charges for Trip ${trip.confirmation_code || tripId.slice(0, 8)} (${tolls.length} ${tolls.length === 1 ? 'toll' : 'tolls'})`;

  let memberChargeId;
  const chargeRes = await client.query(
    `INSERT INTO fs.member_charge (
       member_id,
       vehicle_trip_id,
       reservation_id,
       vehicle_id,
       charge_type_code,
       charge_style,
       charge_amount,
       description,
       payment_status,
       created_by_user_id
     ) VALUES (
       (SELECT member_id FROM fs.member WHERE member_id = $1),
       $2,
       (SELECT vehicle_reservation_id FROM fs.vehicle_reservation WHERE vehicle_reservation_id = $3),
       (SELECT vehicle_id FROM fs.vehicle WHERE vehicle_id = $4),
       'TOLL',
       'DEBIT'::fs.member_charge_charge_style_enum,
       $5,
       $6,
       'PENDING'::fs.member_charge_payment_status_enum,
       $7
     ) RETURNING member_charge_id, charge_amount, description, payment_status, created_at`,
    [
      trip.member_id,
      tripId,
      trip.vehicle_reservation_id,
      trip.vehicle_id,
      roundedTotal,
      description,
      actorUserId
    ]
  );

  memberChargeId = chargeRes.rows[0].member_charge_id;

  // 4. Update every toll in this group to point at the one charge (Guide 10.5 Step 3.4)
  await client.query(
    `UPDATE fs.vehicle_toll_transaction
        SET member_charge_id = $1,
            updated_at = now(),
            updated_by_user_id = $2
      WHERE vehicle_toll_transaction_id = ANY($3::uuid[])`,
    [memberChargeId, actorUserId, tollIds]
  );

  return {
    billed: true,
    member_charge_id: memberChargeId,
    charge: chargeRes.rows[0],
    toll_count: tolls.length,
    total_amount: roundedTotal,
    toll_ids: tollIds
  };
}

/**
 * Get Unmatched Toll Queue (Guide 10.5 Step 5: Working the Unmatched)
 */
export async function getUnmatchedTolls(client, { limit = 50, offset = 0 } = {}) {
  const res = await client.query(
    `SELECT t.vehicle_toll_transaction_id as id,
            t.toll_tag,
            t.transaction_at,
            t.toll_authority_code,
            t.location,
            t.amount,
            t.import_source,
            t.import_batch_id,
            t.match_status,
            t.notes,
            v.id as vehicle_id,
            v.license_plate,
            vm.model_name as vehicle_model
       FROM fs.vehicle_toll_transaction t
       LEFT JOIN fs.vehicles v ON v.id = t.vehicle_id
       LEFT JOIN fs.vehicle_models vm ON vm.id = v.model_id
      WHERE t.match_status = 'Unmatched'::fs.vehicle_toll_transaction_match_status_enum
      ORDER BY t.transaction_at ASC
      LIMIT $1 OFFSET $2`,
    [Math.min(100, Math.max(1, limit)), Math.max(0, offset)]
  );

  const countRes = await client.query(
    `SELECT count(*) FROM fs.vehicle_toll_transaction
      WHERE match_status = 'Unmatched'::fs.vehicle_toll_transaction_match_status_enum`
  );

  return {
    unmatched_tolls: res.rows,
    total_unmatched: parseInt(countRes.rows[0].count, 10)
  };
}

/**
 * Mark a Toll as Disputed (Guide 10.5 Step 4)
 */
export async function disputeToll(client, { tollId, notes = null, actorUserId = null }) {
  const res = await client.query(
    `UPDATE fs.vehicle_toll_transaction
        SET match_status = 'Disputed'::fs.vehicle_toll_transaction_match_status_enum,
            notes = CASE WHEN $1::text IS NOT NULL THEN COALESCE(notes || E'\n', '') || $1::text ELSE notes END,
            updated_at = now(),
            updated_by_user_id = $2
      WHERE vehicle_toll_transaction_id = $3
      RETURNING *`,
    [notes, actorUserId, tollId]
  );
  if (res.rowCount === 0) throw new HttpError(404, `Toll ${tollId} not found`);
  return res.rows[0];
}

/**
 * Mark a Toll as Excluded (Guide 10.5 Step 2.5)
 */
export async function excludeToll(client, { tollId, notes = null, actorUserId = null }) {
  const res = await client.query(
    `UPDATE fs.vehicle_toll_transaction
        SET match_status = 'Excluded'::fs.vehicle_toll_transaction_match_status_enum,
            notes = CASE WHEN $1::text IS NOT NULL THEN COALESCE(notes || E'\n', '') || $1::text ELSE notes END,
            updated_at = now(),
            updated_by_user_id = $2
      WHERE vehicle_toll_transaction_id = $3
      RETURNING *`,
    [notes, actorUserId, tollId]
  );
  if (res.rowCount === 0) throw new HttpError(404, `Toll ${tollId} not found`);
  return res.rows[0];
}
