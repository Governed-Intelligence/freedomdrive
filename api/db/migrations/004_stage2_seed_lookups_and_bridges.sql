-- =============================================================================
-- Migration 004: Seed Stage 2 Lookups and Operational Entity Bridges
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

-- 1. Seed US States into fs.state_select
INSERT INTO fs.state_select (state_code, state_name, country_code, sort_order, is_active)
VALUES
  ('AL', 'Alabama', 'US', 1, TRUE),
  ('AK', 'Alaska', 'US', 2, TRUE),
  ('AZ', 'Arizona', 'US', 3, TRUE),
  ('AR', 'Arkansas', 'US', 4, TRUE),
  ('CA', 'California', 'US', 5, TRUE),
  ('CO', 'Colorado', 'US', 6, TRUE),
  ('CT', 'Connecticut', 'US', 7, TRUE),
  ('DE', 'Delaware', 'US', 8, TRUE),
  ('DC', 'District of Columbia', 'US', 9, TRUE),
  ('FL', 'Florida', 'US', 10, TRUE),
  ('GA', 'Georgia', 'US', 11, TRUE),
  ('HI', 'Hawaii', 'US', 12, TRUE),
  ('ID', 'Idaho', 'US', 13, TRUE),
  ('IL', 'Illinois', 'US', 14, TRUE),
  ('IN', 'Indiana', 'US', 15, TRUE),
  ('IA', 'Iowa', 'US', 16, TRUE),
  ('KS', 'Kansas', 'US', 17, TRUE),
  ('KY', 'Kentucky', 'US', 18, TRUE),
  ('LA', 'Louisiana', 'US', 19, TRUE),
  ('ME', 'Maine', 'US', 20, TRUE),
  ('MD', 'Maryland', 'US', 21, TRUE),
  ('MA', 'Massachusetts', 'US', 22, TRUE),
  ('MI', 'Michigan', 'US', 23, TRUE),
  ('MN', 'Minnesota', 'US', 24, TRUE),
  ('MS', 'Mississippi', 'US', 25, TRUE),
  ('MO', 'Missouri', 'US', 26, TRUE),
  ('MT', 'Montana', 'US', 27, TRUE),
  ('NE', 'Nebraska', 'US', 28, TRUE),
  ('NV', 'Nevada', 'US', 29, TRUE),
  ('NH', 'New Hampshire', 'US', 30, TRUE),
  ('NJ', 'New Jersey', 'US', 31, TRUE),
  ('NM', 'New Mexico', 'US', 32, TRUE),
  ('NY', 'New York', 'US', 33, TRUE),
  ('NC', 'North Carolina', 'US', 34, TRUE),
  ('ND', 'North Dakota', 'US', 35, TRUE),
  ('OH', 'Ohio', 'US', 36, TRUE),
  ('OK', 'Oklahoma', 'US', 37, TRUE),
  ('OR', 'Oregon', 'US', 38, TRUE),
  ('PA', 'Pennsylvania', 'US', 39, TRUE),
  ('RI', 'Rhode Island', 'US', 40, TRUE),
  ('SC', 'South Carolina', 'US', 41, TRUE),
  ('SD', 'South Dakota', 'US', 42, TRUE),
  ('TN', 'Tennessee', 'US', 43, TRUE),
  ('TX', 'Texas', 'US', 44, TRUE),
  ('UT', 'Utah', 'US', 45, TRUE),
  ('VT', 'Vermont', 'US', 46, TRUE),
  ('VA', 'Virginia', 'US', 47, TRUE),
  ('WA', 'Washington', 'US', 48, TRUE),
  ('WV', 'West Virginia', 'US', 49, TRUE),
  ('WI', 'Wisconsin', 'US', 50, TRUE),
  ('WY', 'Wyoming', 'US', 51, TRUE)
ON CONFLICT (state_code) DO UPDATE
SET state_name = EXCLUDED.state_name, is_active = TRUE;

-- 2. Seed Timezones into fs.timezone_select
INSERT INTO fs.timezone_select (timezone_code, timezone_label, sort_order, is_active)
VALUES
  ('America/Chicago', 'Central Time (US & Canada)', 1, TRUE),
  ('America/New_York', 'Eastern Time (US & Canada)', 2, TRUE),
  ('America/Denver', 'Mountain Time (US & Canada)', 3, TRUE),
  ('America/Los_Angeles', 'Pacific Time (US & Canada)', 4, TRUE),
  ('America/Phoenix', 'Arizona Time', 5, TRUE),
  ('UTC', 'Coordinated Universal Time', 6, TRUE)
ON CONFLICT (timezone_code) DO NOTHING;

-- 3. Seed Vehicle Years into fs.vehicle_year_select
INSERT INTO fs.vehicle_year_select (vehicle_year_code, vehicle_year_label, sort_order, is_active)
SELECT y::text, y::text, y - 1990, TRUE
  FROM generate_series(1990, 2030) y
ON CONFLICT (vehicle_year_code) DO NOTHING;

-- 4. Seed Pricing Types into fs.pricing_type_select
INSERT INTO fs.pricing_type_select (pricing_type_code, pricing_type_name, description, sort_order, is_active)
VALUES
  ('annual_price', 'Annual Price', 'Annual membership plan price', 1, TRUE),
  ('monthly_price', 'Monthly Price', 'Monthly recurring subscription fee', 2, TRUE),
  ('initiation_fee', 'Initiation Fee', 'One-time onboarding fee', 3, TRUE),
  ('renewal_fee', 'Renewal Fee', 'Annual renewal fee', 4, TRUE),
  ('joining_bonus', 'Joining Bonus', 'Points bonus on sign-up', 5, TRUE)
ON CONFLICT (pricing_type_code) DO NOTHING;

-- 5. Seed Points & Caps Types into fs.points_cap_type_select
INSERT INTO fs.points_cap_type_select (points_cap_type_code, points_cap_type_name, description, sort_order, is_active)
VALUES
  ('monthly_cap', 'Monthly Cap', 'Maximum points that can be burned in one month', 1, TRUE),
  ('rollover_cap', 'Rollover Cap', 'Maximum points that can roll over into next year', 2, TRUE),
  ('spend_ahead_percent', 'Spend Ahead %', 'Percentage of points that can be spent ahead', 3, TRUE),
  ('allocation_bonus', 'Allocation Bonus', 'Supplemental bonus points added to plan', 4, TRUE)
ON CONFLICT (points_cap_type_code) DO NOTHING;

-- 6. Seed Booking Types into fs.booking_type_select
INSERT INTO fs.booking_type_select (booking_type_code, booking_type_name, description, sort_order, is_active)
VALUES
  ('simultaneous_reservations', 'Simultaneous Reservations', 'Max concurrent reservations permitted', 1, TRUE),
  ('advance_window_days', 'Advance Window Days', 'How many days in advance bookings can be made', 2, TRUE),
  ('cancellation_allowance', 'Cancellation Allowance', 'Number of penalty-free cancellations per year', 3, TRUE),
  ('avg_days_per_reservation', 'Avg Days Per Reservation', 'Average reservation duration baseline', 4, TRUE)
ON CONFLICT (booking_type_code) DO NOTHING;

-- 7. Seed Mileage Types into fs.mileage_type_select
INSERT INTO fs.mileage_type_select (mileage_type_code, mileage_type_name, description, sort_order, is_active)
VALUES
  ('included_daily_miles', 'Included Daily Miles', 'Daily mileage allowance included in booking', 1, TRUE),
  ('extra_mile_point_rate', 'Extra Mile Point Rate', 'Tier points charged per extra mile', 2, TRUE),
  ('extra_mile_dollar_rate', 'Extra Mile Dollar Rate', 'Dollar fee charged per extra mile', 3, TRUE)
ON CONFLICT (mileage_type_code) DO NOTHING;

-- 8. Seed Perk Types into fs.perk_type_select
INSERT INTO fs.perk_type_select (perk_type_code, perk_type_name, description, sort_order, is_active)
VALUES
  ('free_pass_weekends', 'Free Pass Weekends', 'Complimentary weekend drive passes', 1, TRUE),
  ('complimentary_delivery', 'Complimentary Delivery', 'Free vehicle delivery to member location', 2, TRUE),
  ('simulator_hours', 'Simulator Hours', 'Club racing simulator hours', 3, TRUE),
  ('track_day_passes', 'Track Day Passes', 'Guest passes for club track day events', 4, TRUE)
ON CONFLICT (perk_type_code) DO NOTHING;

-- 9. Bridge fs.locations -> fs.branch
INSERT INTO fs.branch (
    branch_id, branch_code, branch_name, branch_type, time_zone,
    address_physical, city_physical, state_physical, zip_physical, is_active
)
SELECT id, code, name, 'Main'::fs.branch_branch_type_enum, timezone,
       address_line1, city, state, postal_code, is_active
  FROM fs.locations
ON CONFLICT (branch_id) DO NOTHING;

-- 10. Bridge fs.vehicles -> fs.vehicle
INSERT INTO fs.vehicle (
    vehicle_id, vin, vehicle_name, model, trim,
    exterior_color, year, home_branch_id, fleet_stage
)
SELECT v.id,
       COALESCE(v.vin, 'UNKNOWN-' || SUBSTRING(v.id::text, 1, 8)),
       COALESCE(m.name || ' ' || vm.model_name, 'Fleet Vehicle'),
       vm.model_name,
       vm.trim,
       v.exterior_color,
       v.model_year::varchar(4),
       v.location_id,
       'Fleet'::fs.vehicle_fleet_stage_enum
  FROM fs.vehicles v
  LEFT JOIN fs.vehicle_models vm ON vm.id = v.model_id
  LEFT JOIN fs.manufacturers m ON m.id = vm.manufacturer_id
ON CONFLICT (vehicle_id) DO NOTHING;

-- 11. Bridge fs.members -> fs.member
INSERT INTO fs.member (
    member_id, member_number, first_name, last_name,
    license_number, license_state, license_expires_on,
    date_of_birth, member_since, home_branch_id, lifecycle_status
)
SELECT id, member_number, first_name, last_name,
       drivers_license_number, drivers_license_state, drivers_license_expires,
       date_of_birth, joined_on, primary_location_id,
       'Active'::fs.member_lifecycle_status_enum
  FROM fs.members
ON CONFLICT (member_id) DO NOTHING;

-- 12. Bidirectional sync triggers between fs.members and fs.member
CREATE OR REPLACE FUNCTION fs.sync_members_to_member()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO fs.member (
      member_id, member_number, first_name, last_name,
      license_number, license_state, license_expires_on,
      date_of_birth, member_since, home_branch_id, lifecycle_status,
      created_at, updated_at
  ) VALUES (
      NEW.id, NEW.member_number, NEW.first_name, NEW.last_name,
      NEW.drivers_license_number, NEW.drivers_license_state, NEW.drivers_license_expires,
      NEW.date_of_birth, NEW.joined_on, NEW.primary_location_id,
      'Active'::fs.member_lifecycle_status_enum,
      NEW.created_at, NEW.updated_at
  )
  ON CONFLICT (member_id) DO UPDATE SET
      first_name = EXCLUDED.first_name,
      last_name = EXCLUDED.last_name,
      license_number = EXCLUDED.license_number,
      license_state = EXCLUDED.license_state,
      license_expires_on = EXCLUDED.license_expires_on,
      date_of_birth = EXCLUDED.date_of_birth,
      updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_members_to_member ON fs.members;
CREATE TRIGGER trg_sync_members_to_member
AFTER INSERT OR UPDATE ON fs.members
FOR EACH ROW EXECUTE FUNCTION fs.sync_members_to_member();

COMMIT;
