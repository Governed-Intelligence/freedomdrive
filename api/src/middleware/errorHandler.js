import { ZodError } from 'zod';
import { logger } from '../logger.js';

export class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

// Map common Postgres error codes to HTTP statuses
const PG_CODE_MAP = {
  '23505': 409, // unique_violation
  '23503': 409, // foreign_key_violation
  '23514': 400, // check_violation
  '23P01': 409, // exclusion_violation — our reservation-overlap guard
  '22P02': 400, // invalid_text_representation (e.g. bad UUID)
  P0001: 400,   // raise_exception (our triggers throw these)
};

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, _next) {
  // Zod validation failures
  if (err instanceof ZodError) {
    return res.status(400).json({
      error: 'validation_error',
      message: 'Request validation failed',
      details: err.errors,
    });
  }

  // Our own HttpError
  if (err instanceof HttpError) {
    return res.status(err.status).json({
      error: err.message,
      details: err.details,
    });
  }

  // Postgres errors
  if (err.code && PG_CODE_MAP[err.code]) {
    const status = PG_CODE_MAP[err.code];
    logger.warn({ err, code: err.code }, 'Database constraint violation');
    return res.status(status).json({
      error: 'database_constraint',
      message: err.message,
      code: err.code,
      constraint: err.constraint,
      detail: err.detail,
    });
  }

  // Fallback — log with full context
  logger.error({ err, path: req.path, method: req.method }, 'Unhandled error');
  res.status(500).json({
    error: 'internal_error',
    message: 'Something went wrong. Please try again.',
  });
}
