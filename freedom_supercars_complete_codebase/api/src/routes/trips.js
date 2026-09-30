import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import { checkoutTrip, checkinTrip, adjustTripMiles } from '../services/trips.js';

export const tripsRouter = Router();

const checkoutSchema = z.object({
  reservation_id: z.string().uuid().optional(),
  reservationId: z.string().uuid().optional(),
  starting_odometer: z.number().nonnegative().optional(),
  startingOdometer: z.number().nonnegative().optional(),
  mileage: z.number().nonnegative().optional(),
  fuel_start_percent: z.number().min(0).max(100).default(100).optional(),
  fuelStartPercent: z.number().min(0).max(100).default(100).optional(),
  fuel_level_pct: z.number().min(0).max(100).default(100).optional(),
  condition: z.enum(['excellent', 'good', 'fair', 'needs_attention', 'out_of_service']).default('excellent').optional(),
  condition_signature: z.string().optional(),
  conditionSignature: z.string().optional(),
  member_signature_url: z.string().optional(),
  signature: z.string().optional(),
  pre_existing_damage: z.string().max(2000).optional(),
  photos_url: z.array(z.string().url()).optional(),
  notes: z.string().max(2000).optional(),
  handled_by_staff: z.string().uuid().optional(),
  start_time_actual: z.string().datetime({ offset: true }).optional(),
  startTimeActual: z.string().datetime({ offset: true }).optional(),
  start_type: z.string().max(20).default('Pickup').optional(),
  startType: z.string().max(20).default('Pickup').optional(),
});

const checkinSchema = z.object({
  closing_odometer: z.number().nonnegative().optional(),
  closingOdometer: z.number().nonnegative().optional(),
  mileage: z.number().nonnegative().optional(),
  fuel_end_percent: z.number().min(0).max(100).default(100).optional(),
  fuelEndPercent: z.number().min(0).max(100).default(100).optional(),
  fuel_level_pct: z.number().min(0).max(100).default(100).optional(),
  condition: z.enum(['excellent', 'good', 'fair', 'needs_attention', 'out_of_service']).default('good').optional(),
  condition_signature: z.string().optional(),
  conditionSignature: z.string().optional(),
  member_signature_url: z.string().optional(),
  signature: z.string().optional(),
  new_damage: z.string().max(2000).optional(),
  photos_url: z.array(z.string().url()).optional(),
  notes: z.string().max(2000).optional(),
  handled_by_staff: z.string().uuid().optional(),
  end_time_actual: z.string().datetime({ offset: true }).optional(),
  endTimeActual: z.string().datetime({ offset: true }).optional(),
  end_type: z.string().max(20).default('Dropoff').optional(),
  endType: z.string().max(20).default('Dropoff').optional(),
});

const adjustMilesSchema = z.object({
  adjustment_miles: z.number().int().optional(),
  adjustmentMiles: z.number().int().optional(),
  adjustment_reason: z.string().min(3).max(500).optional(),
  adjustmentReason: z.string().min(3).max(500).optional(),
});

/**
 * POST /v1/trips/checkout
 * Opens a trip from a confirmed reservation with odometer capture, condition signature, and pricing snapshot freeze
 */
tripsRouter.post('/checkout', optionalAuth, async (req, res) => {
  const data = checkoutSchema.parse(req.body);
  const reservationId = data.reservation_id || data.reservationId;
  const startingOdometer = data.starting_odometer ?? data.startingOdometer ?? data.mileage;
  const fuelStartPercent = data.fuel_start_percent ?? data.fuelStartPercent ?? data.fuel_level_pct ?? 100;
  const startTimeActual = data.start_time_actual || data.startTimeActual;
  const startType = data.start_type || data.startType || 'Pickup';
  const signatureUrl = data.condition_signature || data.conditionSignature || data.member_signature_url || data.signature || null;

  if (!reservationId) throw new HttpError(400, 'reservation_id is required');
  if (startingOdometer == null) throw new HttpError(400, 'starting_odometer is required');

  const result = await withTransaction(async (client) => {
    return await checkoutTrip(client, {
      reservationId,
      startingOdometer,
      fuelStartPercent,
      startTimeActual,
      startType,
      condition: data.condition || 'excellent',
      conditionSignature: signatureUrl,
      preExistingDamage: data.pre_existing_damage,
      photosUrl: data.photos_url,
      notes: data.notes,
      handledByStaff: data.handled_by_staff,
      actorUserId: req.user?.userId || null,
    });
  });

  res.status(201).json({ trip: result });
});

/**
 * POST /v1/trips/:id/checkin
 * Checks in vehicle, records closing odometer, computes overage & fuel replenishment fees, debits ledger, completes reservation
 */
tripsRouter.post('/:id/checkin', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const data = checkinSchema.parse(req.body);
  const closingOdometer = data.closing_odometer ?? data.closingOdometer ?? data.mileage;
  const fuelEndPercent = data.fuel_end_percent ?? data.fuelEndPercent ?? data.fuel_level_pct ?? 100;
  const endTimeActual = data.end_time_actual || data.endTimeActual;
  const endType = data.end_type || data.endType || 'Dropoff';
  const signatureUrl = data.condition_signature || data.conditionSignature || data.member_signature_url || data.signature || null;

  if (closingOdometer == null) throw new HttpError(400, 'closing_odometer is required');

  const result = await withTransaction(async (client) => {
    return await checkinTrip(client, {
      tripId: id,
      closingOdometer,
      fuelEndPercent,
      endTimeActual,
      endType,
      condition: data.condition || 'good',
      conditionSignature: signatureUrl,
      newDamage: data.new_damage,
      photosUrl: data.photos_url,
      notes: data.notes,
      handledByStaff: data.handled_by_staff,
      actorUserId: req.user?.userId || null,
    });
  });

  res.json({ trip: result });
});

/**
 * POST /v1/trips/:id/adjust-miles
 * Goodwill mileage adjustment recording adjustment with mandatory reason
 */
tripsRouter.post('/:id/adjust-miles', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const data = adjustMilesSchema.parse(req.body);
  const adjustmentMiles = data.adjustment_miles ?? data.adjustmentMiles;
  const adjustmentReason = data.adjustment_reason || data.adjustmentReason;

  if (adjustmentMiles == null) throw new HttpError(400, 'adjustment_miles is required');
  if (!adjustmentReason) throw new HttpError(400, 'adjustment_reason is required');

  const result = await withTransaction(async (client) => {
    return await adjustTripMiles(client, {
      tripId: id,
      adjustmentMiles,
      adjustmentReason,
      actorUserId: req.user?.userId || null,
    });
  });

  res.json({ adjustment: result });
});

/**
 * GET /v1/trips/:id
 * Retrieve trip details, companion member trip details, and odometer log entries
 */
tripsRouter.get('/:id', optionalAuth, async (req, res) => {
  const { id } = req.params;

  const tripRes = await query(
    `SELECT t.*,
            tm.miles_member,
            tm.miles_member_adjustment,
            tm.miles_member_adjustment_reason,
            tm.vehicle_tier_snapshot,
            tm.weekday_point_value_snapshot,
            tm.weekend_point_value_snapshot,
            tm.extra_mile_point_value_snapshot,
            tm.included_miles_snapshot,
            tm.overage_miles_snapshot,
            tm.base_points,
            tm.extra_mileage_points,
            tm.total_points,
            tm.calculation_version,
            tm.calculation_detail,
            vm.model_name as vehicle_model,
            m.name as vehicle_make,
            v.license_plate,
            r.id as reservation_id,
            r.confirmation_code,
            r.member_id
       FROM fs.vehicle_trip t
       LEFT JOIN fs.vehicle_trip_member tm ON tm.vehicle_trip_id = t.vehicle_trip_id
       LEFT JOIN fs.vehicles v ON v.id = t.vehicle_id
       LEFT JOIN fs.vehicle_models vm ON vm.id = v.model_id
       LEFT JOIN fs.manufacturers m ON m.id = vm.manufacturer_id
       LEFT JOIN fs.reservations r ON r.id = t.vehicle_reservation_id
      WHERE t.vehicle_trip_id = $1`,
    [id]
  );

  if (tripRes.rowCount === 0) {
    throw new HttpError(404, `Trip ${id} not found`);
  }

  const trip = tripRes.rows[0];

  // Fetch odometer logs
  let odoLogs = [];
  const logIds = [trip.odometer_start_id, trip.odometer_end_id].filter(Boolean);
  if (logIds.length > 0) {
    const odoRes = await query(
      `SELECT * FROM fs.vehicle_odometer_log WHERE vehicle_odometer_id = ANY($1::uuid[])`,
      [logIds]
    );
    odoLogs = odoRes.rows;
  }

  res.json({
    trip: {
      ...trip,
      odometer_logs: odoLogs,
    },
  });
});

/**
 * GET /v1/trips
 * List trips with optional filtering by vehicle, reservation, member, or status
 */
tripsRouter.get('/', optionalAuth, async (req, res) => {
  const { reservation_id, vehicle_id, member_id, status, limit = 50, offset = 0 } = req.query;

  const conditions = [];
  const params = [];
  let paramIdx = 1;

  if (reservation_id) {
    conditions.push(`t.vehicle_reservation_id = $${paramIdx++}`);
    params.push(reservation_id);
  }
  if (vehicle_id) {
    conditions.push(`t.vehicle_id = $${paramIdx++}`);
    params.push(vehicle_id);
  }
  if (member_id) {
    conditions.push(`r.member_id = $${paramIdx++}`);
    params.push(member_id);
  }
  if (status === 'open') {
    conditions.push(`t.end_time_actual IS NULL`);
  } else if (status === 'completed') {
    conditions.push(`t.end_time_actual IS NOT NULL`);
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  params.push(Math.min(100, Math.max(1, Number(limit))));
  const limitIdx = paramIdx++;
  params.push(Math.max(0, Number(offset)));
  const offsetIdx = paramIdx++;

  const listQuery = `
    SELECT t.*,
           tm.miles_member,
           tm.overage_miles_snapshot as overage_miles,
           tm.extra_mileage_points,
           tm.total_points,
           vm.model_name as vehicle_model,
           m.name as vehicle_make,
           r.confirmation_code,
           r.member_id
      FROM fs.vehicle_trip t
      LEFT JOIN fs.vehicle_trip_member tm ON tm.vehicle_trip_id = t.vehicle_trip_id
      LEFT JOIN fs.vehicles v ON v.id = t.vehicle_id
      LEFT JOIN fs.vehicle_models vm ON vm.id = v.model_id
      LEFT JOIN fs.manufacturers m ON m.id = vm.manufacturer_id
      LEFT JOIN fs.reservations r ON r.id = t.vehicle_reservation_id
     ${whereClause}
     ORDER BY t.start_time_actual DESC NULLS LAST
     LIMIT $${limitIdx} OFFSET $${offsetIdx}
  `;

  const results = await query(listQuery, params);
  res.json({ trips: results.rows, count: results.rowCount });
});
