-- Migration 014: Stage 2 Vehicle Visibility & Launch (Guide 8.6)

BEGIN;

-- 1. Seed AwaitingLaunch withhold reason
INSERT INTO fs.reservation_withhold_reason_select (withhold_reason_code, label, is_system_placed, is_active, sort_order)
VALUES
  ('AwaitingLaunch', 'Awaiting Launch', TRUE, TRUE, 11)
ON CONFLICT (withhold_reason_code) DO UPDATE
SET label = EXCLUDED.label, is_active = TRUE;

-- 2. Ensure task_type_select has vehicle launch task
INSERT INTO fs.task_type_select (task_type_code, task_type_name, description, is_active, sort_order)
VALUES
  ('VEHICLE_LAUNCH', 'Vehicle Launch Form', 'Complete vehicle launch form to release withhold and set launch date', TRUE, 15)
ON CONFLICT (task_type_code) DO UPDATE
SET task_type_name = EXCLUDED.task_type_name, is_active = TRUE;

-- 3. Ensure task_status has PENDING, COMPLETED, CANCELLED
INSERT INTO fs.task_status (task_status_code, task_status_name, description, sort_order, is_active)
VALUES
  ('PENDING', 'Pending', 'Pending execution', 1, TRUE),
  ('COMPLETED', 'Completed', 'Task completed', 2, TRUE),
  ('CANCELLED', 'Cancelled', 'Task cancelled', 3, TRUE)
ON CONFLICT (task_status_code) DO NOTHING;

-- 4. Seed default release template
INSERT INTO fs.vehicle_release_template (vehicle_release_template_id, template_name, description, is_default, is_active, sort_order)
VALUES
  ('d1111111-1111-1111-1111-111111111111', 'Standard Staged Launch', '14 days Platinum exclusive followed by 14 days Gold exclusive', TRUE, TRUE, 1)
ON CONFLICT (vehicle_release_template_id) DO UPDATE
SET template_name = EXCLUDED.template_name, description = EXCLUDED.description, is_active = TRUE;

INSERT INTO fs.vehicle_release_template_row (vehicle_release_template_row_id, vehicle_release_template_id, sort_order, duration_days, minimum_podium_status_code, hide_from_lower_tiers)
VALUES
  ('d2222222-2222-2222-2222-222222222221', 'd1111111-1111-1111-1111-111111111111', 1, 14, 'PLATINUM', FALSE),
  ('d2222222-2222-2222-2222-222222222222', 'd1111111-1111-1111-1111-111111111111', 2, 14, 'GOLD', FALSE)
ON CONFLICT (vehicle_release_template_row_id) DO UPDATE
SET minimum_podium_status_code = EXCLUDED.minimum_podium_status_code, duration_days = EXCLUDED.duration_days;

COMMIT;
