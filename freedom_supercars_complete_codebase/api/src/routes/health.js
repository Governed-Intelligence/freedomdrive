import { Router } from 'express';
import { query } from '../db.js';

export const healthRouter = Router();

// Liveness — is the process up?
healthRouter.get('/healthz', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Readiness — is the process up AND can it reach the DB?
healthRouter.get('/readyz', async (_req, res) => {
  try {
    const result = await query('SELECT 1 AS ok');
    const tableRes = await query("SELECT count(*)::int AS count FROM information_schema.tables WHERE table_schema = 'fs'");
    res.json({
      status: 'ready',
      database: result.rows[0].ok === 1 ? 'connected' : 'unknown',
      tables_in_fs: tableRes.rows[0]?.count ?? 0,
      timestamp: new Date().toISOString(),
    });
  } catch (err) {
    res.status(503).json({
      status: 'not_ready',
      database: 'unreachable',
      error: err.message,
    });
  }
});
