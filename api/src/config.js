// Central config - fail fast on missing required env vars
const required = (name) => {
  const v = process.env[name];
  if (!v || v.length === 0) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
};

const optional = (name, fallback = '') => process.env[name] ?? fallback;

const parseOrigins = (raw) => {
  if (!raw || raw.trim().length === 0) return [];
  return raw.split(',').map((s) => s.trim()).filter(Boolean);
};

export const config = Object.freeze({
  env: optional('NODE_ENV', 'development'),
  port: parseInt(optional('PORT', '8080'), 10),
  gcpProjectId: optional('GCP_PROJECT_ID'),
  databaseUrl: required('DATABASE_URL'),
  anthropicApiKey: optional('ANTHROPIC_API_KEY'),
  stripeSecretKey: optional('STRIPE_SECRET_KEY'),
  logLevel: optional('LOG_LEVEL', 'info'),
  jwtSecret: optional('JWT_SECRET', 'fs-supercars-internal-jwt-secret-replace-in-production'),
  allowedOrigins: parseOrigins(
    optional(
      'ALLOWED_ORIGINS',
      'http://localhost:5173,http://localhost:8080,http://127.0.0.1:5173,http://127.0.0.1:8080'
    )
  ),
});

export const isProd = () => config.env === 'production';

