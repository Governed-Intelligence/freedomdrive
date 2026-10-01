import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';
import { optionalAuth, requireAuth } from '../middleware/auth.js';
import {
  importTolls,
  matchTolls,
  billTripTolls,
  getUnmatchedTolls,
  disputeToll,
  excludeToll
} from '../services/tolls.js';

export const tollsRouter = Router();

const tollItemSchema = z.object({
  toll_tag: z.string().min(1),
  tag: z.string().min(1).optional(),
  transaction_at: z.string().datetime({ offset: true }).optional(),
  timestamp: z.string().datetime({ offset: true }).optional(),
  toll_authority_code: z.string().max(20).default('OTHER').optional(),
  authority: z.string().max(20).optional(),
  location: z.string().max(160).optional(),
  gantry: z.string().max(160).optional(),
  amount: z.number().positive(),
  notes: z.string().max(500).optional(),
});

const importSchema = z.object({
  batch_id: z.string().max(60).optional(),
  batchId: z.string().max(60).optional(),
  source: z.string().max(80).default('import').optional(),
  tolls: z.array(tollItemSchema).min(1),
});

const noteSchema = z.object({
  notes: z.string().max(1000).optional(),
  reason: z.string().max(1000).optional(),
});

/**
 * POST /v1/tolls/import
 * Batch import of toll authority records with deduplication
 */
tollsRouter.post('/import', optionalAuth, async (req, res) => {
  const data = importSchema.parse(req.body);
  const batchId = data.batch_id || data.batchId;

  const result = await withTransaction(async (client) => {
    return await importTolls(client, {
      batchId,
      source: data.source || 'import',
      tolls: data.tolls,
      actorUserId: req.user?.userId || null,
    });
  });

  res.status(201).json(result);
});

/**
 * POST /v1/tolls/match
 * Matches unmatched tolls against actual trip windows
 */
tollsRouter.post('/match', optionalAuth, async (req, res) => {
  const result = await withTransaction(async (client) => {
    return await matchTolls(client, {
      actorUserId: req.user?.userId || null,
    });
  });

  res.json(result);
});

/**
 * GET /v1/tolls/unmatched
 * Retrieves unmatched toll queue, ordered oldest first
 */
tollsRouter.get('/unmatched', optionalAuth, async (req, res) => {
  const limit = req.query.limit ? Number(req.query.limit) : 50;
  const offset = req.query.offset ? Number(req.query.offset) : 0;

  const result = await withTransaction(async (client) => {
    return await getUnmatchedTolls(client, { limit, offset });
  });

  res.json(result);
});

/**
 * PATCH /v1/tolls/:id/dispute
 * Marks a toll as Disputed
 */
tollsRouter.patch('/:id/dispute', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const body = noteSchema.parse(req.body || {});
  const notes = body.notes || body.reason;

  const result = await withTransaction(async (client) => {
    return await disputeToll(client, {
      tollId: id,
      notes,
      actorUserId: req.user?.userId || null,
    });
  });

  res.json({ toll: result });
});

/**
 * PATCH /v1/tolls/:id/exclude
 * Marks a toll as Excluded (club decision)
 */
tollsRouter.patch('/:id/exclude', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const body = noteSchema.parse(req.body || {});
  const notes = body.notes || body.reason;

  const result = await withTransaction(async (client) => {
    return await excludeToll(client, {
      tollId: id,
      notes,
      actorUserId: req.user?.userId || null,
    });
  });

  res.json({ toll: result });
});

/**
 * POST /v1/tolls/bill/:tripId
 * Convenience alias for billing tolls on a trip
 */
tollsRouter.post('/bill/:tripId', optionalAuth, async (req, res) => {
  const { tripId } = req.params;

  const result = await withTransaction(async (client) => {
    return await billTripTolls(client, {
      tripId,
      actorUserId: req.user?.userId || null,
    });
  });

  res.json(result);
});
