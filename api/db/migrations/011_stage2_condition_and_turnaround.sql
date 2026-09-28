-- Migration 011: Stage 2 Vehicle Condition and Turnaround (Guide 8.4)
-- Canonical conditions, reasons, transition rules, and history tracking

BEGIN;

-- 1. Ensure condition_reason_code column exists on fs.vehicle
ALTER TABLE fs.vehicle ADD COLUMN IF NOT EXISTS condition_reason_code VARCHAR(40);

-- 2. Seed fs.vehicle_condition_code (The 6 canonical conditions: 8.4-R01, 8.4-C11)
INSERT INTO fs.vehicle_condition_code (condition_code, status_code, name, description, is_active, sort_order)
VALUES
  ('Arrived',  'ARRIVED',  'Arrived',  'Here from somewhere else needing verification: intake, vendor return, or branch transfer', TRUE, 1),
  ('Returned', 'RETURNED', 'Returned', 'Returned from member trip, event, or local use at own branch; untouched', TRUE, 2),
  ('Review',   'REVIEW',   'Review',   'Moderate issue found; awaiting vehicle service manager decision (Prep or Down)', TRUE, 3),
  ('Prep',     'PREP',     'Prep',     'Turnaround preparation, detailing, fueling, cleaning in progress', TRUE, 4),
  ('Ready',    'READY',    'Ready',    'Turned around and ready for member service', TRUE, 5),
  ('Down',     'DOWN',     'Down',     'In club care but cannot go out; carries a condition reason', TRUE, 6)
ON CONFLICT (condition_code) DO UPDATE
SET status_code = EXCLUDED.status_code,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = TRUE,
    sort_order = EXCLUDED.sort_order;

-- 3. Seed fs.vehicle_condition_reason (8.4-R04, 8.4-R05, 8.4-C09, 8.4-C10)
INSERT INTO fs.vehicle_condition_reason (condition_reason_code, status_reason_name, description, is_active, sort_order)
VALUES
  ('ScheduledMaintenance', 'Scheduled Maintenance', 'Routine manufacturer service or preventive maintenance scheduled', TRUE, 1),
  ('DamageFound',          'Damage Found',          'Damage or mechanical fault detected during inspection', TRUE, 2),
  ('ReturnedWithDamage',   'Returned with Damage',   'Vehicle returned by member with damage reported at check-in', TRUE, 3),
  ('AwaitingParts',        'Awaiting Parts',        'Awaiting delivery of replacement parts or components', TRUE, 4),
  ('AwaitingVendor',       'Awaiting Vendor',       'Awaiting vendor availability or appointment slot', TRUE, 5),
  ('MemberReservation',    'Member Reservation',    'Staged or allocated for specific member reservation', TRUE, 6),
  ('ComplianceInspection', 'Compliance Inspection', 'State inspection, registration renewal, or emissions check', TRUE, 7),
  ('TurnaroundPrep',       'Turnaround Prep',       'Routine cleaning, detailing, and fluid top-off', TRUE, 8),
  ('ManagerDecision',      'Manager Decision',      'Condition set by vehicle service manager review decision', TRUE, 9),
  ('Other',                'Other',                'Other operational reason recorded in notes', TRUE, 10)
ON CONFLICT (condition_reason_code) DO UPDATE
SET status_reason_name = EXCLUDED.status_reason_name,
    description = EXCLUDED.description,
    is_active = TRUE,
    sort_order = EXCLUDED.sort_order;

-- 4. Foreign key on fs.vehicle.condition_reason_code
DO $$ BEGIN
  ALTER TABLE fs.vehicle ADD CONSTRAINT fk_vehicle_condition_reason
  FOREIGN KEY (condition_reason_code) REFERENCES fs.vehicle_condition_reason (condition_reason_code) ON DELETE RESTRICT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 5. Unique constraint on fs.vehicle_condition_transition_rule
DO $$ BEGIN
  ALTER TABLE fs.vehicle_condition_transition_rule ADD CONSTRAINT uq_condition_transition UNIQUE (from_condition_code, to_condition_code);
EXCEPTION WHEN duplicate_table OR duplicate_object THEN NULL;
END $$;

-- 6. Seed fs.vehicle_condition_transition_rule (8.4-R06, 8.4-C18)
INSERT INTO fs.vehicle_condition_transition_rule (from_condition_code, to_condition_code, requires_approval, is_active)
VALUES
  -- From Returned:
  ('Returned', 'Prep',   FALSE, TRUE),
  ('Returned', 'Review', FALSE, TRUE),
  ('Returned', 'Down',   FALSE, TRUE),

  -- From Arrived:
  ('Arrived',  'Prep',   FALSE, TRUE),
  ('Arrived',  'Review', FALSE, TRUE),
  ('Arrived',  'Down',   FALSE, TRUE),

  -- From Review (8.4-R08: Exactly two exits):
  ('Review',   'Prep',   TRUE,  TRUE),
  ('Review',   'Down',   TRUE,  TRUE),

  -- From Prep:
  ('Prep',     'Ready',  FALSE, TRUE),
  ('Prep',     'Review', FALSE, TRUE),
  ('Prep',     'Down',   FALSE, TRUE),

  -- From Ready:
  ('Ready',    'Prep',   FALSE, TRUE),
  ('Ready',    'Down',   FALSE, TRUE),

  -- From Down:
  ('Down',     'Prep',   FALSE, TRUE),
  ('Down',     'Ready',  FALSE, TRUE),
  ('Down',     'Down',   FALSE, TRUE)
ON CONFLICT (from_condition_code, to_condition_code) DO UPDATE
SET requires_approval = EXCLUDED.requires_approval,
    is_active = EXCLUDED.is_active;

-- 7. Ensure task_type_select has CONDITION_REVIEW_DECISION
INSERT INTO fs.task_type_select (task_type_code, task_type_name, description, is_active)
VALUES
  ('CONDITION_REVIEW_DECISION', 'Condition Review Decision', 'Vehicle service manager review decision on moderate check-in issue', TRUE)
ON CONFLICT (task_type_code) DO NOTHING;

COMMIT;
