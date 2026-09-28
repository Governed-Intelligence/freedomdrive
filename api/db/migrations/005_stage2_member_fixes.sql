-- =============================================================================
-- Migration 005: Member Schema Alignments & Operational Hardening
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

-- 1. Support middle_name, user_id, and nullable member_number on fs.members (Guide 6.1)
ALTER TABLE fs.members ADD COLUMN IF NOT EXISTS middle_name VARCHAR(100);
ALTER TABLE fs.members ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE fs.members ALTER COLUMN member_number DROP NOT NULL;

-- 2. Ensure sync trigger forwards middle_name and maps lifecycle status
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
        WHEN NEW.status = 'active' THEN 'Active'::fs.member_lifecycle_status_enum
        WHEN NEW.status = 'former' THEN 'Former'::fs.member_lifecycle_status_enum
        WHEN NEW.status = 'cancelled' THEN 'Cancelled'::fs.member_lifecycle_status_enum
        WHEN NEW.status = 'suspended' THEN 'Suspended'::fs.member_lifecycle_status_enum
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

-- 3. Operational hardening: prep buffers and idempotency from 002 if not present
ALTER TABLE fs.tiers
    ADD COLUMN IF NOT EXISTS prep_buffer_hours INTEGER NOT NULL DEFAULT 0
    CHECK (prep_buffer_hours >= 0 AND prep_buffer_hours <= 168);

ALTER TABLE fs.reservations
    ADD COLUMN IF NOT EXISTS prep_buffer_hours INTEGER NOT NULL DEFAULT 0
    CHECK (prep_buffer_hours >= 0 AND prep_buffer_hours <= 168);

ALTER TABLE fs.reservations
    ADD COLUMN IF NOT EXISTS block_until TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION fs.set_block_until()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.block_until := NEW.return_at + (NEW.prep_buffer_hours * INTERVAL '1 hour');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reservations_block_until ON fs.reservations;
CREATE TRIGGER trg_reservations_block_until
BEFORE INSERT OR UPDATE OF return_at, prep_buffer_hours ON fs.reservations
FOR EACH ROW EXECUTE FUNCTION fs.set_block_until();

UPDATE fs.reservations SET block_until = return_at + (prep_buffer_hours * INTERVAL '1 hour')
 WHERE block_until IS NULL;

ALTER TABLE fs.reservations
    ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_reservations_idempotency_key
    ON fs.reservations(idempotency_key) WHERE idempotency_key IS NOT NULL;

ALTER TABLE fs.point_transactions
    ADD COLUMN IF NOT EXISTS source_event_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_point_txn_source_event
    ON fs.point_transactions(source_event_id) WHERE source_event_id IS NOT NULL;

COMMIT;
