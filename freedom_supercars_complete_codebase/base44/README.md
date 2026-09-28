# Base44 integration for FreedomDRIVE

This folder wires the FreedomDRIVE Base44 app (SMEPro workspace, app id
`6ab5bac131b677eb0a191b2d`) to the Freedom Supercars API in this repository.
The API is the system of record for reservations, points, holds, and vehicle
state. Base44 supplies pages, login, and roles.

```
base44/
  functions/fs-gateway/entry.ts   the one backend function every write goes through
  rls/lockdown.json               row-level security that closes browser writes
  README.md                       this file
```

## How the pieces fit

```
browser (Base44 pages)
   |  base44.functions.invoke("fs-gateway", { op, ... })
   v
fs-gateway (Deno, runs server side inside Base44)
   |  authenticates the session, maps user -> API member by email,
   |  applies role rules, then calls the API with FS_API_KEY
   v
Freedom Supercars API (Cloud Run, this repo)
   |  Zod validation, tier rules, plan caps, idempotency
   v
PostgreSQL (Cloud SQL)
      exclusion constraint: no overlapping holds or trips, prep buffer included
      triggers: append-only ledger, refunds, status history, vehicle log
```

Nothing in the browser holds an API key, and no page writes a reservation,
ledger, service block, or inspection record directly once the RLS in
`rls/lockdown.json` is applied.

## Operations exposed by fs-gateway

| op | who | what it does |
|----|-----|--------------|
| `balance` | member or staff | active subscription and points remaining |
| `history` | member or staff | full point ledger |
| `fleet` | anyone signed in | fleet list, optional `tier`, `status` |
| `availability` | anyone signed in | blocked periods for `vehicle_id` between `from` and `to` |
| `quote` | member or staff | price a booking before committing |
| `reserve` | member or staff | create the reservation; members confirm immediately, staff create holds |
| `confirm` | owner or staff | confirm a hold; the API trigger debits points |
| `cancel` | owner or staff | cancel; the API trigger refunds if it was confirmed |
| `submit_inspection` | staff | store structured findings; on `pickup` or `return` also post odometer, fuel, condition to the API |

Staff act on another member by passing `member_email`. A member passing someone
else's email gets 403.

`reserve` is idempotent: pass `idempotency_key` or let the function derive one
from user, vehicle, and dates, so a double-tapped button cannot double-book.

## Page wiring (what changes in the app)

Replace direct entity writes with gateway calls. Examples:

```javascript
// Make Reservation page: live quote as dates change
const q = await base44.functions.invoke("fs-gateway", {
  op: "quote", vehicle_id: fsVehicleId, pickup_at, return_at,
});
setQuote(q.data.quote);   // { days_booked, total_points_cost, balance_after_confirm }

// Confirm button
const r = await base44.functions.invoke("fs-gateway", {
  op: "reserve", vehicle_id: fsVehicleId, pickup_at, return_at,
  local_vehicle_id: vehicle.id, vehicle_name: `${vehicle.make} ${vehicle.model}`,
  branch, special_requests,
});
if (!r.data.ok) toast(r.data.error || r.data.message);

// Voice Inspection page, after the review step
await base44.functions.invoke("fs-gateway", {
  op: "submit_inspection", phase: "return", fs_reservation_id,
  local_vehicle_id: vehicle.id, vehicle_name, odometer, fuel_level,
  findings,        // [{ area, description, severity }]
  dictation,       // raw transcript
});
```

`functions.invoke` returns the raw response; the function's JSON is on `.data`,
and non-2xx responses throw with the body on `err.response.data`.

Vehicles: the Base44 `Vehicle` entity needs an `fs_vehicle_id` field holding the
API vehicle UUID (one-time mapping by stock number or make/model), or the pages
can read the fleet from `op: "fleet"` and skip the local catalog entirely.

## Deploying the function and the lockdown

Two routes, same result.

**Route A, Base44 Builder plan (MCP tools with sandbox access):**

1. `write_file` `base44/functions/fs-gateway/entry.ts` into the app sandbox.
   Writing the file deploys it.
2. Set secrets in the app: `FS_API_URL`, `FS_API_KEY`.
3. `update_entity_schema` for each entity in `rls/lockdown.json`, adding the
   `rls` block and the fields under `_schema_additions`.
4. `create_checkpoint` named "fs-gateway + RLS lockdown".

**Route B, Base44 CLI (any plan, needs `npx base44 login`):**

```bash
npm install --save-dev base44
npx base44 login
npx base44 scaffold --app-id 6ab5bac131b677eb0a191b2d   # pulls the app locally
# copy functions/fs-gateway into the scaffolded base44/functions/
npx base44 secrets set FS_API_URL=https://... FS_API_KEY=...
npx base44 functions deploy fs-gateway
# add the rls blocks to base44/entities/*.jsonc, then
npx base44 entities push
```

The API keys come from Terraform: `terraform output -raw api_key_primary`.

## Order of operations for go-live

1. `terraform apply` (creates the API keys and secrets alongside the services).
2. Push `main` so CI builds, migrates, and deploys API and web.
3. Set `FS_API_URL` and `FS_API_KEY` in Base44 and deploy `fs-gateway`.
4. Apply the RLS lockdown. From this point the pages cannot write around the API.
5. Rewire the four write paths in the app: reserve, confirm, cancel, inspection.
6. Run `npm run smoke` in `api/` against the deployed API URL to prove the rules hold in the cloud, not just locally.
