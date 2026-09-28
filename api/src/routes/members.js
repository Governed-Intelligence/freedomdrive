import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';

export const membersRouter = Router();

// US 50 States + DC for 6.1-C04 validation
const VALID_US_STATES = new Set([
  'AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA',
  'HI','ID','IL','IN','IA','KS','KY','LA','ME','MD',
  'MA','MI','MN','MS','MO','MT','NE','NV','NH','NJ',
  'NM','NY','NC','ND','OH','OK','OR','PA','RI','SC',
  'SD','TN','TX','UT','VT','VA','WA','WV','WI','WY','DC'
]);

// Authoritative member_number formatter: YYYY-BRN-XXX-XXX (Guide 6.3 p. 16, e.g. 2009-HOU-000-005)
export function formatMemberNumber(year, branchCode, seq) {
  if (!year || !branchCode || !seq) return null;
  const padded = String(seq).padStart(6, '0');
  const seg1 = padded.slice(0, 3);
  const seg2 = padded.slice(3, 6);
  return `${year}-${String(branchCode).trim().toUpperCase()}-${seg1}-${seg2}`;
}

function normalizeName(str) {
  if (!str) return '';
  return str.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function normalizePhone(str) {
  if (!str) return '';
  const digits = str.replace(/\D/g, '');
  return (digits.length === 11 && digits.startsWith('1')) ? digits.slice(1) : digits;
}

export function getPlanPricing(planCode, planRow) {
  const code = (planCode || planRow?.code || 'PLAN_15').toUpperCase();
  let annual = planRow?.annual_price_usd;
  let monthly = planRow?.monthly_price_usd;

  if (!annual || !monthly) {
    switch (code) {
      case 'PLAN_15':
        annual = 27000.00;
        monthly = 2250.00;
        break;
      case 'PLAN_30':
        annual = 45000.00;
        monthly = 3750.00;
        break;
      case 'PLAN_60':
        annual = 84000.00;
        monthly = 7000.00;
        break;
      case 'PLAN_100':
        annual = 132000.00;
        monthly = 11000.00;
        break;
      default:
        annual = 30000.00;
        monthly = 2500.00;
    }
  }
  return { annualPrice: Number(annual), monthlyPrice: Number(monthly) };
}

// Rule 6.1-R14 & 6.1-C19: Dues are never prorated, always fall on the first, and run as 12 equal payments
export function calculatePaymentSchedule(startDateStr, monthlyDues, annualDues) {
  const start = new Date(startDateStr);
  const monthlyAmount = Number(monthlyDues) || (Number(annualDues) / 12) || 0;
  const installments = [];

  // Month 1: Due at activation / start_date
  installments.push({
    installment_number: 1,
    due_date: start.toISOString().slice(0, 10),
    amount: monthlyAmount,
    status: 'paid',
  });

  // Months 2 through 12: Due on the 1st of each succeeding calendar month
  let curYear = start.getUTCFullYear();
  let curMonth = start.getUTCMonth(); // 0-indexed

  for (let i = 2; i <= 12; i++) {
    curMonth += 1;
    if (curMonth > 11) {
      curMonth = 0;
      curYear += 1;
    }
    const nextFirst = new Date(Date.UTC(curYear, curMonth, 1));
    installments.push({
      installment_number: i,
      due_date: nextFirst.toISOString().slice(0, 10),
      amount: monthlyAmount,
      status: 'pending',
    });
  }

  return {
    installment_count: 12,
    amount_total: Number(annualDues) || (monthlyAmount * 12),
    monthly_dues: monthlyAmount,
    frequency: 'Monthly',
    start_due_date: start.toISOString().slice(0, 10),
    installments,
  };
}

const checkDuplicateSchema = z.object({
  first_name: z.string().optional(),
  last_name: z.string().optional(),
  date_of_birth: z.string().optional(),
  email: z.string().email().optional(),
  phone: z.string().optional(),
  drivers_license_number: z.string().optional(),
  address_line1: z.string().optional(),
});

const onboardSchema = z.object({
  first_name: z.string().min(1).max(100),
  middle_name: z.string().max(100).optional(),
  last_name: z.string().min(1).max(100),
  preferred_name: z.string().max(80).optional(),
  email: z.string().email().max(320),
  account_email: z.string().email().optional(),
  vehicle_email: z.string().email().optional(),
  phone: z.string().max(25),
  date_of_birth: z.string().optional(),
  drivers_license_number: z.string().max(50),
  drivers_license_state: z.string().length(2),
  drivers_license_expires: z.string().optional(),
  address_line1: z.string().max(200).optional(),
  address_line2: z.string().max(200).optional(),
  city: z.string().max(100).optional(),
  state: z.string().length(2).optional(),
  postal_code: z.string().max(20).optional(),
  primary_location_code: z.string().max(10).default('HOU'),
  plan_code: z.enum(['PLAN_15', 'PLAN_30', 'PLAN_60', 'PLAN_100']).optional(),
  planned_start_date: z.string().optional(),
  payment_arrangement_confirmed: z.boolean().default(false),
  payment_method_type: z.enum(['Card', 'ACH', 'Wire', 'credit_card', 'ach', 'wire']).optional(),
  billing_email: z.string().email().optional(),
  referral_source: z.string().max(100).optional(),
  notes: z.string().optional(),
  override_duplicate_flag: z.boolean().default(false),
  duplicate_review_note: z.string().optional(),
  user_id: z.string().uuid().optional(),
});

const activateSchema = z.object({
  payment_arrangement_confirmed: z.boolean().default(true),
  payment_schedule_id: z.string().uuid().optional(),
  activation_date: z.string().optional(),
  planned_start_date: z.string().optional(),
  joining_bonus_points: z.number().int().min(0).default(0),
});

const createSchema = z.object({
  first_name: z.string().min(1).max(100),
  middle_name: z.string().max(100).optional(),
  last_name: z.string().min(1).max(100),
  preferred_name: z.string().max(80).optional(),
  email: z.string().email().max(320),
  phone: z.string().max(25).optional(),
  date_of_birth: z.string().optional(),
  drivers_license_number: z.string().max(50).optional(),
  drivers_license_state: z.string().length(2).optional(),
  drivers_license_expires: z.string().optional(),
  address_line1: z.string().max(200).optional(),
  address_line2: z.string().max(200).optional(),
  city: z.string().max(100).optional(),
  state: z.string().length(2).optional(),
  postal_code: z.string().max(20).optional(),
  primary_location_code: z.string().max(10).default('HOU'),
  referral_source: z.string().max(100).optional(),
});

const listSchema = z.object({
  status: z.enum(['prospect', 'pending', 'active', 'paused', 'suspended', 'cancelled', 'expired', 'former']).optional(),
  q: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

// GET /v1/members — list & search (Guide 6.3 Rules 6.3-R04, 6.3-R05; 6.3-C19, 6.3-C20)
membersRouter.get('/', async (req, res) => {
  const params = listSchema.parse(req.query);
  const clauses = [];
  const values = [];

  if (params.status) {
    values.push(params.status);
    clauses.push(`m.status = $${values.length}`);
  }

  if (params.q) {
    const rawQ = params.q.trim();
    const bareSeq = parseInt(rawQ, 10);
    // 6.3-C19: Match formatted number and bare sequence
    // 6.3-C20: Match name, preferred_name, phone, email, and member number
    if (!isNaN(bareSeq) && String(bareSeq) === rawQ) {
      clauses.push(`(m.member_seq = $${values.length + 1} OR m.member_number ILIKE $${values.length + 2} OR m.phone ILIKE $${values.length + 2})`);
      values.push(bareSeq, `%${rawQ}%`);
    } else {
      clauses.push(`(m.member_number ILIKE $${values.length + 1} OR m.first_name ILIKE $${values.length + 1} OR m.last_name ILIKE $${values.length + 1} OR COALESCE(m.preferred_name, '') ILIKE $${values.length + 1} OR m.email ILIKE $${values.length + 1} OR COALESCE(m.phone, '') ILIKE $${values.length + 1})`);
      values.push(`%${rawQ}%`);
    }
  }

  const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
  values.push(params.limit, params.offset);

  const result = await query(
    `
    SELECT m.id, m.member_seq, m.member_number, m.first_name, m.middle_name, m.last_name,
           m.preferred_name, m.email, m.phone, m.status,
           m.joined_on, m.primary_location_id, l.code AS branch_code, l.name AS branch_name,
           m.created_at
      FROM fs.members m
      LEFT JOIN fs.locations l ON l.id = m.primary_location_id
      ${where}
     ORDER BY m.created_at DESC
     LIMIT $${values.length - 1} OFFSET $${values.length}
    `,
    values
  );
  res.json({ count: result.rowCount, members: result.rows });
});

// GET /v1/members/by-email/:email
membersRouter.get('/by-email/:email', async (req, res) => {
  const email = z.string().email().parse(decodeURIComponent(req.params.email)).toLowerCase();
  const result = await query(
    `SELECT m.id, m.member_seq, m.member_number, m.first_name, m.middle_name, m.last_name,
            m.preferred_name, m.email, m.phone, m.status, m.primary_location_id,
            l.code AS branch_code, l.name AS branch_name
       FROM fs.members m
       LEFT JOIN fs.locations l ON l.id = m.primary_location_id
      WHERE lower(m.email) = $1 LIMIT 1`,
    [email]
  );
  if (result.rowCount === 0) throw new HttpError(404, 'No member with that email');
  res.json({ member: result.rows[0] });
});

// POST /v1/members/check-duplicate — Guide 6.1 Rules 6.1-R03, 6.1-R04 (6.1-C05 through 6.1-C12)
membersRouter.post('/check-duplicate', async (req, res) => {
  const data = checkDuplicateSchema.parse(req.body);
  const flags = [];
  let rejoinEligible = false;
  let matchedMember = null;

  const existing = await query(`
    SELECT id, first_name, last_name, preferred_name, email, phone, drivers_license_number, date_of_birth, address_line1, status
      FROM fs.members
  `);

  const normLastName = normalizeName(data.last_name);
  const normPhone = normalizePhone(data.phone);
  const normEmail = data.email ? data.email.toLowerCase().trim() : '';
  const normDl = data.drivers_license_number ? data.drivers_license_number.replace(/[^A-Za-z0-9]/g, '').toUpperCase() : '';

  for (const m of existing.rows) {
    const exDl = (m.drivers_license_number || '').replace(/[^A-Za-z0-9]/g, '').toUpperCase();
    const exEmail = (m.email || '').toLowerCase().trim();
    const exLastName = normalizeName(m.last_name);
    const exPhone = normalizePhone(m.phone);
    const exDob = m.date_of_birth ? new Date(m.date_of_birth).toISOString().slice(0, 10) : '';
    const reqDob = data.date_of_birth ? new Date(data.date_of_birth).toISOString().slice(0, 10) : '';

    // 6.1-C05: License match flags on its own
    if (normDl && exDl && normDl === exDl) {
      flags.push({ type: 'license_match', reason: `Driving license matches member ${m.id}`, matched_id: m.id });
      matchedMember = m;
    }

    // 6.1-C06: Email match flags on its own
    if (normEmail && exEmail && normEmail === exEmail) {
      flags.push({ type: 'email_match', reason: `Email matches member ${m.id}`, matched_id: m.id });
      matchedMember = m;
    }

    // 6.1-C08: Last name + Date of Birth flags together
    if (normLastName && exLastName && normLastName === exLastName) {
      if (reqDob && exDob && reqDob === exDob) {
        flags.push({ type: 'name_dob_match', reason: `Last name and date of birth match member ${m.id}`, matched_id: m.id });
        matchedMember = m;
      }

      // Any two of last name, dob, phone, address flag together (6.1-R04)
      let secondaryMatches = 0;
      if (normPhone && exPhone && normPhone === exPhone) secondaryMatches++;
      if (data.address_line1 && m.address_line1 && normalizeName(data.address_line1) === normalizeName(m.address_line1)) secondaryMatches++;
      if (secondaryMatches >= 1) {
        flags.push({ type: 'multi_attribute_match', reason: `Last name plus contact details match member ${m.id}`, matched_id: m.id });
        matchedMember = m;
      }
    }

    // 6.1-C12: Match on former member routes to rejoin
    if (matchedMember && (m.status === 'former' || m.status === 'cancelled' || m.status === 'expired')) {
      rejoinEligible = true;
    }
  }

  res.json({
    flagged: flags.length > 0,
    flags,
    rejoin_eligible: rejoinEligible,
    matched_member: matchedMember ? { id: matchedMember.id, status: matchedMember.status } : null,
  });
});

// POST /v1/members/onboard — Guide 6.1 & Guide 6.3 Onboarding (6.1-C01 to C16, 6.3-C01, 6.3-C08, 6.3-R11)
membersRouter.post('/onboard', async (req, res) => {
  const data = onboardSchema.parse(req.body);

  // 6.1-C04: License state not present in STATE_SELECT rejected
  const stateUpper = data.drivers_license_state.toUpperCase();
  if (!VALID_US_STATES.has(stateUpper)) {
    throw new HttpError(400, `License state '${data.drivers_license_state}' is not in STATE_SELECT`);
  }

  // Duplicate check before write (6.1-R03)
  const normDl = data.drivers_license_number.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  const dlCheck = await query(
    `SELECT id FROM fs.members WHERE UPPER(REPLACE(drivers_license_number, '-', '')) = $1 LIMIT 1`,
    [normDl]
  );
  if (dlCheck.rowCount > 0 && !data.override_duplicate_flag) {
    throw new HttpError(409, `Duplicate flag: License matches existing member ${dlCheck.rows[0].id}. Review required to proceed.`);
  }

  const accountEmail = data.account_email || data.email;
  const vehicleEmail = data.vehicle_email || data.email;

  // Resolve branch location
  let locationId = null;
  let locationCode = 'HOU';
  if (data.primary_location_code) {
    const loc = await query(`SELECT id, code FROM fs.locations WHERE code = $1`, [data.primary_location_code.toUpperCase()]);
    if (loc.rowCount > 0) {
      locationId = loc.rows[0].id;
      locationCode = loc.rows[0].code;
    }
  }

  // 6.1-C01 / 6.3-C01 / 6.3-C08: Saved member written atomically, pending, NO member number, seeded branch history
  const result = await withTransaction(async (client) => {
    let userId = data.user_id;
    if (userId) {
      const userCheck = await client.query(`SELECT id FROM fs.members WHERE user_id = $1`, [userId]);
      if (userCheck.rowCount > 0) {
        throw new HttpError(409, 'A second member profile cannot be created against a login account that already has one.');
      }
    }

    // 6.1-C03 & 6.3-C01: A saved member has a member_id, Pending status, NO member_number, and NO member_seq
    const insertMember = await client.query(
      `
      INSERT INTO fs.members (
        first_name, middle_name, last_name, preferred_name, email, phone, date_of_birth,
        drivers_license_number, drivers_license_state, drivers_license_expires,
        address_line1, address_line2, city, state, postal_code,
        primary_location_id, referral_source, status, member_number, member_seq, joined_on, user_id
      ) VALUES (
        $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,'pending',NULL,NULL,NULL,$18
      )
      RETURNING id, first_name, middle_name, last_name, preferred_name, email, status, member_number, member_seq, created_at
      `,
      [
        data.first_name,
        data.middle_name ?? null,
        data.last_name,
        data.preferred_name ?? data.first_name,
        data.email,
        data.phone,
        data.date_of_birth ?? null,
        data.drivers_license_number,
        stateUpper,
        data.drivers_license_expires ?? null,
        data.address_line1 ?? null,
        data.address_line2 ?? null,
        data.city ?? null,
        data.state ?? null,
        data.postal_code ?? null,
        locationId,
        data.referral_source ?? null,
        userId ?? null,
      ]
    );
    const member = insertMember.rows[0];

    // 6.3-C08, 6.3-R08: Creating a member seeds one branch history row
    let branchRecordId = null;
    const branchRes = await client.query(
      `SELECT branch_id FROM fs.branch WHERE UPPER(branch_code) = UPPER($1) LIMIT 1`,
      [locationCode]
    );
    if (branchRes.rowCount > 0) {
      branchRecordId = branchRes.rows[0].branch_id;
    } else if (locationId) {
      const bCheck = await client.query(`SELECT branch_id FROM fs.branch WHERE branch_id = $1`, [locationId]);
      if (bCheck.rowCount > 0) branchRecordId = locationId;
    }

    if (branchRecordId) {
      await client.query(
        `
        INSERT INTO fs.member_branch_history (
          member_id, branch_id, effective_from, effective_to, reason
        ) VALUES ($1, $2, CURRENT_DATE, NULL, 'Initial Enrollment')
        `,
        [member.id, branchRecordId]
      );
    }

    // Update payment arrangement & planned start date on member
    if (data.planned_start_date || data.payment_arrangement_confirmed || data.payment_method_type || data.billing_email) {
      await client.query(
        `
        UPDATE fs.members
           SET planned_start_date = COALESCE($1, planned_start_date),
               payment_arrangement_confirmed = COALESCE($2, payment_arrangement_confirmed),
               payment_method_type = COALESCE($3, payment_method_type),
               billing_email = COALESCE($4, billing_email)
         WHERE id = $5
        `,
        [data.planned_start_date ?? null, data.payment_arrangement_confirmed ?? false, data.payment_method_type ?? null, data.billing_email ?? null, member.id]
      );
    }

    // If a plan was chosen, create a pending subscription package & draft payment schedule (6.1-C18, 6.1-C19)
    let subId = null;
    let scheduleId = null;
    let scheduleObj = null;
    if (data.plan_code) {
      const planRes = await client.query(`SELECT id, code, annual_tier_points, annual_price_usd, monthly_price_usd FROM fs.plans WHERE code = $1`, [data.plan_code]);
      if (planRes.rowCount > 0) {
        const plan = planRes.rows[0];
        const startDate = data.planned_start_date || new Date().toISOString().slice(0, 10);
        const subInsert = await client.query(
          `
          INSERT INTO fs.member_subscriptions (
            member_id, plan_id, status, start_date, end_date, points_granted, auto_renew
          ) VALUES ($1, $2, 'pending', $3, ($3::date + INTERVAL '1 year')::date, $4, TRUE)
          RETURNING id
          `,
          [member.id, plan.id, startDate, plan.annual_tier_points]
        );
        subId = subInsert.rows[0].id;

        // Draft payment schedule (6.1-C18, 6.1-C19)
        const pricing = getPlanPricing(plan.code, plan);
        const sched = calculatePaymentSchedule(startDate, pricing.monthlyPrice, pricing.annualPrice);
        const schedInsert = await client.query(
          `
          INSERT INTO fs.member_payment_schedule (
            member_id, amount_total, frequency, installment_count, start_due_date,
            status, payment_method_type, billing_email, installments_json, notes
          ) VALUES ($1, $2, $3::fs.member_payment_schedule_frequency_enum, $4, $5, 'Draft', $6, $7, $8, 'Draft Onboarding Payment Schedule')
          RETURNING member_payment_schedule_id
          `,
          [member.id, sched.amount_total, sched.frequency, sched.installment_count, sched.start_due_date, data.payment_method_type || 'Card', data.billing_email || member.email, JSON.stringify(sched.installments)]
        );
        scheduleId = schedInsert.rows[0]?.member_payment_schedule_id;
        scheduleObj = {
          schedule_id: scheduleId,
          amount_total: sched.amount_total,
          monthly_dues: sched.monthly_dues,
          frequency: sched.frequency,
          start_due_date: sched.start_due_date,
          installment_count: sched.installment_count,
          installments: sched.installments,
        };
      }
    }

    return {
      member_id: member.id,
      member_number: null,
      member_seq: null,
      status: 'pending',
      first_name: member.first_name,
      last_name: member.last_name,
      preferred_name: member.preferred_name,
      email: member.email,
      account_email: accountEmail,
      vehicle_email: vehicleEmail,
      branch_code: locationCode,
      subscription_id: subId,
      payment_schedule: scheduleObj,
      created_at: member.created_at,
    };
  });

  res.status(201).json({ ok: true, member: result });
});

// POST /v1/members/:id/activate — Guide 6.1 & Guide 6.3 Atomic Minting & Activation (6.3-R02, R03, R04, R05, R06; 6.3-C02 to C07; 6.1-R09, R10, R14; 6.1-C18 to C31)
membersRouter.post('/:id/activate', async (req, res) => {
  const { id } = req.params;
  const data = activateSchema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const mRes = await client.query(`SELECT * FROM fs.members WHERE id = $1`, [id]);
    if (mRes.rowCount === 0) throw new HttpError(404, 'Member not found');
    const member = mRes.rows[0];

    // 6.1-C20 / 6.1-R09: Activation without a payment arrangement is refused
    const isArrangementConfirmed = data.payment_arrangement_confirmed === true || member.payment_arrangement_confirmed === true;
    if (!isArrangementConfirmed) {
      throw new HttpError(400, 'Activation without a payment arrangement is refused.');
    }

    // 6.1-C29, 6.3-C04: A second activation does NOT mint a new number
    if (member.status === 'active' && member.member_number) {
      return {
        member_id: member.id,
        member_number: member.member_number,
        member_seq: member.member_seq,
        member_since: member.joined_on,
        status: member.status,
        re_activated: true,
      };
    }

    // Resolve branch code for member
    let branchCode = 'HOU';
    let branchId = member.primary_location_id;
    if (branchId) {
      const locRes = await client.query(`SELECT id, code FROM fs.locations WHERE id = $1`, [branchId]);
      if (locRes.rowCount > 0 && locRes.rows[0].code) {
        branchCode = locRes.rows[0].code.trim().toUpperCase();
      }
    } else {
      const defaultLoc = await client.query(`SELECT id, code FROM fs.locations WHERE code = 'HOU' LIMIT 1`);
      if (defaultLoc.rowCount > 0) {
        branchId = defaultLoc.rows[0].id;
        branchCode = defaultLoc.rows[0].code;
      }
    }

    // 6.3-R05, 6.3-C06: The sequence is club-wide, not per branch
    const seqRes = await client.query(`SELECT nextval('fs.member_number_seq')::int AS seq`);
    const seq = seqRes.rows[0].seq;

    // 6.3-R04, 6.3-C05: Formatted as joining year, branch code at activation, and padded sequence
    const actDate = data.activation_date ? new Date(data.activation_date) : new Date();
    const year = actDate.getFullYear();
    const actIso = actDate.toISOString().slice(0, 10);
    const memberNumber = formatMemberNumber(year, branchCode, seq);

    // Rule 6.1-R10, 6.1-C22, 6.1-C23, 6.1-C31: Activation sets start date in both directions
    // Preserve planned_start_date in record history
    const plannedStartDate = data.planned_start_date || member.planned_start_date;

    // Update Member to Active in one transaction (6.3-R03)
    await client.query(
      `
      UPDATE fs.members
         SET member_seq = $1,
             member_number = $2,
             joined_on = $3,
             primary_location_id = COALESCE(primary_location_id, $4),
             status = 'active',
             payment_arrangement_confirmed = TRUE,
             planned_start_date = COALESCE($5, planned_start_date),
             updated_at = now()
       WHERE id = $6
      `,
      [seq, memberNumber, actIso, branchId, plannedStartDate, id]
    );

    // Ensure member_branch_history row exists (6.3-C08, 6.3-C09, 6.3-C13)
    const openHist = await client.query(
      `SELECT member_branch_history_id FROM fs.member_branch_history WHERE member_id = $1 AND effective_to IS NULL LIMIT 1`,
      [id]
    );
    if (openHist.rowCount === 0) {
      await client.query(
        `
        INSERT INTO fs.member_branch_history (
          member_id, branch_id, effective_from, effective_to, reason
        ) VALUES ($1, $2, $3, NULL, 'Charter Activation')
        `,
        [id, branchId, actIso]
      );
    }

    // Activate subscription package & grant points
    let pointsBalance = 0;
    let paymentSchedule = null;
    const subRes = await client.query(
      `SELECT s.id, s.plan_id, s.start_date, p.code AS plan_code, p.annual_tier_points, p.annual_price_usd, p.monthly_price_usd
         FROM fs.member_subscriptions s
         JOIN fs.plans p ON p.id = s.plan_id
        WHERE s.member_id = $1
        ORDER BY s.created_at DESC LIMIT 1`,
      [id]
    );

    if (subRes.rowCount > 0) {
      const sub = subRes.rows[0];
      const annualPts = sub.annual_tier_points || 0;

      // 6.1-C23 & 6.1-C31: Start date moved to activation date, end date recomputed to +1 year
      await client.query(
        `
        UPDATE fs.member_subscriptions
           SET status = 'active',
               start_date = $1,
               end_date = ($1::date + INTERVAL '1 year')::date,
               points_granted = $2
         WHERE id = $3
        `,
        [actIso, annualPts, sub.id]
      );

      // Insert initial annual point grant transaction upon subscription activation
      const existingTxn = await client.query(
        `SELECT id FROM fs.point_transactions WHERE subscription_id = $1 AND txn_type = 'grant' LIMIT 1`,
        [sub.id]
      );
      if (existingTxn.rowCount === 0 && annualPts > 0) {
        await client.query(
          `
          INSERT INTO fs.point_transactions (
            subscription_id, txn_type, points, balance_after, reason
          ) VALUES ($1, 'grant', $2, $2, 'Initial Annual Plan Tier Points Grant')
          `,
          [sub.id, annualPts]
        );
        pointsBalance = annualPts;
      } else {
        const balRes = await client.query(
          `SELECT balance_after FROM fs.point_transactions WHERE subscription_id = $1 ORDER BY id DESC LIMIT 1`,
          [sub.id]
        );
        pointsBalance = balRes.rows[0]?.balance_after ?? annualPts;
      }

      if (data.joining_bonus_points > 0) {
        const bonusTxn = await client.query(
          `
          INSERT INTO fs.point_transactions (
            subscription_id, txn_type, points, balance_after, reason
          ) VALUES ($1, 'bonus', $2, $3, 'Joining Bonus')
          RETURNING balance_after
          `,
          [sub.id, data.joining_bonus_points, pointsBalance + data.joining_bonus_points]
        );
        pointsBalance = bonusTxn.rows[0]?.balance_after || (pointsBalance + data.joining_bonus_points);
      }

      // Convert tentative reservations (6.1-R11, 6.1-C27, 9.2-C17)
      await client.query(
        `
        UPDATE fs.reservations
           SET status = 'confirmed', is_tentative = false, updated_at = now()
         WHERE member_id = $1 AND status IN ('requested', 'tentative')
        `,
        [id]
      );

      // Generate & Activate the 12-month payment schedule (6.1-R14, 6.1-C18, 6.1-C19, 6.1-C31)
      const pricing = getPlanPricing(sub.plan_code, sub);
      const sched = calculatePaymentSchedule(actIso, pricing.monthlyPrice, pricing.annualPrice);

      const existSched = await client.query(
        `SELECT member_payment_schedule_id FROM fs.member_payment_schedule WHERE member_id = $1 LIMIT 1`,
        [id]
      );

      let scheduleId;
      if (existSched.rowCount > 0) {
        scheduleId = existSched.rows[0].member_payment_schedule_id;
        await client.query(
          `
          UPDATE fs.member_payment_schedule
             SET amount_total = $1,
                 frequency = $2::fs.member_payment_schedule_frequency_enum,
                 installment_count = $3,
                 start_due_date = $4,
                 status = 'Active',
                 payment_method_type = COALESCE(payment_method_type, $5),
                 billing_email = COALESCE(billing_email, $6),
                 installments_json = $7,
                 notes = 'Authoritative 12-Month Non-Prorated Dues Schedule (Activated)',
                 updated_at = now()
           WHERE member_payment_schedule_id = $8
          `,
          [sched.amount_total, sched.frequency, sched.installment_count, sched.start_due_date, member.payment_method_type || 'Card', member.billing_email || member.email, JSON.stringify(sched.installments), scheduleId]
        );
      } else {
        const insSched = await client.query(
          `
          INSERT INTO fs.member_payment_schedule (
            member_id, amount_total, frequency, installment_count, start_due_date,
            status, payment_method_type, billing_email, installments_json, notes
          ) VALUES ($1, $2, $3::fs.member_payment_schedule_frequency_enum, $4, $5, 'Active', $6, $7, $8, 'Authoritative 12-Month Non-Prorated Dues Schedule (Activated)')
          RETURNING member_payment_schedule_id
          `,
          [id, sched.amount_total, sched.frequency, sched.installment_count, sched.start_due_date, member.payment_method_type || 'Card', member.billing_email || member.email, JSON.stringify(sched.installments)]
        );
        scheduleId = insSched.rows[0].member_payment_schedule_id;
      }

      paymentSchedule = {
        schedule_id: scheduleId,
        frequency: sched.frequency,
        installment_count: sched.installment_count,
        amount_total: sched.amount_total,
        monthly_dues: sched.monthly_dues,
        start_due_date: sched.start_due_date,
        installments: sched.installments,
      };
    }

    return {
      member_id: member.id,
      member_number: memberNumber,
      member_seq: seq,
      member_since: actIso,
      status: 'active',
      points_balance: pointsBalance,
      payment_arrangement_confirmed: true,
      payment_schedule: paymentSchedule,
    };
  });

  res.json({ ok: true, activation: result });
});

// POST /v1/members/:id/payment-arrangement — Guide 6.1 Payment Arrangement (6.1-R09, 6.1-C20)
membersRouter.post('/:id/payment-arrangement', async (req, res) => {
  const { id } = req.params;
  const arrangementSchema = z.object({
    payment_method_type: z.enum(['Card', 'ACH', 'Wire', 'credit_card', 'ach', 'wire']).default('Card'),
    payment_arrangement_confirmed: z.boolean().default(true),
    billing_email: z.string().email().optional(),
    stripe_customer_id: z.string().optional(),
    stripe_payment_method_id: z.string().optional(),
    notes: z.string().optional(),
  });
  const data = arrangementSchema.parse(req.body || {});

  let method = 'Card';
  const mLow = (data.payment_method_type || 'card').toLowerCase();
  if (mLow.includes('ach')) method = 'ACH';
  else if (mLow.includes('wire')) method = 'Wire';

  const result = await withTransaction(async (client) => {
    const mRes = await client.query(`SELECT id, email, status FROM fs.members WHERE id = $1`, [id]);
    if (mRes.rowCount === 0) throw new HttpError(404, 'Member not found');
    const member = mRes.rows[0];

    const billingEmail = data.billing_email || member.email;

    await client.query(
      `
      UPDATE fs.members
         SET payment_arrangement_confirmed = $1,
             payment_method_type = $2,
             billing_email = $3,
             stripe_customer_id = COALESCE($4, stripe_customer_id),
             updated_at = now()
       WHERE id = $5
      `,
      [data.payment_arrangement_confirmed, method, billingEmail, data.stripe_customer_id ?? null, id]
    );

    // Update existing payment schedule if one exists
    await client.query(
      `
      UPDATE fs.member_payment_schedule
         SET payment_method_type = $1,
             billing_email = $2,
             updated_at = now()
       WHERE member_id = $3
      `,
      [method, billingEmail, id]
    );

    return {
      member_id: id,
      payment_arrangement_confirmed: data.payment_arrangement_confirmed,
      payment_method_type: method,
      billing_email: billingEmail,
      stripe_customer_id: data.stripe_customer_id || null,
      confirmed_at: new Date().toISOString(),
    };
  });

  res.json({ ok: true, payment_arrangement: result });
});

// GET /v1/members/:id/payment-schedule — Guide 6.1 Dues Schedule (6.1-R14, 6.1-C18, 6.1-C19)
membersRouter.get('/:id/payment-schedule', async (req, res) => {
  const { id } = req.params;

  const mRes = await query(`SELECT id, email, status, joined_on, payment_arrangement_confirmed, payment_method_type, billing_email, planned_start_date FROM fs.members WHERE id = $1`, [id]);
  if (mRes.rowCount === 0) throw new HttpError(404, 'Member not found');
  const member = mRes.rows[0];

  // Check if a saved schedule exists in fs.member_payment_schedule
  const schedRes = await query(
    `SELECT * FROM fs.member_payment_schedule WHERE member_id = $1 ORDER BY created_at DESC LIMIT 1`,
    [id]
  );

  if (schedRes.rowCount > 0) {
    const row = schedRes.rows[0];
    let installments = row.installments_json;
    if (!installments || !Array.isArray(installments)) {
      const calc = calculatePaymentSchedule(row.start_due_date, null, row.amount_total);
      installments = calc.installments;
    }
    return res.json({
      ok: true,
      payment_schedule: {
        schedule_id: row.member_payment_schedule_id,
        member_id: id,
        frequency: row.frequency || 'Monthly',
        installment_count: row.installment_count || 12,
        amount_total: Number(row.amount_total),
        installment_amount: (Number(row.amount_total) / (row.installment_count || 12)),
        start_due_date: row.start_due_date,
        status: row.status || 'Active',
        payment_method_type: row.payment_method_type || member.payment_method_type || 'Card',
        billing_email: row.billing_email || member.billing_email || member.email,
        installments,
      },
    });
  }

  // Otherwise calculate dynamically from subscription/plan
  const subRes = await query(
    `SELECT s.id, s.start_date, s.status AS sub_status, p.code AS plan_code, p.name AS plan_name,
            p.annual_price_usd, p.monthly_price_usd
       FROM fs.member_subscriptions s
       JOIN fs.plans p ON p.id = s.plan_id
      WHERE s.member_id = $1
      ORDER BY s.created_at DESC LIMIT 1`,
    [id]
  );

  let startDate = member.joined_on || member.planned_start_date || new Date().toISOString().slice(0, 10);
  let planCode = 'PLAN_15';
  let planName = '15-Day Starter Membership';
  let pricing = getPlanPricing('PLAN_15');

  if (subRes.rowCount > 0) {
    const sub = subRes.rows[0];
    startDate = sub.start_date ? new Date(sub.start_date).toISOString().slice(0, 10) : startDate;
    planCode = sub.plan_code;
    planName = sub.plan_name;
    pricing = getPlanPricing(planCode, sub);
  }

  const calc = calculatePaymentSchedule(startDate, pricing.monthlyPrice, pricing.annualPrice);

  res.json({
    ok: true,
    payment_schedule: {
      schedule_id: null,
      member_id: id,
      plan_code: planCode,
      plan_name: planName,
      frequency: calc.frequency,
      installment_count: calc.installment_count,
      amount_total: calc.amount_total,
      installment_amount: calc.monthly_dues,
      start_due_date: calc.start_due_date,
      status: member.status === 'active' ? 'Active' : 'Draft',
      payment_method_type: member.payment_method_type || 'Card',
      billing_email: member.billing_email || member.email,
      installments: calc.installments,
    },
  });
});

// POST /v1/members/:id/generate-payment-schedule — Generate/Recompute 12 non-prorated installments (6.1-R14, 6.1-C18, 6.1-C19, 6.1-C31)
membersRouter.post('/:id/generate-payment-schedule', async (req, res) => {
  const { id } = req.params;
  const genSchema = z.object({
    start_date: z.string().optional(),
    plan_code: z.enum(['PLAN_15', 'PLAN_30', 'PLAN_60', 'PLAN_100']).optional(),
    frequency: z.enum(['Monthly', 'Annual', 'Quarterly', 'Custom']).default('Monthly'),
  });
  const data = genSchema.parse(req.body || {});

  const result = await withTransaction(async (client) => {
    const mRes = await client.query(`SELECT id, email, status, joined_on, planned_start_date, payment_method_type, billing_email FROM fs.members WHERE id = $1`, [id]);
    if (mRes.rowCount === 0) throw new HttpError(404, 'Member not found');
    const member = mRes.rows[0];

    // Find active or latest subscription
    const subRes = await client.query(
      `SELECT s.id, s.start_date, p.code AS plan_code, p.annual_price_usd, p.monthly_price_usd
         FROM fs.member_subscriptions s
         JOIN fs.plans p ON p.id = s.plan_id
        WHERE s.member_id = $1
        ORDER BY s.created_at DESC LIMIT 1`,
      [id]
    );

    let planCode = data.plan_code || subRes.rows[0]?.plan_code || 'PLAN_15';
    let pricing = getPlanPricing(planCode, subRes.rows[0]);
    let startDate = data.start_date || (subRes.rows[0]?.start_date ? new Date(subRes.rows[0].start_date).toISOString().slice(0, 10) : (member.joined_on || member.planned_start_date || new Date().toISOString().slice(0, 10)));

    const calc = calculatePaymentSchedule(startDate, pricing.monthlyPrice, pricing.annualPrice);

    // Upsert or insert into fs.member_payment_schedule
    const existing = await client.query(`SELECT member_payment_schedule_id FROM fs.member_payment_schedule WHERE member_id = $1 LIMIT 1`, [id]);

    let scheduleId;
    if (existing.rowCount > 0) {
      scheduleId = existing.rows[0].member_payment_schedule_id;
      await client.query(
        `
        UPDATE fs.member_payment_schedule
           SET amount_total = $1,
               frequency = $2::fs.member_payment_schedule_frequency_enum,
               installment_count = $3,
               start_due_date = $4,
               status = $5,
               payment_method_type = $6,
               billing_email = $7,
               installments_json = $8,
               notes = 'Guide 6.1 Authoritative 12-Month Non-Prorated Dues Schedule',
               updated_at = now()
         WHERE member_payment_schedule_id = $9
        `,
        [calc.amount_total, calc.frequency, calc.installment_count, calc.start_due_date, (member.status === 'active' ? 'Active' : 'Draft'), (member.payment_method_type || 'Card'), (member.billing_email || member.email), JSON.stringify(calc.installments), scheduleId]
      );
    } else {
      const insRes = await client.query(
        `
        INSERT INTO fs.member_payment_schedule (
          member_id, amount_total, frequency, installment_count, start_due_date,
          status, payment_method_type, billing_email, installments_json, notes
        ) VALUES ($1, $2, $3::fs.member_payment_schedule_frequency_enum, $4, $5, 'Draft', $6, $7, $8, 'Guide 6.1 Authoritative 12-Month Non-Prorated Dues Schedule')
        RETURNING member_payment_schedule_id
        `,
        [id, calc.amount_total, calc.frequency, calc.installment_count, calc.start_due_date, (member.payment_method_type || 'Card'), (member.billing_email || member.email), JSON.stringify(calc.installments)]
      );
      scheduleId = insRes.rows[0].member_payment_schedule_id;
    }

    return {
      schedule_id: scheduleId,
      member_id: id,
      plan_code: planCode,
      frequency: calc.frequency,
      installment_count: calc.installment_count,
      amount_total: calc.amount_total,
      installment_amount: calc.monthly_dues,
      start_due_date: calc.start_due_date,
      status: member.status === 'active' ? 'Active' : 'Draft',
      payment_method_type: member.payment_method_type || 'Card',
      billing_email: member.billing_email || member.email,
      installments: calc.installments,
    };
  });

  res.json({ ok: true, payment_schedule: result });
});

// POST /v1/members/:id/transfer-branch — Guide 6.3 Rules 6.3-R07, 6.3-R09 (6.3-C10, 6.3-C11, 6.3-C12, 6.3-C13)
membersRouter.post('/:id/transfer-branch', async (req, res) => {
  const { id } = req.params;
  const transferSchema = z.object({
    new_branch_code: z.string().min(2).max(10), // e.g. 'DFW', 'ATX', 'HOU'
    reason: z.string().max(200).default('Home Branch Relocation'),
    regenerate_number: z.boolean().default(false), // Decision D6: false keeps number (6.3-C12), true regenerates branch segment (6.3-R07)
  });
  const data = transferSchema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const mRes = await client.query(`SELECT * FROM fs.members WHERE id = $1`, [id]);
    if (mRes.rowCount === 0) throw new HttpError(404, 'Member not found');
    const member = mRes.rows[0];

    // Resolve target location
    const newLocRes = await client.query(
      `SELECT id, code, name FROM fs.locations WHERE UPPER(code) = UPPER($1) LIMIT 1`,
      [data.new_branch_code]
    );
    if (newLocRes.rowCount === 0) {
      throw new HttpError(404, `Target branch code '${data.new_branch_code}' not found in locations`);
    }
    const newLoc = newLocRes.rows[0];

    // Resolve target branch from fs.branch (for member_branch_history.branch_id FK)
    let branchRecordId = null;
    const branchRes = await client.query(
      `SELECT branch_id FROM fs.branch WHERE UPPER(branch_code) = UPPER($1) LIMIT 1`,
      [data.new_branch_code]
    );
    if (branchRes.rowCount > 0) {
      branchRecordId = branchRes.rows[0].branch_id;
    } else {
      const insB = await client.query(
        `INSERT INTO fs.branch (branch_code, branch_name, branch_type, is_active)
         VALUES ($1, $2, 'Main', TRUE)
         ON CONFLICT (branch_code) DO UPDATE SET branch_name = EXCLUDED.branch_name
         RETURNING branch_id`,
        [newLoc.code, newLoc.name]
      );
      branchRecordId = insB.rows[0].branch_id;
    }

    // 6.3-C10, 6.3-R09: Close current open branch history row
    await client.query(
      `
      UPDATE fs.member_branch_history
         SET effective_to = CURRENT_DATE,
             updated_at = now()
       WHERE member_id = $1 AND effective_to IS NULL
      `,
      [id]
    );

    // 6.3-C10, 6.3-R09: Open new branch history row
    await client.query(
      `
      INSERT INTO fs.member_branch_history (
        member_id, branch_id, effective_from, effective_to, reason
      ) VALUES ($1, $2, CURRENT_DATE, NULL, $3)
      `,
      [id, branchRecordId, data.reason]
    );

    // 6.3-C11: Update member's primary_location_id to match open row
    let newMemberNumber = member.member_number;
    if (data.regenerate_number && member.member_seq) {
      // 6.3-R07 option: regenerate branch segment
      const year = member.joined_on ? new Date(member.joined_on).getFullYear() : new Date().getFullYear();
      newMemberNumber = formatMemberNumber(year, newLoc.code, member.member_seq);
    }

    await client.query(
      `
      UPDATE fs.members
         SET primary_location_id = $1,
             member_number = $2,
             updated_at = now()
       WHERE id = $3
      `,
      [newLoc.id, newMemberNumber, id]
    );

    return {
      member_id: member.id,
      previous_branch_id: member.primary_location_id,
      new_branch_id: newLoc.id,
      new_branch_code: newLoc.code,
      member_number: newMemberNumber,
      effective_from: new Date().toISOString().slice(0, 10),
      reason: data.reason,
    };
  });

  res.json({ ok: true, transfer: result });
});

// GET /v1/members/:id/branch-history — Guide 6.3 (6.3-C09, 6.3-C13)
membersRouter.get('/:id/branch-history', async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `
    SELECT h.member_branch_history_id, h.member_id, h.branch_id,
           COALESCE(b.branch_code, l.code) AS branch_code,
           COALESCE(b.branch_name, l.name) AS branch_name,
           h.effective_from, h.effective_to, h.reason, h.created_at
      FROM fs.member_branch_history h
      LEFT JOIN fs.branch b ON b.branch_id = h.branch_id
      LEFT JOIN fs.locations l ON l.id = h.branch_id OR UPPER(l.code) = UPPER(b.branch_code)
     WHERE h.member_id = $1
     ORDER BY h.effective_from DESC, h.created_at DESC
    `,
    [id]
  );
  res.json({ count: result.rowCount, branch_history: result.rows });
});

// Legacy POST /v1/members — Guide 6.3 Compliant Save (6.3-C01: saves pending member with NO number)
membersRouter.post('/', async (req, res) => {
  const data = createSchema.parse(req.body);

  let locationId = null;
  let locationCode = 'HOU';
  if (data.primary_location_code) {
    const loc = await query(`SELECT id, code FROM fs.locations WHERE code = $1`, [data.primary_location_code.toUpperCase()]);
    if (loc.rowCount > 0) {
      locationId = loc.rows[0].id;
      locationCode = loc.rows[0].code;
    }
  }

  // 6.3-C01: Saved member has member_id and NO member_number
  const insert = await withTransaction(async (client) => {
    const mRes = await client.query(
      `
      INSERT INTO fs.members (
        first_name, middle_name, last_name, preferred_name, email, phone, date_of_birth,
        drivers_license_number, drivers_license_state, drivers_license_expires,
        address_line1, address_line2, city, state, postal_code,
        primary_location_id, referral_source, status, member_number, member_seq, joined_on
      ) VALUES (
        $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,'pending',NULL,NULL,NULL
      )
      RETURNING id, member_number, member_seq, first_name, last_name, preferred_name, email, status, created_at
      `,
      [
        data.first_name,
        data.middle_name ?? null,
        data.last_name,
        data.preferred_name ?? data.first_name,
        data.email,
        data.phone ?? null,
        data.date_of_birth ?? null,
        data.drivers_license_number ?? null,
        data.drivers_license_state ?? null,
        data.drivers_license_expires ?? null,
        data.address_line1 ?? null,
        data.address_line2 ?? null,
        data.city ?? null,
        data.state ?? null,
        data.postal_code ?? null,
        locationId,
        data.referral_source ?? null,
      ]
    );
    const member = mRes.rows[0];

    // Seed branch history (6.3-C08)
    if (locationId) {
      await client.query(
        `
        INSERT INTO fs.member_branch_history (
          member_id, branch_id, effective_from, effective_to, reason
        ) VALUES ($1, $2, CURRENT_DATE, NULL, 'Initial Registration')
        `,
        [member.id, locationId]
      );
    }
    return member;
  });

  res.status(201).json({ member: insert });
});

// GET /v1/members/:id
membersRouter.get('/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `SELECT m.*, l.code AS branch_code, l.name AS branch_name
       FROM fs.members m
       LEFT JOIN fs.locations l ON l.id = m.primary_location_id
      WHERE m.id = $1`,
    [id]
  );
  if (result.rowCount === 0) {
    throw new HttpError(404, 'Member not found');
  }
  res.json({ member: result.rows[0] });
});

// GET /v1/members/:id/subscription — current active subscription + point balance
membersRouter.get('/:id/subscription', async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `SELECT * FROM fs.v_member_subscription_status WHERE member_id = $1`,
    [id]
  );
  if (result.rowCount === 0) {
    return res.json({ member_id: id, active_subscription: null });
  }
  res.json({ active_subscription: result.rows[0] });
});

// GET /v1/members/:id/reservations
membersRouter.get('/:id/reservations', async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `
    SELECT r.id, r.confirmation_code, r.status, r.pickup_at, r.return_at,
           r.days_booked, r.total_points_cost,
           mf.name || ' ' || vm.model_name AS vehicle,
           v.exterior_color
      FROM fs.reservations r
      JOIN fs.vehicles v ON v.id = r.vehicle_id
      JOIN fs.vehicle_models vm ON vm.id = v.model_id
      JOIN fs.manufacturers mf ON mf.id = vm.manufacturer_id
     WHERE r.member_id = $1
     ORDER BY r.pickup_at DESC
     LIMIT 100
    `,
    [id]
  );
  res.json({ count: result.rowCount, reservations: result.rows });
});

// GET /v1/members/:id/point-history
membersRouter.get('/:id/point-history', async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `
    SELECT pt.id, pt.txn_type, pt.points, pt.balance_after, pt.reason,
           pt.reservation_id, pt.created_at
      FROM fs.point_transactions pt
      JOIN fs.member_subscriptions s ON s.id = pt.subscription_id
     WHERE s.member_id = $1
     ORDER BY pt.created_at DESC
     LIMIT 200
    `,
    [id]
  );
  res.json({ count: result.rowCount, transactions: result.rows });
});
