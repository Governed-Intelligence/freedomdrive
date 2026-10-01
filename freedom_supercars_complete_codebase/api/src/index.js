import 'express-async-errors';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';

import { config, isProd } from './config.js';
import { logger } from './logger.js';
import { closePool } from './db.js';
import { requestLogger } from './middleware/requestLogger.js';
import { errorHandler } from './middleware/errorHandler.js';

import { healthRouter } from './routes/health.js';
import { authRouter } from './routes/auth.js';
import { plansRouter } from './routes/plans.js';
import { tiersRouter } from './routes/tiers.js';
import { fleetRouter } from './routes/fleet.js';
import { membersRouter } from './routes/members.js';
import { subscriptionsRouter } from './routes/subscriptions.js';
import { reservationsRouter } from './routes/reservations.js';
import { conciergeRouter } from './routes/concierge.js';
import { mpcRouter } from './routes/mpc.js';
import { vopRouter } from './routes/vop.js';
import { rateCardsRouter } from './routes/rateCards.js';
import { tripsRouter } from './routes/trips.js';
import { tollsRouter } from './routes/tolls.js';

const app = express();

app.disable('x-powered-by');
app.set('trust proxy', true); // Cloud Run sits behind a load balancer

app.use(helmet());

// Dynamic CORS configuration allowing configured web frontend origins
app.use(
  cors({
    origin: (origin, callback) => {
      // Allow non-browser requests or missing origin
      if (!origin) return callback(null, true);
      // In development, allow all origins
      if (!isProd()) return callback(null, true);
      // In production, check allowlist
      if (
        config.allowedOrigins.length === 0 ||
        config.allowedOrigins.includes('*') ||
        config.allowedOrigins.includes(origin)
      ) {
        return callback(null, true);
      }
      return callback(new Error(`Origin ${origin} not allowed by CORS`));
    },
    credentials: true,
  })
);

app.use(express.json({ limit: '1mb' }));
app.use(requestLogger);

// Health endpoints at root (used by Cloud Run probes)
app.use('/', healthRouter);

// API v1
app.use('/v1/auth', authRouter);
app.use('/v1/plans', plansRouter);
app.use('/v1/tiers', tiersRouter);
app.use('/v1/fleet', fleetRouter);
app.use('/v1/members', membersRouter);
app.use('/v1/subscriptions', subscriptionsRouter);
app.use('/v1/reservations', reservationsRouter);
app.use('/v1/concierge', conciergeRouter);
app.use('/v1/mpc', mpcRouter);
app.use('/v1/vop', vopRouter);
app.use('/v1/rate-cards', rateCardsRouter);
app.use('/v1/trips', tripsRouter);
app.use('/v1/tolls', tollsRouter);

// Root
app.get('/', (_req, res) => {
  res.json({
    service: 'freedom-supercars-api',
    version: '1.0.0',
    environment: config.env,
    endpoints: [
      '/v1/auth',
      '/v1/plans',
      '/v1/tiers',
      '/v1/fleet',
      '/v1/members',
      '/v1/subscriptions',
      '/v1/reservations',
      '/v1/concierge',
      '/v1/mpc',
      '/v1/vop',
      '/v1/rate-cards',
      '/v1/trips',
      '/v1/tolls',
    ],
  });
});

// 404
app.use((req, res) => {
  res.status(404).json({ error: 'not_found', path: req.path });
});

// Error handler - must be last
app.use(errorHandler);

const server = app.listen(config.port, () => {
  logger.info(
    { port: config.port, env: config.env },
    `Freedom Supercars API listening on :${config.port}`
  );
});

// Graceful shutdown - Cloud Run sends SIGTERM with 10s grace period
const shutdown = async (signal) => {
  logger.info({ signal }, 'Shutting down...');
  server.close(async () => {
    await closePool().catch((err) => logger.error({ err }, 'Error closing pool'));
    logger.info('Shutdown complete');
    process.exit(0);
  });
  // Force-exit after 9s if graceful path stalls
  setTimeout(() => {
    logger.warn('Forced exit after shutdown timeout');
    process.exit(1);
  }, 9000).unref();
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('unhandledRejection', (reason) => {
  logger.error({ reason }, 'Unhandled promise rejection');
});
