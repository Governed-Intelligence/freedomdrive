import pg from 'pg';
import { config } from './config.js';
import { logger } from './logger.js';

const { Pool } = pg;

export const pool = new Pool({
  connectionString: config.databaseUrl,
  max: 10,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 10_000,
  application_name: 'freedom-supercars-api',
});

pool.on('error', (err) => {
  logger.error({ err }, 'Unexpected error on idle pg client');
});

// Every new connection starts with search_path pointed at our schema
pool.on('connect', (client) => {
  client.query('SET search_path TO fs, public').catch((err) => {
    logger.error({ err }, 'Failed to set search_path');
  });
});

/**
 * Run a query with parameterized args.
 * @param {string} text  SQL with $1, $2, ... placeholders
 * @param {Array}  params
 * @returns {Promise<pg.QueryResult>}
 */
export async function query(text, params = []) {
  const start = Date.now();
  try {
    const res = await pool.query(text, params);
    const ms = Date.now() - start;
    if (ms > 500) {
      logger.warn({ ms, rowCount: res.rowCount, text: text.slice(0, 120) }, 'Slow query');
    }
    return res;
  } catch (err) {
    logger.error({ err, text: text.slice(0, 200) }, 'Query failed');
    throw err;
  }
}

/**
 * Run multiple statements atomically in a transaction.
 * @template T
 * @param {(client: pg.PoolClient) => Promise<T>} fn
 * @returns {Promise<T>}
 */
export async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SET search_path TO fs, public');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

export async function closePool() {
  await pool.end();
}
