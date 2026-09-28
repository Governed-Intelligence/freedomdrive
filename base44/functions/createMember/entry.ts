// @ts-nocheck
import { createClientFromRequest } from "npm:@base44/sdk";

const STAFF_ROLES = new Set([
  "admin", "Admin", "Management", "Branch Manager", "Vehicle Staff",
  "Member Services", "Finance", "Onboarding"
]);

const STATE_CODES = new Set([
  "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
  "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC",
  "SD","TN","TX","UT","VT","VA","WA","WV","WI","WY","DC",
]);

const API_URL = (Deno.env.get("FS_API_URL") || "").replace(/\/+$/, "");
const API_KEY = Deno.env.get("FS_API_KEY") || "";

const normName = (s: unknown) => String(s ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
const normPhone = (s: unknown) => {
  const d = String(s ?? "").replace(/\D/g, "");
  return d.length === 11 && d.startsWith("1") ? d.slice(1) : d;
};
const normEmail = (s: unknown) => String(s ?? "").trim().toLowerCase();
const normAddress = (s: unknown) => {
  const text = String(s ?? "");
  const number = (text.match(/\b(\d{1,6})\b/) || [])[1] || "";
  const zip = (text.match(/\b(\d{5})(?:-\d{4})?\s*$/) || [])[1] || "";
  return number && zip ? `${number}|${zip}` : "";
};
const lastNameOf = (fullName: unknown) => {
  const parts = String(fullName ?? "").trim().split(/\s+/);
  return parts.length ? parts[parts.length - 1] : "";
};

type Match = { member_id: string; full_name: string; status: string; reasons: string[] };

function detectDuplicates(candidate: Record<string, unknown>, existing: Record<string, unknown>[]): Match[] {
  const cLicense = String(candidate.license_number ?? "").replace(/\s/g, "").toUpperCase();
  const cEmail = normEmail(candidate.email);
  const cLast = normName(lastNameOf(candidate.full_name));
  const cDob = String(candidate.date_of_birth ?? "");
  const cPhone = normPhone(candidate.phone);
  const cAddr = normAddress(candidate.address);
  const out: Match[] = [];

  for (const m of existing) {
    const reasons: string[] = [];
    if (cLicense && String(m.license_number ?? "").replace(/\s/g, "").toUpperCase() === cLicense) {
      reasons.push("license number");
    }
    if (cEmail && normEmail(m.email) === cEmail) {
      reasons.push("email");
    }
    const pair: string[] = [];
    if (cLast && normName(lastNameOf(m.full_name)) === cLast) pair.push("last name");
    if (cDob && String(m.date_of_birth ?? "") === cDob) pair.push("date of birth");
    if (cPhone && normPhone(m.phone) === cPhone) pair.push("phone");
    if (cAddr && normAddress(m.address) === cAddr) pair.push("street address");
    if (pair.length >= 2) reasons.push(pair.join(" and "));

    if (reasons.length) {
      out.push({
        member_id: String(m.id),
        full_name: String(m.full_name ?? ""),
        status: String(m.status ?? ""),
        reasons
      });
    }
  }
  return out;
}

export default async function (req: Request) {
  try {
    const base44 = createClientFromRequest(req);
    const user = await base44.auth.me();
    if (!user) return Response.json({ ok: false, error: "Authentication required" }, { status: 401 });

    const isStaff = STAFF_ROLES.has(user.role) || STAFF_ROLES.has(user._app_role);
    if (!isStaff) return Response.json({ ok: false, error: "Staff role required" }, { status: 403 });

    const sr = base44.asServiceRole;
    const body = await req.json().catch(() => ({}));
    const {
      full_name, preferred_name, email, phone, address, date_of_birth,
      license_number, license_state, license_expiry,
      insurance_provider, insurance_policy, insurance_expiry,
      plan_name, home_branch, home_branch_code,
      acknowledge_duplicates, duplicate_review_note,
    } = body;

    if (!full_name || !String(full_name).trim()) {
      return Response.json({ ok: false, error: "full_name is required (6.1 workflow 1.1)" }, { status: 400 });
    }
    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(email))) {
      return Response.json({ ok: false, error: "A valid email is required (6.1-R05)" }, { status: 400 });
    }
    if (!home_branch) {
      return Response.json({ ok: false, error: "home_branch is required (6.1 workflow 1.4)" }, { status: 400 });
    }
    if (license_state && !STATE_CODES.has(String(license_state).toUpperCase())) {
      return Response.json({ ok: false, error: `License state '${license_state}' is not in STATE_SELECT (6.1-C04)` }, { status: 400 });
    }
    if (license_number && (!license_state || !license_expiry)) {
      return Response.json({ ok: false, error: "A driving license needs number, state and expiry together (6.1 workflow 1.3)" }, { status: 400 });
    }

    // 6.1-R13, 6.1-R15, 6.3-C01: member_number and member_since must not be set on save
    if (body.member_number !== undefined || body.member_since !== undefined) {
      return Response.json({
        ok: false,
        error: "member_number and member_since are set by activation, never on save (6.1-R13, 6.3-C01)"
      }, { status: 400 });
    }

    // Duplicate detection runs before the profile is written (6.1-R03)
    const existing = await sr.entities.Member.list("-created_date", 1000);
    const matches = detectDuplicates(body, existing || []);
    const former = matches.filter((m) => m.status === "Former");

    if (former.length) {
      return Response.json({
        ok: false,
        error: "Match against a former member; use the rejoin path, which reuses the existing record and number (6.1 edge case 1, 6.1-C12)",
        rejoin_candidates: former,
      }, { status: 409 });
    }

    if (matches.length && !acknowledge_duplicates) {
      return Response.json({
        ok: false,
        error: "Possible duplicate; review the matches and resubmit with acknowledge_duplicates=true and a duplicate_review_note (6.1-R03)",
        duplicate_flag: true,
        matches,
      }, { status: 409 });
    }

    if (matches.length && acknowledge_duplicates && !String(duplicate_review_note ?? "").trim()) {
      return Response.json({
        ok: false,
        error: "A duplicate_review_note is required when proceeding past a flag (6.1-C11)"
      }, { status: 400 });
    }

    const now = new Date().toISOString();
    const branchCode = (home_branch_code || (home_branch.toLowerCase().includes("houston") ? "HOU" : home_branch.toLowerCase().includes("dallas") ? "DFW" : "ATX")).toUpperCase();

    // Forward to Cloud Run API if configured
    let fsMemberId: string | null = null;
    if (API_URL && API_KEY) {
      try {
        const apiRes = await fetch(`${API_URL}/v1/members/onboard`, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-api-key": API_KEY,
          },
          body: JSON.stringify({
            first_name: String(full_name).trim().split(/\s+/)[0],
            last_name: lastNameOf(full_name),
            preferred_name: preferred_name ? String(preferred_name).trim() : String(full_name).trim().split(/\s+/)[0],
            email: normEmail(email),
            phone: phone ? String(phone).trim() : "+1-713-555-0100",
            date_of_birth: date_of_birth || undefined,
            drivers_license_number: license_number ? String(license_number).trim() : "TX-PENDING",
            drivers_license_state: license_state ? String(license_state).toUpperCase() : "TX",
            drivers_license_expires: license_expiry || undefined,
            primary_location_code: branchCode,
            override_duplicate_flag: Boolean(acknowledge_duplicates),
            duplicate_review_note: duplicate_review_note || undefined,
          }),
        });
        const apiData = await apiRes.json();
        if (apiData?.member?.member_id) {
          fsMemberId = apiData.member.member_id;
        }
      } catch (err) {
        console.warn("createMember: GCP API sync failed, continuing locally", err);
      }
    }

    // Create Base44 Member entity as Pending with NO number and NO member_since (6.1-C03, 6.3-C01)
    const member = await sr.entities.Member.create({
      full_name: String(full_name).trim(),
      preferred_name: preferred_name ? String(preferred_name).trim() : String(full_name).trim().split(/\s+/)[0],
      email: normEmail(email),
      phone: phone ? String(phone).trim() : undefined,
      address: address ? String(address).trim() : undefined,
      date_of_birth: date_of_birth || undefined,
      license_number: license_number ? String(license_number).trim() : undefined,
      license_state: license_state ? String(license_state).toUpperCase() : undefined,
      license_expiry: license_expiry || undefined,
      insurance_provider, insurance_policy, insurance_expiry,
      plan_name,
      home_branch,
      home_branch_code: branchCode,
      status: "Pending",
      member_number: undefined,
      member_seq: undefined,
      member_since: undefined,
      fs_member_id: fsMemberId || undefined,
      duplicate_reviewed_by: matches.length ? user.email : undefined,
      duplicate_reviewed_at: matches.length ? now : undefined,
      duplicate_review_note: matches.length ? String(duplicate_review_note).trim() : undefined,
    });

    // Seed MemberBranchHistory row (6.3-C08, 6.3-R08)
    try {
      await sr.entities.MemberBranchHistory.create({
        member_id: member.id,
        branch_code: branchCode,
        branch_name: home_branch,
        effective_from: now.slice(0, 10),
        effective_to: null,
        reason: "Initial Enrollment",
      });
    } catch (e) {
      console.warn("createMember: MemberBranchHistory seeding note", e);
    }

    return Response.json({
      ok: true,
      member,
      duplicate_flag: matches.length > 0,
      matches,
    }, { status: 201 });
  } catch (e) {
    console.error("createMember error:", e);
    return Response.json({ ok: false, error: String((e as Error).message || e) }, { status: 500 });
  }
}
