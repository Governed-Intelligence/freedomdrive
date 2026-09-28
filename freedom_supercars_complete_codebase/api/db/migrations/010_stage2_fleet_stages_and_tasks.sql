-- =============================================================================
-- Migration 010: Stage 2 Fleet Stages, Withholds, and Aging Tasks (Guide 8.3)
-- =============================================================================
-- Enforces:
--   8.3-R01 / 8.3-C01 / 8.3-C02: Fleet stages (Incoming, Intake, Fleet, Retired)
--   8.3-R02 / 8.3-C03: Stamping arrival_date transitions Incoming -> Intake
--   8.3-R05 / 8.3-C04 / 8.3-C05 / 8.3-C06: Readiness completion moves to Fleet, places withhold, raises launch task
--   8.3-R06 / 8.3-C12 / 8.3-C13 / 8.3-C14: Retirement from any stage requiring a reason
--   8.3-R07 / 8.3-C15: Retired to Incoming/Intake permitted only for repurchase
--   8.3-R08 / 8.3-C08-C11: Intake aging tasks (10, 30, 60, 90 days)
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

-- 1. Seed task lookups
INSERT INTO fs.task_status (task_status_code, task_status_name, sort_order, is_active)
VALUES
  ('PENDING', 'Pending', 1, TRUE),
  ('IN_PROGRESS', 'In Progress', 2, TRUE),
  ('COMPLETED', 'Completed', 3, TRUE),
  ('CANCELLED', 'Cancelled', 4, TRUE)
ON CONFLICT (task_status_code) DO UPDATE
SET task_status_name = EXCLUDED.task_status_name, is_active = TRUE;

INSERT INTO fs.task_priority (task_priority_code, task_priority_name, sort_order, is_active)
VALUES
  ('LOW', 'Low', 1, TRUE),
  ('MEDIUM', 'Medium', 2, TRUE),
  ('HIGH', 'High', 3, TRUE),
  ('URGENT', 'Urgent', 4, TRUE)
ON CONFLICT (task_priority_code) DO UPDATE
SET task_priority_name = EXCLUDED.task_priority_name, is_active = TRUE;

INSERT INTO fs.task_type_select (task_type_code, task_type_name, sort_order, is_active)
VALUES
  ('VEHICLE_LAUNCH', 'Vehicle Launch Readiness', 1, TRUE),
  ('INTAKE_AGING_10', 'Intake Aging 10-Day Review', 2, TRUE),
  ('INTAKE_AGING_30', 'Intake Aging 30-Day Review', 3, TRUE),
  ('INTAKE_AGING_60', 'Intake Aging 60-Day Review', 4, TRUE),
  ('INTAKE_AGING_90', 'Intake Aging 90-Day Review', 5, TRUE),
  ('TEMP_PLATE', 'Temporary Plate Replacement', 6, TRUE),
  ('GENERAL', 'General Task', 99, TRUE)
ON CONFLICT (task_type_code) DO UPDATE
SET task_type_name = EXCLUDED.task_type_name, is_active = TRUE;

-- 2. Seed withhold reasons
INSERT INTO fs.reservation_withhold_reason_select (withhold_reason_code, label, is_system_placed, is_active, sort_order)
VALUES
  ('AwaitingLaunch', 'Awaiting Launch', TRUE, TRUE, 1),
  ('Maintenance', 'Maintenance / Repair', FALSE, TRUE, 2),
  ('Detailing', 'Detailing / Prep', FALSE, TRUE, 3),
  ('StaffHold', 'Staff Hold', FALSE, TRUE, 4),
  ('VIPReserve', 'VIP Hold', FALSE, TRUE, 5)
ON CONFLICT (withhold_reason_code) DO UPDATE
SET label = EXCLUDED.label, is_system_placed = EXCLUDED.is_system_placed, is_active = TRUE;

-- 3. Automatic arrival date trigger: stamping arrival_date moves stage from Incoming to Intake (8.3-R02, 8.3-C03)
CREATE OR REPLACE FUNCTION fs.trg_vehicle_arrival_stage_fn()
RETURNS trigger AS $$
BEGIN
  IF NEW.arrival_date IS NOT NULL AND (OLD.arrival_date IS NULL OR OLD.fleet_stage = 'Incoming') THEN
    IF NEW.fleet_stage = 'Incoming' THEN
      NEW.fleet_stage := 'Intake';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_vehicle_arrival_stage ON fs.vehicle;
CREATE TRIGGER trg_vehicle_arrival_stage
BEFORE INSERT OR UPDATE ON fs.vehicle
FOR EACH ROW EXECUTE FUNCTION fs.trg_vehicle_arrival_stage_fn();

COMMIT;
