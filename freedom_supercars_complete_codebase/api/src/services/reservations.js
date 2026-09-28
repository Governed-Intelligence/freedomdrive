import { query } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';

/**
 * Compute whole days between two ISO timestamps.
 * 24h00m01s → 2 days (we charge by calendar day usage; partial days round up).
 */
export function computeBookingDays(pickupIso, returnIso) {
  const pickup = new Date(pickupIso);
  const ret = new Date(returnIso);
  if (!(ret > pickup)) {
    throw new HttpError(400, 'return_at must be after pickup_at');
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
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no confusables
  let suffix = '';
  for (let i = 0; i < 4; i++) {
    suffix += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return `FS-${yy}${mm}${dd}-${suffix}`;
}

/**
 * Assemble the full context we need to validate a booking:
 * vehicle + tier rules + subscription + active plan + current balance.
 */
export async function loadBookingContext({ vehicleId, subscriptionId }) {
  const result = await query(
    `
    SELECT
      v.id                     AS vehicle_id,
      v.status                 AS vehicle_status,
      v.retired_on             AS vehicle_retired_on,
      v.tier_id                AS tier_id,
      t.points_per_day         AS points_per_day,
      t.min_booking_days       AS min_booking_days,
      t.max_booking_days       AS max_booking_days,
      s.id                     AS subscription_id,
      s.member_id              AS member_id,
      s.status                 AS subscription_status,
      s.start_date             AS sub_start,
      s.end_date               AS sub_end,
      p.id                     AS plan_id,
      p.code                   AS plan_code,
      fs.subscription_balance(s.id) AS balance,
      pta.max_days_per_year    AS plan_max_days_per_year,
      pta.max_days_per_booking AS plan_max_days_per_booking,
      pta.advance_booking_days AS advance_booking_days
    FROM fs.vehicles v
    JOIN fs.tiers t                 ON t.id = v.tier_id
    JOIN fs.member_subscriptions s  ON s.id = $2
    JOIN fs.plans p                 ON p.id = s.plan_id
    LEFT JOIN fs.plan_tier_allocations pta
           ON pta.plan_id = p.id AND pta.tier_id = v.tier_id
    WHERE v.id = $1
    `,
    [vehicleId, subscriptionId]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Vehicle or subscription not found');
  }
  return result.rows[0];
}

/**
 * Validate a proposed booking against all business rules.
 * Throws HttpError on any violation. Returns the computed cost.
 */
export function validateBooking(ctx, { pickupAt, returnAt }) {
  if (ctx.vehicle_retired_on) {
    throw new HttpError(409, 'Vehicle has been retired from the fleet');
  }
  if (ctx.vehicle_status === 'retired') {
    throw new HttpError(409, 'Vehicle is not bookable');
  }
  if (ctx.subscription_status !== 'active') {
    throw new HttpError(
      409,
      `Subscription is ${ctx.subscription_status} and cannot make reservations`
    );
  }

  const days = computeBookingDays(pickupAt, returnAt);

  if (days < ctx.min_booking_days) {
    throw new HttpError(
      400,
      `Tier ${ctx.tier_id} requires a minimum booking of ${ctx.min_booking_days} days (got ${days})`
    );
  }
  if (days > ctx.max_booking_days) {
    throw new HttpError(
      400,
      `Tier ${ctx.tier_id} allows a maximum booking of ${ctx.max_booking_days} days (got ${days})`
    );
  }
  if (ctx.plan_max_days_per_booking && days > ctx.plan_max_days_per_booking) {
    throw new HttpError(
      400,
      `Your plan caps this tier at ${ctx.plan_max_days_per_booking} days per booking`
    );
  }

  // Pickup must be inside subscription window
  const pickup = new Date(pickupAt);
  const subEnd = new Date(ctx.sub_end);
  if (pickup > subEnd) {
    throw new HttpError(400, 'Pickup is beyond your subscription end date');
  }

  // Advance-booking cap
  if (ctx.advance_booking_days) {
    const maxAdvance = new Date();
    maxAdvance.setDate(maxAdvance.getDate() + ctx.advance_booking_days);
    if (pickup > maxAdvance) {
      throw new HttpError(
        400,
        `Bookings can be made at most ${ctx.advance_booking_days} days in advance for this tier`
      );
    }
  }

  // Cost
  const totalCost = Math.ceil(Number(ctx.points_per_day) * days);
  if (ctx.balance < totalCost) {
    throw new HttpError(
      402,
      `Insufficient tier points: this booking costs ${totalCost}, you have ${ctx.balance}`
    );
  }

  return { days, pointsPerDay: Number(ctx.points_per_day), totalCost };
}

/**
 * Annual-tier-usage check: if the plan caps days-per-year at this tier,
 * make sure the new booking doesn't exceed it.
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
