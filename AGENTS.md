# AGENTS.md — Freedom Supercars (Base44 dev environment)

## Project overview

Fullstack members-club platform: Express API + Vite/React frontend.
- **API** (`api/`): Node.js 20 + Express, PostgreSQL 15, port 8080. Requires `DATABASE_URL`.
- **Web** (`web/`): Vite 6 + React 18, port 5173 (mapped to host 3000). Proxies `/v1` to the API via Vite dev server.
- **DB**: PostgreSQL with schema `fs`. 31 migrations in `api/db/migrations/`.

## Dev environment

```bash
docker compose -f docker-compose.base44.yml up -d
```

Services: `db` (Postgres 15), `migrate` (one-shot, runs all migrations then seeds 20 demo members + 60 reservations), `api` (live reload via `node --watch`), `web` (Vite dev server on port 3000).

## Key setup details

- **PostgreSQL roles**: Migrations 002 and 003 GRANT to roles `fs_app` and `fs_migrator` that Terraform creates in production Cloud SQL. The file `.base44/init-roles.sql` is mounted into the Postgres container's `/docker-entrypoint-initdb.d/` to create them on first init. If the DB volume is wiped, these roles are recreated automatically.
- **Vite proxy**: `web/vite.config.js` uses `API_PROXY_TARGET` (not `VITE_API_URL`) for the dev server proxy target so the client-side `VITE_API_URL` stays empty (same-origin). The compose file sets `API_PROXY_TARGET=http://api:8080`.
- **Vite host**: `server.host: true` + `allowedHosts: true` in vite.config.js to accept the preview's external hostname.
- **No external secrets required**: `DATABASE_URL` is local infra (wired via compose `environment:`). `ANTHROPIC_API_KEY`, `STRIPE_SECRET_KEY`, `JWT_SECRET` are all optional with defaults.

## Verifying the app works

1. `docker compose -f docker-compose.base44.yml ps -a` — db/api/web healthy, migrate/seed exited 0.
2. `curl http://localhost:3000/` — should return HTML with Vite HMR client.
3. `curl http://localhost:3000/v1/tiers` — should return JSON tier data (proves API proxy works).
4. In the preview: the sign-in page loads a member dropdown (20+ members from seed). Select a member to reach the dashboard.

## Live reload

- **Frontend**: Vite HMR — edits to `web/src/*` appear instantly.
- **Backend**: `node --watch` — edits to `api/src/*` restart the API automatically.
