-- =============================================================================
-- Migration 021: Guide 6.3 Member Identity and Numbering
-- Implements:
-- 1. Club-wide sequential member numbering (6.3-R02, 6.3-R04, 6.3-R05, 6.3-R06)
-- 2. Format: YYYY-BRN-000-000 (e.g. 2026-HOU-000-001) per Guide 6.3 p. 16
-- 3. preferred_name and member_seq fields on fs.members and fs.member
-- 4. Complete MEMBER_BRANCH_HISTORY table & trigger tracking (6.3-R08, 6.3-R09)
-- 5. Backfill & normalize existing 11 authoritative members
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

-- 1. Create club-wide member sequence
CREATE SEQUENCE IF NOT EXISTS fs.member_number_seq START 1;

-- 2. Ensure columns exist on operational fs.members table
ALTER TABLE fs.members ADD COLUMN IF NOT EXISTS member_seq INTEGER UNIQUE;
ALTER TABLE fs.members ADD COLUMN IF NOT EXISTS preferred_name VARCHAR(80);

-- 3. Ensure columns exist on canonical fs.member table
ALTER TABLE fs.member ADD COLUMN IF NOT EXISTS preferred_name VARCHAR(80);
ALTER TABLE fs.member ADD COLUMN IF NOT EXISTS member_seq INTEGER UNIQUE;

-- 4. Create formatting function for authoritative member numbers
-- Format: YYYY-BRN-XXX-XXX (e.g. 2009-HOU-000-005, 2026-HOU-000-001)
CREATE OR REPLACE FUNCTION fs.format_member_number(p_year INT, p_branch_code TEXT, p_seq INT)
RETURNS VARCHAR(25) AS $$
DECLARE
  v_padded TEXT;
BEGIN
  IF p_year IS NULL OR p_branch_code IS NULL OR p_seq IS NULL THEN
    RETURN NULL;
  END IF;
  v_padded := LPAD(p_seq::text, 6, '0');
  RETURN p_year::text || '-' || UPPER(TRIM(p_branch_code)) || '-' || SUBSTRING(v_padded, 1, 3) || '-' || SUBSTRING(v_padded, 4, 3);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 5. Ensure fs.member_branch_history table exists with proper indexes
CREATE TABLE IF NOT EXISTS fs.member_branch_history (
    member_branch_history_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID NOT NULL REFERENCES fs.members(id) ON DELETE CASCADE,
    branch_id                           UUID REFERENCES fs.locations(id),
    effective_from                      DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_to                        DATE,
    reason                              VARCHAR(200),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);

CREATE INDEX IF NOT EXISTS idx_member_branch_history_member 
    ON fs.member_branch_history(member_id);
CREATE INDEX IF NOT EXISTS idx_member_branch_history_open 
    ON fs.member_branch_history(member_id) WHERE effective_to IS NULL;

-- 6. Update sync trigger between fs.members and fs.member
CREATE OR REPLACE FUNCTION fs.sync_members_to_member()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.member_number IS NOT NULL THEN
    UPDATE fs.member SET member_number = NULL
     WHERE member_number = NEW.member_number AND member_id <> NEW.id;
  END IF;

  INSERT INTO fs.member (
      member_id, member_seq, member_number, first_name, middle_name, last_name, preferred_name,
      license_number, license_state, license_expires_on,
      date_of_birth, member_since, home_branch_id, lifecycle_status,
      created_at, updated_at
  ) VALUES (
      NEW.id, NEW.member_seq, NEW.member_number, NEW.first_name, NEW.middle_name, NEW.last_name, NEW.preferred_name,
      NEW.drivers_license_number, NEW.drivers_license_state, NEW.drivers_license_expires,
      NEW.date_of_birth, NEW.joined_on, NEW.primary_location_id,
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

-- 7. Normalize the 11 Authoritative Members to Guide 6.3 Canonical Numbers & Sequences
DO $$
DECLARE
    v_hou_id UUID;
    r RECORD;
BEGIN
    SELECT id INTO v_hou_id FROM fs.locations WHERE code = 'HOU';

    -- Clear legacy member numbers in fs.member to avoid collision during renumbering
    UPDATE fs.member SET member_number = NULL;

    FOR r IN (
      SELECT 'marcus.vance.test@freedomsupercars.com' AS em, 1 AS seq, 2026 AS yr, 'Marcus' AS fn, 'Marcus' AS pref UNION ALL
      SELECT 'james.whitaker@freedomsupercars.com', 2, 2026, 'James', 'Jim' UNION ALL
      SELECT 'blaine.sweatt@freedomsupercars.com', 3, 2026, 'Blaine', 'Blaine' UNION ALL
      SELECT 'marc.smith@freedomsupercars.com', 4, 2025, 'Marc', 'Marc' UNION ALL
      SELECT 'cmiguez@smeprotech.com', 5, 2026, 'Carlos', 'Carlos' UNION ALL
      SELECT 'admin@freedomsupercars.com', 6, 2025, 'Club', 'Admin' UNION ALL
      SELECT 'elena.rostova@freedomsupercars.com', 7, 2026, 'Elena', 'Elena' UNION ALL
      SELECT 'david.sterling@freedomsupercars.com', 8, 2026, 'David', 'Dave' UNION ALL
      SELECT 'alex.rossi@freedomsupercars.com', 9, 2026, 'Alexander', 'Alex' UNION ALL
      SELECT 'jordan.reyes@freedomsupercars.com', 10, 2026, 'Jordan', 'Jordan' UNION ALL
      SELECT 'priya.natarajan@freedomsupercars.com', 11, 2026, 'Priya', 'Priya'
    ) LOOP
      UPDATE fs.members
         SET member_seq = r.seq,
             member_number = fs.format_member_number(r.yr, 'HOU', r.seq),
             preferred_name = r.pref,
             status = 'active',
             primary_location_id = v_hou_id,
             updated_at = now()
       WHERE email = r.em;

      -- Seed branch history row if none exists (6.3-R08)
      INSERT INTO fs.member_branch_history (member_id, branch_id, effective_from, effective_to, reason)
      SELECT m.id, v_hou_id, COALESCE(m.joined_on, '2026-01-01'::date), NULL, 'Charter Member'
        FROM fs.members m
       WHERE m.email = r.em
         AND NOT EXISTS (SELECT 1 FROM fs.member_branch_history h WHERE h.member_id = m.id);
    END LOOP;

    -- Advance sequence to current count
    PERFORM setval('fs.member_number_seq', 11, true);

END $$;

COMMIT;
