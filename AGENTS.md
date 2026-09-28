# Freedom Supercars — Base44 Dev Environment

## Architecture

- **API** (`api/`): Express + Node 20, PostgreSQL via `pg`. Listens on port 8080.
- **Web** (`web/`): Vite 6 + React 18. Dev server on port 5173 (mapped to host 3000).
- **DB**: PostgreSQL 16. All app tables live in schema `fs` (the pool sets `search_path TO fs, public` on every connection).

## Running

```bash
docker compose -f docker-compose.base44.yml up -d --build
```

Services start in order: postgres → migrate (one-shot) → seed (one-shot) → api → web.
The API waits for seed to complete, so the first boot has demo data ready.

## Key details

- **DATABASE_URL** is the only required env var (wired to the local postgres service). JWT_SECRET has a built-in default. ANTHROPIC_API_KEY and STRIPE_SECRET_KEY are optional.
- **CORS** is open in development (`NODE_ENV != production` allows all origins). Auth uses JWT Bearer tokens, not cookies.
- **VITE_API_URL** is set to the API's public URL so the React client makes direct cross-origin requests. If unset, the client falls back to relative paths through the Vite proxy.
- **Vite host config**: `server.host: true` + `server.allowedHosts: true` in `web/vite.config.js` are required for Vite 6.0.x to accept the preview's external hostname.
- **Migrations** are idempotent (tracked in `public._migrations`). Re-running is safe.
- **Seed** creates 20 demo members (member numbers `FS-SEED-0001`–`0020`) with subscriptions and ~60 reservations. Also idempotent (skips if seed members exist).

## Optional: Anthropic API key

The concierge chat (`/v1/concierge/chat`) needs `ANTHROPIC_API_KEY`. Without it the app boots fine but concierge returns an error. Set it via the Base44 secrets dashboard if needed.

## Verifying

```bash
curl localhost:8000/healthz        # API liveness
curl localhost:8000/readyz        # API readiness (DB check)
curl localhost:3000               # Web frontend
```
