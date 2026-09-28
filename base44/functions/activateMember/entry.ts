// @ts-nocheck
import { createClientFromRequest } from "npm:@base44/sdk";

const STAFF_ROLES = new Set([
  "admin", "Admin", "Management", "Branch Manager", "Vehicle Staff",
  "Member Services", "Finance", "Onboarding"
]);

const API_URL = (Deno.env.get("FS_API_URL") || "").replace(/\/+$/, "");
const API_KEY = Deno.env.get("FS_API_KEY") || "";

export default async function (req: Request) {
  try {
    const base44 = createClientFromRequest(req);
    const user = await base44.auth.me();
    if (!user) return Response.json({ ok: false, error: "Authentication required" }, { status: 401 });

    const isStaff = STAFF_ROLES.has(user.role) || STAFF_ROLES.has(user._app_role);
    if (!isStaff) return Response.json({ ok: false, error: "Staff role required to activate members" }, { status: 403 });

    const sr = base44.asServiceRole;
    const body = await req.json().catch(() => ({}));
    const memberId = String(body.member_id || body.id || "");
    if (!memberId) return Response.json({ ok: false, error: "member_id is required" }, { status: 400 });

    // Fetch Base44 member
    const member = await sr.entities.Member.get(memberId);
    if (!member) return Response.json({ ok: false, error: "Member not found" }, { status: 404 });

    // 6.3-C04: Second activation does not mint a new number
    if (member.status === "Active" && member.member_number) {
      return Response.json({
        ok: true,
        message: "Member is already active",
        member_id: member.id,
        member_number: member.member_number,
        member_seq: member.member_seq,
        member_since: member.member_since,
        status: member.status,
        re_activated: true,
      });
    }

    if (!API_URL || !API_KEY) {
      return Response.json({ ok: false, error: "FS_API_URL / FS_API_KEY not configured" }, { status: 500 });
    }

    // Call Cloud Run atomic activation endpoint (6.3-R02, 6.3-R03, 6.3-C02)
    const fsTargetId = member.fs_member_id || member.id;
    const apiRes = await fetch(`${API_URL}/v1/members/${fsTargetId}/activate`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": API_KEY,
      },
      body: JSON.stringify({
        payment_arrangement_confirmed: body.payment_arrangement_confirmed ?? true,
        activation_date: body.activation_date,
        joining_bonus_points: body.joining_bonus_points || 0,
      }),
    });

    const apiData = await apiRes.json();
    if (!apiRes.ok || !apiData.ok) {
      // 6.3-C03: Failed activation leaves NO number behind
      return Response.json({
        ok: false,
        error: apiData.error || "Activation rejected by Cloud SQL engine",
        detail: apiData
      }, { status: apiRes.status });
    }

    const { member_number, member_seq, member_since } = apiData.activation;

    // Atomically update Base44 Member entity
    const updatedMember = await sr.entities.Member.update(member.id, {
      status: "Active",
      member_number,
      member_seq,
      member_since,
      fs_member_id: apiData.activation.member_id || member.fs_member_id,
    });

    // Ensure MemberBranchHistory has open row (6.3-C08, 6.3-C13)
    try {
      const openRows = await sr.entities.MemberBranchHistory.filter({ member_id: member.id, effective_to: null });
      if (!openRows || openRows.length === 0) {
        await sr.entities.MemberBranchHistory.create({
          member_id: member.id,
          branch_code: member.home_branch_code || "HOU",
          branch_name: member.home_branch || "Houston",
          effective_from: member_since || new Date().toISOString().slice(0, 10),
          effective_to: null,
          reason: "Charter Activation",
        });
      }
    } catch (e) {
      console.warn("activateMember: MemberBranchHistory sync note", e);
    }

    return Response.json({
      ok: true,
      activation: {
        member: updatedMember,
        member_number,
        member_seq,
        member_since,
        points_balance: apiData.activation.points_balance,
      }
    });
  } catch (e) {
    console.error("activateMember error:", e);
    return Response.json({ ok: false, error: String((e as Error).message || e) }, { status: 500 });
  }
}
