import { Router } from 'express';
import { query } from '../db.js';

export const tiersRouter = Router();

// GET /v1/tiers — all tiers with point costs and booking rules
tiersRouter.get('/', async (_req, res) => {
  const result = await query(`
    SELECT id, name, points_per_day, min_booking_days, max_booking_days,
           daily_mileage_cap, overage_fee_per_mile, description
      FROM fs.tiers
     ORDER BY id ASC
  `);
  res.json({ tiers: result.rows });
});
