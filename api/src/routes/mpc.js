import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';

export const mpcRouter = Router();

// Validation Schemas
const createCustomizationSchema = z.object({
  member_id: z.string().uuid(),
  label: z.string().max(120),
  effective_package_mode: z.enum([
    'First Year (Period)',
    'Current Year (Period)',
    'Every Year (Period)',
    'Custom',
  ]).default('Current Year (Period)'),
  package_start_number: z.number().int().optional(),
  package_end_number: z.number().int().optional(),
  effective_from: z.string().optional(),
  effective_to: z.string().optional(),
  is_active: z.boolean().default(true),
  overrides_json: z.record(z.any()).optional(),
  created_by_user_id: z.string().uuid().optional(),
});

// GET /v1/mpc/customizations — list customizations with optional filters
mpcRouter.get('/customizations', async (req, res) => {
  const { member_id, is_active } = req.query;
  const clauses = [];
  const values = [];

  if (member_id) {
    values.push(member_id);
    clauses.push(`member_id = $${values.length}`);
  }
  if (is_active !== undefined) {
    values.push(is_active === 'true');
    clauses.push(`is_active = $${values.length}`);
  }

  const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
  const sql = `
    SELECT *
      FROM fs.member_package_customization
     ${where}
     ORDER BY created_at DESC
  `;
  const result = await query(sql, values);
  res.json({ count: result.rowCount, customizations: result.rows });
});

// GET /v1/mpc/customizations/:id — get customization with all associated child overrides
mpcRouter.get('/customizations/:id', async (req, res) => {
  const { id } = req.params;
  const headerRes = await query(
    `SELECT * FROM fs.member_package_customization WHERE member_package_customization_id = $1`,
    [id]
  );
  if (headerRes.rowCount === 0) {
    throw new HttpError(404, 'Member package customization not found');
  }

  const customization = headerRes.rows[0];
  const memberId = customization.member_id;

  // Fetch overrides concurrently
  const [
    pricingRes,
    pointsRes,
    bookingsRes,
    mileageRes,
    perksRes,
    branchRes,
    tierAccessRes,
    tierAssignRes,
    tierRateRes,
    freePassRes,
  ] = await Promise.all([
    query(`SELECT * FROM fs.mpc_pricing WHERE member_id = $1 ORDER BY created_at DESC`, [memberId]),
    query(`SELECT * FROM fs.mpc_points_and_caps WHERE member_id = $1 ORDER BY created_at DESC`, [memberId]),
    query(`SELECT * FROM fs.mpc_bookings WHERE member_id = $1 ORDER BY created_at DESC`, [memberId]),
    query(`SELECT * FROM fs.mpc_mileage WHERE member_id = $1 ORDER BY created_at DESC`, [memberId]),
    query(`SELECT * FROM fs.mpc_perks WHERE member_id = $1 ORDER BY created_at DESC`, [memberId]),
    query(`SELECT * FROM fs.mpc_branch_access WHERE member_package_customization_id = $1`, [id]),
    query(`SELECT * FROM fs.mpc_vehicle_tier_access WHERE member_package_customization_id = $1`, [id]),
    query(`SELECT * FROM fs.mpc_tier_assignment WHERE member_package_customization_id = $1`, [id]),
    query(`SELECT * FROM fs.mpc_tier_point_rate WHERE member_package_customization_id = $1`, [id]),
    query(`SELECT * FROM fs.mpc_free_pass WHERE mpc_id = $1`, [id]),
  ]);

  res.json({
    customization,
    overrides: {
      pricing: pricingRes.rows,
      points_and_caps: pointsRes.rows,
      bookings: bookingsRes.rows,
      mileage: mileageRes.rows,
      perks: perksRes.rows,
      branch_access: branchRes.rows,
      tier_access: tierAccessRes.rows,
      tier_assignments: tierAssignRes.rows,
      tier_point_rates: tierRateRes.rows,
      free_passes: freePassRes.rows,
    },
  });
});

// POST /v1/mpc/customizations — create new package customization header
mpcRouter.post('/customizations', async (req, res) => {
  const body = createCustomizationSchema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.member_package_customization (
      member_id, label, effective_package_mode,
      package_start_number, package_end_number,
      effective_from, effective_to, is_active,
      overrides_json, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    RETURNING *
    `,
    [
      body.member_id,
      body.label,
      body.effective_package_mode,
      body.package_start_number ?? null,
      body.package_end_number ?? null,
      body.effective_from ?? null,
      body.effective_to ?? null,
      body.is_active,
      body.overrides_json ? JSON.stringify(body.overrides_json) : null,
      body.created_by_user_id ?? null,
    ]
  );
  res.status(201).json({ customization: result.rows[0] });
});

// PUT /v1/mpc/customizations/:id — update customization header
mpcRouter.put('/customizations/:id', async (req, res) => {
  const { id } = req.params;
  const updates = req.body;

  const allowed = [
    'label',
    'effective_package_mode',
    'package_start_number',
    'package_end_number',
    'effective_from',
    'effective_to',
    'is_active',
    'overrides_json',
    'updated_by_user_id',
  ];

  const clauses = [];
  const values = [];

  for (const [key, val] of Object.entries(updates)) {
    if (allowed.includes(key)) {
      values.push(key === 'overrides_json' && typeof val === 'object' ? JSON.stringify(val) : val);
      clauses.push(`${key} = $${values.length}`);
    }
  }

  if (clauses.length === 0) {
    throw new HttpError(400, 'No valid fields provided for update');
  }

  clauses.push('updated_at = now()');
  values.push(id);

  const sql = `
    UPDATE fs.member_package_customization
       SET ${clauses.join(', ')}
     WHERE member_package_customization_id = $${values.length}
 RETURNING *
  `;

  const result = await query(sql, values);
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Member package customization not found');
  }
  res.json({ customization: result.rows[0] });
});

// DELETE /v1/mpc/customizations/:id — soft-deactivate customization header
mpcRouter.delete('/customizations/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `UPDATE fs.member_package_customization SET is_active = false, updated_at = now() WHERE member_package_customization_id = $1 RETURNING *`,
    [id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Member package customization not found');
  }
  res.json({ success: true, message: 'Customization deactivated', customization: result.rows[0] });
});

// POST /v1/mpc/pricing — append immutable pricing override
mpcRouter.post('/pricing', async (req, res) => {
  const schema = z.object({
    member_id: z.string().uuid(),
    membership_level_id: z.string().uuid().optional(),
    pricing_type: z.string().max(40),
    override_value: z.number(),
    notes: z.string().optional(),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.mpc_pricing (
      member_id, membership_level_id, pricing_type,
      override_value, notes, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6)
    RETURNING *
    `,
    [b.member_id, b.membership_level_id ?? null, b.pricing_type, b.override_value, b.notes ?? null, b.created_by_user_id ?? null]
  );
  res.status(201).json({ pricing: result.rows[0] });
});

// POST /v1/mpc/points-and-caps — append points/cap override
mpcRouter.post('/points-and-caps', async (req, res) => {
  const schema = z.object({
    member_id: z.string().uuid(),
    membership_level_id: z.string().uuid().optional(),
    points_cap_type: z.string().max(40),
    add_value: z.number().int().optional(),
    set_value: z.string().max(20).optional(),
    notes: z.string().optional(),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.mpc_points_and_caps (
      member_id, membership_level_id, points_cap_type,
      add_value, set_value, notes, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6, $7)
    RETURNING *
    `,
    [b.member_id, b.membership_level_id ?? null, b.points_cap_type, b.add_value ?? null, b.set_value ?? null, b.notes ?? null, b.created_by_user_id ?? null]
  );
  res.status(201).json({ points_and_caps: result.rows[0] });
});

// POST /v1/mpc/bookings — append booking override
mpcRouter.post('/bookings', async (req, res) => {
  const schema = z.object({
    member_id: z.string().uuid(),
    membership_level_id: z.string().uuid().optional(),
    booking_type: z.string().max(40),
    add_value: z.number().int(),
    notes: z.string().optional(),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.mpc_bookings (
      member_id, membership_level_id, booking_type,
      add_value, notes, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6)
    RETURNING *
    `,
    [b.member_id, b.membership_level_id ?? null, b.booking_type, b.add_value, b.notes ?? null, b.created_by_user_id ?? null]
  );
  res.status(201).json({ bookings: result.rows[0] });
});

// POST /v1/mpc/mileage — append mileage override
mpcRouter.post('/mileage', async (req, res) => {
  const schema = z.object({
    member_id: z.string().uuid(),
    membership_level_id: z.string().uuid().optional(),
    mileage_type: z.string().max(40),
    override_value: z.number().int(),
    notes: z.string().optional(),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.mpc_mileage (
      member_id, membership_level_id, mileage_type,
      override_value, notes, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6)
    RETURNING *
    `,
    [b.member_id, b.membership_level_id ?? null, b.mileage_type, b.override_value, b.notes ?? null, b.created_by_user_id ?? null]
  );
  res.status(201).json({ mileage: result.rows[0] });
});

// POST /v1/mpc/perks — append perk override
mpcRouter.post('/perks', async (req, res) => {
  const schema = z.object({
    member_id: z.string().uuid(),
    membership_level_id: z.string().uuid().optional(),
    perk_type: z.string().max(40),
    add_value: z.number().int(),
    notes: z.string().optional(),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.mpc_perks (
      member_id, membership_level_id, perk_type,
      add_value, notes, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6)
    RETURNING *
    `,
    [b.member_id, b.membership_level_id ?? null, b.perk_type, b.add_value, b.notes ?? null, b.created_by_user_id ?? null]
  );
  res.status(201).json({ perks: result.rows[0] });
});

// POST /v1/mpc/branch-access — grant or revoke branch access override
mpcRouter.post('/branch-access', async (req, res) => {
  const schema = z.object({
    member_package_customization_id: z.string().uuid(),
    branch_id: z.string().uuid(),
    action: z.enum(['Add', 'Remove']),
    granted_at: z.string().optional(),
    granted_by_user_id: z.string().uuid().optional(),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.mpc_branch_access (
      member_package_customization_id, branch_id, action,
      granted_at, granted_by_user_id, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6)
    RETURNING *
    `,
    [
      b.member_package_customization_id,
      b.branch_id,
      b.action,
      b.granted_at ?? new Date().toISOString(),
      b.granted_by_user_id ?? null,
      b.created_by_user_id ?? null,
    ]
  );
  res.status(201).json({ branch_access: result.rows[0] });
});

// POST /v1/mpc/tier-access — grant or revoke tier access override
mpcRouter.post('/tier-access', async (req, res) => {
  const schema = z.object({
    member_package_customization_id: z.string().uuid(),
    vehicle_tier_id: z.string().uuid(),
    action: z.enum(['Add', 'Remove']),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.mpc_vehicle_tier_access (
      member_package_customization_id, vehicle_tier_id, action,
      created_by_user_id
    ) VALUES ($1, $2, $3, $4)
    RETURNING *
    `,
    [b.member_package_customization_id, b.vehicle_tier_id, b.action, b.created_by_user_id ?? null]
  );
  res.status(201).json({ tier_access: result.rows[0] });
});

// POST /v1/mpc/tier-assignment — specific vehicle tier re-tiering
mpcRouter.post('/tier-assignment', async (req, res) => {
  const schema = z.object({
    member_package_customization_id: z.string().uuid(),
    vehicle_id: z.string().uuid(),
    vehicle_tier_id_override: z.string().uuid(),
    notes: z.string().optional(),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.mpc_tier_assignment (
      member_package_customization_id, vehicle_id,
      vehicle_tier_id_override, notes, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5)
    RETURNING *
    `,
    [b.member_package_customization_id, b.vehicle_id, b.vehicle_tier_id_override, b.notes ?? null, b.created_by_user_id ?? null]
  );
  res.status(201).json({ tier_assignment: result.rows[0] });
});

// POST /v1/mpc/tier-point-rate — override tier point values
mpcRouter.post('/tier-point-rate', async (req, res) => {
  const schema = z.object({
    member_package_customization_id: z.string().uuid(),
    vehicle_tier_id: z.string().uuid(),
    weekday_point_value_override: z.number().int().optional(),
    weekend_point_value_override: z.number().int().optional(),
    extra_mile_point_value_override: z.number().optional(),
    notes: z.string().optional(),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.mpc_tier_point_rate (
      member_package_customization_id, vehicle_tier_id,
      weekday_point_value_override, weekend_point_value_override,
      extra_mile_point_value_override, notes, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6, $7)
    RETURNING *
    `,
    [
      b.member_package_customization_id,
      b.vehicle_tier_id,
      b.weekday_point_value_override ?? null,
      b.weekend_point_value_override ?? null,
      b.extra_mile_point_value_override ?? null,
      b.notes ?? null,
      b.created_by_user_id ?? null,
    ]
  );
  res.status(201).json({ tier_point_rate: result.rows[0] });
});

// POST /v1/mpc/free-pass — override free pass rules
mpcRouter.post('/free-pass', async (req, res) => {
  const schema = z.object({
    mpc_id: z.string().uuid(),
    free_pass_total_qty_override: z.number().int().optional(),
    tier_max_id_override: z.string().uuid().optional(),
    book_hours_before_reservation_override: z.number().int().optional(),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.mpc_free_pass (
      mpc_id, free_pass_total_qty_override,
      tier_max_id_override, book_hours_before_reservation_override,
      created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5)
    RETURNING *
    `,
    [
      b.mpc_id,
      b.free_pass_total_qty_override ?? null,
      b.tier_max_id_override ?? null,
      b.book_hours_before_reservation_override ?? null,
      b.created_by_user_id ?? null,
    ]
  );
  res.status(201).json({ free_pass: result.rows[0] });
});

// =============================================================================
// DELETE OVERRIDES (Single items by ID)
// =============================================================================

// DELETE /v1/mpc/pricing/:id
mpcRouter.delete('/pricing/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(`DELETE FROM fs.mpc_pricing WHERE mpc_pricing_id = $1 RETURNING *`, [id]);
  if (result.rowCount === 0) throw new HttpError(404, 'MPC pricing override not found');
  res.json({ success: true, message: 'Pricing override deleted', pricing: result.rows[0] });
});

// DELETE /v1/mpc/points-and-caps/:id
mpcRouter.delete('/points-and-caps/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(`DELETE FROM fs.mpc_points_and_caps WHERE mpc_points_and_caps_id = $1 RETURNING *`, [id]);
  if (result.rowCount === 0) throw new HttpError(404, 'MPC points and caps override not found');
  res.json({ success: true, message: 'Points and caps override deleted', points_and_caps: result.rows[0] });
});

// DELETE /v1/mpc/bookings/:id
mpcRouter.delete('/bookings/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(`DELETE FROM fs.mpc_bookings WHERE mpc_bookings_id = $1 RETURNING *`, [id]);
  if (result.rowCount === 0) throw new HttpError(404, 'MPC booking override not found');
  res.json({ success: true, message: 'Booking override deleted', bookings: result.rows[0] });
});

// DELETE /v1/mpc/mileage/:id
mpcRouter.delete('/mileage/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(`DELETE FROM fs.mpc_mileage WHERE mpc_mileage_id = $1 RETURNING *`, [id]);
  if (result.rowCount === 0) throw new HttpError(404, 'MPC mileage override not found');
  res.json({ success: true, message: 'Mileage override deleted', mileage: result.rows[0] });
});

// DELETE /v1/mpc/perks/:id
mpcRouter.delete('/perks/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(`DELETE FROM fs.mpc_perks WHERE mpc_perks_id = $1 RETURNING *`, [id]);
  if (result.rowCount === 0) throw new HttpError(404, 'MPC perk override not found');
  res.json({ success: true, message: 'Perk override deleted', perks: result.rows[0] });
});

// DELETE /v1/mpc/branch-access/:id
mpcRouter.delete('/branch-access/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(`DELETE FROM fs.mpc_branch_access WHERE mpc_branch_access_id = $1 RETURNING *`, [id]);
  if (result.rowCount === 0) throw new HttpError(404, 'MPC branch access override not found');
  res.json({ success: true, message: 'Branch access override deleted', branch_access: result.rows[0] });
});

// DELETE /v1/mpc/tier-access/:id
mpcRouter.delete('/tier-access/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(`DELETE FROM fs.mpc_vehicle_tier_access WHERE mpc_vehicle_tier_access_id = $1 RETURNING *`, [id]);
  if (result.rowCount === 0) throw new HttpError(404, 'MPC tier access override not found');
  res.json({ success: true, message: 'Tier access override deleted', tier_access: result.rows[0] });
});

// DELETE /v1/mpc/tier-assignment/:id
mpcRouter.delete('/tier-assignment/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(`DELETE FROM fs.mpc_tier_assignment WHERE mpc_tier_assignment_id = $1 RETURNING *`, [id]);
  if (result.rowCount === 0) throw new HttpError(404, 'MPC tier assignment override not found');
  res.json({ success: true, message: 'Tier assignment override deleted', tier_assignment: result.rows[0] });
});

// DELETE /v1/mpc/tier-point-rate/:id
mpcRouter.delete('/tier-point-rate/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(`DELETE FROM fs.mpc_tier_point_rate WHERE mpc_tier_point_rate_id = $1 RETURNING *`, [id]);
  if (result.rowCount === 0) throw new HttpError(404, 'MPC tier point rate override not found');
  res.json({ success: true, message: 'Tier point rate override deleted', tier_point_rate: result.rows[0] });
});

// DELETE /v1/mpc/free-pass/:id
mpcRouter.delete('/free-pass/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(`DELETE FROM fs.mpc_free_pass WHERE mpc_free_pass_id = $1 RETURNING *`, [id]);
  if (result.rowCount === 0) throw new HttpError(404, 'MPC free pass override not found');
  res.json({ success: true, message: 'Free pass override deleted', free_pass: result.rows[0] });
});

