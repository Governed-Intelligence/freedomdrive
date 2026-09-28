// Realistic demo seed data for Freedom Supercars.
// Generates 20 members with mixed subscriptions and 60 reservations
// spread across the prior 60 and next 90 days.
//
// Usage:   DATABASE_URL=postgres://... node scripts/seed.js
// Safe to re-run: skips if data already exists (checks member_number prefix).
//
// The 20 members are given member numbers FS-SEED-0001..0020 so a repeat run
// can be spotted with: SELECT COUNT(*) FROM fs.members WHERE member_number LIKE 'FS-SEED-%';

import pg from 'pg';
import { faker } from '@faker-js/faker';

const { Client } = pg;

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL is required');
  process.exit(1);
}

// Reproducible random data
faker.seed(42);

const NUM_MEMBERS = 20;
const NUM_RESERVATIONS = 60;
const PLAN_MIX = [
  // Roughly what a real club would look like — heavier in the middle
  { code: 'PLAN_15',  count: 4 },
  { code: 'PLAN_30',  count: 9 },
  { code: 'PLAN_60',  count: 5 },
  { code: 'PLAN_100', count: 2 },
];

async function main() {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  await client.query('SET search_path TO fs, public');

  console.log('Checking for existing seed data...');
  const existing = await client.query(
    `SELECT COUNT(*)::int AS n FROM fs.members WHERE member_number LIKE 'FS-SEED-%'`
  );
  if (existing.rows[0].n > 0) {
    console.log(`Found ${existing.rows[0].n} existing seed members — nothing to do.`);
    console.log(`To reseed, delete them first:`);
    console.log(`  DELETE FROM fs.members WHERE member_number LIKE 'FS-SEED-%';`);
    console.log(`  (cascades to subscriptions, reservations, point_transactions)`);
    await client.end();
    return;
  }

  // Load reference data
  console.log('Loading plans, vehicles, locations...');
  const plans = await client.query(`SELECT id, code, annual_tier_points FROM fs.plans`);
  const planByCode = Object.fromEntries(plans.rows.map((p) => [p.code, p]));

  const vehicles = await client.query(
    `SELECT v.id AS vehicle_id, v.tier_id, t.points_per_day, t.min_booking_days
       FROM fs.vehicles v JOIN fs.tiers t ON t.id = v.tier_id
      WHERE v.retired_on IS NULL AND v.is_member_visible = TRUE`
  );
  if (vehicles.rowCount === 0) {
    console.error('No vehicles in the fleet — has the initial migration run?');
    process.exit(1);
  }

  const locations = await client.query(`SELECT id, code FROM fs.locations LIMIT 1`);
  const locationId = locations.rows[0]?.id;

  // ------------------------------------------------------------------
  // 1. Create members
  // ------------------------------------------------------------------
  console.log(`Creating ${NUM_MEMBERS} members...`);
  const members = [];
  for (let i = 0; i < NUM_MEMBERS; i++) {
    const first = faker.person.firstName();
    const last = faker.person.lastName();
    const memberNumber = `FS-SEED-${String(i + 1).padStart(4, '0')}`;
    const joinedDaysAgo = faker.number.int({ min: 30, max: 900 });
    const joinedOn = new Date();
    joinedOn.setDate(joinedOn.getDate() - joinedDaysAgo);

    const result = await client.query(
      `INSERT INTO fs.members
         (member_number, first_name, last_name, email, phone,
          city, state, postal_code, primary_location_id,
          status, joined_on, referral_source)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'active',$10,$11)
       RETURNING id`,
      [
        memberNumber,
        first,
        last,
        `${first.toLowerCase()}.${last.toLowerCase()}${i}@example.com`,
        faker.phone.number({ style: 'national' }),
        faker.location.city(),
        'TX',
        faker.location.zipCode('77###'),
        locationId,
        joinedOn.toISOString().slice(0, 10),
        faker.helpers.arrayElement(['member_referral', 'event', 'partner', 'website', 'social', 'press']),
      ]
    );
    members.push({ id: result.rows[0].id, memberNumber, first, last });
  }

  // ------------------------------------------------------------------
  // 2. Assign plans and create active subscriptions (triggers grant points)
  // ------------------------------------------------------------------
  console.log('Creating subscriptions with plan mix...');
  const planAssignments = [];
  let mi = 0;
  for (const { code, count } of PLAN_MIX) {
    for (let j = 0; j < count; j++) {
      planAssignments.push({ memberId: members[mi].id, planCode: code });
      mi++;
    }
  }
  // Any remainder → PLAN_30
  while (mi < members.length) {
    planAssignments.push({ memberId: members[mi].id, planCode: 'PLAN_30' });
    mi++;
  }

  const subscriptions = [];
  for (const { memberId, planCode } of planAssignments) {
    const plan = planByCode[planCode];
    // Term started somewhere in the past year, ends about a year after start
    const daysAgo = faker.number.int({ min: 30, max: 300 });
    const start = new Date();
    start.setDate(start.getDate() - daysAgo);
    const end = new Date(start);
    end.setFullYear(end.getFullYear() + 1);

    const result = await client.query(
      `INSERT INTO fs.member_subscriptions
         (member_id, plan_id, status, start_date, end_date,
          points_granted, points_rolled_in, auto_renew)
       VALUES ($1,$2,'active',$3,$4,$5,0,TRUE)
       RETURNING id`,
      [
        memberId,
        plan.id,
        start.toISOString().slice(0, 10),
        end.toISOString().slice(0, 10),
        plan.annual_tier_points,
      ]
    );
    subscriptions.push({
      id: result.rows[0].id,
      memberId,
      planCode,
      pointsGranted: plan.annual_tier_points,
    });
  }

  // ------------------------------------------------------------------
  // 3. Create reservations spread across -60 to +90 days
  // ------------------------------------------------------------------
  console.log(`Creating ~${NUM_RESERVATIONS} reservations...`);
  let created = 0;
  let attempts = 0;
  const maxAttempts = NUM_RESERVATIONS * 4;

  while (created < NUM_RESERVATIONS && attempts < maxAttempts) {
    attempts++;
    const sub = faker.helpers.arrayElement(subscriptions);
    const vehicle = faker.helpers.arrayElement(vehicles.rows);

    // Days offset from today: 40% past, 60% future
    const isPast = Math.random() < 0.4;
    const dayOffset = isPast
      ? faker.number.int({ min: -60, max: -1 })
      : faker.number.int({ min: 1, max: 90 });

    const days = faker.number.int({
      min: vehicle.min_booking_days,
      max: Math.min(vehicle.min_booking_days + 2, 5),
    });

    const pickup = new Date();
    pickup.setDate(pickup.getDate() + dayOffset);
    pickup.setHours(10, 0, 0, 0);
    const returnAt = new Date(pickup);
    returnAt.setDate(returnAt.getDate() + days);

    const totalCost = Math.ceil(Number(vehicle.points_per_day) * days);

    // Skip if member can't afford it (some subs will have less to work with)
    const balance = await client.query(
      `SELECT fs.subscription_balance($1)::int AS b`,
      [sub.id]
    );
    if (balance.rows[0].b < totalCost) continue;

    // Decide final status
    let status;
    if (isPast) {
      status = faker.helpers.weightedArrayElement([
        { value: 'returned', weight: 8 },
        { value: 'cancelled', weight: 2 },
      ]);
    } else if (dayOffset < 3) {
      status = 'confirmed'; // imminent
    } else {
      status = faker.helpers.weightedArrayElement([
        { value: 'confirmed', weight: 7 },
        { value: 'requested', weight: 3 },
      ]);
    }

    const code = generateConfirmationCode();

    try {
      // Insert as 'confirmed' first (trigger will debit points), then update to final status
      // if different — this exercises the same code path as the API
      const insertStatus = ['returned', 'confirmed', 'requested'].includes(status)
        ? (status === 'requested' ? 'requested' : 'confirmed')
        : 'confirmed';

      const result = await client.query(
        `INSERT INTO fs.reservations
           (confirmation_code, member_id, subscription_id, vehicle_id, status,
            pickup_at, return_at, days_booked, tier_points_per_day, total_points_cost,
            destination, purpose)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
         RETURNING id`,
        [
          code,
          sub.memberId,
          sub.id,
          vehicle.vehicle_id,
          insertStatus,
          pickup.toISOString(),
          returnAt.toISOString(),
          days,
          vehicle.points_per_day,
          totalCost,
          faker.helpers.arrayElement(['Galveston', 'Austin', 'Dallas', 'San Antonio', 'Fredericksburg', 'The Hill Country', 'Corpus Christi', 'Local drive']),
          faker.helpers.arrayElement(['Weekend getaway', 'Anniversary', 'Birthday', 'Business meeting', 'Track day', 'Photo shoot', 'Just for fun']),
        ]
      );

      // Bump to 'returned' or 'cancelled' if that was the plan
      if (status === 'returned' || status === 'cancelled') {
        await client.query(
          `UPDATE fs.reservations SET status = $2 WHERE id = $1`,
          [result.rows[0].id, status]
        );
      }
      created++;
    } catch (err) {
      // Overlap conflict or insufficient points — just try another combo
      if (err.code === '23P01' || err.code === 'P0001') continue;
      throw err;
    }
  }

  console.log(`Created ${created} reservations after ${attempts} attempts.`);

  // ------------------------------------------------------------------
  // Summary
  // ------------------------------------------------------------------
  const summary = await client.query(`
    SELECT
      (SELECT COUNT(*)::int FROM fs.members WHERE member_number LIKE 'FS-SEED-%') AS members,
      (SELECT COUNT(*)::int FROM fs.member_subscriptions s JOIN fs.members m ON m.id = s.member_id
        WHERE m.member_number LIKE 'FS-SEED-%' AND s.status = 'active') AS active_subs,
      (SELECT COUNT(*)::int FROM fs.reservations r JOIN fs.members m ON m.id = r.member_id
        WHERE m.member_number LIKE 'FS-SEED-%') AS reservations,
      (SELECT COUNT(*)::int FROM fs.point_transactions pt
        JOIN fs.member_subscriptions s ON s.id = pt.subscription_id
        JOIN fs.members m ON m.id = s.member_id
        WHERE m.member_number LIKE 'FS-SEED-%') AS point_txns
  `);
  console.log('\nSeed complete:');
  console.table(summary.rows[0]);

  await client.end();
}

function generateConfirmationCode() {
  const now = new Date();
  const yy = String(now.getFullYear()).slice(2);
  const mm = String(now.getMonth() + 1).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let suffix = '';
  for (let i = 0; i < 4; i++) suffix += alphabet[Math.floor(Math.random() * alphabet.length)];
  return `FS-${yy}${mm}${dd}-${suffix}`;
}

main().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
