import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import {
  checkoutTrip,
  checkinTrip,
  adjustTripMiles,
  getStoryPrompts,
  getTripStory,
  upsertTripStory,
  saveStoryAnswers,
  checkoutServiceTrip,
  checkinServiceTrip,
  updateServiceTripCost,
  listServiceTrips,
} from '../services/trips.js';
import { billTripTolls } from '../services/tolls.js';

export const tripsRouter = Router();

// =============================================================================
// SCHEMAS
// =============================================================================

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

// Guide 10.3: Trip Stories Schemas
const storyAnswerItemSchema = z.object({
  prompt_id: z.string().uuid().optional(),
  promptId: z.string().uuid().optional(),
  answer_text: z.string().max(5000).optional(),
  answerText: z.string().max(5000).optional(),
  assisted_text: z.string().max(5000).optional(),
  assistedText: z.string().max(5000).optional(),
  uses_assisted: z.boolean().default(false).optional(),
  usesAssisted: z.boolean().default(false).optional(),
});

const storyUpsertSchema = z.object({
  story_title: z.string().max(200).optional(),
  storyTitle: z.string().max(200).optional(),
  introduction: z.string().max(5000).optional(),
  cover_document_id: z.string().uuid().optional(),
  coverDocumentId: z.string().uuid().optional(),
  cover_photo_url: z.string().url().optional(),
  coverPhotoUrl: z.string().url().optional(),
  visibility: z.enum(['private', 'members', 'public']).default('members').optional(),
  answers: z.array(storyAnswerItemSchema).default([]).optional(),
});

const storyAnswersBatchSchema = z.object({
  prompt_id: z.string().uuid().optional(),
  promptId: z.string().uuid().optional(),
  answer_text: z.string().max(5000).optional(),
  answerText: z.string().max(5000).optional(),
  assisted_text: z.string().max(5000).optional(),
  assistedText: z.string().max(5000).optional(),
  uses_assisted: z.boolean().default(false).optional(),
  usesAssisted: z.boolean().default(false).optional(),
  answers: z.array(storyAnswerItemSchema).optional(),
});

// Guide 10.4: Service Trips Schemas
const serviceCheckoutSchema = z.object({
  vehicle_id: z.string().uuid().optional(),
  vehicleId: z.string().uuid().optional(),
  vendor_id: z.string().uuid().optional(),
  vendorId: z.string().uuid().optional(),
  starting_odometer: z.number().nonnegative().optional(),
  startingOdometer: z.number().nonnegative().optional(),
  mileage: z.number().nonnegative().optional(),
  service_category_code: z.string().max(40).default('maintenance').optional(),
  serviceCategoryCode: z.string().max(40).default('maintenance').optional(),
  service_type_code: z.string().max(40).default('scheduled').optional(),
  serviceTypeCode: z.string().max(40).default('scheduled').optional(),
  service_reason_code: z.string().max(40).default('oil_change').optional(),
  serviceReasonCode: z.string().max(40).default('oil_change').optional(),
  service_notes: z.string().max(5000).optional(),
  serviceNotes: z.string().max(5000).optional(),
  notes: z.string().max(5000).optional(),
  fuel_start_percent: z.number().min(0).max(100).default(100).optional(),
  fuelStartPercent: z.number().min(0).max(100).default(100).optional(),
  start_time_actual: z.string().datetime({ offset: true }).optional(),
  startTimeActual: z.string().datetime({ offset: true }).optional(),
});

const serviceCheckinSchema = z.object({
  closing_odometer: z.number().nonnegative().optional(),
  closingOdometer: z.number().nonnegative().optional(),
  mileage: z.number().nonnegative().optional(),
  fuel_end_percent: z.number().min(0).max(100).default(100).optional(),
  fuelEndPercent: z.number().min(0).max(100).default(100).optional(),
  end_time_actual: z.string().datetime({ offset: true }).optional(),
  endTimeActual: z.string().datetime({ offset: true }).optional(),
  service_cost: z.number().nonnegative().optional(),
  serviceCost: z.number().nonnegative().optional(),
  warranty_claim_reference: z.string().max(60).optional(),
  warrantyClaimReference: z.string().max(60).optional(),
  service_notes: z.string().max(5000).optional(),
  serviceNotes: z.string().max(5000).optional(),
  notes: z.string().max(5000).optional(),
});

const serviceCostSchema = z.object({
  service_cost: z.number().nonnegative().optional(),
  serviceCost: z.number().nonnegative().optional(),
  warranty_claim_reference: z.string().max(60).optional(),
  warrantyClaimReference: z.string().max(60).optional(),
  billed_member_id: z.string().uuid().optional(),
  billedMemberId: z.string().uuid().optional(),
  billed_vehicle_partner_id: z.string().uuid().optional(),
  billedVehiclePartnerId: z.string().uuid().optional(),
  billed_amount: z.number().nonnegative().optional(),
  billedAmount: z.number().nonnegative().optional(),
  service_notes: z.string().max(5000).optional(),
  serviceNotes: z.string().max(5000).optional(),
  notes: z.string().max(5000).optional(),
});

// =============================================================================
// GUIDE 10.3: STORY PROMPTS (MUST BE BEFORE /:id ROUTE)
// =============================================================================

/**
 * GET /v1/trips/stories/prompts
 * Returns active story prompts in sort_order
 */
tripsRouter.get('/stories/prompts', optionalAuth, async (req, res) => {
  const result = await withTransaction(async (client) => {
    return await getStoryPrompts(client);
  });
  res.json({ prompts: result });
});

// =============================================================================
// GUIDE 10.4: SERVICE TRIPS (MUST BE BEFORE /:id ROUTE)
// =============================================================================

/**
 * POST /v1/trips/service/checkout
 * Dispatches vehicle on vendor maintenance/repair service trip
 */
tripsRouter.post('/service/checkout', optionalAuth, async (req, res) => {
  const data = serviceCheckoutSchema.parse(req.body);
  const vehicleId = data.vehicle_id || data.vehicleId;
  const startingOdometer = data.starting_odometer ?? data.startingOdometer ?? data.mileage;
  const vendorId = data.vendor_id || data.vendorId || null;
  const serviceCategoryCode = data.service_category_code || data.serviceCategoryCode || 'maintenance';
  const serviceTypeCode = data.service_type_code || data.serviceTypeCode || 'scheduled';
  const serviceReasonCode = data.service_reason_code || data.serviceReasonCode || 'oil_change';
  const serviceNotes = data.service_notes || data.serviceNotes || data.notes || null;
  const fuelStartPercent = data.fuel_start_percent ?? data.fuelStartPercent ?? 100;
  const startTimeActual = data.start_time_actual || data.startTimeActual || null;

  if (!vehicleId) throw new HttpError(400, 'vehicle_id is required');
  if (startingOdometer == null) throw new HttpError(400, 'starting_odometer is required');

  const result = await withTransaction(async (client) => {
    return await checkoutServiceTrip(client, {
      vehicleId,
      vendorId,
      startingOdometer,
      serviceCategoryCode,
      serviceTypeCode,
      serviceReasonCode,
      serviceNotes,
      fuelStartPercent,
      startTimeActual,
      actorUserId: req.user?.userId || null,
    });
  });

  res.status(201).json({ service_trip: result });
});

/**
 * GET /v1/trips/service
 * List service trips
 */
tripsRouter.get('/service', optionalAuth, async (req, res) => {
  const { vehicle_id, vendor_id, status, limit, offset } = req.query;

  const result = await withTransaction(async (client) => {
    return await listServiceTrips(client, {
      vehicleId: vehicle_id || null,
      vendorId: vendor_id || null,
      status: status || null,
      limit: limit ? Number(limit) : 50,
      offset: offset ? Number(offset) : 0,
    });
  });

  res.json(result);
});

/**
 * POST /v1/trips/service/:id/checkin
 * Closes service trip, logs closing odometer, isolates service miles from member allowances
 */
tripsRouter.post('/service/:id/checkin', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const data = serviceCheckinSchema.parse(req.body);
  const closingOdometer = data.closing_odometer ?? data.closingOdometer ?? data.mileage;
  const fuelEndPercent = data.fuel_end_percent ?? data.fuelEndPercent ?? 100;
  const endTimeActual = data.end_time_actual || data.endTimeActual || null;
  const serviceCost = data.service_cost ?? data.serviceCost ?? null;
  const warrantyClaimReference = data.warranty_claim_reference || data.warrantyClaimReference || null;
  const serviceNotes = data.service_notes || data.serviceNotes || data.notes || null;

  if (closingOdometer == null) throw new HttpError(400, 'closing_odometer is required');

  const result = await withTransaction(async (client) => {
    return await checkinServiceTrip(client, {
      tripId: id,
      closingOdometer,
      fuelEndPercent,
      endTimeActual,
      serviceCost,
      warrantyClaimReference,
      serviceNotes,
      actorUserId: req.user?.userId || null,
    });
  });

  res.json({ service_trip: result });
});

/**
 * PATCH /v1/trips/service/:id/cost
 * Records service cost, warranty claim, and handles split/partner billing (Rule 10.4-R07)
 */
tripsRouter.patch('/service/:id/cost', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const data = serviceCostSchema.parse(req.body);
  const serviceCost = data.service_cost ?? data.serviceCost ?? null;
  const warrantyClaimReference = data.warranty_claim_reference || data.warrantyClaimReference || null;
  const billedMemberId = data.billed_member_id || data.billedMemberId || null;
  const billedVehiclePartnerId = data.billed_vehicle_partner_id || data.billedVehiclePartnerId || null;
  const billedAmount = data.billed_amount ?? data.billedAmount ?? null;
  const serviceNotes = data.service_notes || data.serviceNotes || data.notes || null;

  const result = await withTransaction(async (client) => {
    return await updateServiceTripCost(client, {
      tripId: id,
      serviceCost,
      warrantyClaimReference,
      billedMemberId,
      billedVehiclePartnerId,
      billedAmount,
      serviceNotes,
      actorUserId: req.user?.userId || null,
    });
  });

  res.json({ service_trip: result });
});

// =============================================================================
// GUIDE 10.1 & 10.2: MEMBER TRIPS CHECKOUT & CHECKIN
// =============================================================================

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

// =============================================================================
// GUIDE 10.3: TRIP STORIES (INDIVIDUAL TRIP)
// =============================================================================

/**
 * GET /v1/trips/:id/story
 * Retrieves the story and prompts/answers for a completed trip
 */
tripsRouter.get('/:id/story', optionalAuth, async (req, res) => {
  const { id } = req.params;

  const result = await withTransaction(async (client) => {
    return await getTripStory(client, {
      tripId: id,
      memberId: req.user?.memberId || null,
      isStaff: req.user?.role === 'staff' || req.user?.role === 'admin',
    });
  });

  if (!result) {
    return res.status(404).json({ message: `No story created yet for trip ${id}`, story: null });
  }

  res.json({ story: result });
});

/**
 * POST /v1/trips/:id/story
 * Creates or updates the story header and answers for a completed trip
 */
tripsRouter.post('/:id/story', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const data = storyUpsertSchema.parse(req.body);

  const result = await withTransaction(async (client) => {
    return await upsertTripStory(client, {
      tripId: id,
      storyTitle: data.story_title || data.storyTitle || null,
      introduction: data.introduction || null,
      coverDocumentId: data.cover_document_id || data.coverDocumentId || null,
      coverPhotoUrl: data.cover_photo_url || data.coverPhotoUrl || null,
      visibility: data.visibility || 'members',
      answers: data.answers || [],
      memberId: req.user?.memberId || null,
      actorUserId: req.user?.userId || null,
    });
  });

  res.status(201).json({ story: result });
});

/**
 * POST /v1/trips/:id/story/answers
 * Autosaves one or more story answers
 */
tripsRouter.post('/:id/story/answers', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const body = req.body;

  let answerList = [];
  if (Array.isArray(body)) {
    answerList = body;
  } else if (Array.isArray(body.answers)) {
    answerList = body.answers;
  } else if (body.prompt_id || body.promptId) {
    answerList = [body];
  } else {
    throw new HttpError(400, 'answers array or prompt_id answer object is required');
  }

  const result = await withTransaction(async (client) => {
    return await saveStoryAnswers(client, {
      tripId: id,
      answers: answerList,
      memberId: req.user?.memberId || null,
      actorUserId: req.user?.userId || null,
    });
  });

  res.json(result);
});

// =============================================================================
// GUIDE 10.5: TOLL RECHARGING FOR A TRIP
// =============================================================================

/**
 * POST /v1/trips/:id/tolls/bill
 * Recharges all matched tolls on this trip as a single aggregate member charge
 */
tripsRouter.post('/:id/tolls/bill', optionalAuth, async (req, res) => {
  const { id } = req.params;

  const result = await withTransaction(async (client) => {
    return await billTripTolls(client, {
      tripId: id,
      actorUserId: req.user?.userId || null,
    });
  });

  res.json(result);
});

// =============================================================================
// CORE TRIP RETRIEVAL & LISTING
// =============================================================================

/**
 * GET /v1/trips/:id
 * Retrieve trip details, companion member/service details, and odometer log entries
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
            ts.vendor_id as service_vendor_id,
            ts.service_category_code,
            ts.service_type_code,
            ts.service_reason_code,
            ts.service_cost,
            ts.billed_amount as service_billed_amount,
            ts.warranty_claim_reference,
            vm.model_name as vehicle_model,
            m.name as vehicle_make,
            v.license_plate,
            r.id as reservation_id,
            r.confirmation_code,
            r.member_id
       FROM fs.vehicle_trip t
       LEFT JOIN fs.vehicle_trip_member tm ON tm.vehicle_trip_id = t.vehicle_trip_id
       LEFT JOIN fs.vehicle_trip_service ts ON ts.vehicle_trip_id = t.vehicle_trip_id
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
 * List trips with optional filtering by vehicle, reservation, member, trip_type, or status
 */
tripsRouter.get('/', optionalAuth, async (req, res) => {
  const { reservation_id, vehicle_id, member_id, trip_type, status, limit = 50, offset = 0 } = req.query;

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
    conditions.push(`(r.member_id = $${paramIdx} OR tm.member_id = $${paramIdx++})`);
    params.push(member_id);
  }
  if (trip_type) {
    conditions.push(`t.trip_type_code = $${paramIdx++}`);
    params.push(trip_type);
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
           COALESCE(tm.member_id, r.member_id) as member_id
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
