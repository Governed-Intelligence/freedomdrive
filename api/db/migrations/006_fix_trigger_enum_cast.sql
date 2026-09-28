-- =============================================================================
-- Migration 006: Fix trigger text cast for member status comparison
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

CREATE OR REPLACE FUNCTION fs.sync_members_to_member()
RETURNS TRIGGER AS $$
BEGIN
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
        WHEN NEW.status::text = 'cancelled' THEN 'Cancelled'::fs.member_lifecycle_status_enum
        WHEN NEW.status::text = 'suspended' THEN 'Suspended'::fs.member_lifecycle_status_enum
        ELSE 'Prospect'::fs.member_lifecycle_status_enum
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

COMMIT;
