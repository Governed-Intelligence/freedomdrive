import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import { resolveTripPrice } from '../services/rateResolver.js';

export const rateCardsRouter = Router();

// GET /v1/rate-cards - list rate cards
rateCardsRouter.get('/', async (_req, res) => {
  const result = await query(`
    SELECT rc.rate_card_id,
           rc.card_code,
           rc.card_name,
           rc.description,
           rc.first_used_on,
           (rc.first_used_on IS NOT NULL) AS is_frozen,
           rc.created_at,
           COUNT(DISTINCT rcr.rate_card_rate_id)::int AS rates_count,
           COUNT(DISTINCT rcp.rate_card_placement_id)::int AS placements_count,
           COUNT(DISTINCT rcs.rate_card_season_id)::int AS seasons_count
      FROM fs.rate_card rc
      LEFT JOIN fs.rate_card_rate rcr ON rcr.rate_card_id = rc.rate_card_id
      LEFT JOIN fs.rate_card_placement rcp ON rcp.rate_card_id = rc.rate_card_id
      LEFT JOIN fs.rate_card_season rcs ON rcs.rate_card_id = rc.rate_card_id
     GROUP BY rc.rate_card_id
     ORDER BY rc.first_used_on DESC NULLS LAST, rc.created_at DESC
  `);
  res.json({ rate_cards: result.rows });
});

// POST /v1/rate-cards - create new draft rate card (7.6-C01)
rateCardsRouter.post('/', optionalAuth, async (req, res) => {
  const schema = z.object({
    card_code: z.string().min(2).max(20),
    card_name: z.string().min(2).max(100),
    description: z.string().optional(),
    first_used_on: z.string().date().optional(),
  });
  const data = schema.parse(req.body);

  const existing = await query(`SELECT 1 FROM fs.rate_card WHERE card_code = $1`, [data.card_code]);
  if (existing.rowCount > 0) {
    throw new HttpError(409, `Rate card code ${data.card_code} already exists`);
  }

  const result = await query(
    `
    INSERT INTO fs.rate_card (card_code, card_name, description, first_used_on)
    VALUES ($1, $2, $3, $4)
    RETURNING *
    `,
    [data.card_code, data.card_name, data.description ?? null, data.first_used_on ?? null]
  );
  res.status(201).json({ rate_card: result.rows[0] });
});

// GET /v1/rate-cards/:id - get rate card with all rates, placements, and seasons
rateCardsRouter.get('/:id', async (req, res) => {
  const { id } = req.params;

  const cardRes = await query(`SELECT * FROM fs.rate_card WHERE rate_card_id = $1`, [id]);
  if (cardRes.rowCount === 0) {
    throw new HttpError(404, 'Rate card not found');
  }
  const card = cardRes.rows[0];

  const ratesRes = await query(
    `
    SELECT rcr.*,
           vt.vehicle_tier,
           vt.vehicle_tier_name,
           vt.sort_order AS tier_sort_order,
           rcs.season_name
      FROM fs.rate_card_rate rcr
      JOIN fs.vehicle_tier vt ON vt.vehicle_tier_id = rcr.vehicle_tier_id
      LEFT JOIN fs.rate_card_season rcs ON rcs.rate_card_season_id = rcr.rate_card_season_id
     WHERE rcr.rate_card_id = $1
     ORDER BY vt.sort_order ASC, rcs.season_name ASC NULLS FIRST
    `,
    [id]
  );

  const placementsRes = await query(
    `
    SELECT rcp.*,
           v.id AS vehicle_id,
           mf.name || ' ' || vm.model_name AS vehicle_display,
           v.stock_number,
           vt.vehicle_tier,
           vt.vehicle_tier_name
      FROM fs.rate_card_placement rcp
      JOIN fs.vehicles v ON v.id = rcp.vehicle_id
      JOIN fs.vehicle_models vm ON vm.id = v.model_id
      JOIN fs.manufacturers mf ON mf.id = vm.manufacturer_id
      JOIN fs.vehicle_tier vt ON vt.vehicle_tier_id = rcp.vehicle_tier_id
     WHERE rcp.rate_card_id = $1
     ORDER BY v.stock_number ASC
    `,
    [id]
  );

  const seasonsRes = await query(
    `SELECT * FROM fs.rate_card_season WHERE rate_card_id = $1 ORDER BY start_month, start_day`,
    [id]
  );

  res.json({
    rate_card: {
      ...card,
      is_frozen: card.first_used_on != null,
      rates: ratesRes.rows,
      placements: placementsRes.rows,
      seasons: seasonsRes.rows,
    },
  });
});

// POST /v1/rate-cards/:id/freeze - freeze a card (7.6-C02)
rateCardsRouter.post('/:id/freeze', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    first_used_on: z.string().date().optional(),
  });
  const data = schema.parse(req.body ?? {});

  const firstUsed = data.first_used_on ?? new Date().toISOString().split('T')[0];
  const result = await query(
    `UPDATE fs.rate_card SET first_used_on = $1 WHERE rate_card_id = $2 RETURNING *`,
    [firstUsed, id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Rate card not found');
  }
  res.json({ rate_card: result.rows[0], message: '7.6-C02: Rate card is now frozen.' });
});

// POST /v1/rate-cards/:id/copy - copy card into new editable draft (7.6-C08)
rateCardsRouter.post('/:id/copy', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    new_card_code: z.string().min(2).max(20),
    new_card_name: z.string().min(2).max(100),
    description: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const newCard = await withTransaction(async (client) => {
    // 1. Create new draft card (first_used_on = NULL)
    const insCard = await client.query(
      `
      INSERT INTO fs.rate_card (card_code, card_name, description, first_used_on)
      VALUES ($1, $2, $3, NULL)
      RETURNING *
      `,
      [data.new_card_code, data.new_card_name, data.description ?? null]
    );
    const cardRow = insCard.rows[0];

    // 2. Copy rates
    await client.query(
      `
      INSERT INTO fs.rate_card_rate (rate_card_id, vehicle_tier_id, rate_card_season_id, weekday_point_value, weekend_point_value, extra_mile_point_value)
      SELECT $1, vehicle_tier_id, rate_card_season_id, weekday_point_value, weekend_point_value, extra_mile_point_value
        FROM fs.rate_card_rate
       WHERE rate_card_id = $2
      `,
      [cardRow.rate_card_id, id]
    );

    // 3. Copy placements
    await client.query(
      `
      INSERT INTO fs.rate_card_placement (rate_card_id, vehicle_id, vehicle_tier_id, effective_from)
      SELECT $1, vehicle_id, vehicle_tier_id, now()::date
        FROM fs.rate_card_placement
       WHERE rate_card_id = $2
      `,
      [cardRow.rate_card_id, id]
    );

    return cardRow;
  });

  res.status(201).json({ rate_card: newCard, message: '7.6-C08: Card copied successfully. Rates and placements are editable.' });
});

// POST /v1/rate-cards/:id/rates - add rate row (7.6-C05)
rateCardsRouter.post('/:id/rates', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    vehicle_tier_id: z.string().uuid(),
    rate_card_season_id: z.string().uuid().optional(),
    weekday_point_value: z.number().int().positive(),
    weekend_point_value: z.number().int().positive(),
    extra_mile_point_value: z.number().positive().default(1.0),
  });
  const data = schema.parse(req.body);

  try {
    const result = await query(
      `
      INSERT INTO fs.rate_card_rate (rate_card_id, vehicle_tier_id, rate_card_season_id, weekday_point_value, weekend_point_value, extra_mile_point_value)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
      `,
      [id, data.vehicle_tier_id, data.rate_card_season_id ?? null, data.weekday_point_value, data.weekend_point_value, data.extra_mile_point_value]
    );
    res.status(201).json({ rate: result.rows[0] });
  } catch (err) {
    if (err.code === '23505') {
      throw new HttpError(409, 'Rate row already exists for this tier and season on this card');
    }
    throw err;
  }
});

// PATCH /v1/rate-cards/:id/rates/:rateId - edit rate row (refused by DB trigger if card used 7.6-C03)
rateCardsRouter.patch('/:id/rates/:rateId', optionalAuth, async (req, res) => {
  const { id, rateId } = req.params;
  const schema = z.object({
    weekday_point_value: z.number().int().positive().optional(),
    weekend_point_value: z.number().int().positive().optional(),
    extra_mile_point_value: z.number().positive().optional(),
  });
  const data = schema.parse(req.body);

  try {
    const result = await query(
      `
      UPDATE fs.rate_card_rate
         SET weekday_point_value = COALESCE($1, weekday_point_value),
             weekend_point_value = COALESCE($2, weekend_point_value),
             extra_mile_point_value = COALESCE($3, extra_mile_point_value),
             updated_at = now()
       WHERE rate_card_rate_id = $4 AND rate_card_id = $5
       RETURNING *
      `,
      [data.weekday_point_value ?? null, data.weekend_point_value ?? null, data.extra_mile_point_value ?? null, rateId, id]
    );
    if (result.rowCount === 0) {
      throw new HttpError(404, 'Rate row not found');
    }
    res.json({ rate: result.rows[0] });
  } catch (err) {
    // 7.6-C03: DB trigger error translation
    if (err.message && err.message.includes('7.6-R02 / 7.6-C03')) {
      throw new HttpError(409, '7.6-C03: An edit to an existing rate on a used card is refused. Copy the card instead.');
    }
    throw err;
  }
});

// POST /v1/rate-cards/:id/placements - add vehicle placement (7.6-C04, 7.7-C04)
rateCardsRouter.post('/:id/placements', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    vehicle_id: z.string().uuid(),
    vehicle_tier_id: z.string().uuid(),
    effective_from: z.string().date().optional(),
  });
  const data = schema.parse(req.body);

  try {
    const result = await query(
      `
      INSERT INTO fs.rate_card_placement (rate_card_id, vehicle_id, vehicle_tier_id, effective_from)
      VALUES ($1, $2, $3, COALESCE($4::date, now()::date))
      RETURNING *
      `,
      [id, data.vehicle_id, data.vehicle_tier_id, data.effective_from ?? null]
    );
    res.status(201).json({ placement: result.rows[0] });
  } catch (err) {
    // 7.6-C06 / 7.7-C05: Duplicate placement on same card refused
    if (err.code === '23505' || (err.message && err.message.includes('uq_rate_card_placement_card_vehicle'))) {
      throw new HttpError(409, '7.6-C06 / 7.7-C05: A second placement for the same vehicle on the same card is refused');
    }
    throw err;
  }
});

// PATCH /v1/rate-cards/:id/placements/:placementId - edit placement (refused by DB trigger if card used 7.6-C07, 7.7-C03)
rateCardsRouter.patch('/:id/placements/:placementId', optionalAuth, async (req, res) => {
  const { id, placementId } = req.params;
  const schema = z.object({
    vehicle_tier_id: z.string().uuid().optional(),
    effective_to: z.string().date().optional(),
  });
  const data = schema.parse(req.body);

  try {
    const result = await query(
      `
      UPDATE fs.rate_card_placement
         SET vehicle_tier_id = COALESCE($1, vehicle_tier_id),
             effective_to = COALESCE($2::date, effective_to),
             updated_at = now()
       WHERE rate_card_placement_id = $3 AND rate_card_id = $4
       RETURNING *
      `,
      [data.vehicle_tier_id ?? null, data.effective_to ?? null, placementId, id]
    );
    if (result.rowCount === 0) {
      throw new HttpError(404, 'Placement not found');
    }
    res.json({ placement: result.rows[0] });
  } catch (err) {
    if (err.message && err.message.includes('7.6-C07 / 7.7-C03')) {
      throw new HttpError(409, '7.6-C07 / 7.7-C03: Editing, closing, or superseding an existing placement on a card in use is refused.');
    }
    throw err;
  }
});

// POST /v1/rate-cards/resolve - run 5-step resolver directly (7.7-C09, 7.7-C10)
rateCardsRouter.post('/resolve', async (req, res) => {
  const schema = z.object({
    member_id: z.string().uuid().optional(),
    subscription_id: z.string().uuid().optional(),
    vehicle_id: z.string().uuid(),
    pickup_at: z.string().datetime(),
    return_at: z.string().datetime(),
    is_courtesy: z.boolean().default(false),
  });
  const data = schema.parse(req.body);

  const pricing = await resolveTripPrice({
    memberId: data.member_id,
    subscriptionId: data.subscription_id,
    vehicleId: data.vehicle_id,
    pickupAt: data.pickup_at,
    returnAt: data.return_at,
    isCourtesy: data.is_courtesy,
  });

  res.json({ pricing });
});

// POST /v1/rate-cards/overrides/tier - set member tier override (7.7-C11)
rateCardsRouter.post('/overrides/tier', optionalAuth, async (req, res) => {
  const schema = z.object({
    member_id: z.string().uuid(),
    vehicle_id: z.string().uuid(),
    vehicle_tier_id_override: z.string().uuid(),
    notes: z.string().optional(),
  });
  const data = schema.parse(req.body);

  // Ensure customization parent exists
  let mpc = await query(
    `SELECT member_package_customization_id FROM fs.member_package_customization WHERE member_id = $1 LIMIT 1`,
    [data.member_id]
  );
  let customizationId;
  if (mpc.rowCount === 0) {
    const ins = await query(
      `INSERT INTO fs.member_package_customization (member_id, label, is_active) VALUES ($1, 'Member Customization', true) RETURNING member_package_customization_id`,
      [data.member_id]
    );
    customizationId = ins.rows[0].member_package_customization_id;
  } else {
    customizationId = mpc.rows[0].member_package_customization_id;
  }

  const result = await query(
    `
    INSERT INTO fs.mpc_tier_assignment (member_package_customization_id, vehicle_id, vehicle_tier_id_override, notes)
    VALUES ($1, $2, $3, $4)
    RETURNING *
    `,
    [customizationId, data.vehicle_id, data.vehicle_tier_id_override, data.notes ?? null]
  );
  res.status(201).json({ tier_override: result.rows[0] });
});

// POST /v1/rate-cards/overrides/rate - set member point rate override (7.7-C12)
rateCardsRouter.post('/overrides/rate', optionalAuth, async (req, res) => {
  const schema = z.object({
    member_id: z.string().uuid(),
    vehicle_tier_id: z.string().uuid(),
    weekday_point_value_override: z.number().int().positive().optional(),
    weekend_point_value_override: z.number().int().positive().optional(),
    extra_mile_point_value_override: z.number().positive().optional(),
    notes: z.string().optional(),
  });
  const data = schema.parse(req.body);

  let mpc = await query(
    `SELECT member_package_customization_id FROM fs.member_package_customization WHERE member_id = $1 LIMIT 1`,
    [data.member_id]
  );
  let customizationId;
  if (mpc.rowCount === 0) {
    const ins = await query(
      `INSERT INTO fs.member_package_customization (member_id, label, is_active) VALUES ($1, 'Member Customization', true) RETURNING member_package_customization_id`,
      [data.member_id]
    );
    customizationId = ins.rows[0].member_package_customization_id;
  } else {
    customizationId = mpc.rows[0].member_package_customization_id;
  }

  const result = await query(
    `
    INSERT INTO fs.mpc_tier_point_rate (
      member_package_customization_id, vehicle_tier_id,
      weekday_point_value_override, weekend_point_value_override, extra_mile_point_value_override, notes
    ) VALUES ($1, $2, $3, $4, $5, $6)
    RETURNING *
    `,
    [
      customizationId,
      data.vehicle_tier_id,
      data.weekday_point_value_override ?? null,
      data.weekend_point_value_override ?? null,
      data.extra_mile_point_value_override ?? null,
      data.notes ?? null,
    ]
  );
  res.status(201).json({ rate_override: result.rows[0] });
});
