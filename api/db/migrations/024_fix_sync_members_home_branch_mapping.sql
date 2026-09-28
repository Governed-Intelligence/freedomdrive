-- =============================================================================
-- Migration 024: Fix fs.sync_members_to_member home_branch_id FK mapping
-- Maps fs.members.primary_location_id (locations.id) to fs.branch.branch_id
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

CREATE OR REPLACE FUNCTION fs.sync_members_to_member()
RETURNS TRIGGER AS $$
DECLARE
  v_branch_id UUID := NULL;
BEGIN
  -- Prevent member_number duplicate key violation during sync
  IF NEW.member_number IS NOT NULL THEN
    UPDATE fs.member SET member_number = NULL
     WHERE member_number = NEW.member_number AND member_id <> NEW.id;
  END IF;

  -- Map from fs.locations.id to fs.branch.branch_id via branch_code
  IF NEW.primary_location_id IS NOT NULL THEN
    SELECT b.branch_id INTO v_branch_id
      FROM fs.branch b
      JOIN fs.locations l ON UPPER(l.code) = UPPER(b.branch_code)
     WHERE l.id = NEW.primary_location_id
     LIMIT 1;

    -- If no match via code join, check if primary_location_id already matches a branch_id directly
    IF v_branch_id IS NULL THEN
      SELECT branch_id INTO v_branch_id FROM fs.branch WHERE branch_id = NEW.primary_location_id LIMIT 1;
    END IF;
  END IF;

  INSERT INTO fs.member (
      member_id, member_seq, member_number, first_name, middle_name, last_name, preferred_name,
      license_number, license_state, license_expires_on,
      date_of_birth, member_since, home_branch_id, lifecycle_status,
      created_at, updated_at
  ) VALUES (
      NEW.id, NEW.member_seq, NEW.member_number, NEW.first_name, NEW.middle_name, NEW.last_name, NEW.preferred_name,
      NEW.drivers_license_number, NEW.drivers_license_state, NEW.drivers_license_expires,
      NEW.date_of_birth, NEW.joined_on, v_branch_id,
      CASE
        WHEN NEW.status::text = 'active' THEN 'Active'::fs.member_lifecycle_status_enum
        WHEN NEW.status::text IN ('former', 'expired') THEN 'Former'::fs.member_lifecycle_status_enum
        WHEN NEW.status::text IN ('cancelled', 'suspended') THEN 'Inactive'::fs.member_lifecycle_status_enum
        ELSE 'Pending'::fs.member_lifecycle_status_enum
      END,
      NEW.created_at, NEW.updated_at
  )
  ON CONFLICT (member_id) DO UPDATE SET
      member_seq = EXCLUDED.member_seq,
      member_number = EXCLUDED.member_number,
      first_name = EXCLUDED.first_name,
      middle_name = EXCLUDED.middle_name,
      last_name = EXCLUDED.last_name,
      preferred_name = EXCLUDED.preferred_name,
      license_number = EXCLUDED.license_number,
      license_state = EXCLUDED.license_state,
      license_expires_on = EXCLUDED.license_expires_on,
      date_of_birth = EXCLUDED.date_of_birth,
      member_since = EXCLUDED.member_since,
      home_branch_id = EXCLUDED.home_branch_id,
      lifecycle_status = EXCLUDED.lifecycle_status,
      updated_at = now();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update existing rows in fs.member to ensure home_branch_id is valid
UPDATE fs.member m
   SET home_branch_id = b.branch_id
  FROM fs.members o
  JOIN fs.locations l ON l.id = o.primary_location_id
  JOIN fs.branch b ON UPPER(b.branch_code) = UPPER(l.code)
 WHERE m.member_id = o.id
   AND (m.home_branch_id IS NULL OR m.home_branch_id NOT IN (SELECT branch_id FROM fs.branch));

COMMIT;
