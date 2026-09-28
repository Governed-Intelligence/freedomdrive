-- =============================================================================
-- Migration 023: Seed 'HOU' into fs.branch and align fs.member_branch_history FKs
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

-- 1. Ensure Houston (HOU) is seeded in fs.branch
INSERT INTO fs.branch (
  branch_code, branch_name, branch_type, time_zone,
  address_physical, city_physical, state_physical, zip_physical, is_active
)
VALUES (
  'HOU', 'Freedom Supercars Houston', 'Main'::fs.branch_branch_type_enum, 'America/Chicago',
  '2119 Brittmoore Rd', 'Houston', 'TX', '77043', TRUE
)
ON CONFLICT (branch_code) DO NOTHING;

-- 2. Align any existing member_branch_history rows where branch_id might have pointed to fs.locations(id)
UPDATE fs.member_branch_history h
   SET branch_id = b.branch_id
  FROM fs.branch b
 WHERE b.branch_code = 'HOU'
   AND (h.branch_id IS NULL OR h.branch_id NOT IN (SELECT branch_id FROM fs.branch));

COMMIT;
