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
    if (!isStaff) return Response.json({ ok: false, error: "Staff role required to transfer member home branch" }, { status: 403 });

    const sr = base44.asServiceRole;
    const body = await req.json().catch(() => ({}));
    const memberId = String(body.member_id || body.id || "");
    const newBranch = String(body.new_branch || body.home_branch || "").trim();
    let newBranchCode = String(body.new_branch_code || "").trim().toUpperCase();
    const reason = String(body.reason || "Home Branch Relocation").trim();
    const regenerateNumber = Boolean(body.regenerate_number);

    if (!memberId) return Response.json({ ok: false, error: "member_id is required" }, { status: 400 });
    if (!newBranch && !newBranchCode) {
      return Response.json({ ok: false, error: "new_branch or new_branch_code is required" }, { status: 400 });
    }

    if (!newBranchCode) {
      if (newBranch.toLowerCase().includes("houston")) newBranchCode = "HOU";
      else if (newBranch.toLowerCase().includes("dallas")) newBranchCode = "DFW";
      else if (newBranch.toLowerCase().includes("austin")) newBranchCode = "ATX";
      else newBranchCode = "HOU";
    }

    const member = await sr.entities.Member.get(memberId);
    if (!member) return Response.json({ ok: false, error: "Member not found" }, { status: 404 });

    const fsTargetId = member.fs_member_id || member.id;
    let apiTransferResult: any = null;

    if (API_URL && API_KEY) {
      const apiRes = await fetch(`${API_URL}/v1/members/${fsTargetId}/transfer-branch`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": API_KEY,
        },
        body: JSON.stringify({
          new_branch_code: newBranchCode,
          reason,
          regenerate_number: regenerateNumber,
        }),
      });

      const apiData = await apiRes.json();
      if (!apiRes.ok || !apiData.ok) {
        return Response.json({
          ok: false,
          error: apiData.error || "Branch transfer rejected by Cloud SQL engine",
          detail: apiData
        }, { status: apiRes.status });
      }
      apiTransferResult = apiData.transfer;
    }

    const todayIso = new Date().toISOString().slice(0, 10);
    const updatedMemberNumber = apiTransferResult?.member_number || member.member_number;

    // 6.3-C10, 6.3-R09: Close open history row and open a new one in one sequence
    const openRows = await sr.entities.MemberBranchHistory.filter({ member_id: member.id, effective_to: null });
    if (openRows && openRows.length > 0) {
      for (const openRow of openRows) {
        await sr.entities.MemberBranchHistory.update(openRow.id, {
          effective_to: todayIso,
        });
      }
    }

    await sr.entities.MemberBranchHistory.create({
      member_id: member.id,
      branch_code: newBranchCode,
      branch_name: newBranch || newBranchCode,
      effective_from: todayIso,
      effective_to: null,
      reason,
    });

    // 6.3-C11: Update Member record home_branch to match open row
    const updatedMember = await sr.entities.Member.update(member.id, {
      home_branch: newBranch || newBranchCode,
      home_branch_code: newBranchCode,
      member_number: updatedMemberNumber,
    });

    return Response.json({
      ok: true,
      transfer: {
        member: updatedMember,
        member_id: member.id,
        new_branch: newBranch || newBranchCode,
        new_branch_code: newBranchCode,
        member_number: updatedMemberNumber,
        effective_from: todayIso,
        reason,
      }
    });
  } catch (e) {
    console.error("transferMember error:", e);
    return Response.json({ ok: false, error: String((e as Error).message || e) }, { status: 500 });
  }
}
