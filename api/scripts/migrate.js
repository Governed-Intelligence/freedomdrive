// Migration runner — runs as a Cloud Run Job.
// Idempotent: tracks applied files in public._migrations and skips them on re-run.
//
// Usage (locally):   DATABASE_URL=... node scripts/migrate.js
// Usage (on GCP):    gcloud run jobs execute freedom-supercars-prod-migrate --region=us-south1

import { readdir, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const { Client } = pg;

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Migrations live at db/migrations/ relative to the repo root.
// From /app/scripts/migrate.js in the container, that's ../db/migrations.
const MIGRATIONS_DIR = resolve(__dirname, '..', 'db', 'migrations');

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL is required');
  process.exit(1);
}

function sha256(input) {
  return createHash('sha256').update(input).digest('hex');
}

async function ensureMigrationsTable(client) {
  await client.query(`
    CREATE TABLE IF NOT EXISTS public._migrations (
      filename    TEXT PRIMARY KEY,
      checksum    TEXT NOT NULL,
      applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      duration_ms INTEGER NOT NULL
    )
  `);
}

async function loadMigrationFiles() {
  let entries;
  try {
    entries = await readdir(MIGRATIONS_DIR);
  } catch (err) {
    if (err.code === 'ENOENT') {
      console.error(`Migrations directory not found: ${MIGRATIONS_DIR}`);
      process.exit(1);
    }
    throw err;
  }
  // Sort lexicographically — relies on 001_, 002_, ... naming convention
  return entries.filter((f) => f.endsWith('.sql')).sort();
}

async function alreadyApplied(client, filename, checksum) {
  const res = await client.query(
    'SELECT checksum FROM public._migrations WHERE filename = $1',
    [filename]
  );
  if (res.rowCount === 0) return false;
  const existing = res.rows[0].checksum;
  if (existing !== checksum) {
    throw new Error(
      `Checksum mismatch for ${filename}: applied=${existing.slice(0, 10)}... current=${checksum.slice(0, 10)}... Migrations are immutable once applied.`
    );
  }
  return true;
}

async function applyOne(client, filename) {
  const fullPath = join(MIGRATIONS_DIR, filename);
  const sql = await readFile(fullPath, 'utf8');
  const checksum = sha256(sql);

  if (await alreadyApplied(client, filename, checksum)) {
    console.log(`✓ ${filename}  (already applied)`);
    return;
  }

  console.log(`→ ${filename}  (applying...)`);
  const start = Date.now();

  // Each migration file should manage its own BEGIN/COMMIT if it needs to;
  // our schema file already does. We run it as one statement batch.
  try {
    await client.query(sql);
  } catch (err) {
    console.error(`✗ ${filename} FAILED:`, err.message);
    throw err;
  }

  const durationMs = Date.now() - start;
  await client.query(
    'INSERT INTO public._migrations (filename, checksum, duration_ms) VALUES ($1, $2, $3)',
    [filename, checksum, durationMs]
  );
  console.log(`✓ ${filename}  (${durationMs}ms)`);
}

async function main() {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  console.log('Connected to database.');

  try {
    await ensureMigrationsTable(client);
    const files = await loadMigrationFiles();
    if (files.length === 0) {
      console.log('No migration files found.');
      return;
    }
    console.log(`Found ${files.length} migration file(s) in ${MIGRATIONS_DIR}`);
    for (const filename of files) {
      await applyOne(client, filename);
    }
    console.log('All migrations applied.');
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error('Migration run failed:', err);
  process.exit(1);
});
