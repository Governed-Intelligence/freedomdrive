import pino from 'pino';
import { config, isProd } from './config.js';

// Cloud Logging reads `severity` not `level`; map pino levels to GCP severities.
const gcpSeverity = {
  trace: 'DEBUG',
  debug: 'DEBUG',
  info: 'INFO',
  warn: 'WARNING',
  error: 'ERROR',
  fatal: 'CRITICAL',
};

export const logger = pino({
  level: config.logLevel,
  base: { service: 'freedom-supercars-api' },
  timestamp: pino.stdTimeFunctions.isoTime,
  formatters: {
    level: (label) => ({ severity: gcpSeverity[label] ?? 'DEFAULT' }),
  },
  // Pretty output in local dev only
  transport: isProd()
    ? undefined
    : {
        target: 'pino/file',
        options: { destination: 1 }, // stdout
      },
});
