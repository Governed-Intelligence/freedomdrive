-- Migration 019: Stage 2 Vehicle Financing and Disposal (Guide 8.8)

BEGIN;

-- 1. Ensure unique constraint on fs.vehicle_financing_lifecycle (vehicle_id)
DO $$ BEGIN
  ALTER TABLE fs.vehicle_financing_lifecycle ADD CONSTRAINT uq_vehicle_financing_veh_id UNIQUE (vehicle_id);
EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL;
END $$;

-- 2. Add disposal_type column if missing
ALTER TABLE fs.vehicle_financing_lifecycle ADD COLUMN IF NOT EXISTS disposal_type VARCHAR(40);
ALTER TABLE fs.vehicle_financing_lifecycle_shadow ADD COLUMN IF NOT EXISTS disposal_type VARCHAR(40);

-- 3. Ensure indexes
CREATE INDEX IF NOT EXISTS idx_vehicle_financing_veh_id ON fs.vehicle_financing_lifecycle (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_financing_shadow_veh_id ON fs.vehicle_financing_lifecycle_shadow (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_financing_end_dates ON fs.vehicle_financing_lifecycle (end_target_date, end_date_is_committed);

-- 4. Seed MileageLimit into reservation_withhold_reason_select (Guide 8.9)
INSERT INTO fs.reservation_withhold_reason_select (withhold_reason_code, label, is_system_placed, is_active, sort_order)
VALUES
  ('MileageLimit', 'Mileage Allowance Exceeded', TRUE, TRUE, 12)
ON CONFLICT (withhold_reason_code) DO UPDATE
SET label = EXCLUDED.label, is_active = TRUE;

-- 5. Ensure unique constraint on fs.vehicle_mileage_allowance (vehicle_id)
DO $$ BEGIN
  ALTER TABLE fs.vehicle_mileage_allowance ADD CONSTRAINT uq_vehicle_mileage_allowance_veh_id UNIQUE (vehicle_id);
EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL;
END $$;

-- 6. Indexes for mileage tracking
CREATE INDEX IF NOT EXISTS idx_vehicle_mileage_allocation_veh_date ON fs.vehicle_mileage_allocation (vehicle_id, allocated_on);
CREATE INDEX IF NOT EXISTS idx_vehicle_mileage_allowance_active ON fs.vehicle_mileage_allowance (vehicle_id, is_active);

COMMIT;
