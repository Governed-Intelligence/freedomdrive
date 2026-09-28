import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';

export const subscriptionsRouter = Router();

const createSchema = z.object({
  member_id: z.string().uuid(),
  plan_code: z.enum(['PLAN_15', 'PLAN_30', 'PLAN_60', 'PLAN_100']),
  start_date: z.string().date(),
  end_date: z.string().date().optional(), // default: +1 year
  auto_renew: z.boolean().default(true),
  rollover_from_subscription_id: z.string().uuid().optional(),
});

// POST /v1/subscriptions
subscriptionsRouter.post('/', async (req, res) => {
  const data = createSchema.parse(req.body);

  const plan = await query(
    `SELECT id, annual_tier_points, rollover_allowed, rollover_cap_points
       FROM fs.plans WHERE code = $1 AND is_active = TRUE`,
    [data.plan_code]
  );
  if (plan.rowCount === 0) {
    throw new HttpError(400, `Unknown or inactive plan: ${data.plan_code}`);
  }
  const planRow = plan.rows[0];

  const endDate =
    data.end_date ??
    new Date(new Date(data.start_date).setFullYear(new Date(data.start_date).getFullYear() + 1))
      .toISOString()
      .slice(0, 10);

  // Rollover calculation if requested
  let pointsRolledIn = 0;
  if (data.rollover_from_subscription_id) {
    if (!planRow.rollover_allowed) {
      throw new HttpError(400, 'Plan does not support rollover');
    }
    const prior = await query(
      `SELECT member_id, fs.subscription_balance(id) AS balance
         FROM fs.member_subscriptions WHERE id = $1`,
      [data.rollover_from_subscription_id]
    );
    if (prior.rowCount === 0) {
      throw new HttpError(404, 'Prior subscription not found');
    }
    if (prior.rows[0].member_id !== data.member_id) {
      throw new HttpError(400, 'Prior subscription belongs to a different member');
    }
    const available = prior.rows[0].balance;
    const cap = planRow.rollover_cap_points ?? 0;
    pointsRolledIn = Math.min(available, cap);
  }

  // Create the subscription; trigger will grant points on 'active' insertion
  const result = await withTransaction(async (client) => {
    // If prior subscription is being rolled over, forfeit its remaining balance
    if (data.rollover_from_subscription_id && pointsRolledIn >= 0) {
      const priorBal = await client.query(
        `SELECT fs.subscription_balance($1)::int AS balance`,
        [data.rollover_from_subscription_id]
      );
      const forfeit = priorBal.rows[0].balance;
      if (forfeit > 0) {
        await client.query(
          `INSERT INTO fs.point_transactions
             (subscription_id, txn_type, points, balance_after, reason)
           VALUES ($1, 'forfeit', $2, 0, $3)`,
          [
            data.rollover_from_subscription_id,
            -forfeit,
            `End of term: ${pointsRolledIn} rolled forward, ${forfeit - pointsRolledIn} forfeited`,
          ]
        );
      }
      await client.query(
        `UPDATE fs.member_subscriptions SET status = 'renewed' WHERE id = $1`,
        [data.rollover_from_subscription_id]
      );
    }

    const insert = await client.query(
      `
      INSERT INTO fs.member_subscriptions (
        member_id, plan_id, status, start_date, end_date,
        points_granted, points_rolled_in, auto_renew
      ) VALUES (
        $1, $2, 'active', $3, $4, $5, $6, $7
      )
      RETURNING id, member_id, plan_id, status, start_date, end_date,
                points_granted, points_rolled_in, auto_renew, created_at
      `,
      [
        data.member_id,
        planRow.id,
        data.start_date,
        endDate,
        planRow.annual_tier_points,
        pointsRolledIn,
        data.auto_renew,
      ]
    );

    // Member → active if they were prospect
    await client.query(
      `UPDATE fs.members
          SET status = 'active', joined_on = COALESCE(joined_on, CURRENT_DATE)
        WHERE id = $1 AND status IN ('prospect','paused','expired','cancelled')`,
      [data.member_id]
    );

    return insert.rows[0];
  });

  res.status(201).json({ subscription: result });
});

// GET /v1/subscriptions/plans — List membership plans with pricing
subscriptionsRouter.get('/plans', async (req, res) => {
  const result = await query(
    `SELECT id, code, name, driving_days, annual_tier_points,
            COALESCE(annual_price_usd,
              CASE code
                WHEN 'PLAN_15' THEN 27000.00
                WHEN 'PLAN_30' THEN 45000.00
                WHEN 'PLAN_60' THEN 84000.00
                WHEN 'PLAN_100' THEN 132000.00
                ELSE 30000.00
              END
            ) AS annual_price_usd,
            COALESCE(monthly_price_usd,
              CASE code
                WHEN 'PLAN_15' THEN 2250.00
                WHEN 'PLAN_30' THEN 3750.00
                WHEN 'PLAN_60' THEN 7000.00
                WHEN 'PLAN_100' THEN 11000.00
                ELSE 2500.00
              END
            ) AS monthly_price_usd,
            initiation_fee_usd, guest_drivers_allowed, rollover_allowed, rollover_cap_points, is_active, description
       FROM fs.plans
      WHERE is_active = TRUE
      ORDER BY sort_order ASC`
  );
  res.json({ plans: result.rows });
});

// GET /v1/subscriptions/:id
subscriptionsRouter.get('/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `
    SELECT s.*, p.code AS plan_code, p.name AS plan_name, p.driving_days,
           fs.subscription_balance(s.id) AS points_remaining
      FROM fs.member_subscriptions s
      JOIN fs.plans p ON p.id = s.plan_id
     WHERE s.id = $1
    `,
    [id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Subscription not found');
  }
  res.json({ subscription: result.rows[0] });
});

// POST /v1/subscriptions/:id/cancel
subscriptionsRouter.post('/:id/cancel', async (req, res) => {
  const { id } = req.params;
  const reasonSchema = z.object({ reason: z.string().max(500).optional() });
  const { reason } = reasonSchema.parse(req.body ?? {});

  const result = await query(
    `
    UPDATE fs.member_subscriptions
       SET status = 'cancelled',
           cancellation_date = CURRENT_DATE,
           cancellation_reason = $2
     WHERE id = $1 AND status IN ('active','paused')
     RETURNING id, status, cancellation_date
    `,
    [id, reason ?? null]
  );
  if (result.rowCount === 0) {
    throw new HttpError(409, 'Subscription not in a cancellable state');
  }
  res.json({ subscription: result.rows[0] });
});
