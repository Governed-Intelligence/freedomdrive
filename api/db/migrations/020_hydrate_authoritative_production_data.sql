-- =============================================================================
-- Migration 020: Hydrate Authoritative Production Data
-- 15 Vehicles, 22 Houston Service Vendors, and 11 Authoritative Members
-- =============================================================================

BEGIN;

-- Update sync trigger to prevent member_member_number_key duplicate violations
CREATE OR REPLACE FUNCTION fs.sync_members_to_member()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.member_number IS NOT NULL THEN
    UPDATE fs.member SET member_number = NULL
     WHERE member_number = NEW.member_number AND member_id <> NEW.id;
  END IF;

  INSERT INTO fs.member (
      member_id, member_number, first_name, middle_name, last_name,
      license_number, license_state, license_expires_on,
      date_of_birth, member_since, home_branch_id, lifecycle_status,
      created_at, updated_at
  ) VALUES (
      NEW.id, NEW.member_number, NEW.first_name, NEW.middle_name, NEW.last_name,
      NEW.drivers_license_number, NEW.drivers_license_state, NEW.drivers_license_expires,
      NEW.date_of_birth, NEW.joined_on, NEW.primary_location_id,
      CASE
        WHEN NEW.status::text = 'active' THEN 'Active'::fs.member_lifecycle_status_enum
        WHEN NEW.status::text IN ('former', 'expired') THEN 'Former'::fs.member_lifecycle_status_enum
        WHEN NEW.status::text IN ('cancelled', 'suspended') THEN 'Inactive'::fs.member_lifecycle_status_enum
        ELSE 'Pending'::fs.member_lifecycle_status_enum
      END,
      NEW.created_at, NEW.updated_at
  )
  ON CONFLICT (member_id) DO UPDATE SET
      first_name = EXCLUDED.first_name,
      middle_name = EXCLUDED.middle_name,
      last_name = EXCLUDED.last_name,
      member_number = EXCLUDED.member_number,
      license_number = EXCLUDED.license_number,
      license_state = EXCLUDED.license_state,
      license_expires_on = EXCLUDED.license_expires_on,
      date_of_birth = EXCLUDED.date_of_birth,
      member_since = EXCLUDED.member_since,
      lifecycle_status = EXCLUDED.lifecycle_status,
      updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    v_hou_id UUID;
    v_plan_15 UUID;
    v_plan_30 UUID;
    v_plan_60 UUID;
    v_plan_100 UUID;
    r RECORD;
BEGIN
    SELECT id INTO v_hou_id FROM fs.locations WHERE code = 'HOU';
    IF v_hou_id IS NULL THEN
        INSERT INTO fs.locations (code, name, address_line1, city, state, postal_code, is_active)
        VALUES ('HOU', 'Houston Club & Fleet Depot', '9950 Brittmoore Park Dr', 'Houston', 'TX', '77041', TRUE)
        RETURNING id INTO v_hou_id;
    END IF;

    -- Ensure canonical plans exist
    SELECT id INTO v_plan_15 FROM fs.plans WHERE code = 'PLAN_15';
    SELECT id INTO v_plan_30 FROM fs.plans WHERE code = 'PLAN_30';
    SELECT id INTO v_plan_60 FROM fs.plans WHERE code = 'PLAN_60';
    SELECT id INTO v_plan_100 FROM fs.plans WHERE code = 'PLAN_100';

    -- -------------------------------------------------------------------------
    -- 0. Ensure Vendor Type Lookups Exist
    -- -------------------------------------------------------------------------
    INSERT INTO fs.vendor_type_select (vendor_type_code, vendor_type_name, is_active)
    VALUES
      ('Maintenance', 'Maintenance', TRUE),
      ('Detailing', 'Detailing', TRUE),
      ('Catering', 'Catering', TRUE),
      ('Cleaning', 'Cleaning', TRUE),
      ('Insurance', 'Insurance', TRUE),
      ('Transport', 'Transport', TRUE),
      ('Delivery', 'Delivery', TRUE),
      ('Authorized Dealer', 'Authorized Dealer', TRUE),
      ('Specialty Performance', 'Specialty Performance', TRUE),
      ('Exotic Tuning & Prep', 'Exotic Tuning & Prep', TRUE),
      ('Exotic & Classic Service', 'Exotic & Classic Service', TRUE),
      ('Independent European', 'Independent European', TRUE),
      ('Collision & Body', 'Collision & Body', TRUE),
      ('Cosmetic Protection', 'Cosmetic Protection', TRUE),
      ('Tire Specialist', 'Tire Specialist', TRUE),
      ('Glass Defense', 'Glass Defense', TRUE),
      ('Logistics & Towing', 'Logistics & Towing', TRUE),
      ('Internal Division', 'Internal Division', TRUE)
    ON CONFLICT (vendor_type_code) DO NOTHING;

    -- -------------------------------------------------------------------------
    -- 1. Hydrate 15 Authoritative Fleet Vehicles (Houston)
    -- -------------------------------------------------------------------------
    -- Clean up synthetic scratch vehicles with NULL stock_numbers from tests
    DELETE FROM fs.vehicles WHERE stock_number IS NULL;

    -- Upsert the 15 Authoritative Vehicles
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 2450, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-001';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 3100, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-002';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 4200, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-003';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 5800, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-004';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 1400, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-005';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 2800, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-006';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 6200, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-007';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 3900, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-008';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 7500, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-009';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 4100, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-010';
    -- Deduplicated Urus: ensure single active row
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 5300, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-011';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 6800, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-012';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 3200, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-013';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 1950, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-014';
    UPDATE fs.vehicles SET status = 'available', condition = 'excellent', location_id = v_hou_id, current_mileage = 4800, is_member_visible = TRUE WHERE stock_number = 'FS-HOU-017';

    -- -------------------------------------------------------------------------
    -- 2. Hydrate 22 Real Houston Service Vendors
    -- -------------------------------------------------------------------------
    INSERT INTO fs.vendor (vendor_name, vendor_type_code, home_branch_id, vendor_phone, vendor_email, address_line1, city, state, postal_code, is_active, notes)
    VALUES
      ('Audi Houston North', 'Authorized Dealer', v_hou_id, '(281) 598-4900', 'service@audihoustonnorth.com', '18111 North Fwy', 'Houston', 'TX', '77090', TRUE, 'Factory warranty, annual service & brake fluid specialist'),
      ('Porsche River Oaks', 'Authorized Dealer', v_hou_id, '(713) 423-3500', 'service@porscheriveroaks.com', '4007 Greenbriar Dr', 'Houston', 'TX', '77098', TRUE, 'Porsche maintenance & performance inspections'),
      ('Porsche North Houston', 'Authorized Dealer', v_hou_id, '(281) 944-2122', 'service@porschenorthhouston.com', '13911 North Fwy', 'Houston', 'TX', '77090', TRUE, 'GT series alignment & factory recall servicing'),
      ('Ferrari of Houston', 'Authorized Dealer', v_hou_id, '(713) 772-3868', 'service@ferrariofhouston.com', '6100 Southwest Fwy', 'Houston', 'TX', '77057', TRUE, 'Authorized Ferrari Classiche & 296/Portofino factory technicians'),
      ('Lamborghini Houston', 'Authorized Dealer', v_hou_id, '(281) 248-8400', 'service@lamborghinihouston.com', '13921 North Fwy', 'Houston', 'TX', '77090', TRUE, 'Urus & Sterrato warranty & drivetrain certified'),
      ('McLaren Houston', 'Authorized Dealer', v_hou_id, '(832) 797-2844', 'service@mclarenhouston.com', '16210 North Fwy', 'Houston', 'TX', '77090', TRUE, 'Artura hybrid powertrain diagnostics & servicing'),
      ('Post Oak Motor Cars / Rolls-Royce', 'Authorized Dealer', v_hou_id, '(713) 398-4000', 'service@postoakmotors.com', '1530 West Loop S', 'Houston', 'TX', '77027', TRUE, 'Rolls-Royce Cullinan & bespoke luxury vehicle specialist'),
      ('Bentley Houston', 'Authorized Dealer', v_hou_id, '(713) 398-4001', 'service@bentleyhouston.com', '1530 West Loop S', 'Houston', 'TX', '77027', TRUE, 'Continental GT W12/V8 scheduled service'),
      ('Aston Martin Houston', 'Authorized Dealer', v_hou_id, '(713) 398-4002', 'service@astonmartinhouston.com', '1530 West Loop S', 'Houston', 'TX', '77027', TRUE, 'Vantage F1 Edition and DBX 707 certified workshop'),
      ('Mercedes-Benz of Houston Greenway', 'Authorized Dealer', v_hou_id, '(713) 986-9700', 'service@mbgreenway.com', '3900 Southwest Fwy', 'Houston', 'TX', '77027', TRUE, 'AMG G63 & SL63 engine, trans & suspension certified'),
      ('Mercedes-Benz of Houston North', 'Authorized Dealer', v_hou_id, '(281) 378-4200', 'service@mbnorth.com', '16929 North Fwy', 'Houston', 'TX', '77090', TRUE, 'AMG factory brake and electronic diagnostics'),
      ('BMW of West Houston', 'Authorized Dealer', v_hou_id, '(855) 755-9008', 'service@bmwwesthouston.com', '20822 Katy Fwy', 'Katy', 'TX', '77449', TRUE, 'Bavarian mechanical support & sensor calibrations'),
      ('Freedom Auto Spa', 'Internal Division', v_hou_id, '(713) 555-0190', 'autospa@freedomsupercars.com', '9950 Brittmoore Park Dr', 'Houston', 'TX', '77041', TRUE, 'In-house detailing, wash, ceramic maintenance, and leather turnaround'),
      ('EVS Motors Houston', 'Specialty Performance', v_hou_id, '(888) 878-2213', 'sales@evsmotors.com', '12320 Bellaire Blvd', 'Houston', 'TX', '77072', TRUE, 'High-end custom forging, wheel balancing & performance fitments'),
      ('Sphere Performance Houston', 'Exotic Tuning & Prep', v_hou_id, '(713) 485-0210', 'tech@sphereperformance.com', '11020 Katy Fwy', 'Houston', 'TX', '77043', TRUE, 'Exotic suspension geometry, corner-balancing & track inspections'),
      ('DriverSource Houston', 'Exotic & Classic Service', v_hou_id, '(281) 497-1000', 'service@driversource.com', '14750 Memorial Dr', 'Houston', 'TX', '77079', TRUE, 'Secure collector storage, mechanical overhaul & historical preservation'),
      ('Bemer Motor Cars', 'Independent European', v_hou_id, '(713) 266-2690', 'service@bemermotorcars.com', '9201 Richmond Ave', 'Houston', 'TX', '77063', TRUE, 'Independent German & Italian mechanical specialist'),
      ('Modern Auto Collision', 'Collision & Body', v_hou_id, '(713) 869-2345', 'estimates@modernautocollision.com', '5500 Washington Ave', 'Houston', 'TX', '77007', TRUE, 'Aluminum bodywork, carbon fiber repair & factory color matching'),
      ('Houston PPF & Ceramic Coatings', 'Cosmetic Protection', v_hou_id, '(713) 936-2244', 'info@houstonppf.com', '2115 Washington Ave', 'Houston', 'TX', '77007', TRUE, 'Self-healing PPF wrap replacements, windshield film defense'),
      ('Discount Tire - Memorial', 'Tire Specialist', v_hou_id, '(281) 493-2111', 'txh_09@discounttire.com', '14615 Memorial Dr', 'Houston', 'TX', '77079', TRUE, 'Michelin Pilot Sport Cup 2 / Pirelli P Zero supply & touchless mounting'),
      ('Sunbusters Window Tint & Protection', 'Glass Defense', v_hou_id, '(713) 868-8468', 'sales@sunbusterstx.com', '8200 Washington Ave', 'Houston', 'TX', '77007', TRUE, 'Ceramic IR glass thermal shielding & UV interior protection'),
      ('Gulf Coast Exotic Auto Transport', 'Logistics & Towing', v_hou_id, '(713) 555-0188', 'dispatch@gulfcoasttransport.com', '9950 Brittmoore Park Dr', 'Houston', 'TX', '77041', TRUE, 'Enclosed low-angle hydraulic flatbed recovery & dealer transport')
    ON CONFLICT (vendor_name) DO UPDATE SET
      vendor_type_code = EXCLUDED.vendor_type_code,
      home_branch_id = EXCLUDED.home_branch_id,
      vendor_phone = EXCLUDED.vendor_phone,
      vendor_email = EXCLUDED.vendor_email,
      address_line1 = EXCLUDED.address_line1,
      city = EXCLUDED.city,
      state = EXCLUDED.state,
      postal_code = EXCLUDED.postal_code,
      is_active = EXCLUDED.is_active,
      notes = EXCLUDED.notes;

    -- Grant vendor branch access
    INSERT INTO fs.vendor_branch_access (vendor_id, branch_id, granted_at)
    SELECT v.vendor_id, v_hou_id, now()
      FROM fs.vendor v
     WHERE v.is_active = TRUE
       AND NOT EXISTS (
         SELECT 1 FROM fs.vendor_branch_access vba
          WHERE vba.vendor_id = v.vendor_id AND vba.branch_id = v_hou_id
       );

    -- -------------------------------------------------------------------------
    -- 3. Hydrate 11 Authoritative Members (Cleaned & Deduplicated)
    -- -------------------------------------------------------------------------
    -- Clean duplicate or scratch members if present
    DELETE FROM fs.point_transactions
     WHERE subscription_id IN (
       SELECT id FROM fs.member_subscriptions
        WHERE member_id IN (SELECT id FROM fs.members WHERE email LIKE 'alex.rossi.%@freedomsupercars.com')
     );
    DELETE FROM fs.reservations
     WHERE member_id IN (SELECT id FROM fs.members WHERE email LIKE 'alex.rossi.%@freedomsupercars.com');
    DELETE FROM fs.member_subscriptions
     WHERE member_id IN (SELECT id FROM fs.members WHERE email LIKE 'alex.rossi.%@freedomsupercars.com');
    DELETE FROM fs.authorized_drivers
     WHERE member_id IN (SELECT id FROM fs.members WHERE email LIKE 'alex.rossi.%@freedomsupercars.com');
    DELETE FROM fs.members
     WHERE email LIKE 'alex.rossi.%@freedomsupercars.com';

    DELETE FROM fs.point_transactions
     WHERE subscription_id IN (
       SELECT id FROM fs.member_subscriptions
        WHERE member_id IN (SELECT id FROM fs.members WHERE email LIKE 'marcus.vance.%@freedomsupercars.com' AND email <> 'marcus.vance.test@freedomsupercars.com')
     );
    DELETE FROM fs.reservations
     WHERE member_id IN (SELECT id FROM fs.members WHERE email LIKE 'marcus.vance.%@freedomsupercars.com' AND email <> 'marcus.vance.test@freedomsupercars.com');
    DELETE FROM fs.member_subscriptions
     WHERE member_id IN (SELECT id FROM fs.members WHERE email LIKE 'marcus.vance.%@freedomsupercars.com' AND email <> 'marcus.vance.test@freedomsupercars.com');
    DELETE FROM fs.authorized_drivers
     WHERE member_id IN (SELECT id FROM fs.members WHERE email LIKE 'marcus.vance.%@freedomsupercars.com' AND email <> 'marcus.vance.test@freedomsupercars.com');
    DELETE FROM fs.members
     WHERE email LIKE 'marcus.vance.%@freedomsupercars.com' AND email <> 'marcus.vance.test@freedomsupercars.com';

    -- Clear member_number on any existing rows in fs.member so the sync trigger never conflicts
    UPDATE fs.member SET member_number = NULL
     WHERE member_number IN (
       'FS-2026-0001', 'FS-2026-0002', 'FS-2026-0003', 'FS-2026-0004',
       'FS-2026-0005', 'FS-2026-0006', 'FS-2026-0007', 'FS-2026-0008',
       'FS-2026-0009', 'FS-2026-0010', 'FS-2026-0011'
     );

    -- Upsert the 11 Authoritative Members (matching either email or member_number)
    FOR r IN (
      SELECT 'FS-2026-0001' AS num, 'Marcus' AS fn, 'Vance' AS ln, 'marcus.vance.test@freedomsupercars.com' AS em, '+1-713-555-0100' AS ph, 'Houston' AS ci, 'TX' AS st, '77024' AS zp, '2026-01-15'::date AS jd, 'Founding Member' AS rf UNION ALL
      SELECT 'FS-2026-0002', 'James', 'Whitaker', 'james.whitaker@freedomsupercars.com', '+1-713-555-0101', 'Houston', 'TX', '77005', '2026-02-01'::date, 'Club Sponsor' UNION ALL
      SELECT 'FS-2026-0003', 'Blaine', 'Sweatt', 'blaine.sweatt@freedomsupercars.com', '+1-713-555-0102', 'Houston', 'TX', '77019', '2026-02-15'::date, 'Member Referral' UNION ALL
      SELECT 'FS-2026-0004', 'Marc', 'Smith', 'marc.smith@freedomsupercars.com', '+1-713-555-0103', 'Houston', 'TX', '77056', '2025-11-01'::date, 'Executive Leadership' UNION ALL
      SELECT 'FS-2026-0005', 'Carlos', 'Miguez', 'cmiguez@smeprotech.com', '+1-713-555-0104', 'Houston', 'TX', '77041', '2026-01-01'::date, 'Platform Architecture Partner' UNION ALL
      SELECT 'FS-2026-0006', 'Club', 'Administrator', 'admin@freedomsupercars.com', '+1-713-555-0105', 'Houston', 'TX', '77041', '2025-10-01'::date, 'Club Operations' UNION ALL
      SELECT 'FS-2026-0007', 'Elena', 'Rostova', 'elena.rostova@freedomsupercars.com', '+1-713-555-0106', 'Houston', 'TX', '77007', '2026-03-01'::date, 'Private Concierge Invitation' UNION ALL
      SELECT 'FS-2026-0008', 'David', 'Sterling', 'david.sterling@freedomsupercars.com', '+1-713-555-0107', 'The Woodlands', 'TX', '77380', '2026-03-15'::date, 'Memorial Drive Event' UNION ALL
      SELECT 'FS-2026-0009', 'Alexander', 'Rossi', 'alex.rossi@freedomsupercars.com', '+1-713-555-0108', 'Sugar Land', 'TX', '77478', '2026-04-01'::date, 'Track Day Guest' UNION ALL
      SELECT 'FS-2026-0010', 'Jordan', 'Reyes', 'jordan.reyes@freedomsupercars.com', '+1-713-555-0109', 'Houston', 'TX', '77002', '2026-04-15'::date, 'River Oaks Invitational' UNION ALL
      SELECT 'FS-2026-0011', 'Priya', 'Natarajan', 'priya.natarajan@freedomsupercars.com', '+1-713-555-0110', 'Bellaire', 'TX', '77401', '2026-05-01'::date, 'Exotic Car Showcase'
    ) LOOP
      IF EXISTS (SELECT 1 FROM fs.members WHERE email = r.em) THEN
        UPDATE fs.members SET
          member_number = r.num,
          first_name = r.fn,
          last_name = r.ln,
          phone = r.ph,
          city = r.ci,
          state = r.st,
          postal_code = r.zp,
          primary_location_id = v_hou_id,
          status = 'active',
          joined_on = r.jd,
          referral_source = r.rf
        WHERE email = r.em;
      ELSIF EXISTS (SELECT 1 FROM fs.members WHERE member_number = r.num) THEN
        UPDATE fs.members SET
          email = r.em,
          first_name = r.fn,
          last_name = r.ln,
          phone = r.ph,
          city = r.ci,
          state = r.st,
          postal_code = r.zp,
          primary_location_id = v_hou_id,
          status = 'active',
          joined_on = r.jd,
          referral_source = r.rf
        WHERE member_number = r.num;
      ELSE
        INSERT INTO fs.members (member_number, first_name, last_name, email, phone, city, state, postal_code, primary_location_id, status, joined_on, referral_source)
        VALUES (r.num, r.fn, r.ln, r.em, r.ph, r.ci, r.st, r.zp, v_hou_id, 'active', r.jd, r.rf);
      END IF;
    END LOOP;

    -- Ensure subscriptions and initial allocations exist for all 11 members
    -- 1. Marcus Vance -> PLAN_100 (Daytona)
    INSERT INTO fs.member_subscriptions (member_id, plan_id, status, start_date, end_date, points_granted, auto_renew)
    SELECT m.id, v_plan_100, 'active', '2026-01-15', '2027-01-15', 200, TRUE
      FROM fs.members m WHERE m.email = 'marcus.vance.test@freedomsupercars.com'
       AND NOT EXISTS (SELECT 1 FROM fs.member_subscriptions s WHERE s.member_id = m.id AND s.status = 'active');

    -- 2. James Whitaker -> PLAN_60 (Le Mans with 1500 points allocation)
    INSERT INTO fs.member_subscriptions (member_id, plan_id, status, start_date, end_date, points_granted, auto_renew)
    SELECT m.id, v_plan_60, 'active', '2026-02-01', '2027-02-01', 1500, TRUE
      FROM fs.members m WHERE m.email = 'james.whitaker@freedomsupercars.com'
       AND NOT EXISTS (SELECT 1 FROM fs.member_subscriptions s WHERE s.member_id = m.id AND s.status = 'active');

    -- 3. Blaine Sweatt -> PLAN_30 (Sebring)
    INSERT INTO fs.member_subscriptions (member_id, plan_id, status, start_date, end_date, points_granted, auto_renew)
    SELECT m.id, v_plan_30, 'active', '2026-02-15', '2027-02-15', 60, TRUE
      FROM fs.members m WHERE m.email = 'blaine.sweatt@freedomsupercars.com'
       AND NOT EXISTS (SELECT 1 FROM fs.member_subscriptions s WHERE s.member_id = m.id AND s.status = 'active');

    -- 4. Marc Smith -> PLAN_100
    INSERT INTO fs.member_subscriptions (member_id, plan_id, status, start_date, end_date, points_granted, auto_renew)
    SELECT m.id, v_plan_100, 'active', '2025-11-01', '2026-11-01', 200, TRUE
      FROM fs.members m WHERE m.email = 'marc.smith@freedomsupercars.com'
       AND NOT EXISTS (SELECT 1 FROM fs.member_subscriptions s WHERE s.member_id = m.id AND s.status = 'active');

    -- 5. Carlos Miguez -> PLAN_60
    INSERT INTO fs.member_subscriptions (member_id, plan_id, status, start_date, end_date, points_granted, auto_renew)
    SELECT m.id, v_plan_60, 'active', '2026-01-01', '2027-01-01', 120, TRUE
      FROM fs.members m WHERE m.email = 'cmiguez@smeprotech.com'
       AND NOT EXISTS (SELECT 1 FROM fs.member_subscriptions s WHERE s.member_id = m.id AND s.status = 'active');

    -- 6. Admin -> PLAN_100
    INSERT INTO fs.member_subscriptions (member_id, plan_id, status, start_date, end_date, points_granted, auto_renew)
    SELECT m.id, v_plan_100, 'active', '2025-10-01', '2026-10-01', 200, TRUE
      FROM fs.members m WHERE m.email = 'admin@freedomsupercars.com'
       AND NOT EXISTS (SELECT 1 FROM fs.member_subscriptions s WHERE s.member_id = m.id AND s.status = 'active');

    -- 7. Elena Rostova -> PLAN_60
    INSERT INTO fs.member_subscriptions (member_id, plan_id, status, start_date, end_date, points_granted, auto_renew)
    SELECT m.id, v_plan_60, 'active', '2026-03-01', '2027-03-01', 120, TRUE
      FROM fs.members m WHERE m.email = 'elena.rostova@freedomsupercars.com'
       AND NOT EXISTS (SELECT 1 FROM fs.member_subscriptions s WHERE s.member_id = m.id AND s.status = 'active');

    -- 8. David Sterling -> PLAN_30
    INSERT INTO fs.member_subscriptions (member_id, plan_id, status, start_date, end_date, points_granted, auto_renew)
    SELECT m.id, v_plan_30, 'active', '2026-03-15', '2027-03-15', 60, TRUE
      FROM fs.members m WHERE m.email = 'david.sterling@freedomsupercars.com'
       AND NOT EXISTS (SELECT 1 FROM fs.member_subscriptions s WHERE s.member_id = m.id AND s.status = 'active');

    -- 9. Alexander Rossi -> PLAN_30
    INSERT INTO fs.member_subscriptions (member_id, plan_id, status, start_date, end_date, points_granted, auto_renew)
    SELECT m.id, v_plan_30, 'active', '2026-04-01', '2027-04-01', 60, TRUE
      FROM fs.members m WHERE m.email = 'alex.rossi@freedomsupercars.com'
       AND NOT EXISTS (SELECT 1 FROM fs.member_subscriptions s WHERE s.member_id = m.id AND s.status = 'active');

    -- 10. Jordan Reyes -> PLAN_60
    INSERT INTO fs.member_subscriptions (member_id, plan_id, status, start_date, end_date, points_granted, auto_renew)
    SELECT m.id, v_plan_60, 'active', '2026-04-15', '2027-04-15', 120, TRUE
      FROM fs.members m WHERE m.email = 'jordan.reyes@freedomsupercars.com'
       AND NOT EXISTS (SELECT 1 FROM fs.member_subscriptions s WHERE s.member_id = m.id AND s.status = 'active');

    -- 11. Priya Natarajan -> PLAN_15
    INSERT INTO fs.member_subscriptions (member_id, plan_id, status, start_date, end_date, points_granted, auto_renew)
    SELECT m.id, v_plan_15, 'active', '2026-05-01', '2027-05-01', 30, TRUE
      FROM fs.members m WHERE m.email = 'priya.natarajan@freedomsupercars.com'
       AND NOT EXISTS (SELECT 1 FROM fs.member_subscriptions s WHERE s.member_id = m.id AND s.status = 'active');

    -- Post initial annual allocation transaction for any active subscription without a ledger entry
    INSERT INTO fs.point_transactions (subscription_id, txn_type, points, balance_after, reason)
    SELECT s.id, 'grant', s.points_granted, s.points_granted, 'Annual Allocation'
      FROM fs.member_subscriptions s
     WHERE s.status = 'active'
       AND NOT EXISTS (SELECT 1 FROM fs.point_transactions pt WHERE pt.subscription_id = s.id);

END $$;

COMMIT;
