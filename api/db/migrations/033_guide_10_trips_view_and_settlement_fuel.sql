-- =============================================================================
-- Migration 033: Guide 10.1 & 10.2 Canonical fs.trips View, Condition Signatures,
-- and Member Fuel Replenishment Charges
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

-- 1. Seed fs.member_charge_type if not present so FK fk_member_charge_charge_type_code succeeds
INSERT INTO fs.member_charge_type (charge_type_code, charge_type_name, charge_description, sort_order, is_active)
VALUES
  ('FUEL',     'Fuel Replenishment', 'Fuel consumed during trip marked up per membership plan', 1, TRUE),
  ('DELIVERY', 'Delivery Fee',       'Vehicle delivery or collection service charge',          2, TRUE),
  ('OVERAGE',  'Mileage Overage',    'Cash overage charge for miles beyond allowance',         3, TRUE),
  ('DAMAGE',   'Damage Incident',    'Repair or deductible charges from return inspection',    4, TRUE),
  ('OTHER',    'Other Fee',          'Miscellaneous administrative or club fee',               5, TRUE)
ON CONFLICT (charge_type_code) DO UPDATE
SET charge_type_name = EXCLUDED.charge_type_name,
    charge_description = EXCLUDED.charge_description,
    is_active = TRUE;

-- 2. Add signature and condition columns to fs.vehicle_trip if missing
ALTER TABLE fs.vehicle_trip ADD COLUMN IF NOT EXISTS condition_signature_url TEXT;
ALTER TABLE fs.vehicle_trip ADD COLUMN IF NOT EXISTS condition_return_signature_url TEXT;
ALTER TABLE fs.vehicle_trip ADD COLUMN IF NOT EXISTS condition_snapshot VARCHAR(40);
ALTER TABLE fs.vehicle_trip ADD COLUMN IF NOT EXISTS condition_return_snapshot VARCHAR(40);

-- 3. Add signature column to fs.vehicle_trip_member if missing
ALTER TABLE fs.vehicle_trip_member ADD COLUMN IF NOT EXISTS condition_signature_url TEXT;
ALTER TABLE fs.vehicle_trip_member ADD COLUMN IF NOT EXISTS condition_return_signature_url TEXT;

-- 4. Create or Replace canonical fs.trips VIEW
-- Allows direct queries to fs.trips matching Guide 10.1 & 10.2 requirements
CREATE OR REPLACE VIEW fs.trips AS
SELECT
  t.vehicle_trip_id,
  t.vehicle_trip_id                         AS id,
  t.vehicle_reservation_id,
  t.vehicle_reservation_id                  AS reservation_id,
  t.vehicle_id,
  t.trip_type_code,
  t.start_time_actual,
  t.end_time_actual,
  t.odometer_start_id,
  t.odometer_end_id,
  t.miles_driven,
  t.fuel_start_percent,
  t.fuel_end_percent,
  t.extra_miles,
  t.extra_miles_reason,
  t.pay_vop_use,
  t.condition_signature_url,
  t.condition_return_signature_url,
  t.condition_snapshot,
  t.condition_return_snapshot,
  tm.member_id,
  tm.member_package_id,
  tm.branch_id,
  tm.start_type,
  tm.return_type,
  tm.miles_member,
  tm.miles_member_adjustment,
  tm.miles_member_adjustment_reason,
  tm.vehicle_tier_snapshot,
  tm.weekday_point_value_snapshot,
  tm.weekend_point_value_snapshot,
  tm.extra_mile_point_value_snapshot,
  tm.included_miles_snapshot,
  tm.overage_miles_snapshot,
  tm.base_points,
  tm.extra_mileage_points,
  tm.total_points,
  tm.calculation_version,
  tm.calculation_detail,
  vm.model_name                             AS vehicle_model,
  m.name                                    AS vehicle_make,
  v.license_plate,
  r.confirmation_code,
  t.created_at,
  t.updated_at
FROM fs.vehicle_trip t
LEFT JOIN fs.vehicle_trip_member tm ON tm.vehicle_trip_id = t.vehicle_trip_id
LEFT JOIN fs.vehicles v ON v.id = t.vehicle_id
LEFT JOIN fs.vehicle_models vm ON vm.id = v.model_id
LEFT JOIN fs.manufacturers m ON m.id = vm.manufacturer_id
LEFT JOIN fs.reservations r ON r.id = t.vehicle_reservation_id;

-- 5. Grant permissions on fs.trips and fs.member_charge_type
GRANT SELECT ON fs.trips TO PUBLIC;
GRANT ALL ON fs.member_charge_type TO PUBLIC;

COMMIT;
