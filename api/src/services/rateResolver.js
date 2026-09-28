import { query } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';

/**
 * Classify a reservation window into weekday days and bundled weekend units.
 * Rules (Guide 7.6-R9, 9.2-R7, 9.2-C10, 9.2-C11, 9.2-C12):
 * - Friday-to-Monday trip charges 1 bundled weekend rate (never 3x daily).
 * - Thursday-to-Monday trip charges 1 weekday rate + 1 bundled weekend rate.
 * - Weekday trips charge the weekday rate per calendar day.
 */
export function classifyTripDays(pickupIso, returnIso) {
  const start = new Date(pickupIso);
  const end = new Date(returnIso);

  if (!(end > start)) {
    throw new HttpError(400, 'return_at must be strictly after pickup_at');
  }

  // Iterate calendar day by day (UTC)
  let curr = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate()));
  const endLimit = new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate()));

  // If return time is past 10:00 AM on the return date, that return day counts as active usage
  // unless it is a standard Monday morning return from a Friday weekend
  const days = [];
  while (curr <= endLimit) {
    days.push(curr.getUTCDay()); // 0: Sun, 1: Mon, 2: Tue, 3: Wed, 4: Thu, 5: Fri, 6: Sat
    curr = new Date(curr.getTime() + 86400000);
  }

  // If start is Friday and end is Monday morning
  const startDay = start.getUTCDay();
  const endDay = end.getUTCDay();
  const totalDurationDays = Math.max(1, Math.ceil((end - start) / 86400000));

  let weekdayCount = 0;
  let weekendCount = 0;

  // Handle canonical Friday-to-Monday weekend trip
  if (startDay === 5 && endDay === 1 && totalDurationDays <= 4) {
    // Exactly 1 weekend bundle
    weekendCount = 1;
    weekdayCount = 0;
  } else if (startDay === 4 && endDay === 1 && totalDurationDays <= 5) {
    // Thursday to Monday: 1 weekday + 1 weekend
    weekendCount = 1;
    weekdayCount = 1;
  } else if (startDay === 5 && endDay === 2 && totalDurationDays <= 5) {
    // Friday to Tuesday: 1 weekend + 1 weekday
    weekendCount = 1;
    weekdayCount = 1;
  } else {
    // General breakdown
    let hasWeekend = false;
    for (let i = 0; i < days.length - 1; i++) {
      const d = days[i];
      if (d === 5 || d === 6 || d === 0) {
        hasWeekend = true;
      } else {
        weekdayCount++;
      }
    }
    if (hasWeekend) {
      weekendCount = 1;
    }
    if (weekdayCount === 0 && weekendCount === 0) {
      weekdayCount = 1;
    }
  }

  return {
    totalDurationDays,
    weekdayDays: weekdayCount,
    weekendUnits: weekendCount,
  };
}

/**
 * Canonical 5-step resolver engine (Guide 7.7 Note 1 & Rule 8):
 * 1. Card: Resolve package rate card pointer effective on trip date (or active standard card)
 * 2. Placement: Resolve vehicle placement on that card (gives vehicle_tier_id)
 * 3. Tier Override: Check per-member mpc_tier_assignment
 * 4. Season: Resolve season covering trip date on that card
 * 5. Rate: Resolve rate row for (rate_card_id, vehicle_tier_id, season_id)
 * 6. Rate Override: Check per-member mpc_tier_point_rate
 * 7. Bundling: Calculate weekday_points, weekend_points, total_points
 */
export async function resolveTripPrice({
  memberId,
  subscriptionId,
  memberPackageId,
  vehicleId,
  pickupAt,
  returnAt,
  isCourtesy = false,
}) {
  const tripDate = new Date(pickupAt).toISOString().split('T')[0];

  // 1. Resolve Rate Card Pointer effective on trip date (7.6-R10, 7.6-C17)
  let targetCardId = null;
  let targetCardCode = null;

  if (memberPackageId) {
    const pkgRate = await query(
      `
      SELECT mpr.rate_card_id, rc.card_code
        FROM fs.member_package_rate mpr
        JOIN fs.rate_card rc ON rc.rate_card_id = mpr.rate_card_id
       WHERE mpr.member_package_id = $1
         AND mpr.effective_from <= $2::date
       ORDER BY mpr.effective_from DESC
       LIMIT 1
      `,
      [memberPackageId, tripDate]
    );
    if (pkgRate.rowCount > 0) {
      targetCardId = pkgRate.rows[0].rate_card_id;
      targetCardCode = pkgRate.rows[0].card_code;
    }
  }

  if (!targetCardId && memberId) {
    const memRate = await query(
      `
      SELECT mpr.rate_card_id, rc.card_code
        FROM fs.member_package mp
        JOIN fs.member_package_rate mpr ON mpr.member_package_id = mp.member_package_id
        JOIN fs.rate_card rc ON rc.rate_card_id = mpr.rate_card_id
       WHERE mp.member_id = $1
         AND mpr.effective_from <= $2::date
       ORDER BY mpr.effective_from DESC
       LIMIT 1
      `,
      [memberId, tripDate]
    );
    if (memRate.rowCount > 0) {
      targetCardId = memRate.rows[0].rate_card_id;
      targetCardCode = memRate.rows[0].card_code;
    }
  }

  if (!targetCardId) {
    // Default to active standard card
    const defCard = await query(
      `SELECT rate_card_id, card_code FROM fs.rate_card WHERE card_code = 'RC_STANDARD_2026' LIMIT 1`
    );
    if (defCard.rowCount > 0) {
      targetCardId = defCard.rows[0].rate_card_id;
      targetCardCode = defCard.rows[0].card_code;
    } else {
      const anyCard = await query(`SELECT rate_card_id, card_code FROM fs.rate_card LIMIT 1`);
      if (anyCard.rowCount > 0) {
        targetCardId = anyCard.rows[0].rate_card_id;
        targetCardCode = anyCard.rows[0].card_code;
      }
    }
  }

  if (!targetCardId) {
    throw new HttpError(500, 'No active rate card found in system');
  }

  // 2. Resolve Vehicle Placement on this card (7.7-R1, 7.7-R9, 7.7-C14)
  const placement = await query(
    `
    SELECT rcp.rate_card_placement_id,
           rcp.vehicle_tier_id,
           vt.vehicle_tier,
           vt.vehicle_tier_name,
           vt.sort_order AS tier_sort_order
      FROM fs.rate_card_placement rcp
      JOIN fs.vehicle_tier vt ON vt.vehicle_tier_id = rcp.vehicle_tier_id
     WHERE rcp.rate_card_id = $1
       AND rcp.vehicle_id = $2
       AND (rcp.effective_from IS NULL OR rcp.effective_from <= $3::date)
       AND (rcp.effective_to IS NULL OR rcp.effective_to >= $3::date)
     ORDER BY rcp.effective_from DESC NULLS LAST
     LIMIT 1
    `,
    [targetCardId, vehicleId, tripDate]
  );

  if (placement.rowCount === 0) {
    throw new HttpError(
      400,
      `7.7-R9 / 7.7-C14: Vehicle has no placement on rate card ${targetCardCode} and cannot be priced`
    );
  }

  let effectiveTierId = placement.rows[0].vehicle_tier_id;
  let effectiveTierCode = placement.rows[0].vehicle_tier;
  let effectiveTierName = placement.rows[0].vehicle_tier_name;
  let hasTierOverride = false;

  // 3. Per-member Tier Assignment Override (7.7-C11)
  if (memberId) {
    const tierOverride = await query(
      `
      SELECT mta.vehicle_tier_id_override,
             vt.vehicle_tier,
             vt.vehicle_tier_name
        FROM fs.mpc_tier_assignment mta
        JOIN fs.member_package_customization mpc ON mpc.member_package_customization_id = mta.member_package_customization_id
        JOIN fs.vehicle_tier vt ON vt.vehicle_tier_id = mta.vehicle_tier_id_override
       WHERE mpc.member_id = $1
         AND mta.vehicle_id = $2
         AND (mpc.effective_from IS NULL OR mpc.effective_from <= $3::date)
         AND (mpc.effective_to IS NULL OR mpc.effective_to >= $3::date)
       LIMIT 1
      `,
      [memberId, vehicleId, tripDate]
    );
    if (tierOverride.rowCount > 0) {
      effectiveTierId = tierOverride.rows[0].vehicle_tier_id_override;
      effectiveTierCode = tierOverride.rows[0].vehicle_tier;
      effectiveTierName = tierOverride.rows[0].vehicle_tier_name;
      hasTierOverride = true;
    }
  }

  // 4. Resolve Season (7.6-R7, 7.6-R8, 7.6-C09)
  const tripMonth = new Date(pickupAt).getUTCMonth() + 1;
  const tripDay = new Date(pickupAt).getUTCDate();

  const season = await query(
    `
    SELECT rate_card_season_id, season_name
      FROM fs.rate_card_season
     WHERE rate_card_id = $1
       AND (
         (start_month < end_month AND (start_month < $2 OR (start_month = $2 AND start_day <= $3))
                                  AND (end_month > $2 OR (end_month = $2 AND end_day >= $3)))
         OR
         (start_month > end_month AND ((start_month < $2 OR (start_month = $2 AND start_day <= $3))
                                   OR (end_month > $2 OR (end_month = $2 AND end_day >= $3))))
       )
     LIMIT 1
    `,
    [targetCardId, tripMonth, tripDay]
  );
  const seasonId = season.rowCount > 0 ? season.rows[0].rate_card_season_id : null;
  const seasonName = season.rowCount > 0 ? season.rows[0].season_name : 'Flat';

  // 5. Resolve Rate Row (7.6-R6, 7.7-R7, 7.7-C08)
  const rateRow = await query(
    `
    SELECT rcr.rate_card_rate_id,
           rcr.weekday_point_value,
           rcr.weekend_point_value,
           rcr.extra_mile_point_value
      FROM fs.rate_card_rate rcr
     WHERE rcr.rate_card_id = $1
       AND rcr.vehicle_tier_id = $2
       AND (rcr.rate_card_season_id = $3 OR (rcr.rate_card_season_id IS NULL AND $3 IS NULL))
     LIMIT 1
    `,
    [targetCardId, effectiveTierId, seasonId]
  );

  // Fallback to unseasonal rate on card if seasonal not found
  let baseRate = rateRow.rowCount > 0 ? rateRow.rows[0] : null;
  if (!baseRate && seasonId) {
    const unseasonal = await query(
      `
      SELECT rcr.rate_card_rate_id,
             rcr.weekday_point_value,
             rcr.weekend_point_value,
             rcr.extra_mile_point_value
        FROM fs.rate_card_rate rcr
       WHERE rcr.rate_card_id = $1
         AND rcr.vehicle_tier_id = $2
         AND rcr.rate_card_season_id IS NULL
       LIMIT 1
      `,
      [targetCardId, effectiveTierId]
    );
    if (unseasonal.rowCount > 0) baseRate = unseasonal.rows[0];
  }

  if (!baseRate) {
    throw new HttpError(
      400,
      `7.7-R7 / 7.7-C08: Placed tier ${effectiveTierCode} has no rate row on rate card ${targetCardCode} and is unpriceable`
    );
  }

  let weekdayPointValue = Number(baseRate.weekday_point_value);
  let weekendPointValue = Number(baseRate.weekend_point_value);
  let extraMilePointValue = Number(baseRate.extra_mile_point_value);
  let hasRateOverride = false;

  // 6. Per-member Point Rate Override (7.7-C12)
  if (memberId) {
    const rateOverride = await query(
      `
      SELECT mtpr.weekday_point_value_override,
             mtpr.weekend_point_value_override,
             mtpr.extra_mile_point_value_override
        FROM fs.mpc_tier_point_rate mtpr
        JOIN fs.member_package_customization mpc ON mpc.member_package_customization_id = mtpr.member_package_customization_id
       WHERE mpc.member_id = $1
         AND mtpr.vehicle_tier_id = $2
         AND (mpc.effective_from IS NULL OR mpc.effective_from <= $3::date)
         AND (mpc.effective_to IS NULL OR mpc.effective_to >= $3::date)
       LIMIT 1
      `,
      [memberId, effectiveTierId, tripDate]
    );
    if (rateOverride.rowCount > 0) {
      const o = rateOverride.rows[0];
      if (o.weekday_point_value_override != null) {
        weekdayPointValue = Number(o.weekday_point_value_override);
        hasRateOverride = true;
      }
      if (o.weekend_point_value_override != null) {
        weekendPointValue = Number(o.weekend_point_value_override);
        hasRateOverride = true;
      }
      if (o.extra_mile_point_value_override != null) {
        extraMilePointValue = Number(o.extra_mile_point_value_override);
        hasRateOverride = true;
      }
    }
  }

  // 7. Day Classification & Pricing (9.2-R7, 9.2-R8, 9.2-C10-C13, 9.2-C16)
  const classification = classifyTripDays(pickupAt, returnAt);

  let weekdayPoints = classification.weekdayDays * weekdayPointValue;
  let weekendPoints = classification.weekendUnits * weekendPointValue;
  let totalPoints = weekdayPoints + weekendPoints;

  if (isCourtesy) {
    // 9.2-R10 / 9.2-C16: Courtesy booking occupies calendar and consumes 0 points
    weekdayPoints = 0;
    weekendPoints = 0;
    totalPoints = 0;
  }

  return {
    rateCardId: targetCardId,
    rateCardCode: targetCardCode,
    tierId: effectiveTierId,
    tierCode: effectiveTierCode,
    tierName: effectiveTierName,
    seasonName,
    weekdayDays: classification.weekdayDays,
    weekendUnits: classification.weekendUnits,
    totalDays: classification.totalDurationDays,
    weekdayPointValue,
    weekendPointValue,
    extraMilePointValue,
    weekdayPoints,
    weekendPoints,
    totalPoints,
    hasTierOverride,
    hasRateOverride,
    isCourtesy,
  };
}
