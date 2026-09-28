import { Router } from 'express';
import { query } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';

export const plansRouter = Router();

// GET /v1/plans — list all active plans
plansRouter.get('/', async (_req, res) => {
  const result = await query(`
    SELECT p.id, p.code, p.name, p.driving_days, p.annual_tier_points,
           p.annual_price_usd, p.initiation_fee_usd, p.monthly_price_usd,
           p.guest_drivers_allowed, p.rollover_allowed, p.rollover_cap_points,
           p.description, p.sort_order
      FROM fs.plans p
     WHERE p.is_active = TRUE
     ORDER BY p.sort_order ASC
  `);
  res.json({ plans: result.rows });
});

// GET /v1/plans/:code — single plan by code
plansRouter.get('/:code', async (req, res) => {
  const { code } = req.params;
  const result = await query(
    `SELECT * FROM fs.plans WHERE code = $1 AND is_active = TRUE`,
    [code]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Plan not found');
  }
  res.json({ plan: result.rows[0] });
});

// GET /v1/plans/:code/tier-allocations — plan-tier access caps
plansRouter.get('/:code/tier-allocations', async (req, res) => {
  const { code } = req.params;
  const result = await query(
    `
    SELECT pta.tier_id, t.name AS tier_name, t.points_per_day, t.min_booking_days,
           pta.max_days_per_year, pta.max_days_per_booking,
           pta.advance_booking_days, pta.blackout_weekend_eligible
      FROM fs.plan_tier_allocations pta
      JOIN fs.plans p ON p.id = pta.plan_id
      JOIN fs.tiers t ON t.id = pta.tier_id
     WHERE p.code = $1
     ORDER BY pta.tier_id
    `,
    [code]
  );
  res.json({ plan_code: code, allocations: result.rows });
});
