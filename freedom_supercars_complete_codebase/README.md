# Freedom Supercars — GCP Deployment

Production-grade deployment of the Freedom Supercars members-club API on Google Cloud Platform.

**Stack:** Node.js 20 + Express · PostgreSQL 15 (Cloud SQL) · Cloud Run · Artifact Registry · Secret Manager · Terraform · GitHub Actions

---

## Repository Layout

```
freedom-supercars-gcp/
├── api/                          Node.js API container
│   ├── Dockerfile                Multi-stage, distroless, non-root
│   ├── package.json              Pinned deps
│   ├── src/
│   │   ├── index.js              Express app wiring
│   │   ├── config.js             Env-var validation
│   │   ├── logger.js             Pino → Cloud Logging
│   │   ├── db.js                 pg Pool + withTransaction helper
│   │   ├── middleware/
│   │   │   ├── errorHandler.js   Postgres + Zod → HTTP mapping
│   │   │   └── requestLogger.js  pino-http
│   │   ├── routes/
│   │   │   ├── health.js         /healthz, /readyz
│   │   │   ├── plans.js          4 membership plans
│   │   │   ├── tiers.js          5 vehicle tiers
│   │   │   ├── fleet.js          Current fleet, availability
│   │   │   ├── members.js        Members + point history
│   │   │   ├── subscriptions.js  Plan activation, rollover, cancel
│   │   │   └── reservations.js   Quote, create, confirm, cancel, pickup, return
│   │   └── services/
│   │       └── reservations.js   Booking validation & point-cost logic
│   ├── scripts/migrate.js        Migration runner (Cloud Run Job)
│   └── db/migrations/
│       └── 001_initial_schema.sql
├── infra/terraform/              Full GCP infrastructure
│   ├── versions.tf               Provider pinning
│   ├── variables.tf
│   ├── main.tf                   Required APIs + locals
│   ├── network.tf                VPC, subnet, VPC connector, private service range
│   ├── cloud_sql.tf              Postgres 15, private IP, PITR, app + migrator users
│   ├── secret_manager.tf         DB URL, Stripe, Anthropic
│   ├── artifact_registry.tf      Docker repo
│   ├── iam.tf                    2 service accounts, least-privilege
│   ├── cloud_run.tf              API service + migrate Job
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── .github/workflows/deploy.yml  Build → push → migrate → deploy
```

---

## One-Time Setup

### 1. Prerequisites

- GCP project with billing enabled
- `gcloud`, `terraform` ≥ 1.6, and Docker installed locally
- GitHub repository

### 2. Bootstrap Terraform state bucket

```bash
export PROJECT_ID=your-gcp-project-id
gcloud config set project $PROJECT_ID
gsutil mb -l us-south1 gs://${PROJECT_ID}-tfstate
gsutil versioning set on gs://${PROJECT_ID}-tfstate
```

Then uncomment the `backend "gcs"` block in `infra/terraform/versions.tf` and set the bucket.

### 3. First apply

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars to set project_id

# Optional: export sensitive values as env vars
export TF_VAR_anthropic_api_key="sk-ant-..."
export TF_VAR_stripe_secret_key="sk_live_..."

terraform init
terraform apply
```

First apply takes ~15 minutes (Cloud SQL provisioning dominates). It deploys a placeholder "hello" image to the Cloud Run service — the real API is deployed by the CI pipeline.

### 4. Run initial migrations (one-time, from your laptop)

Before CI is set up, you can run migrations manually using the Cloud SQL Auth Proxy:

```bash
# Install the proxy
curl -o cloud-sql-proxy \
  https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.2/cloud-sql-proxy.linux.amd64
chmod +x cloud-sql-proxy

# Connect (run in one terminal)
CONN=$(cd infra/terraform && terraform output -raw cloud_sql_connection_name)
./cloud-sql-proxy $CONN

# Apply schema (in another terminal)
# Get the migrator password from Secret Manager
PW=$(gcloud secrets versions access latest \
  --secret="freedom-supercars-prod-db-migrator-url" | \
  sed 's|postgresql://fs_migrator:||;s|@.*||')

PGPASSWORD=$PW psql -h 127.0.0.1 -U fs_migrator -d freedom_supercars \
  -f api/db/migrations/001_initial_schema.sql
```

After CI is set up, migrations run automatically.

### 5. GitHub Actions setup (Workload Identity Federation)

```bash
# Create a WIF pool + provider (one-time)
gcloud iam workload-identity-pools create github \
  --location=global --display-name="GitHub Actions"

gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location=global --workload-identity-pool=github \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='YOUR_ORG/YOUR_REPO'"

# Create the deployer service account
gcloud iam service-accounts create gh-deployer \
  --display-name="GitHub Actions deployer"

DEPLOYER="gh-deployer@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant it roles it needs for deploys
for role in roles/run.admin roles/artifactregistry.writer \
            roles/iam.serviceAccountUser roles/storage.admin; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$DEPLOYER" --role="$role"
done

# Bind the WIF pool to the service account
PROJECT_NUM=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
gcloud iam service-accounts add-iam-policy-binding $DEPLOYER \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUM}/locations/global/workloadIdentityPools/github/attribute.repository/YOUR_ORG/YOUR_REPO"
```

Then in the GitHub repo:

**Secrets:**
- `GCP_WIF_PROVIDER` = `projects/PROJECT_NUM/locations/global/workloadIdentityPools/github/providers/github-provider`
- `GCP_DEPLOYER_SA` = `gh-deployer@PROJECT_ID.iam.gserviceaccount.com`

**Variables:**
- `GCP_PROJECT_ID` = your project ID
- `GCP_REGION` = `us-south1`
- `APP_NAME` = `freedom-supercars`
- `ENVIRONMENT` = `prod`

---

## Daily Operations

**Deploy a change:**
Push to `main`. The workflow builds the image, pushes to Artifact Registry, runs migrations via the Cloud Run Job, and deploys the new revision.

**Add a migration:**
Drop a new file in `api/db/migrations/` named `002_description.sql`, `003_…`, etc. The runner tracks applied files by filename + SHA-256 checksum in `public._migrations`. Migrations are immutable once applied — if you change a file that has already run, the runner will refuse to start.

**Run migrations manually:**
```bash
gcloud run jobs execute freedom-supercars-prod-migrate --region=us-south1 --wait
```

**Tail API logs:**
```bash
gcloud run services logs tail freedom-supercars-prod-api --region=us-south1
```

**Rotate DB password:**
1. `terraform taint random_password.db_app_password`
2. `terraform apply`
3. New password lands in Secret Manager; next Cloud Run revision picks it up.

---

## API Surface (v1)

| Method   | Path                                          | Purpose |
|----------|-----------------------------------------------|---------|
| GET      | `/healthz`, `/readyz`                         | Probes |
| GET      | `/v1/plans`                                   | List the 4 membership plans |
| GET      | `/v1/plans/:code`                             | Plan detail |
| GET      | `/v1/plans/:code/tier-allocations`            | Per-tier caps for the plan |
| GET      | `/v1/tiers`                                   | All 5 tiers + point costs |
| GET      | `/v1/fleet?tier=4&status=available`           | Browse fleet |
| GET      | `/v1/fleet/:vehicleId/availability?from=…&to=…` | Blocked periods |
| POST     | `/v1/members`                                 | Create prospect |
| GET      | `/v1/members/:id/subscription`                | Active sub + point balance |
| GET      | `/v1/members/:id/point-history`               | Full ledger |
| POST     | `/v1/subscriptions`                           | Activate a plan (optionally rolling over) |
| POST     | `/v1/subscriptions/:id/cancel`                | Cancel |
| POST     | `/v1/reservations/_/quote`                    | Price a booking before creating it |
| POST     | `/v1/reservations`                            | Create (requested or auto-confirmed) |
| POST     | `/v1/reservations/:id/confirm`                | Trigger debits points |
| POST     | `/v1/reservations/:id/cancel`                 | Trigger refunds points |
| POST     | `/v1/reservations/:id/pickup`                 | Record mileage + fuel + condition |
| POST     | `/v1/reservations/:id/return`                 | Record return inspection |

---

## MARC — the AI Concierge

MARC (Member Assistance & Reservation Concierge) is an Anthropic-powered chat endpoint that can actually query and mutate the DB via tool use.

**Endpoint:** `POST /v1/concierge/chat` with `{ messages: [{role, content}, ...] }`, plus `X-Member-Id` header for personalized answers.

**Tools MARC has:**
- `search_fleet` — filter by tier, manufacturer, or status
- `get_vehicle_details` — full specs for one vehicle
- `check_availability` — blocked periods in a date window
- `get_member_balance` — current points and subscription
- `quote_booking` — price a hypothetical booking
- `create_reservation` — book (only after quoting + explicit confirmation)
- `list_upcoming_reservations` — the member's upcoming drives

**Config:** requires `ANTHROPIC_API_KEY` in Secret Manager (already provisioned by Terraform). Model is `claude-sonnet-4-5`; max 6 tool-use iterations per turn. If the API key is missing, MARC returns a graceful offline message rather than crashing.

**System prompt** establishes MARC as a five-star concierge, always quotes before booking, and directs out-of-scope requests to 832-726-1940.

## Web Frontend

React 18 + Vite + Tailwind, deployed as a separate Cloud Run service (nginx serving static files, scale-to-zero).

```
web/
├── src/
│   ├── main.jsx    Entry point
│   ├── App.jsx     Router + all pages (Dashboard, Fleet, VehicleDetail, MyReservations, Profile, Concierge)
│   └── index.css   Tailwind + custom components
├── index.html
├── vite.config.js
├── tailwind.config.js
├── nginx.conf.template   Rendered by nginx entrypoint with $PORT
└── Dockerfile
```

Pages:
- **Dashboard** — point balance progress bar, upcoming reservations, featured cars
- **Fleet** — filterable browser (tier, manufacturer, status)
- **VehicleDetail** — specs + availability calendar with click-to-select date range + live quote → book
- **MyReservations** — tabbed (upcoming / active / past / all), with cancel action
- **Profile** — personal info + point history table
- **MARC** — chat with tool-use trace pills

The UI uses a light burgundy + gold palette on cream backgrounds (no dark themes anywhere per house style).

Auth is currently mocked: a sign-in screen lists all active members and lets you pick one — the member ID is stored in localStorage and sent as `X-Member-Id` on every request. Swap this for Firebase Auth or Google Identity before going to prod.

Local dev:
```bash
cd web
npm install
VITE_API_URL=http://localhost:8080 npm run dev
# Then in another terminal: cd api && npm run dev
```

## Seed Data

```bash
cd api
DATABASE_URL=postgres://... npm run seed
```

Creates:
- **20 members** with member numbers `FS-SEED-0001..0020`
- Mixed subscriptions: 4 × PLAN_15, 9 × PLAN_30, 5 × PLAN_60, 2 × PLAN_100
- **~60 reservations** spread across the prior 60 and next 90 days, with realistic status weighting (40% past → returned/cancelled, 60% future → mostly confirmed/requested)
- Point transactions land automatically via existing DB triggers

Idempotent — a second run detects existing `FS-SEED-%` members and does nothing. To reseed:
```sql
DELETE FROM fs.members WHERE member_number LIKE 'FS-SEED-%';
-- cascades to subscriptions, reservations, point_transactions
```

Run the seed as a Cloud Run Job in prod:
```bash
gcloud run jobs deploy fs-seed \
  --image=$REGION-docker.pkg.dev/$PROJECT/$REPO/api:latest \
  --command=node --args=scripts/seed.js \
  --set-cloudsql-instances=$INSTANCE \
  --set-secrets=DATABASE_URL=fs-database-url:latest \
  --region=$REGION
gcloud run jobs execute fs-seed --region=$REGION --wait
```

## What's Deliberately Not Here Yet

- **Auth.** Every endpoint is currently open — mock auth on the frontend. Add Firebase Auth (or Google Identity) before going to prod.
- **Rate limiting.** Drop in `express-rate-limit` backed by Memorystore Redis.
- **Stripe webhook handler.** Add `/v1/webhooks/stripe` with raw-body signature verification.
- **Tests.** No test suite yet — `npm test` is a placeholder.
- **Real tier point values.** The migration seeds placeholder values (T2=1.5, T3=2.0, T4=3.0, T5=5.0 pts/day). Update these with Freedom Supercars' actual business numbers.
- **Runtime testing.** All JS has been syntax-checked but nothing has been booted end-to-end in this repo build. Expect a few small fixes on first `docker compose up` or `terraform apply`.

## Rough Monthly Cost (Light Traffic)

| Line Item | Cost |
|-----------|------|
| Cloud SQL db-custom-2-7680, HA off, 50 GB SSD | ~$100 |
| VPC Connector (min=2 e2-micro) | ~$10 |
| Cloud Run (scale to zero, low traffic) | ~$0–5 |
| Artifact Registry (a few GB) | ~$0.50 |
| Secret Manager (a handful of secrets) | ~$0.30 |
| Egress (small) | ~$1 |
| **Total** | **~$110–120/mo** |

Turn on HA (`db_high_availability = true`) in prod — roughly doubles Cloud SQL cost but halves RTO.
