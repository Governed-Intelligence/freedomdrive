import { query } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';
import { resolveTripPrice, classifyTripDays } from './rateResolver.js';

export { classifyTripDays };

/**
 * Compute whole days between two ISO timestamps.
 */
export function computeBookingDays(pickupIso, returnIso) {
  const pickup = new Date(pickupIso);
  const ret = new Date(returnIso);
  if (!(ret > pickup)) {
    throw new HttpError(400, 'return_at must be strictly after pickup_at');
  }
  const ms = ret - pickup;
  const days = Math.ceil(ms / (1000 * 60 * 60 * 24));
  return Math.max(1, days);
}

/**
 * Generate a human-friendly confirmation code.
 * Format: FS-YYMMDD-XXXX  (e.g. FS-260418-A7K2)
 */
export function generateConfirmationCode() {
  const now = new Date();
  const yy = String(now.getFullYear()).slice(2);
  const mm = String(now.getMonth() + 1).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let suffix = '';
  for (let i = 0; i < 4; i++) {
    suffix += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return `FS-${yy}${mm}${dd}-${suffix}`;
}

/**
 * Check vehicle overlapping reservations, taking into account the automatic
 * turnaround/prep buffer (block_until) on both fs.reservations and fs.vehicle_reservation.
 */
export async function checkVehicleOverlap(dbClient, vehicleId, pickupAt, returnAt) {
  const client = dbClient.query ? dbClient : { query: dbClient };

  const overlap = await client.query(
    `
    SELECT vr.vehicle_reservation_id AS id, vr.reservation_type_code::text AS reservation_type_code, vr.reservation_status_code::text AS reservation_status_code
      FROM fs.vehicle_reservation vr
     WHERE vr.vehicle_id = $1
       AND vr.reservation_status_code IN ('Confirmed', 'Held', 'Tentative')
       AND vr.start_time_scheduled <= $3::timestamptz
       AND (vr.end_time_scheduled + (COALESCE(vr.buffer_days_after_end, 0) || ' days')::interval) >= $2::timestamptz
     UNION ALL
     SELECT r.id, 'Member'::text AS reservation_type_code, r.status::text AS reservation_status_code
       FROM fs.reservations r
      WHERE r.vehicle_id = $1
        AND r.status IN ('requested', 'confirmed', 'picked_up')
        AND r.pickup_at <= $3::timestamptz
        AND COALESCE(r.block_until, r.return_at + (COALESCE(r.prep_buffer_hours, 4) * INTERVAL '1 hour')) >= $2::timestamptz
     LIMIT 1
    `,
    [vehicleId, pickupAt, returnAt]
  );

  if (overlap.rowCount > 0) {
    const c = overlap.rows[0];
    throw new HttpError(
      409,
      `Vehicle is already reserved (${c.reservation_type_code || 'existing'}) or in turnaround detailing buffer for the selected window`
    );
  }
}

/**
 * Assemble full booking context:
 * Vehicle state (stage, condition, prelaunch), withholds,
 * Member state (lifecycle, packages count, insurance),
 * Subscription, plan tier allocations, and current points balance.
 */
export async function loadBookingContext({ vehicleId, subscriptionId, memberId }) {
  // 1. Vehicle details (from fs.vehicles joined with fs.vehicle if present)
  const vRes = await query(
    `
    SELECT
      v.id                     AS vehicle_id,
      v.status                 AS vehicle_status,
      v.retired_on             AS vehicle_retired_on,
      v.tier_id                AS tier_id,
      v.location_id            AS location_id,
      COALESCE(fv.fleet_stage::text, 'Fleet') AS fleet_stage,
      COALESCE(fv.condition_code, 'Ready') AS condition_code,
      CASE
        WHEN fv.launch_date IS NOT NULL AND fv.launch_date > CURRENT_DATE THEN true
        ELSE false
      END AS is_prelaunch
    FROM fs.vehicles v
    LEFT JOIN fs.vehicle fv ON fv.vehicle_id = v.id
    WHERE v.id = $1
    `,
    [vehicleId]
  );

  if (vRes.rowCount === 0) {
    throw new HttpError(404, 'Vehicle not found');
  }
  const vehicle = vRes.rows[0];

  // 2. Subscription and plan details
  let subQuery = `
    SELECT
      s.id                     AS subscription_id,
      s.member_id              AS member_id,
      s.status                 AS subscription_status,
      s.start_date             AS sub_start,
      s.end_date               AS sub_end,
      p.id                     AS plan_id,
      p.code                   AS plan_code,
      p.name                   AS plan_name,
      (SELECT MAX(pta.tier_id) FROM fs.plan_tier_allocations pta WHERE pta.plan_id = p.id) AS plan_max_tier,
      fs.subscription_balance(s.id) AS balance,
      m.status                 AS member_status,
      m.first_name,
      m.last_name,
      m.primary_location_id    AS member_home_location_id
    FROM fs.member_subscriptions s
    JOIN fs.plans p ON p.id = s.plan_id
    JOIN fs.members m ON m.id = s.member_id
    WHERE s.id = $1
  `;
  const subRes = await query(subQuery, [subscriptionId]);

  if (subRes.rowCount === 0) {
    throw new HttpError(404, 'Subscription not found');
  }
  const sub = subRes.rows[0];

  // 3. Count member active subscriptions (Rule 9.2-R4 / 9.2-C09)
  const activeSubs = await query(
    `SELECT COUNT(*)::int AS count FROM fs.member_subscriptions WHERE member_id = $1 AND status = 'active'`,
    [sub.member_id]
  );
  const activePackageCount = activeSubs.rows[0].count;

  // 4. Look up active insurance policies for this member (Rule 9.2-R3, 9.2-C07, 9.2-C08)
  const insRes = await query(
    `
    SELECT member_insurance_policy_id, effective_on, expires_on, verification_status
      FROM fs.member_insurance_policy
     WHERE member_id = $1
     ORDER BY expires_on DESC NULLS LAST
     LIMIT 1
    `,
    [sub.member_id]
  );
  const insurance = insRes.rowCount > 0 ? insRes.rows[0] : null;

  return {
    ...vehicle,
    ...sub,
    activePackageCount,
    insurance,
  };
}

/**
 * Validate booking in strict order of rules (Guide 9.2 Developer Note 1):
 * 1. Vehicle Conditions (Incoming, Prelaunch, Prep/Down, Withhold, Overlap)
 * 2. Member & Subscription Conditions (Duration, Insurance expiry, Explicit package)
 * 3. Access Conditions (Tier access, Branch access)
 * 4. Pricing & Points (Weekday/Weekend bundling, Balance check)
 */
export async function validateBooking(ctx, { pickupAt, returnAt, isStaff = false, isCourtesy = false, requestedSubscriptionId }) {
  const pickup = new Date(pickupAt);
  const ret = new Date(returnAt);
  const tripEndDateStr = ret.toISOString().split('T')[0];

  // -------------------------------------------------------------------------
  // 1. VEHICLE CHECKS (Rule 9.2-R1: All 4 conditions must pass before member evaluation)
  // -------------------------------------------------------------------------

  // 9.2-C01: A vehicle at Incoming cannot be booked
  if (ctx.fleet_stage === 'Incoming') {
    throw new HttpError(409, '9.2-C01: Vehicle is at Incoming stage and cannot be booked');
  }

  // 9.2-C02 / 9.2-C03: Pre-launch cannot be booked by member; allowed for staff
  if (ctx.is_prelaunch && !isStaff) {
    throw new HttpError(409, '9.2-C02: Vehicle is in pre-launch and can only be reserved by authorized staff');
  }

  // 9.2-C04: A vehicle at condition Prep, Review, or Down cannot be booked
  if (['Prep', 'Down', 'Review'].includes(ctx.condition_code)) {
    throw new HttpError(409, `9.2-C04: Vehicle condition is ${ctx.condition_code} and is unavailable for member booking`);
  }

  // 9.2-C05: A vehicle with a withhold covering the dates cannot be booked
  const withholdCheck = await query(
    `
    SELECT reservation_withhold_id, withhold_reason_code
      FROM fs.reservation_withhold
     WHERE vehicle_id = $1
       AND starts_on <= $3::date
       AND ends_on >= $2::date
     LIMIT 1
    `,
    [ctx.vehicle_id, pickup.toISOString().split('T')[0], tripEndDateStr]
  );
  if (withholdCheck.rowCount > 0) {
    throw new HttpError(
      409,
      `9.2-C05: Vehicle has an active withhold (${withholdCheck.rows[0].withhold_reason_code}) covering the requested dates`
    );
  }

  // -------------------------------------------------------------------------
  // 2. MEMBER CHECKS (Order by cost and clarity: Insurance and membership first)
  // -------------------------------------------------------------------------

  // 9.2-R2 / 9.2-C06: Membership must be active across the WHOLE reservation, not merely today
  const subEnd = new Date(ctx.sub_end);
  if (ret > subEnd) {
    throw new HttpError(
      400,
      `9.2-C06: Membership ends on ${ctx.sub_end}, before the reservation return date (${tripEndDateStr}). Membership must be active across the whole reservation.`
    );
  }

  // 9.2-R3 / 9.2-C07 / 9.2-C08: Insurance must be valid through entire trip; expired policy refuses first
  if (ctx.insurance && ctx.insurance.expires_on) {
    const insExp = new Date(ctx.insurance.expires_on);
    if (insExp < ret) {
      throw new HttpError(
        400,
        `9.2-C07: Member insurance policy expires on ${ctx.insurance.expires_on}, before reservation return date (${tripEndDateStr}). Insurance must be valid through the entire trip.`
      );
    }
  }

  // 9.2-R4 / 9.2-C09: Where a member holds several packages, choice is explicit and never defaulted
  if (ctx.activePackageCount > 1 && !requestedSubscriptionId) {
    throw new HttpError(
      400,
      '9.2-C09: Member holds multiple active membership packages. You must explicitly select which package to charge for this reservation.'
    );
  }

  // -------------------------------------------------------------------------
  // 3. ACCESS CHECKS (Rule 9.2-R5: Tier and branch access checked independently of points)
  // -------------------------------------------------------------------------

  // Check tier access: Compare plan allowed tier to vehicle tier
  // Plan max tier (1-5), vehicle tier (1-5)
  if (ctx.plan_max_tier != null && ctx.tier_id != null) {
    if (Number(ctx.tier_id) > Number(ctx.plan_max_tier)) {
      throw new HttpError(
        403,
        `9.2-R5: Your membership tier (${ctx.plan_max_tier}) does not include Tier ${ctx.tier_id} vehicles. Tier access is independent of available points.`
      );
    }
  }

  // -------------------------------------------------------------------------
  // 4. PRICING & POINTS (Rule 9.2-R6, 9.2-R7, 9.2-R8, 9.2-C10-C14)
  // -------------------------------------------------------------------------

  const pricing = await resolveTripPrice({
    memberId: ctx.member_id,
    subscriptionId: ctx.subscription_id,
    vehicleId: ctx.vehicle_id,
    pickupAt,
    returnAt,
    isCourtesy,
  });

  // Balance Check (9.2-C15, unless courtesy booking 9.2-C16, or pending member tentative booking 9.2-C17)
  const isPendingMember = ctx.member_status === 'pending';
  if (!isCourtesy && !isPendingMember && ctx.balance < pricing.totalPoints) {
    throw new HttpError(
      402,
      `Insufficient points: this booking costs ${pricing.totalPoints} points (${pricing.weekdayPoints} weekday, ${pricing.weekendPoints} weekend), but current balance is ${ctx.balance}`
    );
  }

  // Return pricing object with backward-compatible aliases for legacy callers
  return {
    ...pricing,
    days: pricing.totalDays,
    pointsPerDay: pricing.weekdayPointValue,
    totalCost: pricing.totalPoints,
  };
}

/**
 * Annual tier usage check: if plan caps days-per-year at this tier.
 */
export async function checkAnnualTierCap(ctx, days) {
  if (!ctx.plan_max_days_per_year) return;
  const used = await query(
    `
    SELECT COALESCE(SUM(r.days_booked), 0)::int AS days_used
      FROM fs.reservations r
      JOIN fs.vehicles v ON v.id = r.vehicle_id
     WHERE r.subscription_id = $1
       AND v.tier_id = $2
       AND r.status IN ('requested','confirmed','picked_up','returned')
    `,
    [ctx.subscription_id, ctx.tier_id]
  );
  const daysUsed = used.rows[0].days_used;
  if (daysUsed + days > ctx.plan_max_days_per_year) {
    throw new HttpError(
      400,
      `Annual cap exceeded for tier ${ctx.tier_id}: plan allows ${ctx.plan_max_days_per_year} days/year, you've used ${daysUsed} and this would add ${days}`
    );
  }
}
