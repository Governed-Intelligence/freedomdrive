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
  checkVehicleOverlap,
  generateConfirmationCode,
} from '../services/reservations.js';
import { checkoutTrip, checkinTrip } from '../services/trips.js';

export const reservationsRouter = Router();

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
  is_courtesy: z.boolean().default(false),
  prep_buffer_hours: z.number().int().min(0).max(168).default(4),
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

  const isStaff = req.user?.role === 'staff' || req.user?.role === 'admin';

  // Overlap check (including turnaround buffer)
  await checkVehicleOverlap(query, quote.vehicleId, quote.pickupAt, quote.returnAt);

  const ctx = await loadBookingContext({
    vehicleId: quote.vehicleId,
    subscriptionId: quote.subscriptionId,
  });

  const pricing = await validateBooking(ctx, {
    pickupAt: quote.pickupAt,
    returnAt: quote.returnAt,
    isStaff,
    isCourtesy: quote.isCourtesy ?? false,
    requestedSubscriptionId: quote.subscriptionId,
  });

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

  const initialStatus = ctx.member_status === 'pending' ? 'tentative' : 'confirmed';
  const isTentative = initialStatus === 'tentative';
  const confirmationCode = generateConfirmationCode();

  const row = await withTransaction(async (client) => {
    const insert = await client.query(
      `
      INSERT INTO fs.reservations (
        confirmation_code, member_id, subscription_id, vehicle_id,
        authorized_driver_id, status, pickup_at, return_at, days_booked,
        tier_points_per_day, total_points_cost, weekday_points, weekend_points,
        is_courtesy, is_tentative, counts_toward_limits, rate_card_id, prep_buffer_hours,
        destination, purpose, member_notes
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21
      )
      RETURNING *
      `,
      [
        confirmationCode,
        ctx.member_id,
        ctx.subscription_id,
        quote.vehicleId,
        data.authorized_driver_id ?? null,
        initialStatus,
        quote.pickupAt,
        quote.returnAt,
        pricing.totalDays,
        pricing.weekdayPointValue,
        pricing.totalPoints,
        pricing.weekdayPoints,
        pricing.weekendPoints,
        quote.isCourtesy ?? false,
        isTentative,
        !(quote.isCourtesy ?? false),
        pricing.rateCardId,
        4,
        data.destination ?? null,
        data.purpose ?? null,
        data.member_notes ?? null,
      ]
    );

    const resRow = insert.rows[0];

    // 9.2-C15: Post real charge to points ledger upon confirmation
    if (initialStatus === 'confirmed' && !quote.isCourtesy && pricing.totalPoints > 0) {
      await client.query(
        `
        INSERT INTO fs.member_points_ledger (
          member_id, points_change,
          source, description, entry_type, occurred_at
        ) VALUES (
          $1, $2, 'Reservation', $3, 'Charge Reservation', now()
        )
        `,
        [
          ctx.member_id,
          -pricing.totalPoints,
          `Reservation ${confirmationCode} confirmation charge`,
        ]
      );
    }

    return resRow;
  });

  res.status(201).json({ reservation: row, confirmed: initialStatus === 'confirmed' });
}

reservationsRouter.post('/confirm-quote', requireAuth, handleConfirmQuote);
reservationsRouter.post('/_/confirm-quote', requireAuth, handleConfirmQuote);

// POST /v1/reservations - create a reservation
reservationsRouter.post('/', optionalAuth, async (req, res) => {
  const data = createSchema.parse(req.body);
  const isStaff = req.user?.role === 'staff' || req.user?.role === 'admin';

  // 1. Overlap check (including turnaround buffer block_until)
  await checkVehicleOverlap(query, data.vehicle_id, data.pickup_at, data.return_at);

  // 2. Load context
  const ctx = await loadBookingContext({
    vehicleId: data.vehicle_id,
    subscriptionId: data.subscription_id,
  });

  if (req.user && ctx.member_id !== req.user.memberId && !isStaff) {
    throw new HttpError(403, 'Subscription does not belong to authenticated member');
  }

  // 3. Strict order of checks (Vehicle -> Member -> Access -> Pricing -> Points)
  const pricing = await validateBooking(ctx, {
    pickupAt: data.pickup_at,
    returnAt: data.return_at,
    isStaff,
    isCourtesy: data.is_courtesy,
    requestedSubscriptionId: data.subscription_id,
  });

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

  // 9.2-C17: A booking against a Pending member is created tentative
  const initialStatus = ctx.member_status === 'pending'
    ? 'tentative'
    : (data.auto_confirm ? 'confirmed' : 'requested');
  const isTentative = initialStatus === 'tentative';
  const confirmationCode = generateConfirmationCode();

  const row = await withTransaction(async (client) => {
    const insert = await client.query(
      `
      INSERT INTO fs.reservations (
        confirmation_code, member_id, subscription_id, vehicle_id,
        authorized_driver_id, status, pickup_at, return_at, days_booked,
        tier_points_per_day, total_points_cost, weekday_points, weekend_points,
        is_courtesy, is_tentative, counts_toward_limits, rate_card_id, prep_buffer_hours,
        destination, purpose, member_notes
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21
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
        pricing.totalDays,
        pricing.weekdayPointValue,
        pricing.totalPoints,
        pricing.weekdayPoints,
        pricing.weekendPoints,
        data.is_courtesy,
        isTentative,
        !data.is_courtesy,
        pricing.rateCardId,
        data.prep_buffer_hours,
        data.destination ?? null,
        data.purpose ?? null,
        data.member_notes ?? null,
      ]
    );

    const resRow = insert.rows[0];

    // 9.2-C15: Confirming posts a charge to the points ledger
    if (initialStatus === 'confirmed' && !data.is_courtesy && pricing.totalPoints > 0) {
      await client.query(
        `
        INSERT INTO fs.member_points_ledger (
          member_id, points_change,
          source, description, entry_type, occurred_at
        ) VALUES (
          $1, $2, 'Reservation', $3, 'Charge Reservation', now()
        )
        `,
        [
          ctx.member_id,
          -pricing.totalPoints,
          `Reservation ${confirmationCode} confirmation charge`,
        ]
      );
    }

    return resRow;
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
           v.stock_number,
           rc.card_code AS rate_card_code
      FROM fs.reservations r
      JOIN fs.vehicles v ON v.id = r.vehicle_id
      JOIN fs.vehicle_models vm ON vm.id = v.model_id
      JOIN fs.manufacturers mf ON mf.id = vm.manufacturer_id
      LEFT JOIN fs.rate_card rc ON rc.rate_card_id = r.rate_card_id
     WHERE r.id = $1
    `,
    [id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Reservation not found');
  }
  res.json({ reservation: result.rows[0] });
});

// POST /v1/reservations/:id/confirm - confirm a requested or tentative booking
reservationsRouter.post('/:id/confirm', optionalAuth, async (req, res) => {
  const { id } = req.params;

  // Check current reservation
  const existing = await query(
    `
    SELECT r.*, m.status AS member_status, fs.subscription_balance(r.subscription_id) AS balance
      FROM fs.reservations r
      JOIN fs.members m ON m.id = r.member_id
     WHERE r.id = $1
    `,
    [id]
  );

  if (existing.rowCount === 0) {
    throw new HttpError(404, 'Reservation not found');
  }
  const resv = existing.rows[0];

  // 9.2-C17: Tentative booking against Pending member converts at activation
  if (resv.member_status === 'pending') {
    throw new HttpError(
      400,
      '9.2-C17: Member is Pending activation. Tentative reservations convert automatically when member is activated.'
    );
  }

  if (resv.status === 'confirmed') {
    return res.json({ reservation: resv, already_confirmed: true });
  }

  const updated = await withTransaction(async (client) => {
    const up = await client.query(
      `
      UPDATE fs.reservations
         SET status = 'confirmed', is_tentative = false, updated_at = now()
       WHERE id = $1 AND status IN ('requested', 'tentative')
       RETURNING *
      `,
      [id]
    );

    if (up.rowCount === 0) {
      throw new HttpError(409, 'Reservation not in confirmable state');
    }
    const r = up.rows[0];

    // 9.2-C15: Post ledger charge if not already debited
    if (!r.is_courtesy && r.total_points_cost > 0) {
      await client.query(
        `
        INSERT INTO fs.member_points_ledger (
          member_id, points_change,
          source, description, entry_type, occurred_at
        ) VALUES (
          $1, $2, 'Reservation', $3, 'Charge Reservation', now()
        )
        `,
        [
          r.member_id,
          -r.total_points_cost,
          `Reservation ${r.confirmation_code} confirmation charge`,
        ]
      );
    }

    return r;
  });

  res.json({ reservation: updated });
});

// POST /v1/reservations/:id/cancel
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
     WHERE id = $1 AND status IN ('requested','confirmed','tentative')
     RETURNING *
    `,
    [id, body.cancelled_by ?? null, body.reason ?? null]
  );
  if (result.rowCount === 0) {
    throw new HttpError(409, 'Reservation not in a cancellable state');
  }
  res.json({ reservation: result.rows[0] });
});

// POST /v1/reservations/:id/pickup - Connects pickup directly to trip creation (Guide 10.1 & fs.trips)
reservationsRouter.post('/:id/pickup', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    mileage: z.number().int().nonnegative().optional(),
    starting_odometer: z.number().nonnegative().optional(),
    startingOdometer: z.number().nonnegative().optional(),
    fuel_level_pct: z.number().min(0).max(100).default(100).optional(),
    fuel_start_percent: z.number().min(0).max(100).default(100).optional(),
    fuelStartPercent: z.number().min(0).max(100).default(100).optional(),
    condition: z.enum(['excellent', 'good', 'fair', 'needs_attention', 'out_of_service']).default('excellent').optional(),
    member_signature_url: z.string().optional(),
    condition_signature: z.string().optional(),
    conditionSignature: z.string().optional(),
    signature: z.string().optional(),
    pre_existing_damage: z.string().max(2000).optional(),
    handled_by_staff: z.string().uuid().optional(),
    photos_url: z.array(z.string().url()).optional(),
    notes: z.string().max(2000).optional(),
    start_type: z.string().max(20).default('Pickup').optional(),
    startType: z.string().max(20).default('Pickup').optional(),
    start_time_actual: z.string().datetime({ offset: true }).optional(),
    startTimeActual: z.string().datetime({ offset: true }).optional(),
  });
  const data = schema.parse(req.body);
  const startingOdometer = data.starting_odometer ?? data.startingOdometer ?? data.mileage;
  const fuelStartPercent = data.fuel_start_percent ?? data.fuelStartPercent ?? data.fuel_level_pct ?? 100;
  const signatureUrl = data.condition_signature || data.conditionSignature || data.member_signature_url || data.signature || null;

  if (startingOdometer == null) throw new HttpError(400, 'starting_odometer (or mileage) is required');

  const result = await withTransaction(async (client) => {
    const trip = await checkoutTrip(client, {
      reservationId: id,
      startingOdometer,
      fuelStartPercent,
      startTimeActual: data.start_time_actual || data.startTimeActual,
      startType: data.start_type || data.startType || 'Pickup',
      condition: data.condition || 'excellent',
      conditionSignature: signatureUrl,
      preExistingDamage: data.pre_existing_damage,
      photosUrl: data.photos_url,
      notes: data.notes,
      handledByStaff: data.handled_by_staff,
      actorUserId: req.user?.userId || null,
    });

    const resQuery = await client.query('SELECT * FROM fs.reservations WHERE id = $1', [id]);
    return {
      reservation: resQuery.rows[0],
      trip
    };
  });

  res.status(201).json(result);
});

// POST /v1/reservations/:id/return - Connects return directly to trip settlement (Guide 10.2)
reservationsRouter.post('/:id/return', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    mileage: z.number().int().nonnegative().optional(),
    closing_odometer: z.number().nonnegative().optional(),
    closingOdometer: z.number().nonnegative().optional(),
    fuel_level_pct: z.number().min(0).max(100).default(100).optional(),
    fuel_end_percent: z.number().min(0).max(100).default(100).optional(),
    fuelEndPercent: z.number().min(0).max(100).default(100).optional(),
    condition: z.enum(['excellent', 'good', 'fair', 'needs_attention', 'out_of_service']).default('good').optional(),
    member_signature_url: z.string().optional(),
    condition_signature: z.string().optional(),
    conditionSignature: z.string().optional(),
    signature: z.string().optional(),
    new_damage: z.string().max(2000).optional(),
    handled_by_staff: z.string().uuid().optional(),
    photos_url: z.array(z.string().url()).optional(),
    notes: z.string().max(2000).optional(),
    end_type: z.string().max(20).default('Dropoff').optional(),
    endType: z.string().max(20).default('Dropoff').optional(),
    end_time_actual: z.string().datetime({ offset: true }).optional(),
    endTimeActual: z.string().datetime({ offset: true }).optional(),
  });
  const data = schema.parse(req.body);
  const closingOdometer = data.closing_odometer ?? data.closingOdometer ?? data.mileage;
  const fuelEndPercent = data.fuel_end_percent ?? data.fuelEndPercent ?? data.fuel_level_pct ?? 100;
  const signatureUrl = data.condition_signature || data.conditionSignature || data.member_signature_url || data.signature || null;

  if (closingOdometer == null) throw new HttpError(400, 'closing_odometer (or mileage) is required');

  const result = await withTransaction(async (client) => {
    // Find active open trip for this reservation
    const tripLookup = await client.query(
      `SELECT vehicle_trip_id FROM fs.vehicle_trip WHERE vehicle_reservation_id = $1 AND end_time_actual IS NULL`,
      [id]
    );
    if (tripLookup.rowCount === 0) {
      throw new HttpError(404, `No active open trip found for reservation ${id}`);
    }
    const tripId = tripLookup.rows[0].vehicle_trip_id;

    const trip = await checkinTrip(client, {
      tripId,
      closingOdometer,
      fuelEndPercent,
      endTimeActual: data.end_time_actual || data.endTimeActual,
      endType: data.end_type || data.endType || 'Dropoff',
      condition: data.condition || 'good',
      conditionSignature: signatureUrl,
      newDamage: data.new_damage,
      photosUrl: data.photos_url,
      notes: data.notes,
      handledByStaff: data.handled_by_staff,
      actorUserId: req.user?.userId || null,
    });

    const resQuery = await client.query('SELECT * FROM fs.reservations WHERE id = $1', [id]);
    return {
      reservation: resQuery.rows[0],
      trip
    };
  });

  res.json(result);
});

// POST /v1/reservations/:id/checkout - Trip checkout with odometer capture & rate freeze (Guide 10.1)
reservationsRouter.post('/:id/checkout', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    starting_odometer: z.number().nonnegative().optional(),
    startingOdometer: z.number().nonnegative().optional(),
    mileage: z.number().nonnegative().optional(),
    fuel_start_percent: z.number().min(0).max(100).default(100).optional(),
    fuelStartPercent: z.number().min(0).max(100).default(100).optional(),
    fuel_level_pct: z.number().min(0).max(100).default(100).optional(),
    condition: z.enum(['excellent', 'good', 'fair', 'needs_attention', 'out_of_service']).default('excellent').optional(),
    member_signature_url: z.string().optional(),
    condition_signature: z.string().optional(),
    conditionSignature: z.string().optional(),
    signature: z.string().optional(),
    start_time_actual: z.string().datetime({ offset: true }).optional(),
    startTimeActual: z.string().datetime({ offset: true }).optional(),
    start_type: z.string().max(20).default('Pickup').optional(),
    startType: z.string().max(20).default('Pickup').optional(),
    notes: z.string().max(2000).optional(),
    pre_existing_damage: z.string().max(2000).optional(),
    handled_by_staff: z.string().uuid().optional(),
  });
  const data = schema.parse(req.body);
  const startingOdometer = data.starting_odometer ?? data.startingOdometer ?? data.mileage;
  const fuelStartPercent = data.fuel_start_percent ?? data.fuelStartPercent ?? data.fuel_level_pct ?? 100;
  const signatureUrl = data.condition_signature || data.conditionSignature || data.member_signature_url || data.signature || null;

  if (startingOdometer == null) throw new HttpError(400, 'starting_odometer is required');

  const result = await withTransaction(async (client) => {
    return await checkoutTrip(client, {
      reservationId: id,
      startingOdometer,
      fuelStartPercent,
      startTimeActual: data.start_time_actual || data.startTimeActual,
      startType: data.start_type || data.startType || 'Pickup',
      condition: data.condition || 'excellent',
      conditionSignature: signatureUrl,
      preExistingDamage: data.pre_existing_damage,
      notes: data.notes,
      handledByStaff: data.handled_by_staff,
      actorUserId: req.user?.userId || null,
    });
  });

  res.status(201).json({ trip: result });
});

// POST /v1/reservations/:id/checkin - Trip checkin with settlement & ledger debit (Guide 10.2)
reservationsRouter.post('/:id/checkin', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    closing_odometer: z.number().nonnegative().optional(),
    closingOdometer: z.number().nonnegative().optional(),
    mileage: z.number().nonnegative().optional(),
    fuel_end_percent: z.number().min(0).max(100).default(100).optional(),
    fuelEndPercent: z.number().min(0).max(100).default(100).optional(),
    fuel_level_pct: z.number().min(0).max(100).default(100).optional(),
    condition: z.enum(['excellent', 'good', 'fair', 'needs_attention', 'out_of_service']).default('good').optional(),
    member_signature_url: z.string().optional(),
    condition_signature: z.string().optional(),
    conditionSignature: z.string().optional(),
    signature: z.string().optional(),
    end_time_actual: z.string().datetime({ offset: true }).optional(),
    endTimeActual: z.string().datetime({ offset: true }).optional(),
    end_type: z.string().max(20).default('Dropoff').optional(),
    endType: z.string().max(20).default('Dropoff').optional(),
    notes: z.string().max(2000).optional(),
    new_damage: z.string().max(2000).optional(),
    handled_by_staff: z.string().uuid().optional(),
  });
  const data = schema.parse(req.body);
  const closingOdometer = data.closing_odometer ?? data.closingOdometer ?? data.mileage;
  const fuelEndPercent = data.fuel_end_percent ?? data.fuelEndPercent ?? data.fuel_level_pct ?? 100;
  const signatureUrl = data.condition_signature || data.conditionSignature || data.member_signature_url || data.signature || null;

  if (closingOdometer == null) throw new HttpError(400, 'closing_odometer is required');

  const result = await withTransaction(async (client) => {
    // Find active trip for this reservation
    const tripLookup = await client.query(
      `SELECT vehicle_trip_id FROM fs.vehicle_trip WHERE vehicle_reservation_id = $1 AND end_time_actual IS NULL`,
      [id]
    );
    if (tripLookup.rowCount === 0) {
      throw new HttpError(404, `No active open trip found for reservation ${id}`);
    }
    const tripId = tripLookup.rows[0].vehicle_trip_id;

    return await checkinTrip(client, {
      tripId,
      closingOdometer,
      fuelEndPercent,
      endTimeActual: data.end_time_actual || data.endTimeActual,
      endType: data.end_type || data.endType || 'Dropoff',
      condition: data.condition || 'good',
      conditionSignature: signatureUrl,
      newDamage: data.new_damage,
      notes: data.notes,
      handledByStaff: data.handled_by_staff,
      actorUserId: req.user?.userId || null,
    });
  });

  res.json({ trip: result });
});

// GET /v1/reservations/_/upcoming
reservationsRouter.get('/_/upcoming', async (_req, res) => {
  const result = await query(
    `SELECT * FROM fs.v_upcoming_reservations LIMIT 100`
  );
  res.json({ count: result.rowCount, reservations: result.rows });
});

// POST /v1/reservations/_/quote - price prospective booking (9.2-R7, 9.2-R8, 9.2-C10-C13)
reservationsRouter.post('/_/quote', optionalAuth, async (req, res) => {
  const schema = z.object({
    subscription_id: z.string().uuid(),
    vehicle_id: z.string().uuid(),
    pickup_at: z.string().datetime(),
    return_at: z.string().datetime(),
    is_courtesy: z.boolean().default(false),
  });
  const data = schema.parse(req.body);
  const isStaff = req.user?.role === 'staff' || req.user?.role === 'admin';

  // Overlap check
  await checkVehicleOverlap(query, data.vehicle_id, data.pickup_at, data.return_at);

  const ctx = await loadBookingContext({
    vehicleId: data.vehicle_id,
    subscriptionId: data.subscription_id,
  });

  const pricing = await validateBooking(ctx, {
    pickupAt: data.pickup_at,
    returnAt: data.return_at,
    isStaff,
    isCourtesy: data.is_courtesy,
    requestedSubscriptionId: data.subscription_id,
  });

  const reservationToken = signToken(
    {
      type: 'reservation_quote',
      memberId: ctx.member_id,
      subscriptionId: data.subscription_id,
      vehicleId: data.vehicle_id,
      pickupAt: data.pickup_at,
      returnAt: data.return_at,
      isCourtesy: data.is_courtesy,
      days: pricing.totalDays,
      weekdayPoints: pricing.weekdayPoints,
      weekendPoints: pricing.weekendPoints,
      totalCost: pricing.totalPoints,
      rateCardId: pricing.rateCardId,
    },
    { expiresIn: '15m' }
  );

  res.json({
    quote: {
      reservation_token: reservationToken,
      days_booked: pricing.totalDays,
      weekday_days: pricing.weekdayDays,
      weekend_units: pricing.weekendUnits,
      weekday_points: pricing.weekdayPoints,
      weekend_points: pricing.weekendPoints,
      total_points_cost: pricing.totalPoints,
      rate_card_id: pricing.rateCardId,
      rate_card_code: pricing.rateCardCode,
      tier_id: pricing.tierId,
      tier_code: pricing.tierCode,
      tier_name: pricing.tierName,
      season_name: pricing.seasonName,
      is_courtesy: data.is_courtesy,
      has_tier_override: pricing.hasTierOverride,
      has_rate_override: pricing.hasRateOverride,
      balance_before: ctx.balance,
      balance_after_confirm: ctx.balance - pricing.totalPoints,
      expires_in_minutes: 15,
    },
  });
});
