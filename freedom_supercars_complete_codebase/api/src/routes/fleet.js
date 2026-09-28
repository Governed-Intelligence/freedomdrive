import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError } from '../middleware/errorHandler.js';

export const fleetRouter = Router();

// -----------------------------------------------------------------------------
// Validation Schemas
// -----------------------------------------------------------------------------

const listQuerySchema = z.object({
  tier: z.coerce.number().int().min(1).max(5).optional(),
  status: z.enum(['available', 'reserved', 'in_use', 'maintenance', 'detailing', 'in_transit', 'retired']).optional(),
  fleet_stage: z.enum(['Incoming', 'Intake', 'Fleet', 'Retired']).optional(),
  manufacturer: z.string().max(100).optional(),
  location: z.string().max(10).optional(),
  marquee_only: z.coerce.boolean().optional(),
  include_unlaunched: z.coerce.boolean().optional().default(false),
});

const checkVinSchema = z.object({
  vin: z.string().trim().toUpperCase(),
});

const companionDescriptionSchema = z.object({
  body_style: z.enum(['Coupe', 'Convertible', 'SUV', 'Sedan', 'Targa', 'Other']).optional(),
  transmission: z.enum(['Automatic', 'Manual', 'Dual-Clutch', 'Other']).optional(),
  engine: z.enum(['V6', 'V8', 'V10', 'V12', 'Electric', 'Hybrid', 'Other']).optional(),
  seats: z.enum(['2', '4', '5', 'Other']).optional(),
  doors: z.enum(['2', '4', 'Other']).optional(),
  trunk_size: z.enum(['Small', 'Medium', 'Large', 'Front/Rear']).optional(),
  fuel_tank_size: z.number().int().positive().optional(),
  range: z.number().int().positive().optional(),
  image_url: z.string().max(255).optional(),
  description: z.string().optional(),
}).optional();

const companionSpecSchema = z.object({
  engine_oil_brand: z.string().max(40).optional(),
  engine_oil_spec: z.string().max(20).optional(),
  gps_type: z.enum(['Factory', 'Aftermarket', 'Hardwired', 'OBD', 'Other']).optional(),
  gps_device_id: z.string().max(40).optional(),
}).optional();

const companionPerformanceSchema = z.object({
  horsepower: z.number().int().positive().optional(),
  top_speed: z.number().int().positive().optional(),
  zero_to_sixty_time: z.number().positive().optional(),
  rpm_redline: z.number().int().positive().optional(),
}).optional();

const companionRegWarrantySchema = z.object({
  registration_state: z.string().length(2).optional(),
  temp_license_plate: z.string().max(15).optional(),
  license_plate: z.string().max(15).optional(),
  toll_tag: z.string().max(30).optional(),
  registration_expires_on: z.string().optional(),
  inspection_expires_on: z.string().optional(),
  warranty_end: z.string().optional(),
  warranty_company: z.string().max(120).optional(),
}).optional();

const companionTiresSchema = z.object({
  front_tire_size: z.string().max(80).optional(),
  front_tire_psi: z.number().int().optional(),
  front_tire_brand: z.string().max(40).optional(),
  front_tire_model: z.string().max(80).optional(),
  rear_tire_size: z.string().max(20).optional(),
  rear_tire_psi: z.number().int().optional(),
  rear_tire_brand: z.string().max(40).optional(),
  rear_tire_model: z.string().max(80).optional(),
  spare_tire_size: z.string().max(80).optional(),
}).optional();

const companionAccessoriesSchema = z.object({
  manuals: z.boolean().optional(),
  car_cover: z.boolean().optional(),
  charger: z.boolean().optional(),
  number_keys: z.enum(['1', '2', '3+']).optional(),
  accessories: z.string().max(240).optional(),
  features: z.string().max(240).optional(),
}).optional();

const createVehicleSchema = z.object({
  vin: z.string().trim().toUpperCase(),
  vehicle_make_code: z.string().min(1).max(40),
  model: z.string().min(1).max(80),
  trim: z.string().max(40).optional(),
  vehicle_name: z.string().max(160).optional(),
  year: z.string().length(4),
  exterior_color: z.string().min(1).max(40),
  interior_color: z.string().max(40).optional(),
  home_branch_code: z.string().max(10).default('HOU'),
  stock_number: z.string().max(20).optional(),
  tier_id: z.number().int().min(1).max(5).default(3),
  launch_date: z.string().optional(), // NULL = pre-launch (8.1-C12)
  expected_arrival_date: z.string().optional(),
  arrival_date: z.string().optional(),
  notes: z.string().optional(),
  fleet_stage: z.enum(['Incoming', 'Intake', 'Fleet', 'Retired']).default('Incoming'),
  condition_code: z.enum(['Arrived', 'Returned', 'Review', 'Prep', 'Ready', 'Down']).default('Arrived'),
  // Companions (optional at creation, 8.1-C04, 8.1-C06)
  description: companionDescriptionSchema,
  spec: companionSpecSchema,
  performance: companionPerformanceSchema,
  registration_warranty: companionRegWarrantySchema,
  tires: companionTiresSchema,
  accessories: companionAccessoriesSchema,
});

const updateVehicleSchema = z.object({
  vin: z.string().trim().toUpperCase().optional(), // 8.1-C05: edit refused
  vehicle_make_code: z.string().max(40).optional(),
  model: z.string().max(80).optional(),
  trim: z.string().max(40).optional(),
  vehicle_name: z.string().max(160).optional(),
  year: z.string().length(4).optional(),
  exterior_color: z.string().max(40).optional(),
  interior_color: z.string().max(40).optional(),
  launch_date: z.string().nullable().optional(),
  arrival_date: z.string().optional(),
  fleet_stage: z.enum(['Incoming', 'Intake', 'Fleet', 'Retired']).optional(),
  condition_code: z.enum(['Arrived', 'Returned', 'Review', 'Prep', 'Ready', 'Down']).optional(),
  notes: z.string().optional(),
});

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

async function validateLookups(client, make, year, color, interiorColor) {
  // 8.1-C03: A make, year, or color outside its lookup is rejected.
  const makeRes = await client.query(
    `SELECT vehicle_make_code, vehicle_make_name FROM fs.vehicle_make_select
      WHERE UPPER(vehicle_make_code) = UPPER($1) OR UPPER(vehicle_make_name) = UPPER($1)`,
    [make]
  );
  if (makeRes.rowCount === 0) {
    throw new HttpError(400, `8.1-C03: Vehicle make '${make}' is outside VEHICLE_MAKE_SELECT lookup.`);
  }

  const yearRes = await client.query(
    `SELECT vehicle_year_code FROM fs.vehicle_year_select WHERE vehicle_year_code = $1`,
    [year]
  );
  if (yearRes.rowCount === 0) {
    throw new HttpError(400, `8.1-C03: Vehicle year '${year}' is outside VEHICLE_YEAR_SELECT lookup.`);
  }

  const colorRes = await client.query(
    `SELECT vehicle_color_code, vehicle_color_name FROM fs.vehicle_color_select
      WHERE UPPER(vehicle_color_code) = UPPER($1) OR UPPER(vehicle_color_name) = UPPER($1)`,
    [color]
  );
  if (colorRes.rowCount === 0) {
    throw new HttpError(400, `8.1-C03: Vehicle color '${color}' is outside VEHICLE_COLOR_SELECT lookup.`);
  }

  let interiorColorCode = null;
  if (interiorColor) {
    const intRes = await client.query(
      `SELECT vehicle_color_code FROM fs.vehicle_color_select
        WHERE UPPER(vehicle_color_code) = UPPER($1) OR UPPER(vehicle_color_name) = UPPER($1)
           OR UPPER($1) LIKE '%' || UPPER(vehicle_color_name) || '%'`,
      [interiorColor]
    );
    if (intRes.rowCount > 0) {
      interiorColorCode = intRes.rows[0].vehicle_color_code;
    } else {
      interiorColorCode = 'OTHER';
    }
  }

  return {
    make_code: makeRes.rows[0].vehicle_make_code,
    make_name: makeRes.rows[0].vehicle_make_name,
    exterior_color_code: colorRes.rows[0].vehicle_color_code,
    exterior_color_name: colorRes.rows[0].vehicle_color_name,
    interior_color_code: interiorColorCode,
  };
}

async function getCompanionsSummary(client, vehicleId) {
  // 8.1-C09: The completeness summary lists which companions are missing.
  const [desc, spec, perf, reg, tires, acc] = await Promise.all([
    client.query(`SELECT * FROM fs.vehicle_description WHERE vehicle_id = $1`, [vehicleId]),
    client.query(`SELECT * FROM fs.vehicle_spec WHERE vehicle_id = $1`, [vehicleId]),
    client.query(`SELECT * FROM fs.vehicle_performance WHERE vehicle_id = $1`, [vehicleId]),
    client.query(`SELECT * FROM fs.vehicle_registration_warranty WHERE vehicle_id = $1`, [vehicleId]),
    client.query(`SELECT * FROM fs.vehicle_tires WHERE vehicle_id = $1`, [vehicleId]),
    client.query(`SELECT * FROM fs.vehicle_accessories WHERE vehicle_id = $1`, [vehicleId]),
  ]);

  const companions = {
    description: desc.rows[0] || null,
    spec: spec.rows[0] || null,
    performance: perf.rows[0] || null,
    registration_warranty: reg.rows[0] || null,
    tires: tires.rows[0] || null,
    accessories: acc.rows[0] || null,
  };

  const present = [];
  const missing = [];
  for (const [key, val] of Object.entries(companions)) {
    if (val) present.push(key);
    else missing.push(key);
  }

  return {
    companions,
    present_count: present.length,
    missing,
    is_complete: missing.length === 0,
    completeness_percentage: Math.round((present.length / 6) * 100),
  };
}

async function recordVehicleShadow(client, vehicleId, changeReason, changedByUserId = null) {
  try {
    await client.query(
      `INSERT INTO fs.vehicle_shadow (
         vehicle_id, vin, vehicle_make_code, model, trim, vehicle_name, year,
         exterior_color, exterior_color_short, interior_color, paint_code_1, paint_code_2,
         condition_code, condition_since, home_branch_id, launch_date,
         expected_arrival_date, arrival_date, notes, fleet_stage,
         created_at, updated_at, created_by_user_id, updated_by_user_id,
         changed_by_user_id, changed_at, change_reason
       )
       SELECT
         vehicle_id, vin, vehicle_make_code, model, trim, vehicle_name, year,
         exterior_color, exterior_color_short, interior_color, paint_code_1, paint_code_2,
         condition_code, condition_since, home_branch_id, launch_date,
         expected_arrival_date, arrival_date, notes, fleet_stage,
         created_at, updated_at, created_by_user_id, updated_by_user_id,
         $2, now(), $3
       FROM fs.vehicle
       WHERE vehicle_id = $1`,
      [vehicleId, changedByUserId, changeReason]
    );
  } catch (err) {
    console.error('Failed to record vehicle shadow:', err.message);
  }
}


// -----------------------------------------------------------------------------
// Routes
// -----------------------------------------------------------------------------

// POST /v1/fleet/check-vin — Guide 8.1 Rules 8.1-R01, 8.1-R13 (8.1-C01, 8.1-C02, 8.1-C21)
fleetRouter.post('/check-vin', async (req, res) => {
  const { vin } = checkVinSchema.parse(req.body);

  // 8.1-C02: A VIN other than seventeen characters is rejected
  if (vin.length !== 17) {
    throw new HttpError(400, '8.1-C02: A VIN other than seventeen characters is rejected.');
  }

  const existing = await query(
    `SELECT vehicle_id, vin, vehicle_name, model, fleet_stage, condition_code
       FROM fs.vehicle WHERE vin = $1`,
    [vin]
  );

  if (existing.rowCount > 0) {
    const v = existing.rows[0];
    // 8.1-C21: A repurchased vehicle reuses its record and returns from Retired
    if (v.fleet_stage === 'Retired') {
      return res.json({
        ok: true,
        valid: true,
        duplicate: false,
        is_repurchase: true,
        existing_vehicle: v,
        message: `8.1-C21: VIN belongs to retired vehicle ${v.vehicle_name}. Repurchase will return this record from Retired.`,
      });
    }

    // 8.1-C01: A duplicate VIN is rejected at the first step, naming the existing vehicle
    return res.status(409).json({
      ok: false,
      valid: false,
      duplicate: true,
      existing_vehicle: v,
      error: `8.1-C01: Duplicate VIN rejected. Already assigned to existing vehicle '${v.vehicle_name}' (ID: ${v.vehicle_id}).`,
    });
  }

  res.json({
    ok: true,
    valid: true,
    duplicate: false,
    vin,
    message: 'VIN is valid and unique.',
  });
});

// GET /v1/fleet/vendors — List all active service vendors (Houston & network)
fleetRouter.get('/vendors', async (req, res) => {
  const result = await query(
    `SELECT v.vendor_id, v.vendor_name, v.vendor_type_code, v.vendor_phone, v.vendor_email,
            v.address_line1, v.city, v.state, v.postal_code, v.is_active, v.notes,
            b.name AS branch_name
       FROM fs.vendor v
       LEFT JOIN fs.locations b ON b.id = v.home_branch_id
      WHERE v.is_active = TRUE
      ORDER BY v.vendor_name ASC`
  );
  res.json({
    count: result.rowCount,
    vendors: result.rows,
  });
});

// GET /v1/fleet — Current fleet with member visibility rule (8.1-C12, 8.1-C16, 8.6-C02, 8.6-C05, 8.6-C10-C13)
fleetRouter.get('/', async (req, res) => {
  const params = listQuerySchema.parse(req.query);
  const isMember = (Boolean(req.headers['x-member-id']) || req.query.as_member === 'true') && !req.headers['x-staff'] && req.query.as_staff !== 'true';
  const memberPodiumStatus = req.headers['x-member-podium-status'] || req.query.podium_status || null;

  const clauses = [];
  const values = [];

  if (params.tier) {
    values.push(params.tier);
    clauses.push(`tier_id = $${values.length}`);
  }
  if (params.status) {
    values.push(params.status);
    clauses.push(`status = $${values.length}`);
  }
  if (params.manufacturer) {
    values.push(params.manufacturer);
    clauses.push(`manufacturer ILIKE $${values.length}`);
  }
  if (params.location) {
    values.push(params.location.toUpperCase());
    clauses.push(`location_code = $${values.length}`);
  }
  if (params.marquee_only) {
    clauses.push(`vehicle_id IN (SELECT id FROM fs.vehicles WHERE is_marquee = TRUE AND retired_on IS NULL)`);
  }

  // 8.6-C02: A vehicle at Fleet with an open AwaitingLaunch withhold is invisible to members.
  if (isMember) {
    clauses.push(`vehicle_id NOT IN (
      SELECT vehicle_id FROM fs.reservation_withhold 
       WHERE withhold_reason_code = 'AwaitingLaunch' AND released_at IS NULL
    )`);
    // 8.6-C05: A vehicle with no launch date is never visible to members.
    clauses.push(`vehicle_id IN (
      SELECT vehicle_id FROM fs.vehicle WHERE launch_date IS NOT NULL
    )`);
  }

  const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
  const sql = `
    SELECT vehicle_id, stock_number, model_year, manufacturer, model, trim,
           exterior_color, tier_id, points_per_day, min_booking_days,
           horsepower, top_speed_mph, zero_to_60_sec, status, condition,
           current_mileage, location_code
      FROM fs.v_active_fleet
      ${where}
     ORDER BY tier_id ASC, manufacturer ASC, model ASC
  `;
  const result = await query(sql, values);

  // If member, apply Guide 8.6 release row visibility logic (8.6-C10, 8.6-C11, 8.6-C12, 8.6-C13)
  if (isMember) {
    const finalVehicles = [];
    const podiumRank = { NONE: 0, MEMBER: 0, BRONZE: 0, SILVER: 1, GOLD: 2, PLATINUM: 3, BLACK: 4, VIP: 4 };
    const memberRank = podiumRank[String(memberPodiumStatus || '').toUpperCase()] || 0;

    for (const v of result.rows) {
      // Fetch vehicle launch_date and release rows
      const vDetails = await query(
        `SELECT launch_date::text AS launch_date FROM fs.vehicle WHERE vehicle_id = $1`,
        [v.vehicle_id]
      );
      const launchDateStr = vDetails.rows[0]?.launch_date;
      if (!launchDateStr) {
        // 8.6-C05: Vehicle with no launch date is never visible to members
        continue;
      }

      const launchDate = new Date(launchDateStr);
      const today = new Date();
      today.setHours(0, 0, 0, 0);

      // Fetch release rows
      const rowsRes = await query(
        `SELECT sort_order, duration_days, minimum_podium_status_code, hide_from_lower_tiers
           FROM fs.vehicle_release_row
          WHERE vehicle_id = $1
          ORDER BY sort_order ASC`,
        [v.vehicle_id]
      );
      const releaseRows = rowsRes.rows;

      if (launchDate > today) {
        // Pre-launch (before launch date)
        const firstRow = releaseRows[0];
        const hideFromLower = firstRow ? Boolean(firstRow.hide_from_lower_tiers) : false;
        if (hideFromLower) {
          // 8.6-C13: With the flag set, the vehicle is invisible before launch.
          continue;
        } else {
          // 8.6-C12: With the flag clear, the vehicle appears before launch marked Coming Soon.
          finalVehicles.push({
            ...v,
            status: 'Coming Soon',
            is_coming_soon: true,
            launch_date: launchDateStr,
          });
          continue;
        }
      }

      // Launched (launchDate <= today)
      if (releaseRows.length === 0) {
        // 8.6-C06: With no rows, every member can book from the launch date.
        finalVehicles.push(v);
        continue;
      }

      // Check which stage is active today
      let stageStart = new Date(launchDate);
      let activeStage = null;
      let openDateForMember = null;

      for (const row of releaseRows) {
        const dur = Number(row.duration_days) || 0;
        const stageEnd = new Date(stageStart.getTime() + dur * 86400000);
        if (today >= stageStart && today < stageEnd) {
          activeStage = row;
        }
        const rowMinRank = podiumRank[String(row.minimum_podium_status_code || '').toUpperCase()] || 0;
        if (memberRank >= rowMinRank && !openDateForMember) {
          openDateForMember = stageStart.toISOString().slice(0, 10);
        }
        stageStart = stageEnd;
      }

      // If all stages have passed, open to all (8.6-C09)
      if (today >= stageStart) {
        finalVehicles.push(v);
        continue;
      }

      if (!openDateForMember) {
        // Opens when all rows expire
        openDateForMember = stageStart.toISOString().slice(0, 10);
      }

      if (activeStage) {
        const minRank = podiumRank[String(activeStage.minimum_podium_status_code || '').toUpperCase()] || 0;
        if (memberRank < minRank) {
          if (activeStage.hide_from_lower_tiers) {
            // 8.6-C11: With the flag set, that member does not see the vehicle at all.
            continue;
          } else {
            // 8.6-C10: A member below the minimum sees the vehicle with the date it opens to them.
            finalVehicles.push({
              ...v,
              is_exclusive_locked: true,
              minimum_podium_status: activeStage.minimum_podium_status_code,
              available_to_tier_date: openDateForMember,
            });
            continue;
          }
        }
      }

      finalVehicles.push(v);
    }

    return res.json({
      count: finalVehicles.length,
      vehicles: finalVehicles,
    });
  }

  res.json({
    count: result.rowCount,
    vehicles: result.rows,
  });
});

// POST /v1/fleet — Add Vehicle Wizard / Intake (8.1-C01 through 8.1-C22)
fleetRouter.post('/', async (req, res) => {
  const data = createVehicleSchema.parse(req.body);

  // 8.1-C02: 17 character VIN check
  if (data.vin.length !== 17) {
    throw new HttpError(400, '8.1-C02: A VIN other than seventeen characters is rejected.');
  }

  const result = await withTransaction(async (client) => {
    // 8.1-C03: Lookups validation (make, year, color)
    const lookups = await validateLookups(client, data.vehicle_make_code, data.year, data.exterior_color, data.interior_color);

    // 8.1-C01 / 8.1-C21: Check duplicate VIN
    const existing = await client.query(`SELECT * FROM fs.vehicle WHERE vin = $1`, [data.vin]);
    let vehicleId = null;
    let isRepurchase = false;

    if (existing.rowCount > 0) {
      const v = existing.rows[0];
      if (v.fleet_stage === 'Retired') {
        // 8.1-C21: Repurchased vehicle reuses record and returns from Retired
        vehicleId = v.vehicle_id;
        isRepurchase = true;
        await client.query(
          `UPDATE fs.vehicle
              SET fleet_stage = $1,
                  condition_code = $2,
                  launch_date = $3,
                  arrival_date = COALESCE($4, CURRENT_DATE),
                  updated_at = now()
            WHERE vehicle_id = $5`,
          [data.fleet_stage, data.condition_code, data.launch_date ?? null, data.arrival_date ?? null, vehicleId]
        );
      } else {
        throw new HttpError(409, `8.1-C01: Duplicate VIN rejected. Already assigned to existing vehicle '${v.vehicle_name}' (ID: ${v.vehicle_id}).`);
      }
    }

    // Resolve branch
    let branchId = null;
    const branchRes = await client.query(
      `SELECT branch_id FROM fs.branch WHERE UPPER(branch_code) = UPPER($1) LIMIT 1`,
      [data.home_branch_code]
    );
    if (branchRes.rowCount > 0) branchId = branchRes.rows[0].branch_id;

    // 8.1-C22: Two vehicles of identical specification are distinguishable by name
    const vehicleName = data.vehicle_name || `${lookups.make_name} ${data.model}${data.trim ? ' ' + data.trim : ''}`;

    if (!isRepurchase) {
      // 8.1-C04, 8.1-C06: Core record saves before any companion is required / saves with no companions
      const insertCore = await client.query(
        `
        INSERT INTO fs.vehicle (
          vin, vehicle_make_code, model, trim, vehicle_name, year,
          exterior_color, interior_color, home_branch_id, launch_date,
          expected_arrival_date, arrival_date, notes, fleet_stage, condition_code
        ) VALUES (
          $1, $2, $3, $4, $5, $6,
          $7, $8, $9, $10,
          $11, $12, $13, $14, $15
        )
        RETURNING *
        `,
        [
          data.vin,
          lookups.make_code,
          data.model,
          data.trim ?? null,
          vehicleName,
          data.year,
          lookups.exterior_color_code,
          lookups.interior_color_code,
          branchId,
          data.launch_date ?? null, // 8.1-C12: NULL launch date is pre-launch
          data.expected_arrival_date ?? null,
          data.arrival_date ?? null,
          data.notes ?? null,
          data.fleet_stage,
          data.condition_code,
        ]
      );
      vehicleId = insertCore.rows[0].vehicle_id;
    }

    // 8.1-C10: Companions hold at most 1 record per vehicle (1-to-1)
    if (data.description) {
      await client.query(
        `INSERT INTO fs.vehicle_description (
           vehicle_id, body_style, transmission, engine, seats, doors, trunk_size,
           fuel_tank_size, range, image_url, description
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
         ON CONFLICT (vehicle_id) DO UPDATE SET
           body_style=EXCLUDED.body_style, transmission=EXCLUDED.transmission,
           engine=EXCLUDED.engine, seats=EXCLUDED.seats, doors=EXCLUDED.doors,
           trunk_size=EXCLUDED.trunk_size, fuel_tank_size=EXCLUDED.fuel_tank_size,
           range=EXCLUDED.range, image_url=EXCLUDED.image_url, description=EXCLUDED.description,
           updated_at=now()`,
        [
          vehicleId, data.description.body_style ?? null, data.description.transmission ?? null,
          data.description.engine ?? null, data.description.seats ?? null, data.description.doors ?? null,
          data.description.trunk_size ?? null, data.description.fuel_tank_size ?? null,
          data.description.range ?? null, data.description.image_url ?? null, data.description.description ?? null
        ]
      );
    }

    if (data.spec) {
      await client.query(
        `INSERT INTO fs.vehicle_spec (vehicle_id, engine_oil_brand, engine_oil_spec, gps_type, gps_device_id)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (vehicle_id) DO UPDATE SET
           engine_oil_brand=EXCLUDED.engine_oil_brand, engine_oil_spec=EXCLUDED.engine_oil_spec,
           gps_type=EXCLUDED.gps_type, gps_device_id=EXCLUDED.gps_device_id, updated_at=now()`,
        [vehicleId, data.spec.engine_oil_brand ?? null, data.spec.engine_oil_spec ?? null, data.spec.gps_type ?? null, data.spec.gps_device_id ?? null]
      );
    }

    if (data.performance) {
      await client.query(
        `INSERT INTO fs.vehicle_performance (vehicle_id, horsepower, top_speed, zero_to_sixty_time, rpm_redline)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (vehicle_id) DO UPDATE SET
           horsepower=EXCLUDED.horsepower, top_speed=EXCLUDED.top_speed,
           zero_to_sixty_time=EXCLUDED.zero_to_sixty_time, rpm_redline=EXCLUDED.rpm_redline, updated_at=now()`,
        [vehicleId, data.performance.horsepower ?? null, data.performance.top_speed ?? null, data.performance.zero_to_sixty_time ?? null, data.performance.rpm_redline ?? null]
      );
    }

    let tempPlateTaskRaised = false;
    if (data.registration_warranty) {
      await client.query(
        `INSERT INTO fs.vehicle_registration_warranty (
           vehicle_id, registration_state, temp_license_plate, license_plate, toll_tag,
           registration_expires_on, inspection_expires_on, warranty_end, warranty_company
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         ON CONFLICT (vehicle_id) DO UPDATE SET
           registration_state=EXCLUDED.registration_state, temp_license_plate=EXCLUDED.temp_license_plate,
           license_plate=EXCLUDED.license_plate, toll_tag=EXCLUDED.toll_tag,
           registration_expires_on=EXCLUDED.registration_expires_on,
           inspection_expires_on=EXCLUDED.inspection_expires_on, warranty_end=EXCLUDED.warranty_end,
           warranty_company=EXCLUDED.warranty_company, updated_at=now()`,
        [
          vehicleId, data.registration_warranty.registration_state ?? null,
          data.registration_warranty.temp_license_plate ?? null,
          data.registration_warranty.license_plate ?? null,
          data.registration_warranty.toll_tag ?? null,
          data.registration_warranty.registration_expires_on ?? null,
          data.registration_warranty.inspection_expires_on ?? null,
          data.registration_warranty.warranty_end ?? null,
          data.registration_warranty.warranty_company ?? null
        ]
      );

      // 8.1-C07: A temporary plate not replaced within thirty days raises a task
      if (data.registration_warranty.temp_license_plate && !data.registration_warranty.license_plate) {
        tempPlateTaskRaised = true;
      }
    }

    if (data.tires) {
      await client.query(
        `INSERT INTO fs.vehicle_tires (
           vehicle_id, front_tire_size, front_tire_psi, front_tire_brand, front_tire_model,
           rear_tire_size, rear_tire_psi, rear_tire_brand, rear_tire_model, spare_tire_size
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
         ON CONFLICT (vehicle_id) DO UPDATE SET
           front_tire_size=EXCLUDED.front_tire_size, front_tire_psi=EXCLUDED.front_tire_psi,
           front_tire_brand=EXCLUDED.front_tire_brand, front_tire_model=EXCLUDED.front_tire_model,
           rear_tire_size=EXCLUDED.rear_tire_size, rear_tire_psi=EXCLUDED.rear_tire_psi,
           rear_tire_brand=EXCLUDED.rear_tire_brand, rear_tire_model=EXCLUDED.rear_tire_model,
           spare_tire_size=EXCLUDED.spare_tire_size, updated_at=now()`,
        [
          vehicleId, data.tires.front_tire_size ?? null, data.tires.front_tire_psi ?? null,
          data.tires.front_tire_brand ?? null, data.tires.front_tire_model ?? null,
          data.tires.rear_tire_size ?? null, data.tires.rear_tire_psi ?? null,
          data.tires.rear_tire_brand ?? null, data.tires.rear_tire_model ?? null,
          data.tires.spare_tire_size ?? null
        ]
      );
    }

    if (data.accessories) {
      await client.query(
        `INSERT INTO fs.vehicle_accessories (
           vehicle_id, manuals, car_cover, charger, number_keys, accessories, features
         ) VALUES ($1,$2,$3,$4,$5,$6,$7)
         ON CONFLICT (vehicle_id) DO UPDATE SET
           manuals=EXCLUDED.manuals, car_cover=EXCLUDED.car_cover, charger=EXCLUDED.charger,
           number_keys=EXCLUDED.number_keys, accessories=EXCLUDED.accessories,
           features=EXCLUDED.features, updated_at=now()`,
        [
          vehicleId, data.accessories.manuals ?? null, data.accessories.car_cover ?? null,
          data.accessories.charger ?? null, data.accessories.number_keys ?? null,
          data.accessories.accessories ?? null, data.accessories.features ?? null
        ]
      );
    }

    // 8.1-C09: Completeness summary
    const summary = await getCompanionsSummary(client, vehicleId);

    // Audit log
    await recordVehicleShadow(client, vehicleId, isRepurchase ? 'Vehicle repurchased into fleet' : 'Initial vehicle record created');

    const vRow = await client.query(`SELECT * FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);

    return {
      vehicle: vRow.rows[0],
      is_repurchase: isRepurchase,
      temp_plate_task_pending: tempPlateTaskRaised,
      completeness: summary,
    };
  });

  res.status(201).json({ ok: true, ...result });
});

// =============================================================================
// GUIDE 8.2: Vehicle Tier Assignments & Rate Cards (8.2-C01 through 8.2-C10)
// =============================================================================

// GET /v1/fleet/tiers — List tiers in sort order (8.2-R03, 8.2-C01, 8.2-C02)
fleetRouter.get('/tiers', async (req, res) => {
  const forPlacement = req.query.for_placement === 'true' || req.query.for_placement === true;
  let sql = `SELECT vehicle_tier_id, vehicle_tier, vehicle_tier_name, sort_order, is_active, description
               FROM fs.vehicle_tier `;
  if (forPlacement) {
    // 8.2-C02: A retired tier does not appear for new placements
    sql += ` WHERE is_active = TRUE `;
  }
  // 8.2-C01: Tiers display in sort order everywhere
  sql += ` ORDER BY sort_order ASC, vehicle_tier ASC`;

  const result = await query(sql);
  res.json({ ok: true, count: result.rowCount, tiers: result.rows });
});

// GET /v1/fleet/tiers/report — Surface tiers with vehicle counts (8.2-C05)
fleetRouter.get('/tiers/report', async (req, res) => {
  const sql = `
    SELECT vt.vehicle_tier_id,
           vt.vehicle_tier,
           vt.vehicle_tier_name,
           vt.sort_order,
           vt.is_active,
           COUNT(DISTINCT rcp.vehicle_id) AS vehicle_count,
           CASE WHEN COUNT(DISTINCT rcp.vehicle_id) = 0 THEN TRUE ELSE FALSE END AS has_no_vehicles
      FROM fs.vehicle_tier vt
      LEFT JOIN fs.rate_card_placement rcp ON rcp.vehicle_tier_id = vt.vehicle_tier_id
     GROUP BY vt.vehicle_tier_id, vt.vehicle_tier, vt.vehicle_tier_name, vt.sort_order, vt.is_active
     ORDER BY vt.sort_order ASC
  `;
  const result = await query(sql);
  res.json({
    ok: true,
    tiers: result.rows,
    empty_tiers: result.rows.filter(r => r.has_no_vehicles),
  });
});

// POST /v1/fleet/tiers — Create tier with Rule 8.2-R05 validation
fleetRouter.post('/tiers', async (req, res) => {
  const schema = z.object({
    vehicle_tier: z.string().min(1).max(60),
    vehicle_tier_name: z.string().min(1).max(120),
    sort_order: z.number().int().min(1),
    description: z.string().optional(),
    rates: z.array(z.object({
      rate_card_id: z.string().uuid(),
      weekday_point_value: z.number().int().positive(),
      weekend_point_value: z.number().int().positive(),
    })).optional().default([]),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    // 8.2-R05: A new tier needs a rate on every card in use before a vehicle can be placed in it.
    const activeCards = await client.query(`SELECT rate_card_id, card_code FROM fs.rate_card`);
    const cardIdsWithRates = new Set(data.rates.map(r => r.rate_card_id));
    const missingCards = activeCards.rows.filter(c => !cardIdsWithRates.has(c.rate_card_id));

    if (missingCards.length > 0) {
      throw new HttpError(400, `8.2-R05: A new tier needs a rate on every card in use before a vehicle can be placed in it. Missing rate cards: ${missingCards.map(c => c.card_code).join(', ')}`);
    }

    const insTier = await client.query(
      `INSERT INTO fs.vehicle_tier (vehicle_tier, vehicle_tier_name, sort_order, is_active, description)
       VALUES ($1, $2, $3, TRUE, $4)
       RETURNING *`,
      [data.vehicle_tier, data.vehicle_tier_name, data.sort_order, data.description ?? null]
    );
    const tier = insTier.rows[0];

    for (const r of data.rates) {
      await client.query(
        `INSERT INTO fs.rate_card_rate (rate_card_id, vehicle_tier_id, weekday_point_value, weekend_point_value)
         VALUES ($1, $2, $3, $4)`,
        [r.rate_card_id, tier.vehicle_tier_id, r.weekday_point_value, r.weekend_point_value]
      );
    }

    return tier;
  });

  res.status(201).json({ ok: true, tier: result });
});

// PUT /v1/fleet/tiers/:tierId — Retire or update tier (8.2-R04, 8.2-C02, 8.2-C03)
fleetRouter.put('/tiers/:tierId', async (req, res) => {
  const { tierId } = req.params;
  const schema = z.object({
    vehicle_tier_name: z.string().max(120).optional(),
    is_active: z.boolean().optional(),
    sort_order: z.number().int().optional(),
    description: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const result = await query(
    `UPDATE fs.vehicle_tier
        SET vehicle_tier_name = COALESCE($1, vehicle_tier_name),
            is_active = COALESCE($2, is_active),
            sort_order = COALESCE($3, sort_order),
            description = COALESCE($4, description),
            updated_at = now()
      WHERE vehicle_tier_id = $5
      RETURNING *`,
    [data.vehicle_tier_name ?? null, data.is_active ?? null, data.sort_order ?? null, data.description ?? null, tierId]
  );
  if (result.rowCount === 0) throw new HttpError(404, 'Tier not found');
  res.json({ ok: true, tier: result.rows[0] });
});

// DELETE /v1/fleet/tiers/:tierId — Block deletion (8.2-R04, 8.2-C04)
fleetRouter.delete('/tiers/:tierId', async (req, res) => {
  // 8.2-R04 / 8.2-C04: Deleting a tier is not possible through any application path.
  throw new HttpError(400, '8.2-R04 / 8.2-C04: Deleting a tier is not possible through any application path. Tiers must be retired using is_active=false, never deleted.');
});

// POST /v1/fleet/resolve-tier — 3-input Tier Resolution (8.2-R06, 8.2-C07, 8.2-C08, 8.2-C09)
fleetRouter.post('/resolve-tier', async (req, res) => {
  const schema = z.object({
    vehicle_id: z.string().uuid(),
    card_id: z.string().uuid().optional(),
    card_code: z.string().optional(),
    member_id: z.string().uuid().optional(),
    date: z.string().optional(), // defaults to current date
  });
  const { vehicle_id, card_id, card_code, member_id, date: inputDate } = schema.parse(req.body);

  // 8.2-R06 / 8.2-C07: Resolving a tier requires a member or a card, and a date
  if (!card_id && !card_code && !member_id) {
    throw new HttpError(400, '8.2-R06 / 8.2-C07: Resolving a tier requires a member or a card, and a date.');
  }

  const effectiveDate = inputDate || new Date().toISOString().split('T')[0];

  // 1. Check for per-member tier override (8.2-C09)
  if (member_id) {
    const overrideRes = await query(
      `SELECT mta.vehicle_tier_id_override, vt.vehicle_tier, vt.vehicle_tier_name
         FROM fs.mpc_tier_assignment mta
         JOIN fs.vehicle_tier vt ON vt.vehicle_tier_id = mta.vehicle_tier_id_override
         JOIN fs.member_package_customization mpc ON mpc.member_package_customization_id = mta.member_package_customization_id
        WHERE mpc.member_id = $1 AND mta.vehicle_id = $2
        LIMIT 1`,
      [member_id, vehicle_id]
    );
    if (overrideRes.rowCount > 0) {
      const ov = overrideRes.rows[0];
      return res.json({
        ok: true,
        vehicle_id,
        tier: {
          vehicle_tier_id: ov.vehicle_tier_id_override,
          vehicle_tier: ov.vehicle_tier,
          vehicle_tier_name: ov.vehicle_tier_name,
        },
        is_override: true,
        effective_date: effectiveDate,
        message: '8.2-C09: Resolved via per-member tier override.',
      });
    }
  }

  // 2. Resolve Rate Card ID
  let targetCardId = card_id || null;
  if (!targetCardId && card_code) {
    const rc = await query(`SELECT rate_card_id FROM fs.rate_card WHERE card_code = $1`, [card_code]);
    if (rc.rowCount > 0) targetCardId = rc.rows[0].rate_card_id;
  }
  if (!targetCardId && member_id) {
    const subCard = await query(
      `SELECT COALESCE(ms.rate_card_id, rc.rate_card_id) AS rate_card_id
         FROM fs.member_subscriptions ms
         CROSS JOIN (SELECT rate_card_id FROM fs.rate_card WHERE card_code = 'RC_STANDARD_2026' LIMIT 1) rc
        WHERE ms.member_id = $1
        LIMIT 1`,
      [member_id]
    );
    if (subCard.rowCount > 0 && subCard.rows[0].rate_card_id) {
      targetCardId = subCard.rows[0].rate_card_id;
    } else {
      const defCard = await query(`SELECT rate_card_id FROM fs.rate_card WHERE card_code = 'RC_STANDARD_2026' LIMIT 1`);
      if (defCard.rowCount > 0) targetCardId = defCard.rows[0].rate_card_id;
    }
  }

  if (!targetCardId) {
    throw new HttpError(404, 'Rate card could not be resolved.');
  }

  // 3. Resolve Placement on Card for Vehicle effective on Date (8.2-C03, 8.2-C08)
  const placementRes = await query(
    `SELECT rcp.rate_card_placement_id,
            rcp.vehicle_tier_id,
            vt.vehicle_tier,
            vt.vehicle_tier_name,
            vt.is_active,
            rc.rate_card_id,
            rc.card_code,
            rc.card_name
       FROM fs.rate_card_placement rcp
       JOIN fs.vehicle_tier vt ON vt.vehicle_tier_id = rcp.vehicle_tier_id
       JOIN fs.rate_card rc ON rc.rate_card_id = rcp.rate_card_id
      WHERE rcp.vehicle_id = $1
        AND rcp.rate_card_id = $2
        AND (rcp.effective_from IS NULL OR rcp.effective_from <= $3::date)
        AND (rcp.effective_to IS NULL OR rcp.effective_to >= $3::date)
      ORDER BY rcp.effective_from DESC NULLS LAST
      LIMIT 1`,
    [vehicle_id, targetCardId, effectiveDate]
  );

  if (placementRes.rowCount === 0) {
    throw new HttpError(404, `No tier placement found for vehicle on rate card for date ${effectiveDate}.`);
  }

  const p = placementRes.rows[0];
  res.json({
    ok: true,
    vehicle_id,
    effective_date: effectiveDate,
    tier: {
      vehicle_tier_id: p.vehicle_tier_id,
      vehicle_tier: p.vehicle_tier,
      vehicle_tier_name: p.vehicle_tier_name,
      is_active: p.is_active,
    },
    source_card: {
      rate_card_id: p.rate_card_id,
      card_code: p.card_code,
      card_name: p.card_name,
    },
    is_override: false,
  });
});

// POST /v1/fleet/placements — Set rate card placement
fleetRouter.post('/placements', async (req, res) => {
  const schema = z.object({
    vehicle_id: z.string().uuid(),
    rate_card_id: z.string().uuid(),
    vehicle_tier_id: z.string().uuid(),
    effective_from: z.string().optional(),
    effective_to: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const result = await query(
    `INSERT INTO fs.rate_card_placement (vehicle_id, rate_card_id, vehicle_tier_id, effective_from, effective_to)
     VALUES ($1, $2, $3, COALESCE($4::date, CURRENT_DATE), $5::date)
     RETURNING *`,
    [data.vehicle_id, data.rate_card_id, data.vehicle_tier_id, data.effective_from ?? null, data.effective_to ?? null]
  );
  res.status(201).json({ ok: true, placement: result.rows[0] });
});

// =============================================================================
// GUIDE 8.3: Fleet Stages, Aging Tasks, & Retirement (8.3-C01 through 8.3-C16)
// =============================================================================

// POST /v1/fleet/evaluate-intake-aging — Aging Tasks at 10, 30, 60, 90 Days (8.3-R08, 8.3-C08-C11)
fleetRouter.post('/evaluate-intake-aging', async (req, res) => {
  const intakeVehicles = await query(
    `SELECT vehicle_id, vehicle_name, arrival_date,
            (CURRENT_DATE - arrival_date) AS days_in_intake
       FROM fs.vehicle
      WHERE fleet_stage = 'Intake' AND arrival_date IS NOT NULL`
  );

  const tasksCreated = [];

  for (const v of intakeVehicles.rows) {
    const days = parseInt(v.days_in_intake, 10);
    const thresholds = [
      { days: 10, code: 'INTAKE_AGING_10', title: `Vehicle 10 days in intake: ${v.vehicle_name}` },
      { days: 30, code: 'INTAKE_AGING_30', title: `Vehicle 30 days in intake: ${v.vehicle_name}` },
      { days: 60, code: 'INTAKE_AGING_60', title: `Vehicle 60 days in intake: ${v.vehicle_name}` },
      { days: 90, code: 'INTAKE_AGING_90', title: `Vehicle 90 days in intake: ${v.vehicle_name}` },
    ];

    for (const t of thresholds) {
      if (days >= t.days) {
        // 8.3-C09 / 8.3-C10: Independent tasks raised at each aging threshold
        const existingTask = await query(
          `SELECT task_id FROM fs.task
            WHERE task_type_code = $1 AND description LIKE '%' || $2 || '%'`,
          [t.code, v.vehicle_id]
        );
        if (existingTask.rowCount === 0) {
          const newTask = await query(
            `INSERT INTO fs.task (
               task_title, description, task_status_code, task_priority_code, task_type_code, due_date, is_active
             ) VALUES ($1, $2, 'PENDING', 'MEDIUM', $3, now() + interval '3 days', TRUE)
             RETURNING *`,
            [
              t.title,
              `Vehicle ${v.vehicle_name} (ID: ${v.vehicle_id}) has been in Intake stage for ${days} days (threshold: ${t.days} days).`,
              t.code,
            ]
          );
          tasksCreated.push(newTask.rows[0]);
        }
      }
    }
  }

  res.json({ ok: true, evaluated_count: intakeVehicles.rowCount, tasks_created: tasksCreated });
});

// =============================================================================
// GUIDE 8.4: Vehicle Condition & Turnaround (8.4-C01 through 8.4-C18)
// =============================================================================

// GET /v1/fleet/conditions — Canonical Conditions, Reasons, & Transition Rules (8.4-R01, 8.4-R06, 8.4-C11, 8.4-C18)
fleetRouter.get('/conditions', async (req, res) => {
  const [codes, reasons, rules] = await Promise.all([
    query(`SELECT condition_code, status_code, name, description, sort_order FROM fs.vehicle_condition_code WHERE is_active = TRUE ORDER BY sort_order ASC`),
    query(`SELECT condition_reason_code, status_reason_name, description, sort_order FROM fs.vehicle_condition_reason WHERE is_active = TRUE ORDER BY sort_order ASC`),
    query(`SELECT status_transition_id, from_condition_code, to_condition_code, requires_approval FROM fs.vehicle_condition_transition_rule WHERE is_active = TRUE`),
  ]);

  res.json({
    ok: true,
    conditions: codes.rows,
    reasons: reasons.rows,
    transition_rules: rules.rows,
  });
});

// =============================================================================
// GUIDE 8.5: Vehicle Commitment & Bookability (Static Endpoints & Helper)
// =============================================================================

// Helper for Guide 8.5 & 8.6: Evaluate bookability dynamically across requested window
export async function evaluateVehicleBookability(dbClient, vehicleId, startDateStr, endDateStr, options = {}) {
  const { memberId = null, isStaff = false, memberPodiumStatus = null } = options;

  // 1. Vehicle Existence and Stage
  const vRes = await dbClient.query(
    `SELECT vehicle_id, vehicle_name, home_branch_id, fleet_stage, condition_code,
            launch_date::text AS launch_date
       FROM fs.vehicle WHERE vehicle_id = $1`,
    [vehicleId]
  );
  if (vRes.rowCount === 0) {
    throw new HttpError(404, 'Vehicle not found');
  }
  const vehicle = vRes.rows[0];
  if (vehicle.fleet_stage === 'Retired') {
    return {
      is_bookable: false,
      code: 'RETIRED',
      error: 'Vehicle is retired from the fleet and cannot be booked',
    };
  }

  // 1b. Guide 8.6 Pre-Launch / Launch Date Check (8.6-R02, 8.6-R03, 8.6-C03, 8.6-C05, 8.6-C06)
  if (!vehicle.launch_date) {
    if (!isStaff) {
      return {
        is_bookable: false,
        code: 'NOT_LAUNCHED',
        error: 'Vehicle has not yet launched to members (launch date not set). Pre-launch bookings are reserved for staff only.',
      };
    }
  } else if (startDateStr < vehicle.launch_date) {
    if (!isStaff) {
      return {
        is_bookable: false,
        code: 'PRE_LAUNCH',
        error: `Vehicle is in pre-launch stage until ${vehicle.launch_date}. Pre-launch bookings are reserved for staff only.`,
      };
    }
  }

  // 2. Restricted Dates Check (8.5-R03, 8.5-C06, 8.5-C07, 8.5-C08)
  const rdRes = await dbClient.query(
    `SELECT rrd.reservation_restricted_date_id, rrd.restriction_name, rrd.start_date::text AS start_date,
            rrd.end_date::text AS end_date, rdts.restricted_date_type_code, rdts.blocks_outright
       FROM fs.reservation_restricted_dates rrd
       JOIN fs.restricted_date_type_select rdts ON rdts.restricted_date_type_code = rrd.restricted_date_type_code
      WHERE (rrd.branch_id = $1 OR rrd.branch_id IS NULL)
        AND rdts.blocks_outright = TRUE`,
    [vehicle.home_branch_id]
  );

  for (const rd of rdRes.rows) {
    // 8.5-C06: A reservation starting on a restricted date is refused.
    if (startDateStr >= rd.start_date && startDateStr <= rd.end_date) {
      return {
        is_bookable: false,
        code: 'RESTRICTED_START_DATE',
        error: `Reservation cannot start on restricted date (${rd.restriction_name})`,
        restricted_date: rd,
      };
    }
    // 8.5-C07: A reservation ending on a restricted date is refused.
    if (endDateStr >= rd.start_date && endDateStr <= rd.end_date) {
      return {
        is_bookable: false,
        code: 'RESTRICTED_END_DATE',
        error: `Reservation cannot end on restricted date (${rd.restriction_name})`,
        restricted_date: rd,
      };
    }
    // 8.5-C08: A reservation spanning a restricted date is permitted (no block).
  }

  // 3. Withholds Check (8.5-R05, 8.5-C13, 8.5-C14, 8.6-R02, 8.6-C03)
  // "Withhold means everybody. If you find yourself adding a staff bypass, you have confused it with exclusive."
  // Exception: Guide 8.6-R02 / 8.6-C03: A vehicle at Fleet with an AwaitingLaunch withhold is bookable by staff.
  // "A dated withhold releases on its end date." (ends_on >= CURRENT_DATE)
  const whRes = await dbClient.query(
    `SELECT rw.reservation_withhold_id, rw.withhold_reason_code, rw.starts_on::text AS starts_on,
            rw.ends_on::text AS ends_on, rw.withhold_note, rwrs.label AS reason_label
       FROM fs.reservation_withhold rw
       LEFT JOIN fs.reservation_withhold_reason_select rwrs ON rwrs.withhold_reason_code = rw.withhold_reason_code
      WHERE (rw.vehicle_id = $1 OR (rw.vehicle_id IS NULL AND rw.branch_id = $2))
        AND rw.released_at IS NULL
        AND (rw.ends_on IS NULL OR rw.ends_on >= CURRENT_DATE)
        AND rw.starts_on <= $4::date AND (rw.ends_on IS NULL OR rw.ends_on >= $3::date)`,
    [vehicleId, vehicle.home_branch_id, startDateStr, endDateStr]
  );
  if (whRes.rowCount > 0) {
    for (const wh of whRes.rows) {
      if (wh.withhold_reason_code === 'AwaitingLaunch') {
        if (isStaff) {
          // 8.6-C03: A vehicle at Fleet with that withhold open is bookable by staff.
          continue;
        }
        return {
          is_bookable: false,
          code: 'AWAITING_LAUNCH',
          error: `Vehicle is awaiting launch: ${wh.withhold_note || 'Awaiting Launch'}. Bookings refused for members.`,
          withhold: wh,
        };
      }
      return {
        is_bookable: false,
        code: 'WITHHOLD',
        error: `Vehicle is withheld from fleet: ${wh.reason_label || wh.withhold_reason_code} (${wh.withhold_note || 'Active withhold'}). Bookings refused for all users.`,
        withhold: wh,
      };
    }
  }

  // 4. Existing Commitments / Reservations Check (8.5-R02, 8.5-C02, 8.5-C03, 8.5-C04, 8.5-C05, 9.1-C01, 9.1-C02, 9.1-C03, 9.1-C04)
  // Window includes buffer_days_after_end across the one calendar
  const resRes = await dbClient.query(
    `SELECT vr.vehicle_reservation_id, vr.reservation_type_code, vr.reservation_status_code,
            vr.start_time_scheduled, vr.end_time_scheduled, vr.buffer_days_after_end,
            (vr.end_time_scheduled::date + (COALESCE(vr.buffer_days_after_end, 0) || ' days')::interval)::date::text AS effective_end_date
       FROM fs.vehicle_reservation vr
      WHERE vr.vehicle_id = $1
        AND vr.reservation_status_code IN ('Confirmed', 'Held', 'Tentative')
        AND vr.start_time_scheduled::date <= $3::date
        AND (vr.end_time_scheduled::date + (COALESCE(vr.buffer_days_after_end, 0) || ' days')::interval)::date >= $2::date
     UNION ALL
     SELECT r.id AS vehicle_reservation_id, 'Member' AS reservation_type_code, 'Confirmed' AS reservation_status_code,
            r.pickup_at AS start_time_scheduled, r.return_at AS end_time_scheduled, 0 AS buffer_days_after_end,
            r.return_at::date::text AS effective_end_date
       FROM fs.reservations r
      WHERE r.vehicle_id = $1
        AND r.status IN ('requested', 'confirmed', 'picked_up')
        AND r.pickup_at::date <= $3::date
        AND r.return_at::date >= $2::date`,
    [vehicleId, startDateStr, endDateStr]
  );
  if (resRes.rowCount > 0) {
    const conflict = resRes.rows[0];
    return {
      is_bookable: false,
      code: 'CONFLICTING_COMMITMENT',
      error: `Vehicle has conflicting ${conflict.reservation_type_code} reservation (${conflict.reservation_status_code}) through ${conflict.effective_end_date}`,
      conflict,
    };
  }

  // 5. Exclusive Release Stages Check (8.5-R06, 8.5-C15, 8.5-C16, 8.6-R04-R06, 8.6-C06-C09)
  const relRes = await dbClient.query(
    `SELECT vehicle_release_row_id, sort_order, duration_days, minimum_podium_status_code, hide_from_lower_tiers
       FROM fs.vehicle_release_row
      WHERE vehicle_id = $1
      ORDER BY sort_order ASC`,
    [vehicleId]
  );
  if (relRes.rowCount > 0 && vehicle.launch_date) {
    const launchDate = new Date(vehicle.launch_date);
    const bookingStart = new Date(startDateStr);

    let stageStart = new Date(launchDate);
    let activeStage = null;

    for (const row of relRes.rows) {
      const dur = Number(row.duration_days) || 0;
      const stageEnd = new Date(stageStart.getTime() + dur * 86400000);
      if (bookingStart >= stageStart && bookingStart < stageEnd) {
        activeStage = row;
        break;
      }
      stageStart = stageEnd;
    }

    if (activeStage && activeStage.minimum_podium_status_code) {
      const podiumRank = { NONE: 0, MEMBER: 0, BRONZE: 0, SILVER: 1, GOLD: 2, PLATINUM: 3, BLACK: 4, VIP: 4 };
      const memberRank = podiumRank[String(memberPodiumStatus || '').toUpperCase()] || 0;
      const minRank = podiumRank[String(activeStage.minimum_podium_status_code).toUpperCase()] || 99;

      if (memberRank < minRank) {
        if (!isStaff) {
          // 8.5-C15 / 8.6-C07: A member below the current stage minimum cannot book for themselves.
          return {
            is_bookable: false,
            code: 'EXCLUSIVE_STAGE_BLOCKED',
            error: `Vehicle is in exclusive release stage requiring minimum status ${activeStage.minimum_podium_status_code}. Lower tiers cannot self-book.`,
            minimum_status: activeStage.minimum_podium_status_code,
            active_stage: activeStage,
          };
        }
        // 8.5-C16 / 8.6-C08: A staff member can book that vehicle for that member.
      }
    }
    // 8.6-C09: When the last row expires, every member can book.
  }
  // 8.6-C06: With no rows, every member can book from the launch date.

  // 6. Active Watch Check (8.5-R04, 8.5-C09)
  // "A watch never refuses a booking; it creates it and holds it."
  const watchRes = await dbClient.query(
    `SELECT rw.reservation_watch_id, rw.watch_reason_code, rw.starts_on::text AS starts_on,
            rw.ends_on::text AS ends_on, rw.watch_note, rwrs.label AS reason_label
       FROM fs.reservation_watch rw
       LEFT JOIN fs.reservation_withhold_reason_select rwrs ON rwrs.withhold_reason_code = rw.watch_reason_code
      WHERE (rw.vehicle_id = $1 OR rw.branch_id = $2)
        AND rw.cleared_at IS NULL
        AND rw.escalated_to_withhold_id IS NULL
        AND rw.starts_on <= $4::date AND (rw.ends_on IS NULL OR rw.ends_on >= $3::date)`,
    [vehicleId, vehicle.home_branch_id, startDateStr, endDateStr]
  );

  if (watchRes.rowCount > 0) {
    return {
      is_bookable: true,
      has_watch: true,
      resulting_status: 'Held',
      watch: watchRes.rows[0],
    };
  }

  return {
    is_bookable: true,
    has_watch: false,
    resulting_status: 'Confirmed',
  };
}

// GET /v1/fleet/restricted-dates (8.5-C06, 8.5-C07, 8.5-C08)
fleetRouter.get('/restricted-dates', async (req, res) => {
  const result = await query(
    `SELECT rrd.reservation_restricted_date_id, rrd.branch_id, rrd.restricted_date_type_code,
            rrd.restriction_name, rrd.description, rrd.start_date::text AS start_date,
            rrd.end_date::text AS end_date, rdts.type_name, rdts.blocks_outright,
            b.branch_name AS branch_name
       FROM fs.reservation_restricted_dates rrd
       JOIN fs.restricted_date_type_select rdts ON rdts.restricted_date_type_code = rrd.restricted_date_type_code
       LEFT JOIN fs.branch b ON b.branch_id = rrd.branch_id
      ORDER BY rrd.start_date ASC`
  );
  res.json({ ok: true, count: result.rowCount, restricted_dates: result.rows });
});

// POST /v1/fleet/restricted-dates
fleetRouter.post('/restricted-dates', async (req, res) => {
  const schema = z.object({
    branch_id: z.string().uuid().optional(),
    restricted_date_type_code: z.string().default('HOLIDAY'),
    restriction_name: z.string().min(2),
    start_date: z.string(),
    end_date: z.string(),
    description: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const result = await query(
    `INSERT INTO fs.reservation_restricted_dates (
       branch_id, restricted_date_type_code, restriction_name, description, start_date, end_date
     ) VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING *`,
    [
      data.branch_id || null,
      data.restricted_date_type_code,
      data.restriction_name,
      data.description || null,
      data.start_date,
      data.end_date,
    ]
  );
  res.status(201).json({ ok: true, restricted_date: result.rows[0] });
});

// DELETE /v1/fleet/restricted-dates/:id
fleetRouter.delete('/restricted-dates/:id', async (req, res) => {
  const { id } = req.params;
  const result = await query(
    `DELETE FROM fs.reservation_restricted_dates WHERE reservation_restricted_date_id = $1 RETURNING *`,
    [id]
  );
  if (result.rowCount === 0) throw new HttpError(404, 'Restricted date not found');
  res.json({ ok: true, deleted: result.rows[0] });
});

// GET /v1/fleet/watches (8.5-C09, 8.5-C10, 8.5-C11, 8.5-C12)
fleetRouter.get('/watches', async (req, res) => {
  const result = await query(
    `SELECT rw.reservation_watch_id, rw.branch_id, rw.vehicle_id, rw.watch_reason_code,
            rw.starts_on::text AS starts_on, rw.ends_on::text AS ends_on, rw.watch_note,
            rw.escalated_to_withhold_id, rw.cleared_at, rw.created_at,
            rwrs.label AS reason_label, v.vehicle_name, b.branch_name AS branch_name
       FROM fs.reservation_watch rw
       LEFT JOIN fs.reservation_withhold_reason_select rwrs ON rwrs.withhold_reason_code = rw.watch_reason_code
       LEFT JOIN fs.vehicle v ON v.vehicle_id = rw.vehicle_id
       LEFT JOIN fs.branch b ON b.branch_id = rw.branch_id
      ORDER BY rw.created_at DESC`
  );
  res.json({ ok: true, count: result.rowCount, watches: result.rows });
});

// POST /v1/fleet/watches — Place Watch & Hold Existing Bookings (8.5-R04, 8.5-C09, 8.5-C10)
fleetRouter.post('/watches', async (req, res) => {
  const schema = z.object({
    branch_id: z.string().uuid().optional(),
    vehicle_id: z.string().uuid().optional(),
    watch_reason_code: z.string().default('Weather'),
    starts_on: z.string(),
    ends_on: z.string(),
    watch_note: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    // 1. Create the watch
    const watchRes = await client.query(
      `INSERT INTO fs.reservation_watch (
         branch_id, vehicle_id, watch_reason_code, starts_on, ends_on, watch_note
       ) VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [
        data.branch_id || null,
        data.vehicle_id || null,
        data.watch_reason_code,
        data.starts_on,
        data.ends_on,
        data.watch_note || null,
      ]
    );
    const watch = watchRes.rows[0];

    // 2. 8.5-C10: Existing bookings in a watch window are held.
    const holdRes = await client.query(
      `UPDATE fs.vehicle_reservation
          SET reservation_status_code = 'Held',
              updated_at = now()
        WHERE ($1::uuid IS NULL OR vehicle_id = $1::uuid)
          AND ($2::uuid IS NULL OR reserving_branch_id = $2::uuid)
          AND reservation_status_code IN ('Confirmed', 'Tentative')
          AND start_time_scheduled::date <= $4::date
          AND end_time_scheduled::date >= $3::date
        RETURNING vehicle_reservation_id, reservation_type_code, reservation_status_code`,
      [data.vehicle_id || null, data.branch_id || null, data.starts_on, data.ends_on]
    );

    // Audit status history for each held reservation
    for (const h of holdRes.rows) {
      await client.query(
        `INSERT INTO fs.reservation_status_history (
           reservation_id, status, status_reason_code, status_note, created_at
         ) VALUES ($1, 'Held', 'WeatherHold', $2, now())`,
        [h.vehicle_reservation_id, `Watch placed (${data.watch_reason_code}): ${data.watch_note || 'Held due to watch'}`]
      );
    }

    return {
      watch,
      held_reservations: holdRes.rows,
      held_count: holdRes.rowCount,
    };
  });

  res.status(201).json({ ok: true, message: `Watch created. ${result.held_count} reservations placed on hold.`, ...result });
});

// POST /v1/fleet/watches/:watchId/clear — Clear Watch & Release Holds (8.5-C11)
fleetRouter.post('/watches/:watchId/clear', async (req, res) => {
  const { watchId } = req.params;

  const result = await withTransaction(async (client) => {
    const watchRes = await client.query(
      `UPDATE fs.reservation_watch
          SET cleared_at = now(), updated_at = now()
        WHERE reservation_watch_id = $1 AND cleared_at IS NULL
        RETURNING *`,
      [watchId]
    );
    if (watchRes.rowCount === 0) throw new HttpError(404, 'Active watch not found or already cleared');
    const watch = watchRes.rows[0];

    // 8.5-C11: Clearing a watch releases the holds
    const releaseRes = await client.query(
      `UPDATE fs.vehicle_reservation
          SET reservation_status_code = 'Confirmed',
              updated_at = now()
        WHERE ($1::uuid IS NULL OR vehicle_id = $1::uuid)
          AND ($2::uuid IS NULL OR reserving_branch_id = $2::uuid)
          AND reservation_status_code = 'Held'
          AND start_time_scheduled::date <= $4::date
          AND end_time_scheduled::date >= $3::date
        RETURNING vehicle_reservation_id`,
      [watch.vehicle_id, watch.branch_id, watch.starts_on, watch.ends_on]
    );

    for (const r of releaseRes.rows) {
      await client.query(
        `INSERT INTO fs.reservation_status_history (
           reservation_id, status, status_reason_code, status_note, created_at
         ) VALUES ($1, 'Confirmed', NULL, 'Watch cleared: holds released to Confirmed', now())`,
        [r.vehicle_reservation_id]
      );
    }

    return {
      watch,
      released_reservations: releaseRes.rows,
      released_count: releaseRes.rowCount,
    };
  });

  res.json({ ok: true, message: `Watch cleared. ${result.released_count} holds released to Confirmed.`, ...result });
});

// POST /v1/fleet/watches/:watchId/escalate — Escalate Watch to Withhold (8.5-R07, 8.5-R08, 8.5-C12)
fleetRouter.post('/watches/:watchId/escalate', async (req, res) => {
  const { watchId } = req.params;
  const schema = z.object({
    withhold_note: z.string().optional(),
  });
  const { withhold_note } = schema.parse(req.body || {});

  const result = await withTransaction(async (client) => {
    const watchRes = await client.query(
      `SELECT * FROM fs.reservation_watch WHERE reservation_watch_id = $1`,
      [watchId]
    );
    if (watchRes.rowCount === 0) throw new HttpError(404, 'Watch not found');
    const watch = watchRes.rows[0];

    // 1. Create corresponding withhold
    const whRes = await client.query(
      `INSERT INTO fs.reservation_withhold (
         branch_id, vehicle_id, withhold_reason_code, starts_on, ends_on, withhold_note, placed_at
       ) VALUES ($1, $2, $3, $4, $5, $6, now())
       RETURNING *`,
      [
        watch.branch_id,
        watch.vehicle_id,
        watch.watch_reason_code,
        watch.starts_on,
        watch.ends_on,
        withhold_note || `Escalated from watch: ${watch.watch_note || ''}`,
      ]
    );
    const withhold = whRes.rows[0];

    // 2. 8.5-R07: A watch that hardens into a withhold records the link between them.
    await client.query(
      `UPDATE fs.reservation_watch
          SET escalated_to_withhold_id = $2, updated_at = now()
        WHERE reservation_watch_id = $1`,
      [watchId, withhold.reservation_withhold_id]
    );

    // 3. 8.5-R08 / 8.5-C12: Cancellations arising from a withhold are club cancellations:
    // points returned, no allowance charged.
    const cancelRes = await client.query(
      `UPDATE fs.vehicle_reservation
          SET reservation_status_code = 'Cancelled',
              updated_at = now()
        WHERE ($1::uuid IS NULL OR vehicle_id = $1::uuid)
          AND ($2::uuid IS NULL OR reserving_branch_id = $2::uuid)
          AND reservation_status_code = 'Held'
          AND start_time_scheduled::date <= $4::date
          AND end_time_scheduled::date >= $3::date
        RETURNING vehicle_reservation_id`,
      [watch.vehicle_id, watch.branch_id, watch.starts_on, watch.ends_on]
    );

    for (const c of cancelRes.rows) {
      await client.query(
        `INSERT INTO fs.reservation_status_history (
           reservation_id, status, status_reason_code, status_note, created_at
         ) VALUES ($1, 'Cancelled', 'WatchEscalated', 'Club cancellation due to watch escalation. Points returned, no cancellation allowance charged.', now())`,
        [c.vehicle_reservation_id]
      );
    }

    return {
      watch_id: watchId,
      withhold,
      cancelled_reservations: cancelRes.rows,
      cancelled_count: cancelRes.rowCount,
    };
  });

  res.json({ ok: true, message: `Watch escalated to withhold. ${result.cancelled_count} reservations cancelled as club cancellations.`, ...result });
});

// GET /v1/fleet/withholds (8.5-R05, 8.5-C13, 8.5-C14)
fleetRouter.get('/withholds', async (req, res) => {
  const result = await query(
    `SELECT rw.reservation_withhold_id, rw.branch_id, rw.vehicle_id, rw.withhold_reason_code,
            rw.starts_on::text AS starts_on, rw.ends_on::text AS ends_on, rw.withhold_note,
            rw.placed_at, rw.released_at, rw.release_note,
            rwrs.label AS reason_label, v.vehicle_name, b.branch_name AS branch_name
       FROM fs.reservation_withhold rw
       LEFT JOIN fs.reservation_withhold_reason_select rwrs ON rwrs.withhold_reason_code = rw.withhold_reason_code
       LEFT JOIN fs.vehicle v ON v.vehicle_id = rw.vehicle_id
       LEFT JOIN fs.branch b ON b.branch_id = rw.branch_id
      ORDER BY rw.created_at DESC`
  );
  res.json({ ok: true, count: result.rowCount, withholds: result.rows });
});

// POST /v1/fleet/withholds
fleetRouter.post('/withholds', async (req, res) => {
  const schema = z.object({
    branch_id: z.string().uuid().optional(),
    vehicle_id: z.string().uuid().optional(),
    withhold_reason_code: z.string().default('SalePending'),
    starts_on: z.string(),
    ends_on: z.string().optional(),
    withhold_note: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const result = await query(
    `INSERT INTO fs.reservation_withhold (
       branch_id, vehicle_id, withhold_reason_code, starts_on, ends_on, withhold_note, placed_at
     ) VALUES ($1, $2, $3, $4, $5, $6, now())
     RETURNING *`,
    [
      data.branch_id || null,
      data.vehicle_id || null,
      data.withhold_reason_code,
      data.starts_on,
      data.ends_on || null,
      data.withhold_note || null,
    ]
  );

  res.status(201).json({ ok: true, withhold: result.rows[0] });
});

// POST /v1/fleet/withholds/:withholdId/release
fleetRouter.post('/withholds/:withholdId/release', async (req, res) => {
  const { withholdId } = req.params;
  const schema = z.object({
    release_note: z.string().optional(),
  });
  const { release_note } = schema.parse(req.body || {});

  const result = await query(
    `UPDATE fs.reservation_withhold
        SET released_at = now(),
            release_note = $2,
            updated_at = now()
      WHERE reservation_withhold_id = $1 AND released_at IS NULL
      RETURNING *`,
    [withholdId, release_note || 'Withhold released']
  );
  if (result.rowCount === 0) throw new HttpError(404, 'Active withhold not found or already released');

  res.json({ ok: true, message: 'Withhold released', withhold: result.rows[0] });
});

// GET /v1/fleet/:vehicleId/companions — Guide 8.1 (8.1-C09, 8.1-C10)
fleetRouter.get('/:vehicleId/companions', async (req, res) => {
  const { vehicleId } = req.params;
  const vRes = await query(`SELECT vehicle_id, vin, vehicle_name FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
  if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');

  const summary = await getCompanionsSummary({ query }, vehicleId);
  res.json({
    ok: true,
    vehicle_id: vehicleId,
    vehicle_name: vRes.rows[0].vehicle_name,
    vin: vRes.rows[0].vin,
    ...summary,
  });
});

// PUT /v1/fleet/:vehicleId — Update vehicle & Enforce Immutable VIN (8.1-C05, 8.1-C11)
fleetRouter.put('/:vehicleId', async (req, res) => {
  const { vehicleId } = req.params;
  const data = updateVehicleSchema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const existingRes = await client.query(`SELECT * FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
    if (existingRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
    const existing = existingRes.rows[0];

    // 8.1-R01 / 8.1-C05: An edit to a saved VIN is refused
    if (data.vin && data.vin !== existing.vin) {
      throw new HttpError(400, '8.1-C05: An edit to a saved VIN is refused. The VIN is unique and never changes.');
    }

    let extColorCode = null;
    if (data.exterior_color) {
      const cRes = await client.query(
        `SELECT vehicle_color_code FROM fs.vehicle_color_select
          WHERE UPPER(vehicle_color_code) = UPPER($1) OR UPPER(vehicle_color_name) = UPPER($1)`,
        [data.exterior_color]
      );
      if (cRes.rowCount > 0) extColorCode = cRes.rows[0].vehicle_color_code;
      else extColorCode = 'OTHER';
    }

    let intColorCode = null;
    if (data.interior_color) {
      const cRes = await client.query(
        `SELECT vehicle_color_code FROM fs.vehicle_color_select
          WHERE UPPER(vehicle_color_code) = UPPER($1) OR UPPER(vehicle_color_name) = UPPER($1)
             OR UPPER($1) LIKE '%' || UPPER(vehicle_color_name) || '%'`,
        [data.interior_color]
      );
      if (cRes.rowCount > 0) intColorCode = cRes.rows[0].vehicle_color_code;
      else intColorCode = 'OTHER';
    }

    const updateRes = await client.query(
      `UPDATE fs.vehicle
          SET vehicle_name = COALESCE($1, vehicle_name),
              model = COALESCE($2, model),
              trim = COALESCE($3, trim),
              exterior_color = COALESCE($4, exterior_color),
              interior_color = COALESCE($5, interior_color),
              launch_date = COALESCE($6, launch_date),
              fleet_stage = COALESCE($7, fleet_stage),
              condition_code = COALESCE($8, condition_code),
              notes = COALESCE($9, notes),
              updated_at = now()
        WHERE vehicle_id = $10
        RETURNING *`,
      [
        data.vehicle_name ?? null,
        data.model ?? null,
        data.trim ?? null,
        extColorCode,
        intColorCode,
        data.launch_date ?? null,
        data.fleet_stage ?? null,
        data.condition_code ?? null,
        data.notes ?? null,
        vehicleId,
      ]
    );

    // 8.1-C11: Every change to a vehicle record writes a shadow row
    await recordVehicleShadow(client, vehicleId, 'Vehicle record updated');

    return updateRes.rows[0];
  });

  res.json({ ok: true, vehicle: result });
});

// GET /v1/fleet/:vehicleId/staff-tier — Default Card Tier for Staff Display (8.2-C10)
fleetRouter.get('/:vehicleId/staff-tier', async (req, res) => {
  const { vehicleId } = req.params;
  const defCardRes = await query(
    `SELECT rate_card_id, card_code, card_name FROM fs.rate_card WHERE card_code = 'RC_STANDARD_2026' LIMIT 1`
  );
  if (defCardRes.rowCount === 0) throw new HttpError(500, 'Standard rate card not configured');
  const defCard = defCardRes.rows[0];

  const placementRes = await query(
    `SELECT rcp.rate_card_placement_id,
            rcp.vehicle_tier_id,
            vt.vehicle_tier,
            vt.vehicle_tier_name,
            vt.sort_order
       FROM fs.rate_card_placement rcp
       JOIN fs.vehicle_tier vt ON vt.vehicle_tier_id = rcp.vehicle_tier_id
      WHERE rcp.vehicle_id = $1 AND rcp.rate_card_id = $2
      ORDER BY rcp.effective_from DESC NULLS LAST
      LIMIT 1`,
    [vehicleId, defCard.rate_card_id]
  );

  if (placementRes.rowCount === 0) {
    throw new HttpError(404, 'Vehicle has no placement on standard rate card.');
  }

  const p = placementRes.rows[0];
  // 8.2-C10: A staff screen showing a single tier names the card it came from
  res.json({
    ok: true,
    vehicle_id: vehicleId,
    tier: {
      vehicle_tier_id: p.vehicle_tier_id,
      vehicle_tier: p.vehicle_tier,
      vehicle_tier_name: p.vehicle_tier_name,
      sort_order: p.sort_order,
    },
    source_card: {
      rate_card_id: defCard.rate_card_id,
      card_code: defCard.card_code,
      card_name: defCard.card_name,
    },
    display_label: `${p.vehicle_tier_name} (on ${defCard.card_name})`,
  });
});

// =============================================================================
// GUIDE 8.6: Vehicle Visibility & Launch (Templates & Launch Form)
// =============================================================================

// GET /v1/fleet/release-templates (8.6-C14, 8.6-C15)
fleetRouter.get('/release-templates', async (req, res) => {
  const tRes = await query(
    `SELECT vrt.vehicle_release_template_id, vrt.template_name, vrt.description,
            vrt.is_default, vrt.is_active, vrt.sort_order,
            COALESCE(
              json_agg(
                json_build_object(
                  'vehicle_release_template_row_id', vrtr.vehicle_release_template_row_id,
                  'sort_order', vrtr.sort_order,
                  'duration_days', vrtr.duration_days,
                  'minimum_podium_status_code', vrtr.minimum_podium_status_code,
                  'hide_from_lower_tiers', vrtr.hide_from_lower_tiers
                ) ORDER BY vrtr.sort_order ASC
              ) FILTER (WHERE vrtr.vehicle_release_template_row_id IS NOT NULL),
              '[]'::json
            ) AS rows
       FROM fs.vehicle_release_template vrt
       LEFT JOIN fs.vehicle_release_template_row vrtr ON vrtr.vehicle_release_template_id = vrt.vehicle_release_template_id
      WHERE vrt.is_active = TRUE
      GROUP BY vrt.vehicle_release_template_id
      ORDER BY vrt.sort_order ASC, vrt.template_name ASC`
  );
  res.json({ ok: true, count: tRes.rowCount, templates: tRes.rows });
});

// POST /v1/fleet/release-templates
fleetRouter.post('/release-templates', async (req, res) => {
  const schema = z.object({
    template_name: z.string().min(2),
    description: z.string().optional(),
    is_default: z.boolean().default(false),
    rows: z.array(z.object({
      sort_order: z.number().int().default(1),
      duration_days: z.number().int().default(14),
      minimum_podium_status_code: z.string(),
      hide_from_lower_tiers: z.boolean().default(false),
    })).default([]),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const tRes = await client.query(
      `INSERT INTO fs.vehicle_release_template (template_name, description, is_default, is_active)
       VALUES ($1, $2, $3, TRUE)
       RETURNING *`,
      [data.template_name, data.description || null, data.is_default]
    );
    const template = tRes.rows[0];

    const insertedRows = [];
    for (const r of data.rows) {
      const rRes = await client.query(
        `INSERT INTO fs.vehicle_release_template_row (
           vehicle_release_template_id, sort_order, duration_days, minimum_podium_status_code, hide_from_lower_tiers
         ) VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [template.vehicle_release_template_id, r.sort_order, r.duration_days, r.minimum_podium_status_code, r.hide_from_lower_tiers]
      );
      insertedRows.push(rRes.rows[0]);
    }

    return { ...template, rows: insertedRows };
  });

  res.status(201).json({ ok: true, template: result });
});

// PUT /v1/fleet/release-templates/:templateId (8.6-C15: Editing template does not touch launched vehicle rows)
fleetRouter.put('/release-templates/:templateId', async (req, res) => {
  const { templateId } = req.params;
  const schema = z.object({
    template_name: z.string().min(2).optional(),
    description: z.string().optional(),
    rows: z.array(z.object({
      sort_order: z.number().int().default(1),
      duration_days: z.number().int().default(14),
      minimum_podium_status_code: z.string(),
      hide_from_lower_tiers: z.boolean().default(false),
    })).optional(),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const updateRes = await client.query(
      `UPDATE fs.vehicle_release_template
          SET template_name = COALESCE($1, template_name),
              description = COALESCE($2, description),
              updated_at = now()
        WHERE vehicle_release_template_id = $3
        RETURNING *`,
      [data.template_name, data.description, templateId]
    );
    if (updateRes.rowCount === 0) throw new HttpError(404, 'Template not found');

    if (data.rows) {
      await client.query(`DELETE FROM fs.vehicle_release_template_row WHERE vehicle_release_template_id = $1`, [templateId]);
      for (const r of data.rows) {
        await client.query(
          `INSERT INTO fs.vehicle_release_template_row (
             vehicle_release_template_id, sort_order, duration_days, minimum_podium_status_code, hide_from_lower_tiers
           ) VALUES ($1, $2, $3, $4, $5)`,
          [templateId, r.sort_order, r.duration_days, r.minimum_podium_status_code, r.hide_from_lower_tiers]
        );
      }
    }
    return updateRes.rows[0];
  });

  res.json({ ok: true, template: result, message: 'Template updated successfully' });
});

// =============================================================================
// GUIDE 8.8: Vehicle Lifecycle and Financing Helpers & Fleet-Wide Surfaced
// =============================================================================

function checkFinancingAccess(req) {
  const role = req.headers['x-user-role'] || req.user?.role || req.query.role;
  const isMember = role === 'member' || req.query.as_member === 'true';
  if (isMember) {
    // 8.8-C17: A member cannot reach the financing record by any path.
    throw new HttpError(403, '8.8-C17: A member cannot reach the financing record by any path.');
  }

  // 8.8-C16: A user without the financial permission cannot see purchase or sale figures.
  const perms = req.headers['x-user-permissions'] || '';
  const asStaffNoFinance = req.query.as_staff_no_finance === 'true' || req.headers['x-user-no-finance'] === 'true';

  let hasFinancePerm = !asStaffNoFinance;
  if (asStaffNoFinance) {
    hasFinancePerm = false;
  } else if (perms) {
    hasFinancePerm = perms.includes('view_financials') || perms.includes('manage_financials');
  } else if (role) {
    hasFinancePerm = (role === 'admin' || role === 'finance' || role === 'manager');
  }

  return { hasFinancePerm };
}

function redactFinancialFields(fin, hasFinancePerm) {
  if (hasFinancePerm || !fin) return fin;
  return {
    ...fin,
    purchase_price: null,
    sale_price: null,
    end_target_value: null,
    valuation_variance: null,
    valuation_variance_pct: null,
    financial_data_masked: true,
  };
}

async function recordFinancingShadow(client, finRow, changeReason, changedByUserId = null) {
  await client.query(
    `INSERT INTO fs.vehicle_financing_lifecycle_shadow (
       vehicle_financing_lifecycle_id, vehicle_id, finance_type, finance_term_months,
       lender_lessor, guarantor, purchase_date, purchase_price,
       end_target_date, end_target_mileage, end_target_value,
       sale_date, sale_price, end_date_is_committed, end_commitment_note,
       disposal_type, valid_from, valid_to, changed_by_user_id, changed_at, change_reason
     ) VALUES (
       $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16,
       $17, now(), $18, now(), $19
     )`,
    [
      finRow.vehicle_financing_lifecycle_id,
      finRow.vehicle_id,
      finRow.finance_type,
      finRow.finance_term_months,
      finRow.lender_lessor,
      finRow.guarantor,
      finRow.purchase_date,
      finRow.purchase_price,
      finRow.end_target_date,
      finRow.end_target_mileage,
      finRow.end_target_value,
      finRow.sale_date,
      finRow.sale_price,
      finRow.end_date_is_committed,
      finRow.end_commitment_note,
      finRow.disposal_type || null,
      finRow.updated_at || finRow.created_at || new Date(),
      changedByUserId,
      changeReason || 'Target revision',
    ]
  );
}

function computeSurfacingAndWatching(fin, currentOdometer = 0) {
  const odo = Number(currentOdometer || 0);
  const now = new Date();
  const todayStr = now.toISOString().split('T')[0];

  const targetDateStr = fin.end_target_date
    ? (typeof fin.end_target_date === 'string' ? fin.end_target_date.substring(0, 10) : new Date(fin.end_target_date).toISOString().substring(0, 10))
    : null;
  const targetDate = targetDateStr ? new Date(targetDateStr) : null;

  let daysRemaining = null;
  if (targetDate) {
    const diffMs = targetDate.getTime() - new Date(todayStr).getTime();
    daysRemaining = Math.round(diffMs / (1000 * 60 * 60 * 24));
  }

  const targetMileage = fin.end_target_mileage != null ? Number(fin.end_target_mileage) : null;
  const milesRemaining = targetMileage != null ? targetMileage - odo : null;

  const isDisposed = fin.sale_date != null || fin.disposal_type != null || fin.fleet_stage === 'Retired';

  // 8.8-C05: A vehicle approaching its target mileage is surfaced (within 1000 miles or >= 90% of target)
  const approachingMileage = !isDisposed && targetMileage != null && (
    (milesRemaining != null && milesRemaining <= 1000 && milesRemaining >= 0) ||
    (targetMileage > 0 && odo >= targetMileage * 0.90 && milesRemaining >= 0)
  );

  const pastTargetMileage = !isDisposed && targetMileage != null && milesRemaining != null && milesRemaining < 0;

  // 8.8-C07: A committed end date is surfaced earlier (120 days) and more insistently
  // 8.8-C06: A vehicle approaching target date (60 days)
  const isCommitted = Boolean(fin.end_date_is_committed);
  const dateThreshold = isCommitted ? 120 : 60;
  const approachingDate = !isDisposed && daysRemaining != null && daysRemaining <= dateThreshold && daysRemaining >= 0;
  const pastTargetDate = !isDisposed && daysRemaining != null && daysRemaining < 0;

  const pastTargets = pastTargetDate || pastTargetMileage;

  // 8.8-C09: A vehicle past its targets is listed rather than escalated
  let status = 'active';
  let handling = 'standard';
  if (isDisposed) {
    status = 'disposed';
  } else if (pastTargets) {
    status = 'past_target';
    handling = 'listed_rather_than_escalated';
  } else if (approachingMileage || approachingDate) {
    status = 'surfaced';
  }

  // 8.8-C10: A lease nearing term surfaces a return or purchase decision
  let decisionRequired = null;
  let actionOptions = [];
  if (fin.finance_type === 'Lease' && !isDisposed && (approachingDate || pastTargetDate || approachingMileage)) {
    decisionRequired = 'return_or_purchase';
    actionOptions = ['Return', 'Purchase'];
  }

  // 8.8-C15: Valuation variance (difference between target value and sale price is reportable)
  let valuationVariance = null;
  let valuationVariancePct = null;
  if (fin.sale_price != null && fin.end_target_value != null) {
    valuationVariance = Number(fin.sale_price) - Number(fin.end_target_value);
    valuationVariancePct = Number(fin.end_target_value) > 0
      ? Number(((valuationVariance / Number(fin.end_target_value)) * 100).toFixed(2))
      : 0;
  }

  const surfaceReasons = [];
  if (approachingMileage) surfaceReasons.push(`Approaching target mileage (${milesRemaining} miles remaining)`);
  if (approachingDate) surfaceReasons.push(`Approaching target date (${daysRemaining} days remaining, committed=${isCommitted})`);
  if (pastTargetDate) surfaceReasons.push(`Past target date by ${Math.abs(daysRemaining)} days`);
  if (pastTargetMileage) surfaceReasons.push(`Past target mileage by ${Math.abs(milesRemaining)} miles`);

  return {
    is_surfaced: surfaceReasons.length > 0,
    surface_reasons: surfaceReasons,
    approaching_target_mileage: approachingMileage,
    approaching_target_date: approachingDate,
    past_target: pastTargets,
    past_target_date: pastTargetDate,
    past_target_mileage: pastTargetMileage,
    end_date_is_committed: isCommitted,
    end_commitment_note: fin.end_commitment_note || null,
    surfacing_urgency: isCommitted ? 'high_commitment' : 'standard',
    handling: handling,
    escalated: false,
    status: status,
    decision_required: decisionRequired,
    action_options: actionOptions,
    days_remaining: daysRemaining,
    miles_remaining: milesRemaining,
    current_odometer: odo,
    valuation_variance: valuationVariance,
    valuation_variance_pct: valuationVariancePct,
  };
}

// GET /v1/fleet/financing/surfaced (8.8-C05, 8.8-C06, 8.8-C07, 8.8-C09, 8.8-C10)
fleetRouter.get('/financing/surfaced', async (req, res) => {
  const { hasFinancePerm } = checkFinancingAccess(req);

  const q = `
    SELECT vfl.*,
           v.vehicle_name, v.vin, v.model, v.fleet_stage, v.condition_code,
           COALESCE(
             (SELECT odometer_value FROM fs.vehicle_odometer_log WHERE vehicle_id = v.vehicle_id ORDER BY COALESCE(effective_at, captured_at, created_at) DESC LIMIT 1),
             0
           ) AS current_odometer
      FROM fs.vehicle_financing_lifecycle vfl
      JOIN fs.vehicle v ON v.vehicle_id = vfl.vehicle_id
     WHERE vfl.sale_date IS NULL
       AND v.fleet_stage != 'Retired'
  `;
  const result = await query(q);

  const surfaced = [];
  for (const row of result.rows) {
    const analysis = computeSurfacingAndWatching(row, row.current_odometer);
    if (analysis.is_surfaced) {
      const maskedRow = redactFinancialFields(row, hasFinancePerm);
      surfaced.push({
        ...maskedRow,
        watching: analysis,
      });
    }
  }

  res.json({
    ok: true,
    count: surfaced.length,
    surfaced_vehicles: surfaced,
  });
});

// GET /v1/fleet/:vehicleId — Vehicle detail
fleetRouter.get('/:vehicleId', async (req, res) => {
  const { vehicleId } = req.params;
  const result = await query(
    `SELECT * FROM fs.v_active_fleet WHERE vehicle_id = $1`,
    [vehicleId]
  );
  if (result.rowCount > 0) {
    return res.json({ vehicle: result.rows[0] });
  }

  // Fallback to core fs.vehicle for newly added Stage 2 vehicles
  const v2 = await query(
    `SELECT v.vehicle_id, v.vin, v.vehicle_name, v.model, v.trim, v.year AS model_year,
            v.exterior_color, v.interior_color, v.fleet_stage, v.condition_code,
            v.launch_date::text AS launch_date, v.home_branch_id, b.branch_code AS location_code
       FROM fs.vehicle v
       LEFT JOIN fs.branch b ON b.branch_id = v.home_branch_id
      WHERE v.vehicle_id = $1`,
    [vehicleId]
  );
  if (v2.rowCount === 0) {
    throw new HttpError(404, 'Vehicle not found');
  }
  res.json({ vehicle: v2.rows[0] });
});

// GET /v1/fleet/:vehicleId/availability
fleetRouter.get('/:vehicleId/availability', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    from: z.string().datetime(),
    to: z.string().datetime(),
  });
  const { from, to } = schema.parse(req.query);

  const result = await query(
    `
    SELECT id, confirmation_code, pickup_at, return_at, status, 'Member' AS reservation_type
      FROM fs.reservations
     WHERE vehicle_id = $1
       AND status IN ('requested','confirmed','picked_up')
       AND booking_period && tstzrange($2::timestamptz, $3::timestamptz, '[)')
    UNION ALL
    SELECT vr.vehicle_reservation_id AS id,
           COALESCE(vr.vehicle_reservation_id::text, 'VR') AS confirmation_code,
           vr.start_time_scheduled AS pickup_at,
           (vr.end_time_scheduled + (COALESCE(vr.buffer_days_after_end, 0) || ' days')::interval) AS return_at,
           vr.reservation_status_code AS status,
           vr.reservation_type_code AS reservation_type
      FROM fs.vehicle_reservation vr
     WHERE vr.vehicle_id = $1
       AND vr.reservation_status_code IN ('Confirmed', 'Held', 'Tentative')
       AND tstzrange(vr.start_time_scheduled, vr.end_time_scheduled + (COALESCE(vr.buffer_days_after_end, 0) || ' days')::interval, '[)')
           && tstzrange($2::timestamptz, $3::timestamptz, '[)')
     ORDER BY pickup_at ASC
    `,
    [vehicleId, from, to]
  );
  res.json({
    vehicle_id: vehicleId,
    window: { from, to },
    blocked_periods: result.rows,
  });
});

// POST /v1/fleet/:vehicleId/arrival — Stamp Arrival Date & Advance to Intake (8.3-R02, 8.3-C03)
fleetRouter.post('/:vehicleId/arrival', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    arrival_date: z.string().optional(),
  });
  const { arrival_date } = schema.parse(req.body);
  const stampDate = arrival_date || new Date().toISOString().split('T')[0];

  const result = await withTransaction(async (client) => {
    const existingRes = await client.query(`SELECT * FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
    if (existingRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
    const existing = existingRes.rows[0];

    // 8.3-R02 / 8.3-C03: Stamping arrival_date moves the stage from Incoming to Intake
    const newStage = existing.fleet_stage === 'Incoming' ? 'Intake' : existing.fleet_stage;

    const updateRes = await client.query(
      `UPDATE fs.vehicle
          SET arrival_date = $1,
              fleet_stage = $2,
              updated_at = now()
        WHERE vehicle_id = $3
        RETURNING *`,
      [stampDate, newStage, vehicleId]
    );

    // Audit log (8.1-R11)
    await recordVehicleShadow(client, vehicleId, `Arrival stamped on ${stampDate}; fleet_stage updated to ${newStage}`);

    return updateRes.rows[0];
  });

  res.json({ ok: true, vehicle: result, message: `Arrival stamped on ${stampDate}. Vehicle transitioned to ${result.fleet_stage} stage.` });
});

// POST /v1/fleet/:vehicleId/complete-readiness — Complete Readiness to Fleet Stage (8.3-R04, 8.3-R05, 8.3-C04-C06)
fleetRouter.post('/:vehicleId/complete-readiness', async (req, res) => {
  const { vehicleId } = req.params;

  const result = await withTransaction(async (client) => {
    const existingRes = await client.query(`SELECT * FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
    if (existingRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
    const existing = existingRes.rows[0];

    // 8.3-R04: Readiness is derived from records, never set manually by a person
    const summary = await getCompanionsSummary(client, vehicleId);
    if (!summary.is_complete) {
      throw new HttpError(400, `8.3-R04: Readiness cannot complete. Missing required companions: ${summary.missing.join(', ')}`);
    }

    // Check rate card placement on standard rate card (8.1-R10)
    const placementRes = await client.query(
      `SELECT rcp.* FROM fs.rate_card_placement rcp
         JOIN fs.rate_card rc ON rc.rate_card_id = rcp.rate_card_id
        WHERE rcp.vehicle_id = $1 AND rc.card_code = 'RC_STANDARD_2026'`,
      [vehicleId]
    );
    if (placementRes.rowCount === 0) {
      throw new HttpError(400, '8.3-R04 / 8.1-R10: Readiness cannot complete. Vehicle lacks a tier placement on active rate card.');
    }

    // 8.3-R05 / 8.3-C04: Readiness completing moves stage to Fleet
    const updateRes = await client.query(
      `UPDATE fs.vehicle
          SET fleet_stage = 'Fleet',
              condition_code = 'Ready',
              updated_at = now()
        WHERE vehicle_id = $1
        RETURNING *`,
      [vehicleId]
    );

    // 8.3-C05: Readiness completing places an awaiting-launch withhold in same transaction
    const withholdRes = await client.query(
      `INSERT INTO fs.reservation_withhold (
         branch_id, vehicle_id, withhold_reason_code, starts_on, withhold_note, placed_at
       ) VALUES ($1, $2, 'AwaitingLaunch', CURRENT_DATE, 'Readiness complete; awaiting official launch to members', now())
       RETURNING *`,
      [existing.home_branch_id, vehicleId]
    );

    // 8.3-C06: Readiness completing raises a launch task in same transaction
    const taskRes = await client.query(
      `INSERT INTO fs.task (
         task_title, description, task_status_code, task_priority_code, task_type_code, due_date, is_active
       ) VALUES (
         $1, $2, 'PENDING', 'HIGH', 'VEHICLE_LAUNCH', now() + interval '7 days', TRUE
       ) RETURNING *`,
      [
        `Launch vehicle into member service: ${existing.vehicle_name}`,
        `Vehicle ${existing.vehicle_name} (ID: ${vehicleId}) has completed readiness. Open awaiting-launch withhold requires completing launch form to release.`,
      ]
    );

    // Link task to vehicle (8.6-C01)
    await client.query(
      `INSERT INTO fs.task_link (task_id, target_table, target_id, is_primary)
       VALUES ($1, 'vehicle', $2, TRUE)`,
      [taskRes.rows[0].task_id, vehicleId]
    );

    // 8.3-C11: Intake completing stops further aging tasks
    await client.query(
      `UPDATE fs.task
          SET is_active = FALSE,
               task_status_code = 'CANCELLED',
               cancelled_reason = 'Intake completed; vehicle advanced to Fleet'
        WHERE description LIKE '%' || $1 || '%'
          AND task_type_code IN ('INTAKE_AGING_10', 'INTAKE_AGING_30', 'INTAKE_AGING_60', 'INTAKE_AGING_90')`,
      [vehicleId]
    );

    await recordVehicleShadow(client, vehicleId, 'Readiness complete; advanced to Fleet stage');

    return {
      vehicle: updateRes.rows[0],
      withhold: withholdRes.rows[0],
      task: taskRes.rows[0],
    };
  });

  res.json({ ok: true, message: 'Readiness complete. Vehicle transitioned to Fleet stage with awaiting-launch withhold placed and launch task created.', ...result });
});

// POST /v1/fleet/:vehicleId/retire — Retire Vehicle from Any Stage with Reason (8.3-R06, 8.3-C12-C14)
fleetRouter.post('/:vehicleId/retire', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    reason: z.string().min(1, '8.3-R06 / 8.3-C14: Retirement requires a reason and may occur from any stage.'),
    notes: z.string().optional(),
  });
  const { reason, notes } = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const existingRes = await client.query(`SELECT * FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
    if (existingRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
    const existing = existingRes.rows[0];

    // 8.3-R06: Retirement requires a reason and may occur from any stage (Incoming 8.3-C12, Intake 8.3-C13, Fleet)
    const retireNotes = `Retired: ${reason}${notes ? ' - ' + notes : ''}`;

    const updateRes = await client.query(
      `UPDATE fs.vehicle
          SET fleet_stage = 'Retired',
              condition_code = 'Down',
              notes = COALESCE(notes || E'\n', '') || $1,
              updated_at = now()
        WHERE vehicle_id = $2
        RETURNING *`,
      [retireNotes, vehicleId]
    );

    // Stop and cancel any pending aging tasks on this vehicle (8.3-C11)
    await client.query(
      `UPDATE fs.task
          SET is_active = FALSE,
              task_status_code = 'CANCELLED',
              cancelled_reason = 'Vehicle retired: ' || $1
        WHERE description LIKE '%' || $2 || '%' AND is_active = TRUE`,
      [reason, vehicleId]
    );

    // Audit log
    await recordVehicleShadow(client, vehicleId, `Vehicle retired: ${reason}`);

    return updateRes.rows[0];
  });

  res.json({ ok: true, vehicle: result, message: `Vehicle retired from ${result.fleet_stage} stage.` });
});

// GET /v1/fleet/:vehicleId/condition-history — History and Cache (8.4-R03, 8.4-C16, 8.4-C17)
fleetRouter.get('/:vehicleId/condition-history', async (req, res) => {
  const { vehicleId } = req.params;
  const vRes = await query(`SELECT vehicle_id, vin, vehicle_name, condition_code, condition_reason_code, condition_since FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
  if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');

  const historyRes = await query(
    `SELECT h.vehicle_condition_history_id,
            h.vehicle_id,
            h.condition_code,
            cc.name AS condition_name,
            h.condition_reason_code,
            cr.status_reason_name AS reason_name,
            h.notes,
            h.changed_at,
            h.changed_by_user_id
       FROM fs.vehicle_condition_history h
       LEFT JOIN fs.vehicle_condition_code cc ON cc.condition_code = h.condition_code
       LEFT JOIN fs.vehicle_condition_reason cr ON cr.condition_reason_code = h.condition_reason_code
      WHERE h.vehicle_id = $1
      ORDER BY h.changed_at DESC`,
    [vehicleId]
  );

  res.json({
    ok: true,
    vehicle: vRes.rows[0],
    history_count: historyRes.rowCount,
    history: historyRes.rows,
  });
});

// POST /v1/fleet/:vehicleId/transition-condition — Explicit condition transitions with rule check (8.4-R04, 8.4-R06, 8.4-C09, 8.4-C10, 8.4-C18)
fleetRouter.post('/:vehicleId/transition-condition', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    condition_code: z.enum(['Arrived', 'Returned', 'Review', 'Prep', 'Ready', 'Down']).nullable(),
    reason_code: z.string().optional(),
    notes: z.string().optional(),
    changed_by_user_id: z.string().uuid().optional(),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const existingRes = await client.query(
      `SELECT vehicle_id, vin, vehicle_name, condition_code, condition_reason_code, fleet_stage, home_branch_id
         FROM fs.vehicle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    if (existingRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
    const existing = existingRes.rows[0];
    const fromCondition = existing.condition_code;
    const toCondition = data.condition_code;

    // 8.4-R05 / 8.4-C09: A vehicle that cannot go out is set to Down with a reason
    if (toCondition === 'Down' && !data.reason_code && !data.notes) {
      throw new HttpError(400, '8.4-R04 / 8.4-C09: A vehicle set to Down requires a reason.');
    }

    // Check transition rules if transitioning between two conditions (8.4-R06, 8.4-C18)
    if (fromCondition && toCondition) {
      if (fromCondition === toCondition) {
        // 8.4-C10: Booking a service changes the reason and leaves the condition at Down
        if (fromCondition === 'Down') {
          if (!data.reason_code && !data.notes) {
            throw new HttpError(400, '8.4-C10: Updating Down reason requires a new reason_code or notes.');
          }
        } else {
          throw new HttpError(400, `Vehicle is already in ${fromCondition} condition.`);
        }
      } else {
        const ruleRes = await client.query(
          `SELECT * FROM fs.vehicle_condition_transition_rule
            WHERE from_condition_code = $1 AND to_condition_code = $2 AND is_active = TRUE`,
          [fromCondition, toCondition]
        );
        if (ruleRes.rowCount === 0) {
          throw new HttpError(400, `8.4-C18: Condition transition from '${fromCondition}' to '${toCondition}' is forbidden by transition rules.`);
        }
      }
    }

    // 8.4-R03 / 8.4-C16 / 8.4-C17: Update cache on VEHICLE and write history row in one transaction
    const updateRes = await client.query(
      `UPDATE fs.vehicle
          SET condition_code = $1,
              condition_reason_code = $2,
              condition_since = now(),
              updated_at = now()
        WHERE vehicle_id = $3
        RETURNING *`,
      [toCondition, data.reason_code || null, vehicleId]
    );

    const historyRes = await client.query(
      `INSERT INTO fs.vehicle_condition_history (
         vehicle_id, condition_code, condition_reason_code, notes, changed_by_user_id, changed_at
       ) VALUES ($1, $2, $3, $4, $5, now())
       RETURNING *`,
      [vehicleId, toCondition, data.reason_code || null, data.notes || null, data.changed_by_user_id || null]
    );

    await recordVehicleShadow(client, vehicleId, `Condition changed from ${fromCondition || 'None'} to ${toCondition || 'None'}`);

    return {
      vehicle: updateRes.rows[0],
      history: historyRes.rows[0],
    };
  });

  res.json({ ok: true, ...result });
});

// POST /v1/fleet/:vehicleId/check-in — Check-in boundary event with severity routing (8.4-R07, 8.4-C01, 8.4-C02, 8.4-C06, 8.4-C08)
fleetRouter.post('/:vehicleId/check-in', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    worst_issue_severity: z.enum(['none', 'minor', 'moderate', 'major', 'critical']),
    notes: z.string().optional(),
    changed_by_user_id: z.string().uuid().optional(),
  });
  const { worst_issue_severity, notes, changed_by_user_id } = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const existingRes = await client.query(
      `SELECT vehicle_id, vin, vehicle_name, condition_code, fleet_stage, home_branch_id
         FROM fs.vehicle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    if (existingRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
    const existing = existingRes.rows[0];

    // 8.4-R07 / 8.4-C02: Check-in is the boundary between Returned and what comes next:
    // Minor or none to Prep, Moderate to Review, Major or Critical to Down.
    let targetCondition = 'Prep';
    let targetReason = 'TurnaroundPrep';
    let taskCreated = null;

    if (worst_issue_severity === 'moderate') {
      // 8.4-C02 / 8.4-C06: Moderate issue sets condition to Review and opens decision task for VSM
      targetCondition = 'Review';
      targetReason = 'ManagerDecision';

      const taskRes = await client.query(
        `INSERT INTO fs.task (
           task_title, description, task_status_code, task_priority_code, task_type_code, due_date, is_active
         ) VALUES (
           $1, $2, 'PENDING', 'HIGH', 'CONDITION_REVIEW_DECISION', now() + interval '1 day', TRUE
         ) RETURNING *`,
        [
          `Review decision required: ${existing.vehicle_name}`,
          `Vehicle ${existing.vehicle_name} (ID: ${vehicleId}) has a moderate check-in issue. VSM review decision required: approve to Prep or route to Down. Notes: ${notes || 'None'}`,
        ]
      );
      taskCreated = taskRes.rows[0];
    } else if (worst_issue_severity === 'major' || worst_issue_severity === 'critical') {
      // 8.4-C02 / 8.4-C09: Major or Critical issue moves it to Down
      targetCondition = 'Down';
      targetReason = 'ReturnedWithDamage';
    }

    const updateRes = await client.query(
      `UPDATE fs.vehicle
          SET condition_code = $1,
              condition_reason_code = $2,
              condition_since = now(),
              updated_at = now()
        WHERE vehicle_id = $3
        RETURNING *`,
      [targetCondition, targetReason, vehicleId]
    );

    const historyRes = await client.query(
      `INSERT INTO fs.vehicle_condition_history (
         vehicle_id, condition_code, condition_reason_code, notes, changed_by_user_id, changed_at
       ) VALUES ($1, $2, $3, $4, $5, now())
       RETURNING *`,
      [vehicleId, targetCondition, targetReason, `Check-in severity: ${worst_issue_severity}. ${notes || ''}`, changed_by_user_id || null]
    );

    await recordVehicleShadow(client, vehicleId, `Check-in recorded with severity ${worst_issue_severity} -> ${targetCondition}`);

    return {
      vehicle: updateRes.rows[0],
      history: historyRes.rows[0],
      task: taskCreated,
      message: `Check-in processed with severity '${worst_issue_severity}'. Vehicle moved to '${targetCondition}'.`,
    };
  });

  res.json({ ok: true, ...result });
});

// POST /v1/fleet/:vehicleId/review-decision — VSM decision exits Review to Prep or Down (8.4-R08, 8.4-C07)
fleetRouter.post('/:vehicleId/review-decision', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    decision: z.enum(['Prep', 'Down']), // 8.4-R08: Exactly two exits
    reason_code: z.string().optional(),
    notes: z.string().min(1, '8.4-C07: Review decision requires recorded reason/notes'),
    decided_by_user_id: z.string().uuid().optional(),
  });
  const { decision, reason_code, notes, decided_by_user_id } = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const existingRes = await client.query(
      `SELECT vehicle_id, vin, vehicle_name, condition_code, fleet_stage, home_branch_id
         FROM fs.vehicle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    if (existingRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
    const existing = existingRes.rows[0];

    if (existing.condition_code !== 'Review') {
      throw new HttpError(400, `8.4-R08: Cannot make review decision on vehicle in '${existing.condition_code}' condition; vehicle must be in 'Review'.`);
    }

    const assignedReason = decision === 'Down' ? (reason_code || 'DamageFound') : (reason_code || 'TurnaroundPrep');

    // 8.4-C07: Decision to Prep or Down is recorded with who and why, and closes the task
    const updateRes = await client.query(
      `UPDATE fs.vehicle
          SET condition_code = $1,
              condition_reason_code = $2,
              condition_since = now(),
              updated_at = now()
        WHERE vehicle_id = $3
        RETURNING *`,
      [decision, assignedReason, vehicleId]
    );

    const historyRes = await client.query(
      `INSERT INTO fs.vehicle_condition_history (
         vehicle_id, condition_code, condition_reason_code, notes, changed_by_user_id, changed_at
       ) VALUES ($1, $2, $3, $4, $5, now())
       RETURNING *`,
      [vehicleId, decision, assignedReason, `VSM Review Decision: ${decision}. Notes: ${notes}`, decided_by_user_id || null]
    );

    // Closes decision task (8.4-C07)
    await client.query(
      `UPDATE fs.task
          SET is_active = FALSE,
              task_status_code = 'COMPLETED',
              completed_at = now()
        WHERE description LIKE '%' || $1 || '%'
          AND task_type_code = 'CONDITION_REVIEW_DECISION'
          AND is_active = TRUE`,
      [vehicleId]
    );

    await recordVehicleShadow(client, vehicleId, `Review decision executed: moved to ${decision}`);

    return {
      vehicle: updateRes.rows[0],
      history: historyRes.rows[0],
      message: `Review decision recorded: vehicle moved from Review to ${decision}.`,
    };
  });

  res.json({ ok: true, ...result });
});

// POST /v1/fleet/:vehicleId/complete-turnaround — Turnaround completion moves Prep to Ready (8.4-C03)
fleetRouter.post('/:vehicleId/complete-turnaround', async (req, res) => {
  const { vehicleId } = req.params;

  const result = await withTransaction(async (client) => {
    const existingRes = await client.query(
      `SELECT vehicle_id, vin, vehicle_name, condition_code, fleet_stage, home_branch_id
         FROM fs.vehicle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    if (existingRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
    const existing = existingRes.rows[0];

    // 8.4-C03: Turnaround completion moves it to Ready
    if (existing.condition_code !== 'Prep') {
      throw new HttpError(400, `8.4-C03: Turnaround can only complete from 'Prep' condition (current: '${existing.condition_code}').`);
    }

    const updateRes = await client.query(
      `UPDATE fs.vehicle
          SET condition_code = 'Ready',
              condition_reason_code = NULL,
              condition_since = now(),
              updated_at = now()
        WHERE vehicle_id = $1
        RETURNING *`,
      [vehicleId]
    );

    const historyRes = await client.query(
      `INSERT INTO fs.vehicle_condition_history (
         vehicle_id, condition_code, condition_reason_code, notes, changed_at
       ) VALUES ($1, 'Ready', NULL, 'Turnaround detailing and fueling complete', now())
       RETURNING *`,
      [vehicleId]
    );

    await recordVehicleShadow(client, vehicleId, 'Turnaround complete; condition moved to Ready');

    return {
      vehicle: updateRes.rows[0],
      history: historyRes.rows[0],
    };
  });

  res.json({ ok: true, message: 'Turnaround complete. Vehicle is Ready.', ...result });
});

// POST /v1/fleet/:vehicleId/arrive — Arrival from branch transfer or vendor return (8.4-C04, 8.4-C05)
fleetRouter.post('/:vehicleId/arrive', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    source: z.enum(['branch_transfer', 'vendor_return', 'other']),
    notes: z.string().optional(),
  });
  const { source, notes } = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const existingRes = await client.query(
      `SELECT vehicle_id, vin, vehicle_name, condition_code, fleet_stage, home_branch_id
         FROM fs.vehicle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    if (existingRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');

    // 8.4-C04: A vehicle arriving from another branch is set to Arrived, not Returned.
    // 8.4-C05: A vehicle back from a vendor is set to Arrived.
    const updateRes = await client.query(
      `UPDATE fs.vehicle
          SET condition_code = 'Arrived',
              condition_reason_code = NULL,
              condition_since = now(),
              updated_at = now()
        WHERE vehicle_id = $1
        RETURNING *`,
      [vehicleId]
    );

    const historyRes = await client.query(
      `INSERT INTO fs.vehicle_condition_history (
         vehicle_id, condition_code, condition_reason_code, notes, changed_at
       ) VALUES ($1, 'Arrived', NULL, $2, now())
       RETURNING *`,
      [vehicleId, `Arrived via ${source}. ${notes || ''}`]
    );

    await recordVehicleShadow(client, vehicleId, `Arrival recorded via ${source} -> Arrived`);

    return {
      vehicle: updateRes.rows[0],
      history: historyRes.rows[0],
    };
  });

  res.json({ ok: true, message: `Arrival recorded from ${source}. Vehicle set to Arrived.`, ...result });
});

// POST /v1/fleet/:vehicleId/checkout — Absence: no condition while out (8.4-R02, 8.4-C12, 8.4-C13, 8.4-C14)
fleetRouter.post('/:vehicleId/checkout', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    reason: z.enum(['member_trip', 'vendor_service', 'branch_transfer']),
    notes: z.string().optional(),
  });
  const { reason, notes } = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const existingRes = await client.query(
      `SELECT vehicle_id, vin, vehicle_name, condition_code, fleet_stage, home_branch_id
         FROM fs.vehicle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    if (existingRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');

    // 8.4-R02 / 8.4-C12 / 8.4-C13 / 8.4-C14:
    // A vehicle checked out to a member has no condition.
    // A vehicle away at a vendor has no condition.
    // A vehicle on a branch transfer has no condition until it arrives.
    const updateRes = await client.query(
      `UPDATE fs.vehicle
          SET condition_code = NULL,
              condition_reason_code = NULL,
              condition_since = now(),
              updated_at = now()
        WHERE vehicle_id = $1
        RETURNING *`,
      [vehicleId]
    );

    const historyRes = await client.query(
      `INSERT INTO fs.vehicle_condition_history (
         vehicle_id, condition_code, condition_reason_code, notes, changed_at
       ) VALUES ($1, NULL, NULL, $2, now())
       RETURNING *`,
      [vehicleId, `Checked out for ${reason}. Condition cleared (no condition while out). ${notes || ''}`]
    );

    await recordVehicleShadow(client, vehicleId, `Checked out for ${reason}; condition cleared`);

    return {
      vehicle: updateRes.rows[0],
      history: historyRes.rows[0],
    };
  });

  res.json({ ok: true, message: `Vehicle checked out for ${reason}. Condition cleared.`, ...result });
});

// =============================================================================
// GUIDE 8.5: Vehicle-Specific Commitment & Bookability Endpoints
// =============================================================================

// GET /v1/fleet/:vehicleId/bookability (8.5-R01, 8.5-C01 through 8.5-C16)
fleetRouter.get('/:vehicleId/bookability', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    start_date: z.string(), // YYYY-MM-DD
    end_date: z.string(),   // YYYY-MM-DD
    member_id: z.string().uuid().optional(),
    is_staff: z.coerce.boolean().default(false),
    member_podium_status: z.string().optional(),
  });
  const { start_date, end_date, member_id, is_staff, member_podium_status } = schema.parse(req.query);

  const evaluation = await evaluateVehicleBookability(
    { query },
    vehicleId,
    start_date,
    end_date,
    { memberId: member_id, isStaff: is_staff, memberPodiumStatus: member_podium_status }
  );

  res.json({
    ok: true,
    vehicle_id: vehicleId,
    start_date,
    end_date,
    ...evaluation,
  });
});

// POST /v1/fleet/:vehicleId/commitments/internal-block (8.5-C04)
fleetRouter.post('/:vehicleId/commitments/internal-block', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    start_time: z.string(),
    end_time: z.string(),
    buffer_days: z.number().int().min(0).default(0),
    notes: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const startDateStr = data.start_time.slice(0, 10);
  const endDateStr = data.end_time.slice(0, 10);

  const result = await withTransaction(async (client) => {
    // 8.5-R02: One calendar, no exceptions. Internal block is enforced on the single calendar.
    const evalResult = await evaluateVehicleBookability(client, vehicleId, startDateStr, endDateStr, { isStaff: true });
    if (!evalResult.is_bookable) {
      throw new HttpError(409, `Cannot place internal block: ${evalResult.error}`);
    }

    const vRes = await client.query(`SELECT home_branch_id FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
    const homeBranchId = vRes.rows[0]?.home_branch_id;

    const insertRes = await client.query(
      `INSERT INTO fs.vehicle_reservation (
         reservation_type_code, reservation_status_code, vehicle_id,
         reserving_branch_id, source_type_code, start_time_scheduled, end_time_scheduled,
         buffer_days_after_end, notes, created_at, updated_at
       ) VALUES ('InternalBlock', 'Confirmed', $1, $2, 'System', $3, $4, $5, $6, now(), now())
       RETURNING *`,
      [vehicleId, homeBranchId || null, data.start_time, data.end_time, data.buffer_days, data.notes || null]
    );

    await recordVehicleShadow(client, vehicleId, `Internal block placed from ${startDateStr} to ${endDateStr}`);

    return insertRes.rows[0];
  });

  res.status(201).json({ ok: true, message: 'Internal block created', reservation: result });
});

// POST /v1/fleet/:vehicleId/commitments/event (8.5-C05)
fleetRouter.post('/:vehicleId/commitments/event', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    start_time: z.string(),
    end_time: z.string(),
    buffer_days: z.number().int().min(0).default(0),
    notes: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const startDateStr = data.start_time.slice(0, 10);
  const endDateStr = data.end_time.slice(0, 10);

  const result = await withTransaction(async (client) => {
    const evalResult = await evaluateVehicleBookability(client, vehicleId, startDateStr, endDateStr, { isStaff: true });
    if (!evalResult.is_bookable) {
      throw new HttpError(409, `Cannot place event commitment: ${evalResult.error}`);
    }

    const vRes = await client.query(`SELECT home_branch_id FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
    const homeBranchId = vRes.rows[0]?.home_branch_id;

    const insertRes = await client.query(
      `INSERT INTO fs.vehicle_reservation (
         reservation_type_code, reservation_status_code, vehicle_id,
         reserving_branch_id, source_type_code, start_time_scheduled, end_time_scheduled,
         buffer_days_after_end, notes, created_at, updated_at
       ) VALUES ('Event', 'Confirmed', $1, $2, 'StaffPortal', $3, $4, $5, $6, now(), now())
       RETURNING *`,
      [vehicleId, homeBranchId || null, data.start_time, data.end_time, data.buffer_days, data.notes || null]
    );

    await recordVehicleShadow(client, vehicleId, `Event commitment placed from ${startDateStr} to ${endDateStr}`);

    return insertRes.rows[0];
  });

  res.status(201).json({ ok: true, message: 'Event commitment created', reservation: result });
});

// POST /v1/fleet/:vehicleId/commitments/service (9.1-C01, 9.1-C02, 9.1-C05, 9.1-C08)
fleetRouter.post('/:vehicleId/commitments/service', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    start_time: z.string(),
    end_time: z.string(),
    buffer_days: z.number().int().min(0).default(0),
    service_vendor_id: z.string().uuid().optional(),
    vendor_name: z.string().optional(),
    service_category_code: z.string().optional(),
    service_type_code: z.string().optional(),
    notes: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const startDateStr = data.start_time.slice(0, 10);
  const endDateStr = data.end_time.slice(0, 10);

  const result = await withTransaction(async (client) => {
    // 9.1-C02: Refused if overlapping an existing reservation of any type
    const evalResult = await evaluateVehicleBookability(client, vehicleId, startDateStr, endDateStr, { isStaff: true });
    if (!evalResult.is_bookable) {
      throw new HttpError(409, `Cannot place service booking: ${evalResult.error}`);
    }

    const vRes = await client.query(`SELECT home_branch_id FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
    const homeBranchId = vRes.rows[0]?.home_branch_id;

    let vendorId = data.service_vendor_id || null;
    if (!vendorId && data.vendor_name) {
      const vLookup = await client.query(`SELECT vendor_id FROM fs.vendor WHERE vendor_name = $1`, [data.vendor_name]);
      if (vLookup.rowCount > 0) {
        vendorId = vLookup.rows[0].vendor_id;
      } else {
        const vIns = await client.query(
          `INSERT INTO fs.vendor (vendor_name, home_branch_id) VALUES ($1, $2) ON CONFLICT (vendor_name) DO UPDATE SET vendor_name = EXCLUDED.vendor_name RETURNING vendor_id`,
          [data.vendor_name, homeBranchId]
        );
        vendorId = vIns.rows[0]?.vendor_id;
      }
    }

    const insertRes = await client.query(
      `INSERT INTO fs.vehicle_reservation (
         reservation_type_code, reservation_status_code, vehicle_id,
         reserving_branch_id, source_type_code, start_time_scheduled, end_time_scheduled,
         buffer_days_after_end, service_vendor_id, service_category_code, service_type_code,
         notes, created_at, updated_at
       ) VALUES ('Service', 'Confirmed', $1, $2, 'StaffPortal', $3, $4, $5, $6, $7, $8, $9, now(), now())
       RETURNING *`,
      [
        vehicleId,
        homeBranchId || null,
        data.start_time,
        data.end_time,
        data.buffer_days,
        vendorId,
        data.service_category_code || null,
        data.service_type_code || null,
        data.notes || null,
      ]
    );

    await recordVehicleShadow(client, vehicleId, `Service booking placed from ${startDateStr} to ${endDateStr} (vendor: ${data.vendor_name || vendorId || 'Unspecified'})`);

    return insertRes.rows[0];
  });

  res.status(201).json({ ok: true, message: 'Service booking created', reservation: result });
});

// GET /v1/fleet/:vehicleId/release-rows (8.5-C15, 8.5-C16)
fleetRouter.get('/:vehicleId/release-rows', async (req, res) => {
  const { vehicleId } = req.params;
  const result = await query(
    `SELECT * FROM fs.vehicle_release_row WHERE vehicle_id = $1 ORDER BY sort_order ASC`,
    [vehicleId]
  );
  res.json({ ok: true, count: result.rowCount, release_rows: result.rows });
});

// POST /v1/fleet/:vehicleId/release-rows (8.5-C15, 8.5-C16)
fleetRouter.post('/:vehicleId/release-rows', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    stages: z.array(z.object({
      sort_order: z.number().int().default(1),
      duration_days: z.number().int().default(14),
      minimum_podium_status_code: z.string().optional(),
      hide_from_lower_tiers: z.boolean().default(false),
    })),
  });
  const { stages } = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    // Clear old stages if replacing
    await client.query(`DELETE FROM fs.vehicle_release_row WHERE vehicle_id = $1`, [vehicleId]);

    const inserted = [];
    for (const s of stages) {
      const ins = await client.query(
        `INSERT INTO fs.vehicle_release_row (
           vehicle_id, sort_order, duration_days, minimum_podium_status_code, hide_from_lower_tiers
         ) VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [vehicleId, s.sort_order, s.duration_days, s.minimum_podium_status_code || null, s.hide_from_lower_tiers]
      );
      inserted.push(ins.rows[0]);
    }
    return inserted;
  });

  res.status(201).json({ ok: true, count: result.length, release_rows: result });
});

// POST /v1/fleet/:vehicleId/apply-release-template (8.6-R08, 8.6-C14)
fleetRouter.post('/:vehicleId/apply-release-template', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    template_id: z.string().uuid(),
  });
  const { template_id } = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    // 1. Verify vehicle exists
    const vRes = await client.query(`SELECT vehicle_id, vehicle_name FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
    if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');

    // 2. Fetch template rows
    const tRowsRes = await client.query(
      `SELECT * FROM fs.vehicle_release_template_row
        WHERE vehicle_release_template_id = $1
        ORDER BY sort_order ASC`,
      [template_id]
    );
    if (tRowsRes.rowCount === 0) {
      throw new HttpError(400, 'Selected template has no release rows defined.');
    }

    // 3. Clear existing vehicle release rows
    await client.query(`DELETE FROM fs.vehicle_release_row WHERE vehicle_id = $1`, [vehicleId]);

    // 4. 8.6-C14: Copy rows from template onto vehicle
    const copiedRows = [];
    for (const r of tRowsRes.rows) {
      const insRes = await client.query(
        `INSERT INTO fs.vehicle_release_row (
           vehicle_id, sort_order, duration_days, minimum_podium_status_code,
           hide_from_lower_tiers, applied_from_template_id
         ) VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [vehicleId, r.sort_order, r.duration_days, r.minimum_podium_status_code, r.hide_from_lower_tiers, template_id]
      );
      copiedRows.push(insRes.rows[0]);
    }

    await recordVehicleShadow(client, vehicleId, `Applied release template ${template_id} (${copiedRows.length} stages copied)`);

    return copiedRows;
  });

  res.status(201).json({
    ok: true,
    message: `Release template applied. ${result.length} stages copied onto vehicle.`,
    vehicle_id: vehicleId,
    template_id,
    release_rows: result,
  });
});

// POST /v1/fleet/:vehicleId/launch — Complete Launch Form (8.6-R01, 8.6-C04, 8.6-C16)
fleetRouter.post('/:vehicleId/launch', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    launch_date: z.string().optional(),
    notes: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    // 1. Verify vehicle exists
    const vRes = await client.query(`SELECT vehicle_id, vehicle_name, fleet_stage, condition_code FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
    if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');

    // 2. Set launch date on vehicle
    const targetLaunchDate = data.launch_date || new Date().toISOString().slice(0, 10);
    const updateRes = await client.query(
      `UPDATE fs.vehicle
          SET launch_date = $1,
              updated_at = now()
        WHERE vehicle_id = $2
        RETURNING *`,
      [targetLaunchDate, vehicleId]
    );

    // 3. 8.6-C04: Completing launch form releases the awaiting-launch withhold
    const whRes = await client.query(
      `UPDATE fs.reservation_withhold
          SET released_at = now(),
              release_note = 'Vehicle launched into service: ' || COALESCE($1, 'Launch completed'),
              updated_at = now()
        WHERE vehicle_id = $2
          AND withhold_reason_code = 'AwaitingLaunch'
          AND released_at IS NULL
        RETURNING *`,
      [data.notes || null, vehicleId]
    );

    // 4. 8.6-C04: Completing launch form marks vehicle launch task completed
    const taskRes = await client.query(
      `UPDATE fs.task
          SET task_status_code = 'COMPLETED',
              completed_at = now(),
              is_active = FALSE,
              updated_at = now()
        WHERE (
          task_id IN (SELECT task_id FROM fs.task_link WHERE target_table = 'vehicle' AND target_id = $1)
          OR (description LIKE '%' || $1::text || '%' AND task_type_code = 'VEHICLE_LAUNCH')
        )
        AND task_status_code != 'COMPLETED'
        RETURNING *`,
      [vehicleId]
    );

    await recordVehicleShadow(client, vehicleId, `Vehicle launched into member service with launch_date ${targetLaunchDate}`);

    return {
      vehicle: updateRes.rows[0],
      withhold_released: whRes.rows[0] || null,
      task_completed: taskRes.rows[0] || null,
      launch_date: targetLaunchDate,
    };
  });

  res.json({
    ok: true,
    message: `Vehicle ${result.vehicle.vehicle_name} launched successfully into service.`,
    ...result,
  });
});

// POST /v1/fleet/:vehicleId/book (8.5-C01 through 8.5-C16)
fleetRouter.post('/:vehicleId/book', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    member_id: z.string().uuid().optional(),
    reservation_type_code: z.enum(['Member', 'Service', 'InternalBlock', 'Event']).default('Member'),
    start_time: z.string(), // ISO datetime or YYYY-MM-DD
    end_time: z.string(),
    buffer_days: z.number().int().min(0).default(0),
    is_staff: z.boolean().default(false),
    member_podium_status: z.string().optional(),
    service_vendor_id: z.string().uuid().optional(),
    vendor_name: z.string().optional(),
    service_category_code: z.string().optional(),
    service_type_code: z.string().optional(),
    notes: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const startDateStr = data.start_time.slice(0, 10);
  const endDateStr = data.end_time.slice(0, 10);

  const result = await withTransaction(async (client) => {
    // 1. Evaluate Bookability dynamically
    const evalResult = await evaluateVehicleBookability(client, vehicleId, startDateStr, endDateStr, {
      memberId: data.member_id,
      isStaff: data.is_staff,
      memberPodiumStatus: data.member_podium_status,
    });

    if (!evalResult.is_bookable) {
      if (evalResult.code === 'EXCLUSIVE_STAGE_BLOCKED') {
        throw new HttpError(403, evalResult.error);
      }
      throw new HttpError(409, evalResult.error);
    }

    const vRes = await client.query(
      `SELECT vehicle_id, home_branch_id FROM fs.vehicle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    const homeBranchId = vRes.rows[0]?.home_branch_id;

    let vendorId = data.service_vendor_id || null;
    if (!vendorId && data.vendor_name) {
      const vLookup = await client.query(`SELECT vendor_id FROM fs.vendor WHERE vendor_name = $1`, [data.vendor_name]);
      if (vLookup.rowCount > 0) {
        vendorId = vLookup.rows[0].vendor_id;
      } else {
        const vIns = await client.query(
          `INSERT INTO fs.vendor (vendor_name, home_branch_id) VALUES ($1, $2) ON CONFLICT (vendor_name) DO UPDATE SET vendor_name = EXCLUDED.vendor_name RETURNING vendor_id`,
          [data.vendor_name, homeBranchId]
        );
        vendorId = vIns.rows[0]?.vendor_id;
      }
    }

    // 2. Status Determination:
    // 8.5-R04 / 8.5-C09: A watch never refuses a booking; it creates it and holds it.
    const resStatusCode = evalResult.resulting_status; // 'Confirmed' or 'Held'
    const sourceTypeCode = data.is_staff ? 'StaffPortal' : 'MemberApp';

    const insertRes = await client.query(
      `INSERT INTO fs.vehicle_reservation (
         reservation_type_code, reservation_status_code, vehicle_id, member_id,
         reserving_branch_id, source_type_code, start_time_scheduled, end_time_scheduled,
         buffer_days_after_end, service_vendor_id, service_category_code, service_type_code,
         notes, created_at, updated_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, now(), now())
       RETURNING *`,
      [
        data.reservation_type_code,
        resStatusCode,
        vehicleId,
        data.member_id || null,
        homeBranchId || null,
        sourceTypeCode,
        data.start_time,
        data.end_time,
        data.buffer_days,
        vendorId,
        data.service_category_code || null,
        data.service_type_code || null,
        data.notes || null,
      ]
    );
    const resRow = insertRes.rows[0];

    // 3. Status History
    await client.query(
      `INSERT INTO fs.reservation_status_history (
         reservation_id, status, status_reason_code, status_note, created_at
       ) VALUES ($1, $2, $3, $4, now())`,
      [
        resRow.vehicle_reservation_id,
        resStatusCode,
        evalResult.has_watch ? 'WeatherHold' : null,
        evalResult.has_watch ? 'Booking placed on hold due to active watch' : 'Booking confirmed',
      ]
    );

    await recordVehicleShadow(client, vehicleId, `Booking created (${data.reservation_type_code}) -> ${resStatusCode}`);

    return {
      reservation: resRow,
      evaluation: evalResult,
    };
  });

  res.status(201).json({
    ok: true,
    message: `Reservation created with status ${result.reservation.reservation_status_code}`,
    ...result,
  });
});

// =============================================================================
// GUIDE 8.7: Vehicle Location and Transfers (Rules 8.7-R01 to 8.7-R09, 8.7-C01 to 8.7-C13)
// =============================================================================

async function resolveBranchId(client, branchIdOrCode) {
  if (!branchIdOrCode) return null;
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(branchIdOrCode);
  if (isUuid) {
    const res = await client.query('SELECT branch_id FROM fs.branch WHERE branch_id = $1', [branchIdOrCode]);
    return res.rows[0]?.branch_id || null;
  }
  const res = await client.query('SELECT branch_id FROM fs.branch WHERE UPPER(branch_code) = UPPER($1)', [branchIdOrCode]);
  return res.rows[0]?.branch_id || null;
}

// 1. POST /v1/fleet/:vehicleId/transfers/plan (8.7-R03, 8.7-R09, 8.7-C05, 8.7-C12)
// Evaluates transfer window, surfaces overlapping member reservations (8.7-C12),
// and creates an internal block reservation for travel days (8.7-C05).
fleetRouter.post('/:vehicleId/transfers/plan', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    origin_branch_id: z.string().optional(),
    destination_branch_id: z.string(),
    start_time: z.string(),
    end_time: z.string(),
    force: z.boolean().default(false),
    notes: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const startDateStr = data.start_time.slice(0, 10);
  const endDateStr = data.end_time.slice(0, 10);

  const result = await withTransaction(async (client) => {
    const vRes = await client.query('SELECT vehicle_id, vehicle_name, home_branch_id, fleet_stage, condition_code FROM fs.vehicle WHERE vehicle_id = $1', [vehicleId]);
    if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
    const vehicle = vRes.rows[0];

    const destBranchId = await resolveBranchId(client, data.destination_branch_id);
    if (!destBranchId) throw new HttpError(400, 'Invalid destination branch');

    const originBranchId = (await resolveBranchId(client, data.origin_branch_id)) || vehicle.home_branch_id;

    // 8.7-R09 / 8.7-C12: Check for overlapping member reservations
    const conflictRes = await client.query(
      `SELECT vehicle_reservation_id, reservation_type_code, reservation_status_code,
              start_time_scheduled::text AS start_time, end_time_scheduled::text AS end_time,
              member_id
         FROM fs.vehicle_reservation
        WHERE vehicle_id = $1
          AND reservation_type_code = 'Member'
          AND reservation_status_code NOT IN ('Cancelled', 'Completed')
          AND start_time_scheduled::date <= $3::date
          AND end_time_scheduled::date >= $2::date`,
      [vehicleId, startDateStr, endDateStr]
    );

    const hasConflicts = conflictRes.rowCount > 0;
    const conflicts = conflictRes.rows;

    if (hasConflicts && !data.force) {
      // 8.7-C12: Transfer overlapping a member reservation is surfaced for a decision
      return {
        ok: false,
        status: 409,
        has_conflicts: true,
        conflicts_count: conflictRes.rowCount,
        conflicts,
        message: `Transfer overlaps ${conflictRes.rowCount} active member reservation(s). Confirmation required to proceed.`,
      };
    }

    // 8.7-R03 / 8.7-C05: Transfer creates an internal block for the travel days
    const blockRes = await client.query(
      `INSERT INTO fs.vehicle_reservation (
         reservation_type_code, reservation_status_code, vehicle_id,
         reserving_branch_id, source_type_code, start_time_scheduled, end_time_scheduled,
         notes, created_at, updated_at
       ) VALUES ('InternalBlock', 'Confirmed', $1, $2, 'StaffPortal', $3, $4, $5, now(), now())
       RETURNING *`,
      [
        vehicleId,
        originBranchId,
        data.start_time,
        data.end_time,
        `Transfer Internal Block: ${data.notes || 'Branch transfer in transit'}`,
      ]
    );

    await recordVehicleShadow(client, vehicleId, `Transfer internal block created (${startDateStr} to ${endDateStr})`);

    return {
      ok: true,
      has_conflicts: hasConflicts,
      conflicts,
      internal_block: blockRes.rows[0],
      message: 'Transfer planned and internal block reserved.',
    };
  });

  if (!result.ok && result.has_conflicts) {
    return res.status(409).json(result);
  }
  res.status(201).json(result);
});

// 2. POST /v1/fleet/:vehicleId/transfers/depart (8.7-R04, 8.7-R08, 8.7-C02, 8.7-C06, 8.7-C11, 8.7-C13)
// Enforces origin departure inspection (8.7-C06), closes active location row with effective_to (8.7-C02),
// leaves fleet_stage unchanged (8.7-C11), sets condition to NULL in transit (8.7-C13).
fleetRouter.post('/:vehicleId/transfers/depart', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    origin_branch_id: z.string().optional(),
    destination_branch_id: z.string(),
    departure_inspection: z.object({
      keys_count: z.number().int().min(0).default(2),
      fuel_level_code: z.string().optional().default('Full'),
      car_cover_included_flag: z.boolean().default(true),
      owner_manual_included_flag: z.boolean().default(true),
      trickle_charger_included_flag: z.boolean().default(true),
      exterior_damage_found_flag: z.boolean().default(false),
      interior_damage_found_flag: z.boolean().default(false),
      wheels_tires_ok_flag: z.boolean().default(true),
      warning_lights_flag: z.boolean().default(false),
      mechanical_issue_flag: z.boolean().default(false),
      inspection_notes: z.string().optional(),
      inspector_user_id: z.string().uuid().optional(),
    }), // 8.7-C06: departure_inspection is strictly required
    is_temporary_loan: z.boolean().default(true),
    notes: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const vRes = await client.query(
      `SELECT vehicle_id, vehicle_name, home_branch_id, fleet_stage, condition_code FROM fs.vehicle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
    const vehicle = vRes.rows[0];

    const destBranchId = await resolveBranchId(client, data.destination_branch_id);
    if (!destBranchId) throw new HttpError(400, 'Invalid destination branch');

    const originBranchId = (await resolveBranchId(client, data.origin_branch_id)) || vehicle.home_branch_id;

    // 8.7-C06: Transfer cannot begin without departure inspection
    if (!data.departure_inspection) {
      throw new HttpError(400, 'Departure inspection is mandatory before transfer departure (Rule 8.7-R04 / 8.7-C06)');
    }

    const dep = data.departure_inspection;
    const inspRes = await client.query(
      `INSERT INTO fs.vehicle_inspection_transfer (
         vehicle_id, inspection_type_code, origin_branch_id, destination_branch_id,
         fuel_level_code, keys_count, car_cover_included_flag, owner_manual_included_flag,
         trickle_charger_included_flag, exterior_damage_found_flag, interior_damage_found_flag,
         wheels_tires_ok_flag, warning_lights_flag, mechanical_issue_flag,
         transport_damage_flag, inspection_notes, inspector_user_id, inspected_at, created_at, updated_at
       ) VALUES (
         $1, 'Transfer Out', $2, $3,
         $4, $5, $6, $7,
         $8, $9, $10,
         $11, $12, $13,
         FALSE, $14, $15, now(), now(), now()
       ) RETURNING *`,
      [
        vehicleId,
        originBranchId,
        destBranchId,
        dep.fuel_level_code || 'Full',
        dep.keys_count,
        dep.car_cover_included_flag,
        dep.owner_manual_included_flag,
        dep.trickle_charger_included_flag,
        dep.exterior_damage_found_flag,
        dep.interior_damage_found_flag,
        dep.wheels_tires_ok_flag,
        dep.warning_lights_flag,
        dep.mechanical_issue_flag,
        dep.inspection_notes || 'Transfer Out Departure Inspection',
        dep.inspector_user_id || null,
      ]
    );
    const departureInspection = inspRes.rows[0];

    // 8.7-C02: Leaving closes the active location row with an effective end (effective_to = CURRENT_DATE)
    const closeLocRes = await client.query(
      `UPDATE fs.vehicle_location
          SET effective_to = CURRENT_DATE,
              updated_at = now()
        WHERE vehicle_id = $1
          AND effective_to IS NULL
        RETURNING *`,
      [vehicleId]
    );

    // 8.7-C11 & 8.7-C13:
    // - 8.7-C11: The fleet stage is unchanged throughout (vehicle.fleet_stage remains unchanged).
    // - 8.7-C13: A vehicle in transit carries no condition (condition_code = NULL).
    const updateVehRes = await client.query(
      `UPDATE fs.vehicle
          SET condition_code = NULL,
              condition_since = now(),
              updated_at = now()
        WHERE vehicle_id = $1
        RETURNING vehicle_id, vehicle_name, home_branch_id, fleet_stage, condition_code`,
      [vehicleId]
    );

    await client.query(
      `INSERT INTO fs.vehicle_condition_history (
         vehicle_id, condition_code, changed_at, notes
       ) VALUES ($1, NULL, now(), 'In transit for branch transfer')`,
      [vehicleId]
    );

    await recordVehicleShadow(client, vehicleId, `Vehicle departed on transfer. Location closed, condition set to NULL (In Transit)`);

    return {
      vehicle: updateVehRes.rows[0],
      departure_inspection: departureInspection,
      closed_location: closeLocRes.rows[0] || null,
      message: 'Vehicle departed origin branch. In-transit state active.',
    };
  });

  res.status(200).json({ ok: true, ...result });
});

// 3. POST /v1/fleet/:vehicleId/transfers/arrive (8.7-R01, 8.7-R02, 8.7-R05, 8.7-R06, 8.7-R07, 8.7-R08, 8.7-C01, 8.7-C03, 8.7-C04, 8.7-C07, 8.7-C08, 8.7-C09, 8.7-C10, 8.7-C11)
fleetRouter.post('/:vehicleId/transfers/arrive', async (req, res) => {
  const { vehicleId } = req.params;
  const schema = z.object({
    destination_branch_id: z.string(),
    arrival_inspection: z.object({
      keys_count: z.number().int().min(0).default(2),
      fuel_level_code: z.string().optional().default('Full'),
      car_cover_included_flag: z.boolean().default(true),
      owner_manual_included_flag: z.boolean().default(true),
      trickle_charger_included_flag: z.boolean().default(true),
      exterior_damage_found_flag: z.boolean().default(false),
      interior_damage_found_flag: z.boolean().default(false),
      wheels_tires_ok_flag: z.boolean().default(true),
      warning_lights_flag: z.boolean().default(false),
      mechanical_issue_flag: z.boolean().default(false),
      inspection_notes: z.string().optional(),
      inspector_user_id: z.string().uuid().optional(),
    }),
    is_temporary_loan: z.boolean().default(true), // 8.7-R02: Loan = location only; Permanent = home branch too
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const vRes = await client.query(
      `SELECT vehicle_id, vehicle_name, home_branch_id, fleet_stage, condition_code FROM fs.vehicle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
    const vehicle = vRes.rows[0];

    const destBranchId = await resolveBranchId(client, data.destination_branch_id);
    if (!destBranchId) throw new HttpError(400, 'Invalid destination branch');

    // 8.7-R05 / 8.7-C07: Fetch departure inspection for comparison
    const depRes = await client.query(
      `SELECT * FROM fs.vehicle_inspection_transfer
        WHERE vehicle_id = $1 AND inspection_type_code = 'Transfer Out'
        ORDER BY inspected_at DESC LIMIT 1`,
      [vehicleId]
    );
    const dep = depRes.rows[0] || {};

    const arr = data.arrival_inspection;

    // 8.7-R06 / 8.7-C08: Damage present at arrival and absent at departure sets transport damage flag
    const newExtDamage = Boolean(arr.exterior_damage_found_flag && !dep.exterior_damage_found_flag);
    const newIntDamage = Boolean(arr.interior_damage_found_flag && !dep.interior_damage_found_flag);
    const transportDamageFlag = newExtDamage || newIntDamage;

    // 8.7-C09: A missing key is visible in the comparison
    const depKeys = dep.keys_count !== undefined ? Number(dep.keys_count) : 2;
    const arrKeys = Number(arr.keys_count);
    const keysMissingCount = Math.max(0, depKeys - arrKeys);
    const hasMissingKeys = keysMissingCount > 0;

    // Insert Arrival Inspection
    const inspRes = await client.query(
      `INSERT INTO fs.vehicle_inspection_transfer (
         vehicle_id, inspection_type_code, origin_branch_id, destination_branch_id,
         fuel_level_code, keys_count, car_cover_included_flag, owner_manual_included_flag,
         trickle_charger_included_flag, exterior_damage_found_flag, interior_damage_found_flag,
         wheels_tires_ok_flag, warning_lights_flag, mechanical_issue_flag,
         transport_damage_flag, inspection_notes, inspector_user_id, inspected_at, created_at, updated_at
       ) VALUES (
         $1, 'Transfer In', $2, $3,
         $4, $5, $6, $7,
         $8, $9, $10,
         $11, $12, $13,
         $14, $15, $16, now(), now(), now()
       ) RETURNING *`,
      [
        vehicleId,
        dep.origin_branch_id || vehicle.home_branch_id,
        destBranchId,
        arr.fuel_level_code || 'Full',
        arrKeys,
        arr.car_cover_included_flag,
        arr.owner_manual_included_flag,
        arr.trickle_charger_included_flag,
        arr.exterior_damage_found_flag,
        arr.interior_damage_found_flag,
        arr.wheels_tires_ok_flag,
        arr.warning_lights_flag,
        arr.mechanical_issue_flag,
        transportDamageFlag,
        arr.inspection_notes || 'Transfer In Arrival Inspection',
        arr.inspector_user_id || null,
      ]
    );
    const arrivalInspection = inspRes.rows[0];

    // 8.7-C01: Arriving at a branch opens a location row (effective_to = NULL)
    const targetHomeBranchId = data.is_temporary_loan ? vehicle.home_branch_id : destBranchId;
    const locRes = await client.query(
      `INSERT INTO fs.vehicle_location (
         vehicle_id, home_branch_id, current_branch_id, effective_from, effective_to, created_at, updated_at
       ) VALUES ($1, $2, $3, CURRENT_DATE, NULL, now(), now())
       RETURNING *`,
      [vehicleId, targetHomeBranchId, destBranchId]
    );

    // 8.7-C03 / 8.7-C04 / 8.7-C10 / 8.7-C11:
    // - 8.7-C03: Temporary loan leaves home branch unchanged
    // - 8.7-C04: Permanent reassignment changes home branch
    // - 8.7-C10: Vehicle arrives at condition Arrived
    // - 8.7-C11: Fleet stage unchanged throughout (remains 'Fleet')
    const updateVehRes = await client.query(
      `UPDATE fs.vehicle
          SET home_branch_id = $1,
              condition_code = 'Arrived',
              condition_since = now(),
              updated_at = now()
        WHERE vehicle_id = $2
        RETURNING vehicle_id, vehicle_name, home_branch_id, fleet_stage, condition_code`,
      [targetHomeBranchId, vehicleId]
    );

    await client.query(
      `INSERT INTO fs.vehicle_condition_history (
         vehicle_id, condition_code, changed_at, notes
       ) VALUES ($1, 'Arrived', now(), 'Arrived at branch from transfer')`,
      [vehicleId]
    );

    await recordVehicleShadow(
      client,
      vehicleId,
      `Vehicle arrived at branch. Location opened, condition=Arrived, home_branch=${targetHomeBranchId}`
    );

    return {
      vehicle: updateVehRes.rows[0],
      arrival_inspection: arrivalInspection,
      departure_inspection: dep,
      comparison: {
        transport_damage_flag: transportDamageFlag,
        new_exterior_damage: newExtDamage,
        new_interior_damage: newIntDamage,
        keys_departure: depKeys,
        keys_arrival: arrKeys,
        keys_missing: keysMissingCount,
        has_missing_keys: hasMissingKeys,
      },
      opened_location: locRes.rows[0],
      is_temporary_loan: data.is_temporary_loan,
      message: 'Vehicle arrived successfully. Arrival inspection recorded and comparison generated.',
    };
  });

  res.status(200).json({ ok: true, ...result });
});

// 4. GET /v1/fleet/:vehicleId/locations (Location history)
fleetRouter.get('/:vehicleId/locations', async (req, res) => {
  const { vehicleId } = req.params;
  const locs = await query(
    `SELECT vl.vehicle_location_id, vl.vehicle_id, vl.home_branch_id, vl.current_branch_id,
            vl.effective_from::text AS effective_from, vl.effective_to::text AS effective_to,
            hb.branch_name AS home_branch_name, hb.branch_code AS home_branch_code,
            cb.branch_name AS current_branch_name, cb.branch_code AS current_branch_code,
            (vl.effective_to IS NULL) AS is_current
       FROM fs.vehicle_location vl
       LEFT JOIN fs.branch hb ON hb.branch_id = vl.home_branch_id
       LEFT JOIN fs.branch cb ON cb.branch_id = vl.current_branch_id
      WHERE vl.vehicle_id = $1
      ORDER BY vl.effective_from DESC, vl.created_at DESC`,
    [vehicleId]
  );
  res.json({
    ok: true,
    vehicle_id: vehicleId,
    current_location: locs.rows.find((l) => l.is_current) || null,
    locations: locs.rows,
  });
});

// =============================================================================
// GUIDE 8.8: Vehicle Lifecycle and Financing (Routes)
// =============================================================================

// GET /v1/fleet/:vehicleId/financing (8.8-C01, 8.8-C02, 8.8-C04, 8.8-C05, 8.8-C06, 8.8-C07, 8.8-C08, 8.8-C09, 8.8-C10, 8.8-C15, 8.8-C16, 8.8-C17)
fleetRouter.get('/:vehicleId/financing', async (req, res) => {
  const { vehicleId } = req.params;
  const { hasFinancePerm } = checkFinancingAccess(req);

  const vRes = await query(
    `SELECT vehicle_id, vehicle_name, vin, fleet_stage, condition_code FROM fs.vehicle WHERE vehicle_id = $1`,
    [vehicleId]
  );
  if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');
  const vehicle = vRes.rows[0];

  const odoRes = await query(
    `SELECT odometer_value FROM fs.vehicle_odometer_log WHERE vehicle_id = $1 ORDER BY COALESCE(effective_at, captured_at, created_at) DESC LIMIT 1`,
    [vehicleId]
  );
  const currentOdometer = odoRes.rowCount > 0 ? odoRes.rows[0].odometer_value : 0;

  const finRes = await query(
    `SELECT * FROM fs.vehicle_financing_lifecycle WHERE vehicle_id = $1`,
    [vehicleId]
  );

  if (finRes.rowCount === 0) {
    return res.json({
      ok: true,
      vehicle_id: vehicleId,
      vehicle_name: vehicle.vehicle_name,
      has_financing: false,
      financing: null,
      history: [],
      watching: null,
    });
  }

  const fin = finRes.rows[0];
  const watching = computeSurfacingAndWatching(fin, currentOdometer);

  // Fetch shadow history (8.8-C03)
  const historyRes = await query(
    `SELECT * FROM fs.vehicle_financing_lifecycle_shadow
      WHERE vehicle_id = $1
      ORDER BY valid_to DESC, changed_at DESC`,
    [vehicleId]
  );
  const history = historyRes.rows.map((h) => redactFinancialFields(h, hasFinancePerm));
  const maskedFin = redactFinancialFields(fin, hasFinancePerm);

  res.json({
    ok: true,
    vehicle_id: vehicleId,
    vehicle_name: vehicle.vehicle_name,
    has_financing: true,
    financing: maskedFin,
    history: history,
    watching: watching,
  });
});

// POST /v1/fleet/:vehicleId/financing (8.8-C01, 8.8-C02, 8.8-C04, 8.8-C08, 8.8-C16, 8.8-C17)
fleetRouter.post('/:vehicleId/financing', async (req, res) => {
  const { vehicleId } = req.params;
  const { hasFinancePerm } = checkFinancingAccess(req);

  const vRes = await query(`SELECT vehicle_id, vehicle_name FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
  if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');

  const schema = z.object({
    finance_type: z.enum(['Cash', 'Loan', 'Lease', 'Floorplan', 'VOP', 'Other']),
    finance_term_months: z.number().int().positive().nullable().optional(),
    lender_lessor: z.string().max(160).nullable().optional(),
    guarantor: z.string().max(160).nullable().optional(),
    purchase_date: z.string().nullable().optional(),
    purchase_price: z.number().int().positive().nullable().optional(),
    end_target_date: z.string().nullable().optional(),
    end_date_is_committed: z.boolean().default(false),
    end_commitment_note: z.string().max(200).nullable().optional(),
    end_target_mileage: z.number().int().positive().nullable().optional(),
    end_target_value: z.number().int().positive().nullable().optional(),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const existing = await client.query(
      `SELECT * FROM fs.vehicle_financing_lifecycle WHERE vehicle_id = $1`,
      [vehicleId]
    );

    let saved;
    if (existing.rowCount > 0) {
      await recordFinancingShadow(client, existing.rows[0], 'Financing record updated');
      const updateRes = await client.query(
        `UPDATE fs.vehicle_financing_lifecycle
            SET finance_type = $1,
                finance_term_months = $2,
                lender_lessor = $3,
                guarantor = $4,
                purchase_date = $5,
                purchase_price = $6,
                end_target_date = $7,
                end_date_is_committed = $8,
                end_commitment_note = $9,
                end_target_mileage = $10,
                end_target_value = $11,
                updated_at = now()
          WHERE vehicle_id = $12
          RETURNING *`,
        [
          data.finance_type,
          data.finance_term_months ?? null,
          data.lender_lessor ?? null,
          data.guarantor ?? null,
          data.purchase_date ?? null,
          data.purchase_price ?? null,
          data.end_target_date ?? null,
          data.end_date_is_committed ?? false,
          data.end_commitment_note ?? null,
          data.end_target_mileage ?? null,
          data.end_target_value ?? null,
          vehicleId,
        ]
      );
      saved = updateRes.rows[0];
    } else {
      const insertRes = await client.query(
        `INSERT INTO fs.vehicle_financing_lifecycle (
           vehicle_id, finance_type, finance_term_months, lender_lessor, guarantor,
           purchase_date, purchase_price, end_target_date, end_date_is_committed,
           end_commitment_note, end_target_mileage, end_target_value, created_at, updated_at
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, now(), now())
         RETURNING *`,
        [
          vehicleId,
          data.finance_type,
          data.finance_term_months ?? null,
          data.lender_lessor ?? null,
          data.guarantor ?? null,
          data.purchase_date ?? null,
          data.purchase_price ?? null,
          data.end_target_date ?? null,
          data.end_date_is_committed ?? false,
          data.end_commitment_note ?? null,
          data.end_target_mileage ?? null,
          data.end_target_value ?? null,
        ]
      );
      saved = insertRes.rows[0];
    }

    await recordVehicleShadow(client, vehicleId, `Financing configured: ${data.finance_type}`);
    return saved;
  });

  res.status(200).json({
    ok: true,
    financing: redactFinancialFields(result, hasFinancePerm),
    message: 'Financing record saved successfully',
  });
});

// POST /v1/fleet/:vehicleId/financing/revise-targets (8.8-C03)
fleetRouter.post('/:vehicleId/financing/revise-targets', async (req, res) => {
  const { vehicleId } = req.params;
  const { hasFinancePerm } = checkFinancingAccess(req);

  const schema = z.object({
    end_target_date: z.string().optional(),
    end_target_mileage: z.number().int().positive().optional(),
    end_target_value: z.number().int().positive().optional(),
    end_date_is_committed: z.boolean().optional(),
    end_commitment_note: z.string().max(200).optional(),
    change_reason: z.string().default('Target revision'),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const existingRes = await client.query(
      `SELECT * FROM fs.vehicle_financing_lifecycle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    if (existingRes.rowCount === 0) {
      throw new HttpError(404, 'Vehicle financing record not found');
    }
    const existing = existingRes.rows[0];

    // 8.8-C03: A target revision writes a shadow row preserving the original
    await recordFinancingShadow(client, existing, data.change_reason || 'Target revision');

    const updateRes = await client.query(
      `UPDATE fs.vehicle_financing_lifecycle
          SET end_target_date = COALESCE($1, end_target_date),
              end_target_mileage = COALESCE($2, end_target_mileage),
              end_target_value = COALESCE($3, end_target_value),
              end_date_is_committed = COALESCE($4, end_date_is_committed),
              end_commitment_note = COALESCE($5, end_commitment_note),
              updated_at = now()
        WHERE vehicle_id = $6
        RETURNING *`,
      [
        data.end_target_date ?? null,
        data.end_target_mileage ?? null,
        data.end_target_value ?? null,
        data.end_date_is_committed ?? null,
        data.end_commitment_note ?? null,
        vehicleId,
      ]
    );

    await recordVehicleShadow(client, vehicleId, `Target revision: ${data.change_reason}`);

    return updateRes.rows[0];
  });

  res.json({
    ok: true,
    financing: redactFinancialFields(result, hasFinancePerm),
    shadow_recorded: true,
    message: 'Targets revised and shadow record created successfully',
  });
});

// POST /v1/fleet/:vehicleId/dispose (8.8-C11, 8.8-C12, 8.8-C13, 8.8-C14, 8.8-C15)
fleetRouter.post('/:vehicleId/dispose', async (req, res) => {
  const { vehicleId } = req.params;
  const { hasFinancePerm } = checkFinancingAccess(req);

  const schema = z.object({
    disposal_type: z.enum(['Sale', 'LeaseReturn']),
    disposal_date: z.string(),
    sale_price: z.number().int().positive().nullable().optional(),
    notes: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const vRes = await client.query(
      `SELECT vehicle_id, vehicle_name, fleet_stage, condition_code FROM fs.vehicle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');

    const finRes = await client.query(
      `SELECT * FROM fs.vehicle_financing_lifecycle WHERE vehicle_id = $1`,
      [vehicleId]
    );
    if (finRes.rowCount === 0) throw new HttpError(404, 'Financing record not found for vehicle');
    const fin = finRes.rows[0];

    // 8.8-C12: A lease return is distinguishable from a sale and does not record a price of zero (sale_price MUST be NULL)
    let finalSalePrice = null;
    if (data.disposal_type === 'Sale') {
      if (data.sale_price == null) {
        throw new HttpError(400, 'Sale disposal requires sale_price');
      }
      finalSalePrice = data.sale_price;
    } else {
      finalSalePrice = null;
    }

    // Record shadow before disposal
    await recordFinancingShadow(client, fin, `Disposal: ${data.disposal_type}`);

    // Update financing record
    const updateFinRes = await client.query(
      `UPDATE fs.vehicle_financing_lifecycle
          SET sale_date = $1,
              sale_price = $2,
              disposal_type = $3,
              updated_at = now()
        WHERE vehicle_id = $4
        RETURNING *`,
      [data.disposal_date, finalSalePrice, data.disposal_type, vehicleId]
    );
    const updatedFin = updateFinRes.rows[0];

    // 8.8-C11 / 8.8-C13: Update vehicle status to Retired; vehicle is NEVER deleted
    const updateVehRes = await client.query(
      `UPDATE fs.vehicle
          SET fleet_stage = 'Retired',
              condition_code = NULL,
              notes = COALESCE(notes || E'\n', '') || $1,
              updated_at = now()
        WHERE vehicle_id = $2
        RETURNING vehicle_id, vehicle_name, fleet_stage, condition_code`,
      [`Disposed via ${data.disposal_type} on ${data.disposal_date}: ${data.notes || ''}`.trim(), vehicleId]
    );

    // 8.8-C14: Rate card placements survive disposal so historical trips still price (verified by leaving fs.rate_card_placement intact)

    // Record vehicle shadow
    await recordVehicleShadow(client, vehicleId, `Vehicle disposed via ${data.disposal_type} on ${data.disposal_date}`);

    // 8.8-C15: Valuation variance reportable
    let valuationVariance = null;
    let valuationVariancePct = null;
    if (finalSalePrice != null && updatedFin.end_target_value != null) {
      valuationVariance = finalSalePrice - updatedFin.end_target_value;
      valuationVariancePct = updatedFin.end_target_value > 0
        ? Number(((valuationVariance / updatedFin.end_target_value) * 100).toFixed(2))
        : 0;
    }

    return {
      vehicle: updateVehRes.rows[0],
      financing: redactFinancialFields(updatedFin, hasFinancePerm),
      disposal_type: data.disposal_type,
      disposal_date: data.disposal_date,
      sale_price: finalSalePrice,
      is_deleted: false,
      valuation_variance: valuationVariance,
      valuation_variance_pct: valuationVariancePct,
    };
  });

  res.json({
    ok: true,
    ...result,
    message: `Vehicle disposed successfully via ${data.disposal_type}. Vehicle preserved with fleet_stage='Retired'.`,
  });
});

// =============================================================================
// GUIDE 8.9: Vehicle Mileage Allowance (Routes)
// =============================================================================

function checkMileageManagementAccess(req) {
  const role = req.headers['x-user-role'] || req.user?.role || req.query.role;
  const perms = req.headers['x-user-permissions'] || '';
  const isMember = role === 'member' || req.query.as_member === 'true';
  if (isMember) {
    throw new HttpError(403, 'Members cannot manage or view vehicle mileage allowance');
  }

  // 8.9-R01: Setting or editing an allowance requires manage_vehicle_mileage, held by managers and above
  const hasPerm =
    role === 'admin' ||
    role === 'manager' ||
    perms.includes('manage_vehicle_mileage') ||
    perms.includes('manage_fleet');

  if (!hasPerm) {
    throw new HttpError(403, '8.9-R01: Setting or editing an allowance requires manage_vehicle_mileage');
  }
}

// GET /v1/fleet/:vehicleId/mileage-allowance (8.9-C01, 8.9-R04)
fleetRouter.get('/:vehicleId/mileage-allowance', async (req, res) => {
  const { vehicleId } = req.params;

  const vRes = await query(`SELECT vehicle_id, vehicle_name FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
  if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');

  const allowRes = await query(
    `SELECT * FROM fs.vehicle_mileage_allowance WHERE vehicle_id = $1 AND is_active = TRUE`,
    [vehicleId]
  );

  // 8.9-C01 / 8.9-R04: A vehicle with no allowance is never withheld for mileage. Absence is the normal case.
  if (allowRes.rowCount === 0) {
    return res.json({
      ok: true,
      vehicle_id: vehicleId,
      vehicle_name: vRes.rows[0].vehicle_name,
      has_allowance: false,
      is_unlimited: true,
      withheld_for_mileage: false,
      allowance: null,
      allocations: [],
    });
  }

  const allowance = allowRes.rows[0];

  const allocRes = await query(
    `SELECT * FROM fs.vehicle_mileage_allocation
      WHERE vehicle_id = $1
      ORDER BY allocated_on ASC, created_at ASC`,
    [vehicleId]
  );
  const allocations = allocRes.rows;

  const latestAlloc = allocations.length > 0 ? allocations[allocations.length - 1] : null;
  const currentLimit = latestAlloc ? latestAlloc.odometer_limit : allowance.starting_odometer;

  const odoRes = await query(
    `SELECT odometer_value FROM fs.vehicle_odometer_log WHERE vehicle_id = $1 ORDER BY COALESCE(effective_at, captured_at, created_at) DESC LIMIT 1`,
    [vehicleId]
  );
  const currentOdometer = odoRes.rowCount > 0 ? odoRes.rows[0].odometer_value : allowance.starting_odometer;

  // Check active mileage withhold
  const withRes = await query(
    `SELECT * FROM fs.reservation_withhold
      WHERE vehicle_id = $1
        AND withhold_reason_code = 'MileageLimit'
        AND released_at IS NULL`,
    [vehicleId]
  );
  const isWithheldForMileage = withRes.rowCount > 0;

  const threshold = allowance.withhold_threshold_miles || 0;
  const milesOver = Math.max(0, currentOdometer - currentLimit);
  const exceedsThreshold = currentOdometer > (currentLimit + threshold);

  res.json({
    ok: true,
    vehicle_id: vehicleId,
    vehicle_name: vRes.rows[0].vehicle_name,
    has_allowance: true,
    is_unlimited: false,
    allowance: allowance,
    allocations: allocations,
    current_odometer: currentOdometer,
    current_odometer_limit: currentLimit,
    threshold: threshold,
    miles_over: milesOver,
    exceeds_threshold: exceedsThreshold,
    withheld_for_mileage: isWithheldForMileage,
    withhold: isWithheldForMileage ? withRes.rows[0] : null,
  });
});

// POST /v1/fleet/:vehicleId/mileage-allowance (8.9-C02, 8.9-R01)
fleetRouter.post('/:vehicleId/mileage-allowance', async (req, res) => {
  const { vehicleId } = req.params;
  checkMileageManagementAccess(req);

  const schema = z.object({
    monthly_miles: z.number().int().positive(),
    effective_start: z.string(),
    starting_odometer: z.number().int().nonnegative(),
    withhold_threshold_miles: z.number().int().nonnegative().default(0),
    notes: z.string().optional(),
  });
  const data = schema.parse(req.body);

  const result = await withTransaction(async (client) => {
    const vRes = await client.query(`SELECT vehicle_id, vehicle_name FROM fs.vehicle WHERE vehicle_id = $1`, [vehicleId]);
    if (vRes.rowCount === 0) throw new HttpError(404, 'Vehicle not found');

    // Upsert into fs.vehicle_mileage_allowance
    const allowRes = await client.query(
      `INSERT INTO fs.vehicle_mileage_allowance (
         vehicle_id, monthly_miles, effective_start, starting_odometer,
         withhold_threshold_miles, is_active, notes, updated_at
       ) VALUES ($1, $2, $3, $4, $5, TRUE, $6, now())
       ON CONFLICT (vehicle_id) DO UPDATE SET
         monthly_miles = EXCLUDED.monthly_miles,
         effective_start = EXCLUDED.effective_start,
         starting_odometer = EXCLUDED.starting_odometer,
         withhold_threshold_miles = EXCLUDED.withhold_threshold_miles,
         is_active = TRUE,
         notes = EXCLUDED.notes,
         updated_at = now()
       RETURNING *`,
      [
        vehicleId,
        data.monthly_miles,
        data.effective_start,
        data.starting_odometer,
        data.withhold_threshold_miles,
        data.notes || null,
      ]
    );
    const allowance = allowRes.rows[0];

    // 8.9-C02: The first allocation sets the limit to the starting odometer plus one month
    const existingAlloc = await client.query(
      `SELECT * FROM fs.vehicle_mileage_allocation WHERE vehicle_id = $1`,
      [vehicleId]
    );

    let firstAlloc = null;
    if (existingAlloc.rowCount === 0) {
      const initialLimit = data.starting_odometer + data.monthly_miles;
      const allocRes = await client.query(
        `INSERT INTO fs.vehicle_mileage_allocation (
           vehicle_mileage_allowance_id, vehicle_id, allocated_on, miles_allocated,
           odometer_limit, odometer_at_allocation, miles_over_at_allocation, created_at, updated_at
         ) VALUES ($1, $2, $3, $4, $5, $6, 0, now(), now())
         RETURNING *`,
        [
          allowance.vehicle_mileage_allowance_id,
          vehicleId,
          data.effective_start,
          data.monthly_miles,
          initialLimit,
          data.starting_odometer,
        ]
      );
      firstAlloc = allocRes.rows[0];
    }

    await recordVehicleShadow(
      client,
      vehicleId,
      `Mileage allowance configured: ${data.monthly_miles} mi/mo, start odo=${data.starting_odometer}`
    );

    return {
      allowance,
      first_allocation: firstAlloc,
    };
  });

  res.status(201).json({
    ok: true,
    ...result,
    message: 'Vehicle mileage allowance configured and initial allocation posted.',
  });
});

// POST /v1/fleet/:vehicleId/mileage-allowance/allocate (8.9-C03, 8.9-C05, 8.9-R06)
fleetRouter.post('/:vehicleId/mileage-allowance/allocate', async (req, res) => {
  const { vehicleId } = req.params;
  checkMileageManagementAccess(req);

  const schema = z.object({
    allocated_on: z.string().optional(),
    current_odometer: z.number().int().optional(),
  });
  const data = schema.parse(req.body || {});

  const result = await withTransaction(async (client) => {
    const allowRes = await client.query(
      `SELECT * FROM fs.vehicle_mileage_allowance WHERE vehicle_id = $1 AND is_active = TRUE`,
      [vehicleId]
    );
    if (allowRes.rowCount === 0) throw new HttpError(404, 'Active mileage allowance not found for vehicle');
    const allowance = allowRes.rows[0];

    const latestAllocRes = await client.query(
      `SELECT * FROM fs.vehicle_mileage_allocation
        WHERE vehicle_id = $1
        ORDER BY allocated_on DESC, created_at DESC
        LIMIT 1`,
      [vehicleId]
    );

    const prevLimit = latestAllocRes.rowCount > 0
      ? latestAllocRes.rows[0].odometer_limit
      : allowance.starting_odometer;

    // 8.9-C03: A month with no driving still posts an allocation and raises the limit
    const newLimit = prevLimit + allowance.monthly_miles;

    let currentOdo = data.current_odometer;
    if (currentOdo == null) {
      const odoRes = await client.query(
        `SELECT odometer_value FROM fs.vehicle_odometer_log WHERE vehicle_id = $1 ORDER BY COALESCE(effective_at, captured_at, created_at) DESC LIMIT 1`,
        [vehicleId]
      );
      currentOdo = odoRes.rowCount > 0 ? odoRes.rows[0].odometer_value : prevLimit;
    }

    const milesOver = Math.max(0, currentOdo - newLimit);

    const allocDate = data.allocated_on || new Date().toISOString().split('T')[0];
    const allocInsertRes = await client.query(
      `INSERT INTO fs.vehicle_mileage_allocation (
         vehicle_mileage_allowance_id, vehicle_id, allocated_on, miles_allocated,
         odometer_limit, odometer_at_allocation, miles_over_at_allocation, created_at, updated_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, now(), now())
       RETURNING *`,
      [
        allowance.vehicle_mileage_allowance_id,
        vehicleId,
        allocDate,
        allowance.monthly_miles,
        newLimit,
        currentOdo,
        milesOver,
      ]
    );
    const newAlloc = allocInsertRes.rows[0];

    // Evaluate withhold
    const threshold = allowance.withhold_threshold_miles || 0;
    const existingWithhold = await client.query(
      `SELECT * FROM fs.reservation_withhold
        WHERE vehicle_id = $1
          AND withhold_reason_code = 'MileageLimit'
          AND released_at IS NULL`,
      [vehicleId]
    );

    let isWithheld = existingWithhold.rowCount > 0;
    let withholdAction = 'none';

    if (currentOdo > (newLimit + threshold)) {
      // 8.9-C04 / 8.9-C05: A vehicle passing its limit by more than the threshold is withheld, and stays withheld
      if (!isWithheld) {
        await client.query(
          `INSERT INTO fs.reservation_withhold (
             vehicle_id, withhold_reason_code, starts_on, withhold_note, placed_at
           ) VALUES ($1, 'MileageLimit', CURRENT_DATE, 'Automatic withhold: mileage limit exceeded', now())`,
          [vehicleId]
        );
        isWithheld = true;
        withholdAction = 'placed';
      } else {
        // 8.9-C05: A vehicle more than one month over stays withheld through the next allocation
        withholdAction = 'retained';
      }
    } else {
      // Within limit: release mileage withhold if active (8.9-C06: only releases MileageLimit withhold)
      if (isWithheld) {
        await client.query(
          `UPDATE fs.reservation_withhold
              SET released_at = now(),
                  release_note = 'Odometer returned within limit after monthly allocation'
            WHERE reservation_withhold_id = $1`,
          [existingWithhold.rows[0].reservation_withhold_id]
        );
        isWithheld = false;
        withholdAction = 'released';
      }
    }

    await recordVehicleShadow(
      client,
      vehicleId,
      `Monthly allocation posted (+${allowance.monthly_miles} mi). New limit=${newLimit}. Withhold=${withholdAction}`
    );

    return {
      allocation: newAlloc,
      new_odometer_limit: newLimit,
      current_odometer: currentOdo,
      is_withheld: isWithheld,
      withhold_action: withholdAction,
    };
  });

  res.json({
    ok: true,
    ...result,
    message: 'Monthly allocation posted successfully.',
  });
});

// POST /v1/fleet/:vehicleId/mileage-allowance/check-limit (8.9-C01, 8.9-C04, 8.9-C06, 8.9-R03)
fleetRouter.post('/:vehicleId/mileage-allowance/check-limit', async (req, res) => {
  const { vehicleId } = req.params;

  const schema = z.object({
    odometer: z.number().int().optional(),
  });
  const data = schema.parse(req.body || {});

  const result = await withTransaction(async (client) => {
    const allowRes = await client.query(
      `SELECT * FROM fs.vehicle_mileage_allowance WHERE vehicle_id = $1 AND is_active = TRUE`,
      [vehicleId]
    );

    // 8.9-C01: A vehicle with no allowance is never withheld for mileage
    if (allowRes.rowCount === 0) {
      return {
        has_allowance: false,
        is_unlimited: true,
        withheld_for_mileage: false,
        message: '8.9-C01: Vehicle has no mileage allowance and is unlimited.',
      };
    }
    const allowance = allowRes.rows[0];

    let currentOdo = data.odometer;
    if (currentOdo == null) {
      const odoRes = await client.query(
        `SELECT odometer_value FROM fs.vehicle_odometer_log WHERE vehicle_id = $1 ORDER BY COALESCE(effective_at, captured_at, created_at) DESC LIMIT 1`,
        [vehicleId]
      );
      currentOdo = odoRes.rowCount > 0 ? odoRes.rows[0].odometer_value : allowance.starting_odometer;
    }

    const latestAllocRes = await client.query(
      `SELECT * FROM fs.vehicle_mileage_allocation
        WHERE vehicle_id = $1
        ORDER BY allocated_on DESC, created_at DESC
        LIMIT 1`,
      [vehicleId]
    );
    const currentLimit = latestAllocRes.rowCount > 0 ? latestAllocRes.rows[0].odometer_limit : allowance.starting_odometer;
    const threshold = allowance.withhold_threshold_miles || 0;

    const existingWithhold = await client.query(
      `SELECT * FROM fs.reservation_withhold
        WHERE vehicle_id = $1
          AND withhold_reason_code = 'MileageLimit'
          AND released_at IS NULL`,
      [vehicleId]
    );

    let isWithheld = existingWithhold.rowCount > 0;
    let action = 'none';

    // 8.9-C04: A vehicle passing its limit by more than the threshold is withheld, and existing reservations survive
    if (currentOdo > (currentLimit + threshold)) {
      if (!isWithheld) {
        await client.query(
          `INSERT INTO fs.reservation_withhold (
             vehicle_id, withhold_reason_code, starts_on, withhold_note, placed_at
           ) VALUES ($1, 'MileageLimit', CURRENT_DATE, 'Automatic withhold: mileage limit exceeded', now())`,
          [vehicleId]
        );
        isWithheld = true;
        action = 'withheld';
      }
    } else {
      // 8.9-C06: Releasing the mileage withhold does not release a withhold placed for another reason
      if (isWithheld) {
        await client.query(
          `UPDATE fs.reservation_withhold
              SET released_at = now(),
                  release_note = 'Odometer returned within limit'
            WHERE reservation_withhold_id = $1`,
          [existingWithhold.rows[0].reservation_withhold_id]
        );
        isWithheld = false;
        action = 'released';
      }
    }

    return {
      has_allowance: true,
      current_odometer: currentOdo,
      odometer_limit: currentLimit,
      threshold: threshold,
      withheld_for_mileage: isWithheld,
      action: action,
      existing_reservations_survived: true,
    };
  });

  res.json({ ok: true, ...result });
});

// POST /v1/fleet/:vehicleId/mileage-allowance/release-withhold (8.9-C06)
fleetRouter.post('/:vehicleId/mileage-allowance/release-withhold', async (req, res) => {
  const { vehicleId } = req.params;
  checkMileageManagementAccess(req);

  const schema = z.object({
    release_note: z.string().optional().default('Manual mileage withhold release'),
  });
  const data = schema.parse(req.body || {});

  // 8.9-C06: Releasing the mileage withhold does not release a withhold placed for another reason.
  const releaseRes = await query(
    `UPDATE fs.reservation_withhold
        SET released_at = now(),
            release_note = $1
      WHERE vehicle_id = $2
        AND withhold_reason_code = 'MileageLimit'
        AND released_at IS NULL
      RETURNING *`,
    [data.release_note, vehicleId]
  );

  // Check if other withholds remain
  const otherWithholds = await query(
    `SELECT rw.*, rwrs.label
       FROM fs.reservation_withhold rw
       LEFT JOIN fs.reservation_withhold_reason_select rwrs ON rwrs.withhold_reason_code = rw.withhold_reason_code
      WHERE rw.vehicle_id = $1
        AND rw.withhold_reason_code != 'MileageLimit'
        AND rw.released_at IS NULL`,
    [vehicleId]
  );

  res.json({
    ok: true,
    released_mileage_withholds: releaseRes.rows,
    other_active_withholds: otherWithholds.rows,
    other_withholds_intact: otherWithholds.rowCount > 0,
    message: 'Mileage withhold released. Any withholds for other reasons remain intact.',
  });
});


