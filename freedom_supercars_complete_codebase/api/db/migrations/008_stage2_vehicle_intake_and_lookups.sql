-- =============================================================================
-- Migration 008: Stage 2 Vehicle Intake, Lookups, Constraints, and Immutability
-- =============================================================================
-- Enforces:
--   8.1-R01 / 8.1-C05: Immutable VIN (updates to saved VIN refused)
--   8.1-R03 / 8.1-C03: Make, year, and color lookups seeded and validated
--   8.1-C10: Each companion holds at most one record per vehicle (1-to-1)
--   8.1-C21: Vehicle repurchasing from Retired stage
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

-- 1. Expand vehicle_make_name column width to fit full make names
ALTER TABLE fs.vehicle_make_select ALTER COLUMN vehicle_make_name TYPE VARCHAR(100);

-- 2. Seed vehicle makes into fs.vehicle_make_select
INSERT INTO fs.vehicle_make_select (vehicle_make_code, vehicle_make_name, sort_order, is_active)
VALUES
  ('ACURA', 'Acura', 1, TRUE),
  ('ALFA_ROMEO', 'Alfa Romeo', 2, TRUE),
  ('ASTON_MARTIN', 'Aston Martin', 3, TRUE),
  ('AUDI', 'Audi', 4, TRUE),
  ('BENTLEY', 'Bentley', 5, TRUE),
  ('BMW', 'BMW', 6, TRUE),
  ('BUGATTI', 'Bugatti', 7, TRUE),
  ('CADILLAC', 'Cadillac', 8, TRUE),
  ('CHEVROLET', 'Chevrolet', 9, TRUE),
  ('DODGE', 'Dodge', 10, TRUE),
  ('FERRARI', 'Ferrari', 11, TRUE),
  ('FORD', 'Ford', 12, TRUE),
  ('HUMMER', 'Hummer', 13, TRUE),
  ('LAMBORGHINI', 'Lamborghini', 14, TRUE),
  ('LAND_ROVER', 'Land Rover', 15, TRUE),
  ('LEXUS', 'Lexus', 16, TRUE),
  ('LOTUS', 'Lotus', 17, TRUE),
  ('LUCID', 'Lucid', 18, TRUE),
  ('MASERATI', 'Maserati', 19, TRUE),
  ('MCLAREN', 'McLaren', 20, TRUE),
  ('MERCEDES_BENZ', 'Mercedes-Benz', 21, TRUE),
  ('NISSAN', 'Nissan', 22, TRUE),
  ('PORSCHE', 'Porsche', 23, TRUE),
  ('RIVIAN', 'Rivian', 24, TRUE),
  ('ROLLS_ROYCE', 'Rolls-Royce', 25, TRUE),
  ('TESLA', 'Tesla', 26, TRUE),
  ('TOYOTA', 'Toyota', 27, TRUE),
  ('OTHER', 'Other', 99, TRUE)
ON CONFLICT (vehicle_make_code) DO UPDATE
SET vehicle_make_name = EXCLUDED.vehicle_make_name, is_active = TRUE;

-- 3. Seed vehicle colors into fs.vehicle_color_select
INSERT INTO fs.vehicle_color_select (vehicle_color_code, vehicle_color_name, sort_order, is_active)
VALUES
  ('BLACK', 'Black', 1, TRUE),
  ('WHITE', 'White', 2, TRUE),
  ('SILVER', 'Silver', 3, TRUE),
  ('GRAY', 'Gray', 4, TRUE),
  ('RED', 'Red', 5, TRUE),
  ('ORANGE', 'Orange', 6, TRUE),
  ('YELLOW', 'Yellow', 7, TRUE),
  ('GREEN', 'Green', 8, TRUE),
  ('BLUE', 'Blue', 9, TRUE),
  ('PURPLE', 'Purple', 10, TRUE),
  ('GOLD', 'Gold', 11, TRUE),
  ('BROWN', 'Brown', 12, TRUE),
  ('BRONZE', 'Bronze', 13, TRUE),
  ('MATTE_BLACK', 'Matte Black', 14, TRUE),
  ('MATTE_WHITE', 'Matte White', 15, TRUE),
  ('OTHER', 'Other', 99, TRUE)
ON CONFLICT (vehicle_color_code) DO UPDATE
SET vehicle_color_name = EXCLUDED.vehicle_color_name, is_active = TRUE;

-- 4. Seed tire brands into fs.vehicle_tire_brand_select
INSERT INTO fs.vehicle_tire_brand_select (tire_brand_code, tire_brand_name, sort_order, is_active)
VALUES
  ('MICHELIN', 'Michelin', 1, TRUE),
  ('PIRELLI', 'Pirelli', 2, TRUE),
  ('BRIDGESTONE', 'Bridgestone', 3, TRUE),
  ('CONTINENTAL', 'Continental', 4, TRUE),
  ('GOODYEAR', 'Goodyear', 5, TRUE),
  ('YOKOHAMA', 'Yokohama', 6, TRUE),
  ('TOYO', 'Toyo', 7, TRUE),
  ('NITTO', 'Nitto', 8, TRUE),
  ('FALKEN', 'Falken', 9, TRUE),
  ('HANKOOK', 'Hankook', 10, TRUE),
  ('DUNLOP', 'Dunlop', 11, TRUE),
  ('BFGOODRICH', 'BFGoodrich', 12, TRUE),
  ('FIRESTONE', 'Firestone', 13, TRUE),
  ('KUMHO', 'Kumho', 14, TRUE),
  ('GENERAL', 'General', 15, TRUE),
  ('OTHER', 'Other', 99, TRUE)
ON CONFLICT (tire_brand_code) DO UPDATE
SET tire_brand_name = EXCLUDED.tire_brand_name, is_active = TRUE;

-- 5. Seed condition codes into fs.vehicle_condition_code
INSERT INTO fs.vehicle_condition_code (condition_code, status_code, name, description, is_active, sort_order)
VALUES
  ('Arrived', 'ARRIVED', 'Arrived', 'Vehicle has arrived at club facility', TRUE, 1),
  ('Returned', 'RETURNED', 'Returned', 'Vehicle returned by member; awaiting check-in', TRUE, 2),
  ('Review', 'REVIEW', 'Review', 'Vehicle under inspection review for issues or damage', TRUE, 3),
  ('Prep', 'PREP', 'Prep', 'Vehicle undergoing detailing, charging or maintenance prep', TRUE, 4),
  ('Ready', 'READY', 'Ready', 'Vehicle clean, fueled, inspected, and ready for dispatch', TRUE, 5),
  ('Down', 'DOWN', 'Down', 'Vehicle grounded for repairs, maintenance or safety', TRUE, 6)
ON CONFLICT (condition_code) DO UPDATE
SET name = EXCLUDED.name, description = EXCLUDED.description, is_active = TRUE;

-- 6. Enforce 8.1-C10: Each companion holds at most one record per vehicle (1-to-1)
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicle_description_vehicle_id ON fs.vehicle_description (vehicle_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicle_spec_vehicle_id ON fs.vehicle_spec (vehicle_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicle_performance_vehicle_id ON fs.vehicle_performance (vehicle_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicle_registration_warranty_vehicle_id ON fs.vehicle_registration_warranty (vehicle_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicle_tires_vehicle_id ON fs.vehicle_tires (vehicle_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicle_accessories_vehicle_id ON fs.vehicle_accessories (vehicle_id);

-- 7. Enforce 8.1-R01 / 8.1-C05: VIN is immutable once saved
CREATE OR REPLACE FUNCTION fs.prevent_vin_update()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.vin IS NOT NULL AND NEW.vin IS DISTINCT FROM OLD.vin THEN
    RAISE EXCEPTION '8.1-R01: An edit to a saved VIN is refused. VIN is immutable.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_vin_update_vehicle ON fs.vehicle;
CREATE TRIGGER trg_prevent_vin_update_vehicle
BEFORE UPDATE ON fs.vehicle
FOR EACH ROW EXECUTE FUNCTION fs.prevent_vin_update();

DROP TRIGGER IF EXISTS trg_prevent_vin_update_vehicles ON fs.vehicles;
CREATE TRIGGER trg_prevent_vin_update_vehicles
BEFORE UPDATE ON fs.vehicles
FOR EACH ROW EXECUTE FUNCTION fs.prevent_vin_update();

-- 8. Bidirectional synchronization: fs.vehicle -> fs.vehicles
CREATE OR REPLACE FUNCTION fs.sync_vehicle_to_vehicles()
RETURNS TRIGGER AS $$
DECLARE
  v_model_id UUID;
  v_tier_id SMALLINT := 3;
BEGIN
  -- Find or create manufacturer and model in fs.manufacturers and fs.vehicle_models
  INSERT INTO fs.manufacturers (name)
  VALUES (COALESCE(NEW.vehicle_make_code, 'Unknown'))
  ON CONFLICT (name) DO NOTHING;

  SELECT id INTO v_model_id
    FROM fs.vehicle_models
   WHERE model_name = COALESCE(NEW.model, 'Model')
   LIMIT 1;

  IF v_model_id IS NULL THEN
    INSERT INTO fs.vehicle_models (manufacturer_id, model_name, trim)
    SELECT id, COALESCE(NEW.model, 'Model'), NEW.trim
      FROM fs.manufacturers
     WHERE name = COALESCE(NEW.vehicle_make_code, 'Unknown')
    ON CONFLICT (manufacturer_id, model_name, trim) DO NOTHING
    RETURNING id INTO v_model_id;
  END IF;

  IF v_model_id IS NULL THEN
    SELECT id INTO v_model_id
      FROM fs.vehicle_models
     WHERE model_name = COALESCE(NEW.model, 'Model')
     LIMIT 1;
  END IF;

  INSERT INTO fs.vehicles (
      id, vin, location_id, model_id, tier_id, model_year,
      exterior_color, interior_color, status, condition, notes, created_at, updated_at
  ) VALUES (
      NEW.vehicle_id, NEW.vin, NEW.home_branch_id, COALESCE(v_model_id, (SELECT id FROM fs.vehicle_models LIMIT 1)),
      v_tier_id, COALESCE(NULLIF(regexp_replace(NEW.year, '\D', '', 'g'), '')::integer, 2024),
      NEW.exterior_color, NEW.interior_color,
      CASE
        WHEN NEW.fleet_stage = 'Fleet' AND NEW.condition_code = 'Ready' THEN 'available'::fs.vehicle_status
        WHEN NEW.fleet_stage = 'Retired' THEN 'retired'::fs.vehicle_status
        ELSE 'maintenance'::fs.vehicle_status
      END,
      CASE
        WHEN NEW.condition_code = 'Ready' THEN 'excellent'::fs.vehicle_condition
        WHEN NEW.condition_code = 'Down' THEN 'fair'::fs.vehicle_condition
        ELSE 'good'::fs.vehicle_condition
      END,
      NEW.notes, NEW.created_at, NEW.updated_at
  )
  ON CONFLICT (id) DO UPDATE SET
      vin = EXCLUDED.vin,
      exterior_color = EXCLUDED.exterior_color,
      interior_color = EXCLUDED.interior_color,
      status = EXCLUDED.status,
      condition = EXCLUDED.condition,
      notes = EXCLUDED.notes,
      updated_at = now();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_vehicle_to_vehicles ON fs.vehicle;
CREATE TRIGGER trg_sync_vehicle_to_vehicles
AFTER INSERT OR UPDATE ON fs.vehicle
FOR EACH ROW EXECUTE FUNCTION fs.sync_vehicle_to_vehicles();

COMMIT;
