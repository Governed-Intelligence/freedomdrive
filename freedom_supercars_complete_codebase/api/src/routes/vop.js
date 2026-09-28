import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';

export const vopRouter = Router();

// =============================================================================
// 1. VEHICLE PARTNERS & CONTACTS
// =============================================================================

// GET /v1/vop/partners — list consignment partners
vopRouter.get('/partners', async (req, res) => {
  const { is_active } = req.query;
  const clauses = [];
  const values = [];

  if (is_active !== undefined) {
    values.push(is_active === 'true');
    clauses.push(`is_active = $${values.length}`);
  }

  const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
  const result = await query(
    `SELECT * FROM fs.vehicle_partner ${where} ORDER BY business_name ASC`,
    values
  );
  res.json({ count: result.rowCount, partners: result.rows });
});

// GET /v1/vop/partners/:id — get single partner with contacts
vopRouter.get('/partners/:id', async (req, res) => {
  const { id } = req.params;
  const pRes = await query(
    `SELECT * FROM fs.vehicle_partner WHERE vehicle_partner_id = $1`,
    [id]
  );
  if (pRes.rowCount === 0) {
    throw new HttpError(404, 'Vehicle partner not found');
  }

  const cRes = await query(
    `SELECT * FROM fs.vehicle_partner_contact WHERE vehicle_partner_id = $1 ORDER BY is_primary DESC, contact_name ASC`,
    [id]
  );

  res.json({
    partner: pRes.rows[0],
    contacts: cRes.rows,
  });
});

// POST /v1/vop/partners — create new consignment partner
vopRouter.post('/partners', async (req, res) => {
  const schema = z.object({
    business_name: z.string().max(120),
    address_line1: z.string().max(200).optional(),
    address_line2: z.string().max(100).optional(),
    city: z.string().max(100).optional(),
    state: z.string().max(2).optional(),
    postal_code: z.string().max(10).optional(),
    partner_tax_id: z.string().max(20).optional(),
    is_active: z.boolean().default(true),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.vehicle_partner (
      business_name, address_line1, address_line2,
      city, state, postal_code, partner_tax_id,
      is_active, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    RETURNING *
    `,
    [
      b.business_name,
      b.address_line1 ?? null,
      b.address_line2 ?? null,
      b.city ?? null,
      b.state ?? null,
      b.postal_code ?? null,
      b.partner_tax_id ?? null,
      b.is_active,
      b.created_by_user_id ?? null,
    ]
  );
  res.status(201).json({ partner: result.rows[0] });
});

// PUT /v1/vop/partners/:id — update consignment partner
vopRouter.put('/partners/:id', async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    business_name: z.string().max(120).optional(),
    address_line1: z.string().max(200).nullable().optional(),
    address_line2: z.string().max(100).nullable().optional(),
    city: z.string().max(100).nullable().optional(),
    state: z.string().max(2).nullable().optional(),
    postal_code: z.string().max(10).nullable().optional(),
    partner_tax_id: z.string().max(20).nullable().optional(),
    is_active: z.boolean().optional(),
    updated_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const clauses = [];
  const values = [];

  for (const [key, val] of Object.entries(b)) {
    if (val !== undefined) {
      values.push(val);
      clauses.push(`${key} = $${values.length}`);
    }
  }

  if (clauses.length === 0) {
    throw new HttpError(400, 'No fields provided for update');
  }

  clauses.push('updated_at = now()');
  values.push(id);

  const result = await query(
    `UPDATE fs.vehicle_partner SET ${clauses.join(', ')} WHERE vehicle_partner_id = $${values.length} RETURNING *`,
    values
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Vehicle partner not found');
  }
  res.json({ partner: result.rows[0] });
});

// DELETE /v1/vop/partners/:id — soft-deactivate partner (per Chapter 16: "Neither a partner nor a plan is ever deleted")
vopRouter.delete('/partners/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `UPDATE fs.vehicle_partner SET is_active = false, updated_at = now() WHERE vehicle_partner_id = $1 RETURNING *`,
    [id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Vehicle partner not found');
  }
  res.json({
    success: true,
    message: 'Partner deactivated (partners are never deleted per audit rules)',
    partner: result.rows[0],
  });
});

// POST /v1/vop/partners/:id/contacts — add contact to partner
vopRouter.post('/partners/:id/contacts', async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    contact_name: z.string().max(120),
    preferred_name: z.string().max(80).optional(),
    contact_role: z.string().max(80).optional(),
    contact_phone: z.string().max(20).optional(),
    contact_phone_type: z.enum([
      'Home', 'Work', 'Mobile', 'Assistant', 'Family', 'Emergency', 'Other'
    ]).default('Mobile'),
    contact_email: z.string().email().optional(),
    is_primary: z.boolean().default(false),
    contact_active: z.boolean().default(true),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);

  // If this contact is set as primary, demote any existing primary contact for this partner
  if (b.is_primary) {
    await query(
      `UPDATE fs.vehicle_partner_contact SET is_primary = false, updated_at = now() WHERE vehicle_partner_id = $1`,
      [id]
    );
  }

  const result = await query(
    `
    INSERT INTO fs.vehicle_partner_contact (
      vehicle_partner_id, contact_name, preferred_name,
      contact_role, contact_phone, contact_phone_type,
      contact_email, is_primary, contact_active,
      created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    RETURNING *
    `,
    [
      id,
      b.contact_name,
      b.preferred_name ?? null,
      b.contact_role ?? null,
      b.contact_phone ?? null,
      b.contact_phone_type,
      b.contact_email ?? null,
      b.is_primary,
      b.contact_active,
      b.created_by_user_id ?? null,
    ]
  );
  res.status(201).json({ contact: result.rows[0] });
});

// PUT /v1/vop/partners/:id/contacts/:contactId — update partner contact
vopRouter.put('/partners/:id/contacts/:contactId', async (req, res) => {
  const { id, contactId } = req.params;
  const schema = z.object({
    contact_name: z.string().max(120).optional(),
    preferred_name: z.string().max(80).nullable().optional(),
    contact_role: z.string().max(80).nullable().optional(),
    contact_phone: z.string().max(20).nullable().optional(),
    contact_phone_type: z.enum([
      'Home', 'Work', 'Mobile', 'Assistant', 'Family', 'Emergency', 'Other'
    ]).optional(),
    contact_email: z.string().email().nullable().optional(),
    is_primary: z.boolean().optional(),
    contact_active: z.boolean().optional(),
    updated_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);

  const contactRes = await query(
    `SELECT * FROM fs.vehicle_partner_contact WHERE vehicle_partner_id = $1 AND vehicle_partner_contact_id = $2`,
    [id, contactId]
  );
  if (contactRes.rowCount === 0) {
    throw new HttpError(404, 'Partner contact not found');
  }
  const current = contactRes.rows[0];

  // If deactivating primary contact or demoting primary, ensure another active primary exists
  if (current.is_primary && (b.contact_active === false || b.is_primary === false)) {
    const otherPrimary = await query(
      `SELECT 1 FROM fs.vehicle_partner_contact WHERE vehicle_partner_id = $1 AND vehicle_partner_contact_id != $2 AND is_primary = true AND contact_active = true`,
      [id, contactId]
    );
    if (otherPrimary.rowCount === 0) {
      throw new HttpError(400, 'Cannot deactivate or demote the primary contact without promoting another contact to primary');
    }
  }

  // Promoting to primary demotes previous primary in same write
  if (b.is_primary === true) {
    await query(
      `UPDATE fs.vehicle_partner_contact SET is_primary = false, updated_at = now() WHERE vehicle_partner_id = $1 AND vehicle_partner_contact_id != $2`,
      [id, contactId]
    );
  }

  const clauses = [];
  const values = [];
  for (const [key, val] of Object.entries(b)) {
    if (val !== undefined) {
      values.push(val);
      clauses.push(`${key} = $${values.length}`);
    }
  }

  if (clauses.length === 0) {
    throw new HttpError(400, 'No fields provided for update');
  }

  clauses.push('updated_at = now()');
  values.push(contactId);

  const result = await query(
    `UPDATE fs.vehicle_partner_contact SET ${clauses.join(', ')} WHERE vehicle_partner_contact_id = $${values.length} RETURNING *`,
    values
  );
  res.json({ contact: result.rows[0] });
});

// DELETE /v1/vop/partners/:id/contacts/:contactId — soft-deactivate contact
vopRouter.delete('/partners/:id/contacts/:contactId', async (req, res) => {
  const { id, contactId } = req.params;
  const contactRes = await query(
    `SELECT * FROM fs.vehicle_partner_contact WHERE vehicle_partner_id = $1 AND vehicle_partner_contact_id = $2`,
    [id, contactId]
  );
  if (contactRes.rowCount === 0) {
    throw new HttpError(404, 'Partner contact not found');
  }
  if (contactRes.rows[0].is_primary) {
    const otherPrimary = await query(
      `SELECT 1 FROM fs.vehicle_partner_contact WHERE vehicle_partner_id = $1 AND vehicle_partner_contact_id != $2 AND is_primary = true AND contact_active = true`,
      [id, contactId]
    );
    if (otherPrimary.rowCount === 0) {
      throw new HttpError(400, 'Cannot deactivate the primary contact without promoting another contact to primary');
    }
  }

  const result = await query(
    `UPDATE fs.vehicle_partner_contact SET contact_active = false, updated_at = now() WHERE vehicle_partner_contact_id = $1 RETURNING *`,
    [contactId]
  );
  res.json({ success: true, message: 'Contact deactivated', contact: result.rows[0] });
});

// =============================================================================
// 2. VOP PLANS
// =============================================================================

// GET /v1/vop/plans (or /contracts) — list plans with filters
vopRouter.get(['/plans', '/contracts'], async (req, res) => {
  const { vehicle_id, vehicle_partner_id, status } = req.query;
  const clauses = [];
  const values = [];

  if (vehicle_id) {
    values.push(vehicle_id);
    clauses.push(`p.vehicle_id = $${values.length}`);
  }
  if (vehicle_partner_id) {
    values.push(vehicle_partner_id);
    clauses.push(`p.vehicle_partner_id = $${values.length}`);
  }
  if (status) {
    values.push(status);
    clauses.push(`p.status = $${values.length}`);
  }

  const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
  const result = await query(
    `
    SELECT p.*,
           vp.business_name AS partner_name
      FROM fs.vop_plan p
      LEFT JOIN fs.vehicle_partner vp ON vp.vehicle_partner_id = p.vehicle_partner_id
     ${where}
     ORDER BY p.effective_from DESC
    `,
    values
  );
  res.json({ count: result.rowCount, plans: result.rows, contracts: result.rows });
});

// GET /v1/vop/plans/:id (or /contracts/:id) — single plan details
vopRouter.get(['/plans/:id', '/contracts/:id'], async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `
    SELECT p.*,
           vp.business_name AS partner_name
      FROM fs.vop_plan p
      LEFT JOIN fs.vehicle_partner vp ON vp.vehicle_partner_id = p.vehicle_partner_id
     WHERE p.vop_plan_id = $1
    `,
    [id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'VOP plan not found');
  }
  res.json({ plan: result.rows[0], contract: result.rows[0] });
});

// POST /v1/vop/plans (or /contracts) — create VOP plan
vopRouter.post(['/plans', '/contracts'], async (req, res) => {
  const schema = z.object({
    vehicle_id: z.string().uuid(),
    vehicle_partner_id: z.string().uuid(),
    base_fee_amount: z.number().int().default(0),
    per_mile_rate: z.number().default(0),
    owner_plan_fee: z.number().int().default(0),
    minimum_amount_per_period: z.number().int().default(0),
    exclude_vop_miles_flag: z.boolean().default(false),
    effective_from: z.string().optional(),
    effective_to: z.string().optional(),
    notes: z.string().optional(),
    status: z.enum(['Active', 'Pending', 'Suspended', 'Ended']).default('Active'),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.vop_plan (
      vehicle_id, vehicle_partner_id, base_fee_amount,
      per_mile_rate, owner_plan_fee, minimum_amount_per_period,
      exclude_vop_miles_flag, effective_from, effective_to,
      notes, status, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
    RETURNING *
    `,
    [
      b.vehicle_id,
      b.vehicle_partner_id,
      b.base_fee_amount,
      b.per_mile_rate,
      b.owner_plan_fee,
      b.minimum_amount_per_period,
      b.exclude_vop_miles_flag,
      b.effective_from ?? null,
      b.effective_to ?? null,
      b.notes ?? null,
      b.status,
      b.created_by_user_id ?? null,
    ]
  );
  res.status(201).json({ plan: result.rows[0], contract: result.rows[0] });
});

// PUT /v1/vop/plans/:id (or /contracts/:id) — update VOP plan
vopRouter.put(['/plans/:id', '/contracts/:id'], async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    base_fee_amount: z.number().int().optional(),
    per_mile_rate: z.number().optional(),
    owner_plan_fee: z.number().int().optional(),
    minimum_amount_per_period: z.number().int().optional(),
    exclude_vop_miles_flag: z.boolean().optional(),
    effective_from: z.string().optional(),
    effective_to: z.string().nullable().optional(),
    notes: z.string().nullable().optional(),
    status: z.enum(['Active', 'Pending', 'Suspended', 'Ended']).optional(),
    updated_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const clauses = [];
  const values = [];

  for (const [key, val] of Object.entries(b)) {
    if (val !== undefined) {
      values.push(val);
      clauses.push(`${key} = $${values.length}`);
    }
  }

  if (clauses.length === 0) {
    throw new HttpError(400, 'No fields provided for update');
  }

  clauses.push('updated_at = now()');
  values.push(id);

  const result = await query(
    `UPDATE fs.vop_plan SET ${clauses.join(', ')} WHERE vop_plan_id = $${values.length} RETURNING *`,
    values
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'VOP plan not found');
  }
  res.json({ plan: result.rows[0], contract: result.rows[0] });
});

// DELETE /v1/vop/plans/:id (or /contracts/:id) — soft-end plan (per Chapter 16: "Neither a partner nor a plan is ever deleted")
vopRouter.delete(['/plans/:id', '/contracts/:id'], async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `
    UPDATE fs.vop_plan
       SET status = 'Ended',
           effective_to = COALESCE(effective_to, CURRENT_DATE),
           updated_at = now()
     WHERE vop_plan_id = $1
    RETURNING *
    `,
    [id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'VOP plan not found');
  }
  res.json({
    success: true,
    message: 'Plan ended (plans are never deleted per audit rules)',
    plan: result.rows[0],
  });
});

// =============================================================================
// 3. GUARANTEE GROUPS
// =============================================================================

// GET /v1/vop/guarantee-groups (or /guarantee_groups) — list guarantee groups with optional filters
vopRouter.get(['/guarantee-groups', '/guarantee_groups'], async (req, res) => {
  const { vehicle_partner_id, is_active } = req.query;
  const clauses = [];
  const values = [];

  if (vehicle_partner_id) {
    values.push(vehicle_partner_id);
    clauses.push(`g.vehicle_partner_id = $${values.length}`);
  }
  if (is_active !== undefined) {
    values.push(is_active === 'true');
    clauses.push(`g.is_active = $${values.length}`);
  }

  const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
  const result = await query(
    `
    SELECT g.*,
           vp.business_name AS partner_name,
           (SELECT COUNT(*)::int FROM fs.vop_guarantee_group_plan gp
             WHERE gp.vop_guarantee_group_id = g.vop_guarantee_group_id
               AND (gp.effective_to IS NULL OR gp.effective_to >= CURRENT_DATE)) AS active_plan_count
      FROM fs.vop_guarantee_group g
      LEFT JOIN fs.vehicle_partner vp ON vp.vehicle_partner_id = g.vehicle_partner_id
     ${where}
     ORDER BY g.created_at DESC
    `,
    values
  );
  res.json({ count: result.rowCount, guarantee_groups: result.rows });
});

// GET /v1/vop/guarantee-groups/:id (or /guarantee_groups/:id) — get single guarantee group with plans
vopRouter.get(['/guarantee-groups/:id', '/guarantee_groups/:id'], async (req, res) => {
  const { id } = req.params;
  const gRes = await query(
    `
    SELECT g.*, vp.business_name AS partner_name
      FROM fs.vop_guarantee_group g
      LEFT JOIN fs.vehicle_partner vp ON vp.vehicle_partner_id = g.vehicle_partner_id
     WHERE g.vop_guarantee_group_id = $1
    `,
    [id]
  );
  if (gRes.rowCount === 0) {
    throw new HttpError(404, 'Guarantee group not found');
  }

  const plansRes = await query(
    `
    SELECT gp.*,
           p.base_fee_amount,
           p.minimum_amount_per_period,
           p.status AS plan_status,
           v.vehicle_id,
           v.make,
           v.model,
           v.year
      FROM fs.vop_guarantee_group_plan gp
      JOIN fs.vop_plan p ON p.vop_plan_id = gp.vop_plan_id
      LEFT JOIN fs.vehicle v ON v.vehicle_id = p.vehicle_id
     WHERE gp.vop_guarantee_group_id = $1
     ORDER BY gp.effective_from DESC, gp.created_at DESC
    `,
    [id]
  );

  res.json({
    guarantee_group: gRes.rows[0],
    plans: plansRes.rows,
  });
});

// POST /v1/vop/guarantee-groups (or /guarantee_groups) — create guarantee group
vopRouter.post(['/guarantee-groups', '/guarantee_groups'], async (req, res) => {
  const schema = z.object({
    vehicle_partner_id: z.string().uuid(),
    group_name: z.string().max(120),
    effective_from: z.string().optional(),
    effective_to: z.string().optional(),
    is_active: z.boolean().default(true),
    notes: z.string().optional(),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.vop_guarantee_group (
      vehicle_partner_id, group_name, effective_from,
      effective_to, is_active, notes, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6, $7)
    RETURNING *
    `,
    [
      b.vehicle_partner_id,
      b.group_name,
      b.effective_from ?? null,
      b.effective_to ?? null,
      b.is_active,
      b.notes ?? null,
      b.created_by_user_id ?? null,
    ]
  );
  res.status(201).json({ guarantee_group: result.rows[0] });
});

// PUT /v1/vop/guarantee-groups/:id (or /guarantee_groups/:id) — update guarantee group
vopRouter.put(['/guarantee-groups/:id', '/guarantee_groups/:id'], async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    group_name: z.string().max(120).optional(),
    effective_from: z.string().nullable().optional(),
    effective_to: z.string().nullable().optional(),
    is_active: z.boolean().optional(),
    notes: z.string().nullable().optional(),
    updated_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const clauses = [];
  const values = [];

  for (const [key, val] of Object.entries(b)) {
    if (val !== undefined) {
      values.push(val);
      clauses.push(`${key} = $${values.length}`);
    }
  }

  if (clauses.length === 0) {
    throw new HttpError(400, 'No fields provided for update');
  }

  clauses.push('updated_at = now()');
  values.push(id);

  const result = await query(
    `UPDATE fs.vop_guarantee_group SET ${clauses.join(', ')} WHERE vop_guarantee_group_id = $${values.length} RETURNING *`,
    values
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Guarantee group not found');
  }
  res.json({ guarantee_group: result.rows[0] });
});

// DELETE /v1/vop/guarantee-groups/:id (or /guarantee_groups/:id) — soft-deactivate guarantee group
vopRouter.delete(['/guarantee-groups/:id', '/guarantee_groups/:id'], async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `
    UPDATE fs.vop_guarantee_group
       SET is_active = false,
           effective_to = COALESCE(effective_to, CURRENT_DATE),
           updated_at = now()
     WHERE vop_guarantee_group_id = $1
    RETURNING *
    `,
    [id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Guarantee group not found');
  }
  res.json({ success: true, message: 'Guarantee group deactivated', guarantee_group: result.rows[0] });
});

// POST /v1/vop/guarantee-groups/:id/deactivate (or /guarantee_groups/:id/deactivate) — explicit deactivate action
vopRouter.post(['/guarantee-groups/:id/deactivate', '/guarantee_groups/:id/deactivate'], async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `
    UPDATE fs.vop_guarantee_group
       SET is_active = false,
           effective_to = COALESCE(effective_to, CURRENT_DATE),
           updated_at = now()
     WHERE vop_guarantee_group_id = $1
    RETURNING *
    `,
    [id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Guarantee group not found');
  }
  res.json({ success: true, message: 'Guarantee group deactivated', guarantee_group: result.rows[0] });
});

// POST /v1/vop/guarantee-groups/:id/plans (or contracts) — add plan to guarantee group
vopRouter.post(
  [
    '/guarantee-groups/:id/plans',
    '/guarantee_groups/:id/plans',
    '/guarantee-groups/:id/contracts',
    '/guarantee_groups/:id/contracts',
  ],
  async (req, res) => {
    const { id } = req.params;
    const planId = req.body.vop_plan_id || req.body.plan_id || req.body.contract_id;
    if (!planId) {
      throw new HttpError(400, 'vop_plan_id or contract_id is required');
    }

    const effective_from = req.body.effective_from;
    const effective_to = req.body.effective_to;
    const created_by_user_id = req.body.created_by_user_id;

    // Verify group exists
    const gRes = await query(`SELECT * FROM fs.vop_guarantee_group WHERE vop_guarantee_group_id = $1`, [id]);
    if (gRes.rowCount === 0) {
      throw new HttpError(404, 'Guarantee group not found');
    }

    // Verify plan exists
    const pRes = await query(`SELECT * FROM fs.vop_plan WHERE vop_plan_id = $1`, [planId]);
    if (pRes.rowCount === 0) {
      throw new HttpError(404, 'VOP plan / contract not found');
    }

    // Chapter 16 Rule: "A plan belongs to at most one guarantee group at a time."
    // Close any active memberships across any guarantee groups for this plan
    await query(
      `
      UPDATE fs.vop_guarantee_group_plan
         SET effective_to = CURRENT_DATE, updated_at = now()
       WHERE vop_plan_id = $1
         AND (effective_to IS NULL OR effective_to > CURRENT_DATE)
      `,
      [planId]
    );

    const result = await query(
      `
      INSERT INTO fs.vop_guarantee_group_plan (
        vop_guarantee_group_id, vop_plan_id, effective_from, effective_to, created_by_user_id
      ) VALUES ($1, $2, $3, $4, $5)
      RETURNING *
      `,
      [
        id,
        planId,
        effective_from ?? new Date().toISOString().split('T')[0],
        effective_to ?? null,
        created_by_user_id ?? null,
      ]
    );
    res.status(201).json({ guarantee_group_plan: result.rows[0] });
  }
);

// DELETE /v1/vop/guarantee-groups/:id/plans/:plan_id — date-close plan membership in group
vopRouter.delete(
  [
    '/guarantee-groups/:id/plans/:plan_id',
    '/guarantee_groups/:id/plans/:plan_id',
    '/guarantee-groups/:id/contracts/:plan_id',
    '/guarantee_groups/:id/contracts/:plan_id',
  ],
  async (req, res) => {
    const { id, plan_id } = req.params;
    // Per Chapter 16: "Membership is dated rather than edited, so a car joining or leaving is recorded."
    const result = await query(
      `
      UPDATE fs.vop_guarantee_group_plan
         SET effective_to = CURRENT_DATE, updated_at = now()
       WHERE vop_guarantee_group_id = $1
         AND vop_plan_id = $2
         AND (effective_to IS NULL OR effective_to >= CURRENT_DATE)
      RETURNING *
      `,
      [id, plan_id]
    );
    if (result.rowCount === 0) {
      throw new HttpError(404, 'Active plan membership not found in this guarantee group');
    }
    res.json({
      success: true,
      message: 'Plan membership dated closed',
      guarantee_group_plan: result.rows[0],
    });
  }
);

// =============================================================================
// 4. SETTLEMENT PERIODS
// =============================================================================

// GET /v1/vop/payout-periods — list settlement periods
vopRouter.get(['/payout-periods', '/payout_periods', '/payout-period', '/payout_period'], async (_req, res) => {
  const result = await query(
    `SELECT * FROM fs.vop_payout_period ORDER BY period_start_date DESC`
  );
  res.json({ count: result.rowCount, payout_periods: result.rows });
});

// POST /v1/vop/payout-periods — create new settlement period
vopRouter.post(['/payout-periods', '/payout_periods', '/payout-period', '/payout_period'], async (req, res) => {
  const schema = z.object({
    period_start_date: z.string(),
    period_end_date: z.string(),
    status: z.enum(['Open', 'Closed']).default('Open'),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.vop_payout_period (
      period_start_date, period_end_date, status, created_by_user_id
    ) VALUES ($1, $2, $3, $4)
    RETURNING *
    `,
    [b.period_start_date, b.period_end_date, b.status, b.created_by_user_id ?? null]
  );
  res.status(201).json({ payout_period: result.rows[0] });
});

// POST /v1/vop/payout-periods/:id/close (or /payout-periods/close) — close a settlement period (stops new entries being dated into it)
vopRouter.post(
  [
    '/payout-periods/:id/close',
    '/payout-periods/close',
    '/payout_periods/close',
    '/payout_period/close',
    '/payout-period/close',
  ],
  async (req, res) => {
    const id = req.params.id || req.body.id || req.body.payout_period_id || req.body.period_id;
    if (!id) {
      throw new HttpError(400, 'Payout period ID is required (in URL path or JSON body as id/payout_period_id)');
    }
    const pRes = await query(
      `SELECT * FROM fs.vop_payout_period WHERE payout_period_id = $1`,
      [id]
    );
    if (pRes.rowCount === 0) {
      throw new HttpError(404, 'Payout period not found');
    }
    if (pRes.rows[0].status === 'Closed') {
      throw new HttpError(400, 'Payout period is already closed');
    }

    const result = await query(
      `
      UPDATE fs.vop_payout_period
         SET status = 'Closed', updated_at = now()
       WHERE payout_period_id = $1
      RETURNING *
      `,
      [id]
    );
    res.json({
      success: true,
      message: 'Payout period closed',
      payout_period: result.rows[0],
    });
  }
);

// PUT /v1/vop/payout-periods/:id — update payout period
vopRouter.put(['/payout-periods/:id', '/payout_periods/:id', '/payout-period/:id', '/payout_period/:id'], async (req, res) => {
  const { id } = req.params;
  const schema = z.object({
    period_start_date: z.string().optional(),
    period_end_date: z.string().optional(),
    status: z.enum(['Open', 'Closed']).optional(),
    updated_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const clauses = [];
  const values = [];

  for (const [key, val] of Object.entries(b)) {
    if (val !== undefined) {
      values.push(val);
      clauses.push(`${key} = $${values.length}`);
    }
  }

  if (clauses.length === 0) {
    throw new HttpError(400, 'No fields provided for update');
  }

  clauses.push('updated_at = now()');
  values.push(id);

  const result = await query(
    `UPDATE fs.vop_payout_period SET ${clauses.join(', ')} WHERE payout_period_id = $${values.length} RETURNING *`,
    values
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Payout period not found');
  }
  res.json({ payout_period: result.rows[0] });
});

// =============================================================================
// 5. PAYOUT LEDGER
// =============================================================================

// GET /v1/vop/ledger — query append-only payout entries
vopRouter.get('/ledger', async (req, res) => {
  const { payout_period_id, vehicle_id, vehicle_partner_id, entry_type } = req.query;
  const clauses = [];
  const values = [];

  if (payout_period_id) {
    values.push(payout_period_id);
    clauses.push(`payout_period_id = $${values.length}`);
  }
  if (vehicle_id) {
    values.push(vehicle_id);
    clauses.push(`vehicle_id = $${values.length}`);
  }
  if (vehicle_partner_id) {
    values.push(vehicle_partner_id);
    clauses.push(`vehicle_partner_id = $${values.length}`);
  }
  if (entry_type) {
    values.push(entry_type);
    clauses.push(`entry_type = $${values.length}`);
  }

  const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
  const result = await query(
    `
    SELECT *
      FROM fs.vop_payout_log
     ${where}
     ORDER BY entry_date DESC, created_at DESC
    `,
    values
  );
  res.json({ count: result.rowCount, entries: result.rows });
});

// POST /v1/vop/ledger — append entry to financial payout log
vopRouter.post('/ledger', async (req, res) => {
  const schema = z.object({
    vehicle_id: z.string().uuid(),
    vop_plan_id: z.string().uuid().optional(),
    vehicle_partner_id: z.string().uuid(),
    vehicle_reservation_id: z.string().uuid().optional(),
    vehicle_trip_id: z.string().uuid().optional(),
    source_table: z.string().max(40).optional(),
    source_record_id: z.string().uuid().optional(),
    entry_type: z.enum([
      'VOP Day',
      'VOP Mile',
      'VOP Plan Fee',
      'VOP Service',
      'VOP Fuel',
      'VOP Toll',
      'VOP Prepaid TopUp',
      'VOP Prepaid Recoup',
      'VOP Amount',
      'Other',
    ]),
    entry_direction: z.enum(['Credit', 'Charge']),
    entry_value: z.number(),
    reason_code: z.string().max(40).optional(),
    description: z.string().optional(),
    payout_period_id: z.string().uuid().optional(),
    processed_flag: z.boolean().default(false),
    entry_date: z.string().optional(),
    created_by_user_id: z.string().uuid().optional(),
  });
  const b = schema.parse(req.body);
  const result = await query(
    `
    INSERT INTO fs.vop_payout_log (
      vehicle_id, vop_plan_id, vehicle_partner_id,
      vehicle_reservation_id, vehicle_trip_id,
      source_table, source_record_id, entry_type,
      entry_direction, entry_value, reason_code,
      description, payout_period_id, processed_flag,
      entry_date, created_by_user_id
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
    RETURNING *
    `,
    [
      b.vehicle_id,
      b.vop_plan_id ?? null,
      b.vehicle_partner_id,
      b.vehicle_reservation_id ?? null,
      b.vehicle_trip_id ?? null,
      b.source_table ?? null,
      b.source_record_id ?? null,
      b.entry_type,
      b.entry_direction,
      b.entry_value,
      b.reason_code ?? null,
      b.description ?? null,
      b.payout_period_id ?? null,
      b.processed_flag,
      b.entry_date ?? new Date().toISOString().split('T')[0],
      b.created_by_user_id ?? null,
    ]
  );
  res.status(201).json({ entry: result.rows[0] });
});

// =============================================================================
// 6. PAYOUT SUMMARIES & COMPUTATION
// =============================================================================

// GET /v1/vop/summaries (or /summary) — get period payout summaries
vopRouter.get(['/summaries', '/summary', '/payout-summaries', '/payout-summary'], async (req, res) => {
  const { payout_period_id, vehicle_partner_id } = req.query;
  const clauses = [];
  const values = [];

  if (payout_period_id) {
    values.push(payout_period_id);
    clauses.push(`s.payout_period_id = $${values.length}`);
  }
  if (vehicle_partner_id) {
    values.push(vehicle_partner_id);
    clauses.push(`s.vehicle_partner_id = $${values.length}`);
  }

  const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
  const result = await query(
    `
    SELECT s.*,
           vp.business_name AS partner_name
      FROM fs.vop_payout_summary s
      LEFT JOIN fs.vehicle_partner vp ON vp.vehicle_partner_id = s.vehicle_partner_id
     ${where}
     ORDER BY s.created_at DESC
    `,
    values
  );
  res.json({ count: result.rowCount, summaries: result.rows });
});

// POST /v1/vop/summaries/compute (or /summary/compute) — calculate and persist payout summaries
vopRouter.post(
  [
    '/summaries/compute',
    '/summary/compute',
    '/payout-summaries/compute',
    '/payout-summary/compute',
    '/payout_summary/compute',
  ],
  async (req, res) => {
    const payout_period_id = req.body.payout_period_id || req.body.period_id || req.body.id;
    const created_by_user_id = req.body.created_by_user_id;

    if (!payout_period_id) {
      throw new HttpError(400, 'payout_period_id (or period_id / id) is required');
    }

    const periodRes = await query(
      `SELECT * FROM fs.vop_payout_period WHERE payout_period_id = $1`,
      [payout_period_id]
    );
    if (periodRes.rowCount === 0) {
      throw new HttpError(404, 'Payout period not found');
    }
    const period = periodRes.rows[0];

  // 1. Fetch all distinct active plans or plans with ledger entries in this period
  const plansRes = await query(
    `
    SELECT DISTINCT p.*
      FROM fs.vop_plan p
     WHERE p.status = 'Active'
        OR p.vop_plan_id IN (
          SELECT DISTINCT vop_plan_id FROM fs.vop_payout_log WHERE payout_period_id = $1
        )
    `,
    [payout_period_id]
  );

  const summaries = [];

  for (const plan of plansRes.rows) {
    // 2. Fetch ledger entries for this plan & period
    const logRes = await query(
      `
      SELECT entry_type, entry_direction, SUM(entry_value)::numeric AS total
        FROM fs.vop_payout_log
       WHERE vop_plan_id = $1
         AND (payout_period_id = $2 OR (entry_date >= $3 AND entry_date <= $4))
       GROUP BY entry_type, entry_direction
      `,
      [plan.vop_plan_id, payout_period_id, period.period_start_date, period.period_end_date]
    );

    let baseFeeAdjusted = 0;
    let mileageFee = 0;
    let manualAdjustments = 0;

    for (const row of logRes.rows) {
      const val = parseFloat(row.total || 0);
      const sign = row.entry_direction === 'Credit' ? 1 : -1;
      const netVal = val * sign;

      if (row.entry_type === 'VOP Day') {
        baseFeeAdjusted += netVal;
      } else if (row.entry_type === 'VOP Mile') {
        mileageFee += netVal;
      } else if (['VOP Plan Fee', 'VOP Service', 'VOP Fuel', 'VOP Toll', 'Other'].includes(row.entry_type)) {
        manualAdjustments += netVal;
      }
    }

    const baseFeeOriginal = plan.base_fee_amount || 0;
    const grossPayout = baseFeeAdjusted + mileageFee + manualAdjustments;
    let totalPayout = grossPayout;

    // Minimum floor logic:
    const minFloor = plan.minimum_amount_per_period || 0;
    if (minFloor > 0 && totalPayout < minFloor) {
      const topUpAmount = minFloor - totalPayout;
      totalPayout = minFloor;

      // Post top-up entry if not already present
      await query(
        `
        INSERT INTO fs.vop_payout_log (
          vehicle_id, vop_plan_id, vehicle_partner_id,
          source_table, entry_type, entry_direction, entry_value,
          description, payout_period_id, processed_flag, entry_date, created_by_user_id
        ) VALUES ($1, $2, $3, 'vop_payout_summary', 'VOP Prepaid TopUp', 'Credit', $4, $5, $6, true, CURRENT_DATE, $7)
        `,
        [
          plan.vehicle_id,
          plan.vop_plan_id,
          plan.vehicle_partner_id,
          topUpAmount,
          `Floor guarantee top-up for period ${period.period_start_date} to ${period.period_end_date}`,
          payout_period_id,
          created_by_user_id ?? null,
        ]
      );
    }

    // 3. Upsert into vop_payout_summary
    const existingSummary = await query(
      `SELECT vop_payout_summary_id FROM fs.vop_payout_summary WHERE payout_period_id = $1 AND vop_plan_id = $2`,
      [payout_period_id, plan.vop_plan_id]
    );

    let summaryRow;
    if (existingSummary.rowCount > 0) {
      const upd = await query(
        `
        UPDATE fs.vop_payout_summary
           SET base_fee_original = $1,
               base_fee_adjusted = $2,
               mileage_fee = $3,
               manual_adjustments_total = $4,
               total_payout = $5,
               updated_at = now()
         WHERE vop_payout_summary_id = $6
        RETURNING *
        `,
        [
          baseFeeOriginal,
          baseFeeAdjusted,
          mileageFee,
          manualAdjustments,
          totalPayout,
          existingSummary.rows[0].vop_payout_summary_id,
        ]
      );
      summaryRow = upd.rows[0];
    } else {
      const ins = await query(
        `
        INSERT INTO fs.vop_payout_summary (
          payout_period_id, vop_plan_id, vehicle_id, vehicle_partner_id,
          base_fee_original, base_fee_adjusted, mileage_fee,
          manual_adjustments_total, total_payout, created_by_user_id
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        RETURNING *
        `,
        [
          payout_period_id,
          plan.vop_plan_id,
          plan.vehicle_id,
          plan.vehicle_partner_id,
          baseFeeOriginal,
          baseFeeAdjusted,
          mileageFee,
          manualAdjustments,
          totalPayout,
          created_by_user_id ?? null,
        ]
      );
      summaryRow = ins.rows[0];
    }
    summaries.push(summaryRow);
  }

  // Mark all entries for this period processed
  await query(
    `UPDATE fs.vop_payout_log SET processed_flag = true, updated_at = now() WHERE payout_period_id = $1`,
    [payout_period_id]
  );

  res.json({
    success: true,
    count: summaries.length,
    summaries,
  });
});
