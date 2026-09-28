// @ts-nocheck
// fs-gateway: the single enforcement point between the FreedomDRIVE Base44
// front end and the SMEPro Freedom Supercars API on Cloud Run.
//
// Every page in the app calls this function instead of writing reservation,
// ledger, or inspection records itself:
//
//   const res = await base44.functions.invoke("fs-gateway", { op: "reserve", ... });
//   const data = res.data;            // invoke() returns the raw axios response
//
// The function:
//   1. authenticates the caller with the Base44 session (createClientFromRequest)
//   2. maps the signed-in user to the API member record by email
//   3. applies role rules (members act only for themselves, staff for anyone)
//   4. forwards the operation to the API with the server-held FS_API_KEY
//   5. mirrors the outcome into the Base44 entities the pages read from
//
// Required app secrets (Base44 dashboard -> Settings -> Secrets):
//   FS_API_URL   e.g. https://freedom-supercars-prod-api-xxxx-uc.a.run.app
//   FS_API_KEY   one of the API's accepted keys (terraform output api_key_primary)

import { createClientFromRequest } from "npm:@base44/sdk";

const API_URL = (Deno.env.get("FS_API_URL") || "").replace(/\/+$/, "");
const API_KEY = Deno.env.get("FS_API_KEY") || "";

const STAFF_ROLES = new Set(["admin", "Admin", "Management", "Branch Manager", "Vehicle Staff", "Member Services", "Finance", "Onboarding"]);

type Json = Record<string, unknown>;

function bad(status: number, error: string, extra: Json = {}) {
  return Response.json({ ok: false, error, ...extra }, { status });
}

async function api(path: string, init: RequestInit & { memberId?: string; idempotencyKey?: string } = {}) {
  if (!API_URL || !API_KEY) throw new Error("FS_API_URL / FS_API_KEY are not configured");
  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-api-key": API_KEY,
  };
  if (init.memberId) headers["x-member-id"] = init.memberId;
  if (init.idempotencyKey) headers["idempotency-key"] = init.idempotencyKey;
  const res = await fetch(API_URL + path, { ...init, headers });
  const text = await res.text();
  let body: Json = {};
  try { body = text ? JSON.parse(text) : {}; } catch { body = { raw: text }; }
  return { status: res.status, ok: res.ok, body };
}

// Resolve the API member for the signed-in user (or, for staff, for the
// member they name). Cached on the Base44 Member entity as fs_member_id so the
// email lookup only happens once per member.
async function resolveMember(base44: any, user: any, requested?: string) {
  const isStaff = STAFF_ROLES.has(user.role) || STAFF_ROLES.has(user._app_role);
  let email = user.email;
  if (requested && requested !== user.email) {
    if (!isStaff) return { error: bad(403, "Members may only act on their own account") };
    email = requested;
  }
  const rows = await base44.asServiceRole.entities.Member.filter({ email }, undefined, 1);
  const local = rows[0] || null;
  if (local?.fs_member_id) return { member: local, fsMemberId: local.fs_member_id, isStaff };
  const r = await api(`/v1/members/by-email/${encodeURIComponent(email)}`);
  if (!r.ok) return { error: bad(404, "No Freedom Supercars member record for " + email) };
  const fsMemberId = (r.body as any).member.id as string;
  if (local) await base44.asServiceRole.entities.Member.update(local.id, { fs_member_id: fsMemberId });
  return { member: local, fsMemberId, isStaff };
}

async function activeSubscriptionId(fsMemberId: string) {
  const r = await api(`/v1/members/${fsMemberId}/subscription`);
  if (!r.ok) return null;
  return ((r.body as any).active_subscription?.subscription_id || (r.body as any).active_subscription?.id) as string | null;
}

Deno.serve(async (req: any) => {
  if (req.method !== "POST") return bad(405, "POST only");
  const base44 = createClientFromRequest(req);
  const user = await base44.auth.me().catch(() => null);
  if (!user) return bad(401, "Sign in required");

  let input: Json;
  try { input = await req.json(); } catch { return bad(400, "Body must be JSON"); }
  const op = String(input.op || "");

  try {
    switch (op) {
      // ---------------------------------------------------------------- reads
      case "balance": {
        const m = await resolveMember(base44, user, input.member_email as string | undefined);
        if ("error" in m) return m.error;
        const r = await api(`/v1/members/${m.fsMemberId}/subscription`, { memberId: m.fsMemberId });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "history": {
        const m = await resolveMember(base44, user, input.member_email as string | undefined);
        if ("error" in m) return m.error;
        const r = await api(`/v1/members/${m.fsMemberId}/point-history`, { memberId: m.fsMemberId });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "availability": {
        const { vehicle_id, from, to } = input as any;
        const r = await api(`/v1/fleet/${vehicle_id}/availability?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "fleet": {
        const q = new URLSearchParams();
        if (input.tier) q.set("tier", String(input.tier));
        if (input.status) q.set("status", String(input.status));
        const r = await api(`/v1/fleet?${q}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vendors": {
        const r = await api(`/v1/fleet/vendors`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }

      // ---------------------------------------------------------- booking
      case "quote":
      case "reserve": {
        const m = await resolveMember(base44, user, input.member_email as string | undefined);
        if ("error" in m) return m.error;
        const subscription_id = await activeSubscriptionId(m.fsMemberId);
        if (!subscription_id) return bad(409, "No active subscription");
        const payload: Json = {
          subscription_id,
          vehicle_id: input.vehicle_id,
          pickup_at: input.pickup_at,
          return_at: input.return_at,
          destination: input.destination,
          purpose: input.purpose,
          member_notes: input.special_requests,
          // Members confirm immediately (points move now). Staff-created holds
          // stay 'requested' until the member confirms in the app.
          auto_confirm: op === "reserve" && !m.isStaff ? true : Boolean(input.auto_confirm),
        };
        if (op === "quote") {
          const r = await api(`/v1/reservations/_/quote`, { method: "POST", body: JSON.stringify(payload), memberId: m.fsMemberId });
          return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
        }
        const idempotencyKey = String(input.idempotency_key || `${user.id}:${input.vehicle_id}:${input.pickup_at}:${input.return_at}`);
        const r = await api(`/v1/reservations`, { method: "POST", body: JSON.stringify(payload), memberId: m.fsMemberId, idempotencyKey });
        if (r.ok && m.member) {
          const res = (r.body as any).reservation;
          // Mirror into the Base44 Reservation entity so existing pages render it.
          await base44.asServiceRole.entities.Reservation.create({
            fs_reservation_id: res.id,
            confirmation_code: res.confirmation_code,
            member_id: m.member.id,
            member_email: m.member.email,
            member_name: m.member.full_name,
            vehicle_id: input.local_vehicle_id ?? null,
            vehicle_name: input.vehicle_name ?? null,
            branch: input.branch ?? m.member.home_branch ?? null,
            start_date: String(res.pickup_at).slice(0, 10),
            end_date: String(res.return_at).slice(0, 10),
            weekday_count: res.days_booked,
            weekend_count: 0,
            points_cost: res.total_points_cost,
            status: res.status,
            special_requests: input.special_requests ?? "",
            booked_by: user.email,
          }).catch(() => null);
        }
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "confirm":
      case "cancel": {
        const m = await resolveMember(base44, user, input.member_email as string | undefined);
        if ("error" in m) return m.error;
        const id = String(input.fs_reservation_id || "");
        if (!id) return bad(400, "fs_reservation_id required");
        // A member may only touch their own reservation
        const own = await api(`/v1/reservations/${id}`);
        if (!own.ok) return Response.json({ ok: false, ...own.body }, { status: own.status });
        if (!m.isStaff && (own.body as any).reservation.member_id !== m.fsMemberId) return bad(403, "Not your reservation");
        const r = await api(`/v1/reservations/${id}/${op}`, { method: "POST", body: JSON.stringify(op === "cancel" ? { reason: input.reason || "Cancelled in app" } : {}), memberId: m.fsMemberId });
        if (r.ok) {
          const rows = await base44.asServiceRole.entities.Reservation.filter({ fs_reservation_id: id }, undefined, 1);
          if (rows[0]) await base44.asServiceRole.entities.Reservation.update(rows[0].id, { status: (r.body as any).reservation.status, cancelled_at: op === "cancel" ? new Date().toISOString() : null, cancelled_by: op === "cancel" ? user.email : null }).catch(() => null);
        }
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }

      // -------------------------------------------------------- inspections
      // Voice or typed inspection from staff. Structured findings are stored in
      // the Base44 Inspection entity for the ops screens; when the inspection
      // belongs to a pickup or return, the odometer, fuel and condition are also
      // posted to the API so the fs ledger of vehicle state stays authoritative.
      case "submit_inspection": {
        const isStaff = STAFF_ROLES.has(user.role) || STAFF_ROLES.has(user._app_role);
        if (!isStaff) return bad(403, "Staff only");
        const findings = Array.isArray(input.findings) ? input.findings : [];
        const severities = findings.map((f: any) => f.severity);
        const overall = severities.includes("Severe") ? "needs_attention" : severities.includes("Moderate") ? "fair" : severities.includes("Minor") ? "good" : "excellent";
        const record = await base44.asServiceRole.entities.Inspection.create({
          vehicle_id: input.local_vehicle_id ?? null,
          vehicle_name: input.vehicle_name ?? null,
          member_id: input.local_member_id ?? null,
          phase: input.phase ?? "general",
          odometer: input.odometer ?? null,
          fuel_level: input.fuel_level ?? null,
          findings,
          overall_condition: overall,
          dictation: input.dictation ?? "",
          technician: user.email,
          submitted_at: new Date().toISOString(),
        });
        let apiResult: Json | null = null;
        if ((input.phase === "pickup" || input.phase === "return") && input.fs_reservation_id) {
          const body: Json = {
            mileage: input.odometer,
            fuel_level_pct: input.fuel_level,
            condition: overall,
            notes: String(input.dictation || "").slice(0, 2000),
          };
          if (input.phase === "pickup") body.pre_existing_damage = findings.filter((f: any) => f.severity !== "Note").map((f: any) => `${f.area}: ${f.description}`).join("; ").slice(0, 2000);
          else body.new_damage = findings.filter((f: any) => f.severity !== "Note").map((f: any) => `${f.area}: ${f.description}`).join("; ").slice(0, 2000);
          const r = await api(`/v1/reservations/${input.fs_reservation_id}/${input.phase}`, { method: "POST", body: JSON.stringify(body) });
          apiResult = { status: r.status, ...r.body };
        }
        return Response.json({ ok: true, inspection: record, api: apiResult });
      }

      // ---------------------------------------------------------- members (Guide 6.1)
      case "check_duplicate_member": {
        const r = await api(`/v1/members/check-duplicate`, {
          method: "POST",
          body: JSON.stringify(input)
        });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }

      case "onboard_member": {
        const isStaff = STAFF_ROLES.has(user.role) || STAFF_ROLES.has(user._app_role);
        if (!isStaff) return bad(403, "Staff only");
        const r = await api(`/v1/members/onboard`, {
          method: "POST",
          body: JSON.stringify(input)
        });
        if (!r.ok) return Response.json({ ok: false, ...r.body }, { status: r.status });

        const m = (r.body as any).member;
        let localMember = null;
        try {
          localMember = await base44.asServiceRole.entities.Member.create({
            fs_member_id: m.member_id,
            first_name: m.first_name,
            last_name: m.last_name,
            full_name: `${m.first_name} ${m.last_name}`,
            email: m.email,
            phone: input.phone || null,
            status: "Pending",
            member_number: null,
            home_branch: input.primary_location_code || "HOU",
            plan_name: input.plan_name || null,
            tier: 1,
            points_balance: 0,
            active_reservations: 0,
          });
        } catch (mirrorErr) {
          console.error("Base44 member mirror error:", mirrorErr);
        }

        return Response.json({ ok: true, member: m, local_member: localMember }, { status: 201 });
      }

      case "activate_member": {
        const isStaff = STAFF_ROLES.has(user.role) || STAFF_ROLES.has(user._app_role);
        if (!isStaff) return bad(403, "Staff only");
        const fsMemberId = input.fs_member_id;
        if (!fsMemberId) return bad(400, "fs_member_id required");

        const r = await api(`/v1/members/${fsMemberId}/activate`, {
          method: "POST",
          body: JSON.stringify({
            payment_arrangement_confirmed: Boolean(input.payment_arrangement_confirmed ?? true),
            activation_date: input.activation_date,
            planned_start_date: input.planned_start_date,
            joining_bonus_points: Number(input.joining_bonus_points || 0),
          })
        });
        if (!r.ok) return Response.json({ ok: false, ...r.body }, { status: r.status });

        const act = (r.body as any).activation;
        try {
          const rows = await base44.asServiceRole.entities.Member.filter({ fs_member_id: fsMemberId }, undefined, 1);
          if (rows[0]) {
            await base44.asServiceRole.entities.Member.update(rows[0].id, {
              status: "Active",
              member_number: act.member_number,
              member_since: act.member_since,
              points_balance: act.points_balance,
            });

            if (act.points_balance > 0) {
              await base44.asServiceRole.entities.PointsLedger.create({
                member_id: rows[0].id,
                member_email: rows[0].email,
                member_name: rows[0].full_name,
                entry_type: "allocation",
                amount: act.points_balance,
                balance_after: act.points_balance,
                reason: "Initial Annual Allocation",
                created_at: new Date().toISOString(),
              }).catch(() => null);
            }
          }
        } catch (mirrorErr) {
          console.error("Base44 member activation mirror error:", mirrorErr);
        }

        return Response.json({ ok: true, activation: act });
      }

      // ------------------------------------------------------------- VOP Ops
      case "vop_list_partners": {
        const q = input.is_active !== undefined ? `?is_active=${input.is_active}` : "";
        const r = await api(`/v1/vop/partners${q}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_get_partner": {
        const id = String(input.id || input.partner_id || "");
        if (!id) return bad(400, "id or partner_id required");
        const r = await api(`/v1/vop/partners/${id}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_create_partner": {
        const r = await api(`/v1/vop/partners`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_update_partner": {
        const id = String(input.id || input.partner_id || "");
        if (!id) return bad(400, "id or partner_id required");
        const r = await api(`/v1/vop/partners/${id}`, { method: "PUT", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_delete_partner": {
        const id = String(input.id || input.partner_id || "");
        if (!id) return bad(400, "id or partner_id required");
        const r = await api(`/v1/vop/partners/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_add_contact": {
        const id = String(input.partner_id || "");
        if (!id) return bad(400, "partner_id required");
        const r = await api(`/v1/vop/partners/${id}/contacts`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_update_contact": {
        const id = String(input.partner_id || "");
        const cid = String(input.contact_id || "");
        if (!id || !cid) return bad(400, "partner_id and contact_id required");
        const r = await api(`/v1/vop/partners/${id}/contacts/${cid}`, { method: "PUT", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_delete_contact": {
        const id = String(input.partner_id || "");
        const cid = String(input.contact_id || "");
        if (!id || !cid) return bad(400, "partner_id and contact_id required");
        const r = await api(`/v1/vop/partners/${id}/contacts/${cid}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_list_plans": {
        const q = new URLSearchParams();
        if (input.vehicle_id) q.set("vehicle_id", String(input.vehicle_id));
        if (input.vehicle_partner_id) q.set("vehicle_partner_id", String(input.vehicle_partner_id));
        if (input.status) q.set("status", String(input.status));
        const r = await api(`/v1/vop/plans?${q}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_get_plan": {
        const id = String(input.id || input.plan_id || "");
        if (!id) return bad(400, "id or plan_id required");
        const r = await api(`/v1/vop/plans/${id}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_create_plan": {
        const r = await api(`/v1/vop/plans`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_update_plan": {
        const id = String(input.id || input.plan_id || "");
        if (!id) return bad(400, "id or plan_id required");
        const r = await api(`/v1/vop/plans/${id}`, { method: "PUT", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_delete_plan": {
        const id = String(input.id || input.plan_id || "");
        if (!id) return bad(400, "id or plan_id required");
        const r = await api(`/v1/vop/plans/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_list_guarantee_groups": {
        const q = new URLSearchParams();
        if (input.vehicle_partner_id) q.set("vehicle_partner_id", String(input.vehicle_partner_id));
        if (input.is_active !== undefined) q.set("is_active", String(input.is_active));
        const r = await api(`/v1/vop/guarantee-groups?${q}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_get_guarantee_group": {
        const id = String(input.id || input.group_id || "");
        if (!id) return bad(400, "id or group_id required");
        const r = await api(`/v1/vop/guarantee-groups/${id}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_create_guarantee_group": {
        const r = await api(`/v1/vop/guarantee-groups`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_update_guarantee_group": {
        const id = String(input.id || input.group_id || "");
        if (!id) return bad(400, "id or group_id required");
        const r = await api(`/v1/vop/guarantee-groups/${id}`, { method: "PUT", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_delete_guarantee_group": {
        const id = String(input.id || input.group_id || "");
        if (!id) return bad(400, "id or group_id required");
        const r = await api(`/v1/vop/guarantee-groups/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_add_group_plan": {
        const id = String(input.group_id || "");
        if (!id) return bad(400, "group_id required");
        const r = await api(`/v1/vop/guarantee-groups/${id}/plans`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_remove_group_plan": {
        const id = String(input.group_id || "");
        const planId = String(input.plan_id || input.vop_plan_id || "");
        if (!id || !planId) return bad(400, "group_id and plan_id required");
        const r = await api(`/v1/vop/guarantee-groups/${id}/plans/${planId}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_list_periods": {
        const r = await api(`/v1/vop/payout-periods`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_create_period": {
        const r = await api(`/v1/vop/payout-periods`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_close_period": {
        const id = String(input.id || input.period_id || input.payout_period_id || "");
        if (!id) return bad(400, "period_id required");
        const r = await api(`/v1/vop/payout-periods/${id}/close`, { method: "POST" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_update_period": {
        const id = String(input.id || input.period_id || input.payout_period_id || "");
        if (!id) return bad(400, "period_id required");
        const r = await api(`/v1/vop/payout-periods/${id}`, { method: "PUT", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_list_ledger": {
        const q = new URLSearchParams();
        if (input.payout_period_id) q.set("payout_period_id", String(input.payout_period_id));
        if (input.vehicle_id) q.set("vehicle_id", String(input.vehicle_id));
        if (input.vehicle_partner_id) q.set("vehicle_partner_id", String(input.vehicle_partner_id));
        if (input.entry_type) q.set("entry_type", String(input.entry_type));
        const r = await api(`/v1/vop/ledger?${q}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_append_payout": {
        const r = await api(`/v1/vop/ledger`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_list_summaries": {
        const q = new URLSearchParams();
        if (input.payout_period_id) q.set("payout_period_id", String(input.payout_period_id));
        if (input.vehicle_partner_id) q.set("vehicle_partner_id", String(input.vehicle_partner_id));
        const r = await api(`/v1/vop/summaries?${q}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "vop_compute_summaries": {
        const r = await api(`/v1/vop/summaries/compute`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }

      // ------------------------------------------------------------- MPC Ops
      case "mpc_list_customizations": {
        const q = new URLSearchParams();
        if (input.member_id) q.set("member_id", String(input.member_id));
        if (input.is_active !== undefined) q.set("is_active", String(input.is_active));
        const r = await api(`/v1/mpc/customizations?${q}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_get_customization": {
        const id = String(input.id || input.customization_id || "");
        if (!id) return bad(400, "id or customization_id required");
        const r = await api(`/v1/mpc/customizations/${id}`);
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_create_customization": {
        const r = await api(`/v1/mpc/customizations`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_update_customization": {
        const id = String(input.id || input.customization_id || "");
        if (!id) return bad(400, "id or customization_id required");
        const r = await api(`/v1/mpc/customizations/${id}`, { method: "PUT", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_delete_customization": {
        const id = String(input.id || input.customization_id || "");
        if (!id) return bad(400, "id or customization_id required");
        const r = await api(`/v1/mpc/customizations/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_add_pricing": {
        const r = await api(`/v1/mpc/pricing`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_delete_pricing": {
        const id = String(input.id || input.pricing_id || "");
        if (!id) return bad(400, "id required");
        const r = await api(`/v1/mpc/pricing/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_add_points_caps": {
        const r = await api(`/v1/mpc/points-and-caps`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_delete_points_caps": {
        const id = String(input.id || input.points_and_caps_id || "");
        if (!id) return bad(400, "id required");
        const r = await api(`/v1/mpc/points-and-caps/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_add_booking_rule": {
        const r = await api(`/v1/mpc/bookings`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_delete_booking_rule": {
        const id = String(input.id || input.booking_id || "");
        if (!id) return bad(400, "id required");
        const r = await api(`/v1/mpc/bookings/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_add_mileage": {
        const r = await api(`/v1/mpc/mileage`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_delete_mileage": {
        const id = String(input.id || input.mileage_id || "");
        if (!id) return bad(400, "id required");
        const r = await api(`/v1/mpc/mileage/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_add_perk": {
        const r = await api(`/v1/mpc/perks`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_delete_perk": {
        const id = String(input.id || input.perk_id || "");
        if (!id) return bad(400, "id required");
        const r = await api(`/v1/mpc/perks/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_set_branch_access": {
        const r = await api(`/v1/mpc/branch-access`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_delete_branch_access": {
        const id = String(input.id || "");
        if (!id) return bad(400, "id required");
        const r = await api(`/v1/mpc/branch-access/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_set_tier_access": {
        const r = await api(`/v1/mpc/tier-access`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_delete_tier_access": {
        const id = String(input.id || "");
        if (!id) return bad(400, "id required");
        const r = await api(`/v1/mpc/tier-access/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_assign_tier": {
        const r = await api(`/v1/mpc/tier-assignment`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_delete_tier_assignment": {
        const id = String(input.id || "");
        if (!id) return bad(400, "id required");
        const r = await api(`/v1/mpc/tier-assignment/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_set_tier_rate": {
        const r = await api(`/v1/mpc/tier-point-rate`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_delete_tier_rate": {
        const id = String(input.id || "");
        if (!id) return bad(400, "id required");
        const r = await api(`/v1/mpc/tier-point-rate/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_set_free_pass": {
        const r = await api(`/v1/mpc/free-pass`, { method: "POST", body: JSON.stringify(input) });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }
      case "mpc_delete_free_pass": {
        const id = String(input.id || "");
        if (!id) return bad(400, "id required");
        const r = await api(`/v1/mpc/free-pass/${id}`, { method: "DELETE" });
        return Response.json({ ok: r.ok, ...r.body }, { status: r.status });
      }

      default:
        return bad(400, `Unknown op '${op}'`);
    }
  } catch (err) {
    console.error("fs-gateway", op, err);
    return bad(502, "Upstream error", { detail: String((err as Error).message || err) });
  }
});
