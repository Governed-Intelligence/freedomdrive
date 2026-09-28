import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';
import {
  requireAuth,
  optionalAuth,
  verifyToken,
  signToken,
} from '../middleware/auth.js';
import {
  loadBookingContext,
  validateBooking,
  checkAnnualTierCap,
  generateConfirmationCode,
} from '../services/reservations.js';

export const reservationsRouter = Router();

async function checkVehicleOverlap(dbClient, vehicleId, pickupAt, returnAt) {
  const overlap = await (dbClient.query ? dbClient : { query: dbClient }).query(
    `
    SELECT vr.vehicle_reservation_id AS id, vr.reservation_type_code, vr.reservation_status_code
      FROM fs.vehicle_reservation vr
     WHERE vr.vehicle_id = $1
       AND vr.reservation_status_code IN ('Confirmed', 'Held', 'Tentative')
       AND vr.start_time_scheduled <= $3::timestamptz
       AND (vr.end_time_scheduled + (COALESCE(vr.buffer_days_after_end, 0) || ' days')::interval) >= $2::timestamptz
     UNION ALL
     SELECT r.id, 'Member' AS reservation_type_code, r.status AS reservation_status_code
       FROM fs.reservations r
      WHERE r.vehicle_id = $1
        AND r.status IN ('requested', 'confirmed', 'picked_up')
        AND r.pickup_at <= $3::timestamptz
        AND r.return_at >= $2::timestamptz
     LIMIT 1
    `,
    [vehicleId, pickupAt, returnAt]
  );
  if (overlap.rowCount > 0) {
    const c = overlap.rows[0];
    throw new HttpError(409, `Vehicle is already reserved (${c.reservation_type_code || 'existing'}) for the selected window`);
  }
}

const createSchema = z.object({
  subscription_id: z.string().uuid(),
  vehicle_id: z.string().uuid(),
  pickup_at: z.string().datetime(),
  return_at: z.string().datetime(),
  authorized_driver_id: z.string().uuid().optional(),
  destination: z.string().max(200).optional(),
  purpose: z.string().max(200).optional(),
  member_notes: z.string().max(1000).optional(),
  auto_confirm: z.boolean().default(false),
});

const confirmQuoteSchema = z.object({
  reservation_token: z.string().min(10),
  authorized_driver_id: z.string().uuid().optional(),
  destination: z.string().max(200).optional(),
  purpose: z.string().max(200).optional(),
  member_notes: z.string().max(1000).optional(),
});

// POST /v1/reservations/confirm-quote - explicitly confirm an ephemeral quote token
async function handleConfirmQuote(req, res) {
  const data = confirmQuoteSchema.parse(req.body);

  let quote;
  try {
    quote = verifyToken(data.reservation_token);
  } catch (_err) {
    throw new HttpError(400, 'Invalid or expired reservation quote token. Please request a new quote.');
  }

  if (quote.type !== 'reservation_quote') {
    throw new HttpError(400, 'Invalid token payload for reservation confirmation');
  }

  if (req.user && quote.memberId !== req.user.memberId) {
    throw new HttpError(403, 'Reservation quote does not belong to authenticated member');
  }

  // Reload fresh context to ensure subscription is active and balance remains sufficient
  const ctx = await loadBookingContext({
    vehicleId: quote.vehicleId,
    subscriptionId: quote.subscriptionId,
  });

  const { days, pointsPerDay, totalCost } = validateBooking(ctx, {
    pickupAt: quote.pickupAt,
    returnAt: quote.returnAt,
  });
  await checkAnnualTierCap(ctx, days);
  await checkVehicleOverlap(query, quote.vehicleId, quote.pickupAt, quote.returnAt);

  if (data.authorized_driver_id) {
    const drv = await query(
      `SELECT member_id, is_active FROM fs.authorized_drivers WHERE id = $1`,
      [data.authorized_driver_id]
    );
    if (drv.rowCount === 0 || drv.rows[0].member_id !== ctx.member_id) {
      throw new HttpError(400, 'Authorized driver not found for this member');
    }
    if (!drv.rows[0].is_active) {
      throw new HttpError(400, 'Authorized driver is inactive');
    }
  }

  const confirmationCode = generateConfirmationCode();

  const row = await withTransaction(async (client) => {
    const insert = await client.query(
      `
      INSERT INTO fs.reservations (
        confirmation_code, member_id, subscription_id, vehicle_id,
        authorized_driver_id, status, pickup_at, return_at, days_booked,
        tier_points_per_day, total_points_cost, destination, purpose, member_notes
      ) VALUES (
        $1, $2, $3, $4, $5, 'confirmed', $6, $7, $8, $9, $10, $11, $12, $13
      )
      RETURNING *
      `,
      [
        confirmationCode,
        ctx.member_id,
        ctx.subscription_id,
        quote.vehicleId,
        data.authorized_driver_id ?? null,
        quote.pickupAt,
        quote.returnAt,
        days,
        pointsPerDay,
        totalCost,
        data.destination ?? null,
        data.purpose ?? null,
        data.member_notes ?? null,
      ]
    );
    return insert.rows[0];
  });

  res.status(201).json({ reservation: row, confirmed: true });
}

reservationsRouter.post('/confirm-quote', requireAuth, handleConfirmQuote);
reservationsRouter.post('/_/confirm-quote', requireAuth, handleConfirmQuote);

// POST /v1/reservations - create a reservation request
reservationsRouter.post('/', optionalAuth, async (req, res) => {
  const data = createSchema.parse(req.body);

  const ctx = await loadBookingContext({
    vehicleId: data.vehicle_id,
    subscriptionId: data.subscription_id,
  });

  if (req.user && ctx.member_id !== req.user.memberId) {
    throw new HttpError(403, 'Subscription does not belong to authenticated member');
  }

  const { days, pointsPerDay, totalCost } = validateBooking(ctx, {
    pickupAt: data.pickup_at,
    returnAt: data.return_at,
  });
  await checkAnnualTierCap(ctx, days);
  await checkVehicleOverlap(query, data.vehicle_id, data.pickup_at, data.return_at);

  if (data.authorized_driver_id) {
    const drv = await query(
      `SELECT member_id, is_active FROM fs.authorized_drivers WHERE id = $1`,
      [data.authorized_driver_id]
    );
    if (drv.rowCount === 0 || drv.rows[0].member_id !== ctx.member_id) {
      throw new HttpError(400, 'Authorized driver not found for this member');
    }
    if (!drv.rows[0].is_active) {
      throw new HttpError(400, 'Authorized driver is inactive');
    }
  }

  const initialStatus = data.auto_confirm ? 'confirmed' : 'requested';
  const confirmationCode = generateConfirmationCode();

  const row = await withTransaction(async (client) => {
    const insert = await client.query(
      `
      INSERT INTO fs.reservations (
        confirmation_code, member_id, subscription_id, vehicle_id,
        authorized_driver_id, status, pickup_at, return_at, days_booked,
        tier_points_per_day, total_points_cost, destination, purpose, member_notes
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14
      )
      RETURNING *
      `,
      [
        confirmationCode,
        ctx.member_id,
        ctx.subscription_id,
        data.vehicle_id,
        data.authorized_driver_id ?? null,
        initialStatus,
        data.pickup_at,
        data.return_at,
        days,
        pointsPerDay,
        totalCost,
        data.destination ?? null,
        data.purpose ?? null,
        data.member_notes ?? null,
      ]
    );
    return insert.rows[0];
  });

  res.status(201).json({ reservation: row });
});

// GET /v1/reservations/:id
reservationsRouter.get('/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `
    SELECT r.*,
           mf.name || ' ' || vm.model_name AS vehicle_display,
           v.exterior_color,
           v.stock_number
      FROM fs.reservations r
      JOIN fs.vehicles v ON v.id = r.vehicle_id
      JOIN fs.vehicle_models vm ON vm.id = v.model_id
      JOIN fs.manufacturers mf ON mf.id = vm.manufacturer_id
     WHERE r.id = $1
    `,
    [id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Reservation not found');
  }
  res.json({ reservation: result.rows[0] });
});

// POST /v1/reservations/:id/confirm - trigger handles point debit
reservationsRouter.post('/:id/confirm', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `
    UPDATE fs.reservations
       SET status = 'confirmed', updated_at = now()
     WHERE id = $1 AND status = 'requested'
     RETURNING *
    `,
    [id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(409, 'Reservation not in requested state');
  }
  res.json({ reservation: result.rows[0] });
});

// POST /v1/reservations/:id/cancel - trigger handles refund if already confirmed
reservationsRouter.post('/:id/cancel', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    reason: z.string().max(500).optional(),
    cancelled_by: z.string().uuid().optional(),
  });
  const body = schema.parse(req.body ?? {});

  const result = await query(
    `
    UPDATE fs.reservations
       SET status = 'cancelled',
           cancelled_at = now(),
           cancelled_by = $2,
           cancellation_reason = $3
     WHERE id = $1 AND status IN ('requested','confirmed')
     RETURNING *
    `,
    [id, body.cancelled_by ?? null, body.reason ?? null]
  );
  if (result.rowCount === 0) {
    throw new HttpError(409, 'Reservation not in a cancellable state');
  }
  res.json({ reservation: result.rows[0] });
});

// POST /v1/reservations/:id/pickup - member has taken the car
reservationsRouter.post('/:id/pickup', async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    mileage: z.number().int().nonnegative(),
    fuel_level_pct: z.number().int().min(0).max(100),
    condition: z.enum(['excellent', 'good', 'fair', 'needs_attention', 'out_of_service']),
    pre_existing_damage: z.string().max(2000).optional(),
    handled_by_staff: z.string().uuid().optional(),
    photos_url: z.array(z.string().url()).optional(),
    notes: z.string().max(2000).optional(),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const res1 = await client.query(
      `
      UPDATE fs.reservations
         SET status = 'picked_up', updated_at = now()
       WHERE id = $1 AND status = 'confirmed'
       RETURNING id, vehicle_id, confirmation_code
      `,
      [id]
    );
    if (res1.rowCount === 0) {
      throw new HttpError(409, 'Reservation not in confirmed state');
    }
    const { vehicle_id } = res1.rows[0];

    await client.query(
      `
      INSERT INTO fs.reservation_pickups_returns
        (reservation_id, event_type, mileage, fuel_level_pct, condition,
         pre_existing_damage, handled_by_staff, photos_url, notes)
      VALUES ($1, 'pickup', $2, $3, $4, $5, $6, $7, $8)
      `,
      [
        id,
        data.mileage,
        data.fuel_level_pct,
        data.condition,
        data.pre_existing_damage ?? null,
        data.handled_by_staff ?? null,
        data.photos_url ?? null,
        data.notes ?? null,
      ]
    );

    await client.query(
      `UPDATE fs.vehicles SET status = 'in_use', current_mileage = $1 WHERE id = $2`,
      [data.mileage, vehicle_id]
    );

    return res1.rows[0];
  });
  res.json({ reservation: result });
});

// POST /v1/reservations/:id/return - member has returned the car
reservationsRouter.post('/:id/return', async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    mileage: z.number().int().nonnegative(),
    fuel_level_pct: z.number().int().min(0).max(100),
    condition: z.enum(['excellent', 'good', 'fair', 'needs_attention', 'out_of_service']),
    new_damage: z.string().max(2000).optional(),
    handled_by_staff: z.string().uuid().optional(),
    photos_url: z.array(z.string().url()).optional(),
    notes: z.string().max(2000).optional(),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const res1 = await client.query(
      `
      UPDATE fs.reservations
         SET status = 'returned', updated_at = now()
       WHERE id = $1 AND status = 'picked_up'
       RETURNING id, vehicle_id, confirmation_code
      `,
      [id]
    );
    if (res1.rowCount === 0) {
      throw new HttpError(409, 'Reservation not in picked_up state');
    }
    const { vehicle_id } = res1.rows[0];

    await client.query(
      `
      INSERT INTO fs.reservation_pickups_returns
        (reservation_id, event_type, mileage, fuel_level_pct, condition,
         new_damage, handled_by_staff, photos_url, notes)
      VALUES ($1, 'return', $2, $3, $4, $5, $6, $7, $8)
      `,
      [
        id,
        data.mileage,
        data.fuel_level_pct,
        data.condition,
        data.new_damage ?? null,
        data.handled_by_staff ?? null,
        data.photos_url ?? null,
        data.notes ?? null,
      ]
    );

    await client.query(
      `UPDATE fs.vehicles SET status = 'detailing', current_mileage = $1 WHERE id = $2`,
      [data.mileage, vehicle_id]
    );

    return res1.rows[0];
  });
  res.json({ reservation: result });
});

// GET /v1/reservations/_/upcoming - dashboard
reservationsRouter.get('/_/upcoming', async (_req, res) => {
  const result = await query(
    `SELECT * FROM fs.v_upcoming_reservations LIMIT 100`
  );
  res.json({ count: result.rowCount, reservations: result.rows });
});

// POST /v1/reservations/_/quote - price a prospective booking and issue ephemeral token
reservationsRouter.post('/_/quote', optionalAuth, async (req, res) => {
  const schema = z.object({
    subscription_id: z.string().uuid(),
    vehicle_id: z.string().uuid(),
    pickup_at: z.string().datetime(),
    return_at: z.string().datetime(),
  });
  const data = schema.parse(req.body);

  const ctx = await loadBookingContext({
    vehicleId: data.vehicle_id,
    subscriptionId: data.subscription_id,
  });
  const { days, pointsPerDay, totalCost } = validateBooking(ctx, {
    pickupAt: data.pickup_at,
    returnAt: data.return_at,
  });
  await checkAnnualTierCap(ctx, days);
  await checkVehicleOverlap(query, data.vehicle_id, data.pickup_at, data.return_at);

  const reservationToken = signToken(
    {
      type: 'reservation_quote',
      memberId: ctx.member_id,
      subscriptionId: data.subscription_id,
      vehicleId: data.vehicle_id,
      pickupAt: data.pickup_at,
      returnAt: data.return_at,
      days,
      pointsPerDay,
      totalCost,
    },
    { expiresIn: '15m' }
  );

  res.json({
    quote: {
      reservation_token: reservationToken,
      days_booked: days,
      tier_id: ctx.tier_id,
      points_per_day: pointsPerDay,
      total_points_cost: totalCost,
      balance_before: ctx.balance,
      balance_after_confirm: ctx.balance - totalCost,
      expires_in_minutes: 15,
    },
  });
});
