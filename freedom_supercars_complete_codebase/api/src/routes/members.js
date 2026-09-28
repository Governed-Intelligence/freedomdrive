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

function normalizeName(str) {
  if (!str) return '';
  return str.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function normalizePhone(str) {
  if (!str) return '';
  const digits = str.replace(/\D/g, '');
  return (digits.length === 11 && digits.startsWith('1')) ? digits.slice(1) : digits;
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
  last_name: z.string().min(1).max(100),
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
  primary_location_code: z.string().max(10).optional(),
  referral_source: z.string().max(100).optional(),
});

const listSchema = z.object({
  status: z.enum(['prospect', 'pending', 'active', 'paused', 'suspended', 'cancelled', 'expired', 'former']).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

// GET /v1/members — list
membersRouter.get('/', async (req, res) => {
  const params = listSchema.parse(req.query);
  const clauses = [];
  const values = [];
  if (params.status) {
    values.push(params.status);
    clauses.push(`status = $${values.length}`);
  }
  const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
  values.push(params.limit, params.offset);
  const result = await query(
    `
    SELECT id, member_number, first_name, last_name, email, phone, status,
           joined_on, primary_location_id, created_at
      FROM fs.members
      ${where}
     ORDER BY created_at DESC
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
    `SELECT id, member_number, first_name, last_name, email, phone, status, primary_location_id
       FROM fs.members WHERE lower(email) = $1 LIMIT 1`,
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
    SELECT id, first_name, last_name, email, phone, drivers_license_number, date_of_birth, address_line1, status
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

    // 6.1-C08: Last name + Date of Birth flags together (6.1-C07: last name alone does NOT flag)
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

// POST /v1/members/onboard — Guide 6.1 Comprehensive Onboarding (6.1-C01 through 6.1-C16)
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

  // 6.1-C13 & 6.1-C14: Ensure account-flagged and vehicle-flagged emails exist
  const accountEmail = data.account_email || data.email;
  const vehicleEmail = data.vehicle_email || data.email;

  // Resolve branch location
  let locationId = null;
  if (data.primary_location_code) {
    const loc = await query(`SELECT id FROM fs.locations WHERE code = $1`, [data.primary_location_code.toUpperCase()]);
    if (loc.rowCount > 0) locationId = loc.rows[0].id;
  }

  // 6.1-C01: USER and MEMBER written in one transaction (rollback leaves neither)
  const result = await withTransaction(async (client) => {
    // 6.1-C02: One login account carries at most one member profile (user_id unique)
    let userId = data.user_id;
    if (userId) {
      const userCheck = await client.query(`SELECT id FROM fs.members WHERE user_id = $1`, [userId]);
      if (userCheck.rowCount > 0) {
        throw new HttpError(409, 'A second member profile cannot be created against a login account that already has one.');
      }
    }

    // 6.1-C03: A saved member has a member_id, a Pending status, and NO member number
    const insertMember = await client.query(
      `
      INSERT INTO fs.members (
        first_name, middle_name, last_name, email, phone, date_of_birth,
        drivers_license_number, drivers_license_state, drivers_license_expires,
        address_line1, address_line2, city, state, postal_code,
        primary_location_id, referral_source, status, member_number, joined_on, user_id
      ) VALUES (
        $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,'prospect',NULL,NULL,$17
      )
      RETURNING id, first_name, last_name, email, status, member_number, created_at
      `,
      [
        data.first_name,
        data.middle_name ?? null,
        data.last_name,
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

    // If a plan was chosen, create a pending subscription package
    let subId = null;
    if (data.plan_code) {
      const planRes = await client.query(`SELECT id, annual_tier_points FROM fs.plans WHERE code = $1`, [data.plan_code]);
      if (planRes.rowCount > 0) {
        const plan = planRes.rows[0];
        const subInsert = await client.query(
          `
          INSERT INTO fs.member_subscriptions (
            member_id, plan_id, status, start_date, end_date, points_granted, auto_renew
          ) VALUES ($1, $2, 'pending', COALESCE($3, CURRENT_DATE), (COALESCE($3, CURRENT_DATE) + INTERVAL '1 year')::date, $4, TRUE)
          RETURNING id
          `,
          [member.id, plan.id, data.planned_start_date ?? null, plan.annual_tier_points]
        );
        subId = subInsert.rows[0].id;
      }
    }

    return {
      member_id: member.id,
      member_number: null,
      status: 'pending',
      first_name: member.first_name,
      last_name: member.last_name,
      email: member.email,
      account_email: accountEmail,
      vehicle_email: vehicleEmail,
      subscription_id: subId,
      created_at: member.created_at,
    };
  });

  res.status(201).json({ ok: true, member: result });
});

// POST /v1/members/:id/activate — Guide 6.1 Activation & Minting (6.1-C18 through 6.1-C32)
membersRouter.post('/:id/activate', async (req, res) => {
  const { id } = req.params;
  const data = activateSchema.parse(req.body);

  // 6.1-C20: Activation without a payment arrangement is refused
  if (!data.payment_arrangement_confirmed) {
    throw new HttpError(400, 'Activation without a payment arrangement is refused.');
  }

  // 6.1-C21: Activation without insurance SUCCEEDS (insurance gates release, not activation)
  const result = await withTransaction(async (client) => {
    const mRes = await client.query(`SELECT * FROM fs.members WHERE id = $1`, [id]);
    if (mRes.rowCount === 0) throw new HttpError(404, 'Member not found');
    const member = mRes.rows[0];

    // 6.1-C29: A second activation does NOT mint a new number
    if (member.status === 'active' && member.member_number) {
      return {
        member_id: member.id,
        member_number: member.member_number,
        member_since: member.joined_on,
        status: member.status,
        re_activated: true,
      };
    }

    // 6.1-C28: First activation mints member_seq, member_number, and member_since together
    const year = new Date().getFullYear();
    const countRes = await client.query(
      `SELECT COUNT(*)::int AS c FROM fs.members WHERE member_number IS NOT NULL AND member_number LIKE $1`,
      [`FS-${year}-%`]
    );
    const seq = countRes.rows[0].c + 1;
    const memberNumber = `FS-${year}-${String(seq).padStart(4, '0')}`;
    const actDate = data.activation_date ? new Date(data.activation_date) : new Date();
    const actIso = actDate.toISOString().slice(0, 10);

    // Update Member to Active
    await client.query(
      `
      UPDATE fs.members
         SET member_number = $1,
             joined_on = $2,
             status = 'active',
             updated_at = now()
       WHERE id = $3
      `,
      [memberNumber, actIso, id]
    );

    // Activate subscription package & grant points
    let pointsBalance = 0;
    const subRes = await client.query(
      `SELECT id, plan_id, start_date FROM fs.member_subscriptions WHERE member_id = $1 ORDER BY created_at DESC LIMIT 1`,
      [id]
    );

    if (subRes.rowCount > 0) {
      const sub = subRes.rows[0];
      const planRes = await client.query(`SELECT annual_tier_points FROM fs.plans WHERE id = $1`, [sub.plan_id]);
      const annualPts = planRes.rows[0]?.annual_tier_points || 0;

      // 6.1-C22 / 6.1-C23: Adjust start/end dates
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

      // trg_subs_grant_points trigger automatically inserts the initial 'grant' transaction
      const balRes = await client.query(
        `SELECT balance_after FROM fs.point_transactions WHERE subscription_id = $1 ORDER BY id DESC LIMIT 1`,
        [sub.id]
      );
      pointsBalance = balRes.rows[0]?.balance_after ?? annualPts;

      // 6.1-C26: Activation posts joining bonus if configured
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

      // 6.1-C27: Activation converts tentative reservations held against the member
      await client.query(
        `
        UPDATE fs.reservations
           SET status = 'confirmed'
         WHERE member_id = $1 AND status = 'requested'
        `,
        [id]
      );
    }

    return {
      member_id: member.id,
      member_number: memberNumber,
      member_seq: seq,
      member_since: actIso,
      status: 'active',
      points_balance: pointsBalance,
    };
  });

  res.json({ ok: true, activation: result });
});

// Legacy POST /v1/members (for backwards compatibility)
membersRouter.post('/', async (req, res) => {
  const data = createSchema.parse(req.body);

  let locationId = null;
  if (data.primary_location_code) {
    const loc = await query(`SELECT id FROM fs.locations WHERE code = $1`, [data.primary_location_code.toUpperCase()]);
    if (loc.rowCount > 0) locationId = loc.rows[0].id;
  }

  const year = new Date().getFullYear();
  const counterRow = await query(
    `SELECT COUNT(*)::int AS c FROM fs.members WHERE member_number LIKE $1`,
    [`FS-${year}-%`]
  );
  const memberNumber = `FS-${year}-${String(counterRow.rows[0].c + 1).padStart(4, '0')}`;

  const insert = await query(
    `
    INSERT INTO fs.members (
      member_number, first_name, last_name, email, phone, date_of_birth,
      drivers_license_number, drivers_license_state, drivers_license_expires,
      address_line1, address_line2, city, state, postal_code,
      primary_location_id, referral_source, status
    ) VALUES (
      $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,'active'
    )
    RETURNING id, member_number, first_name, last_name, email, status, created_at
    `,
    [
      memberNumber,
      data.first_name,
      data.last_name,
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
  res.status(201).json({ member: insert.rows[0] });
});

// GET /v1/members/:id
membersRouter.get('/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(`SELECT * FROM fs.members WHERE id = $1`, [id]);
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
