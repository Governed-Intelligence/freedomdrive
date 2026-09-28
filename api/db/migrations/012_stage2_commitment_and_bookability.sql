-- Migration 012: Stage 2 Vehicle Commitment & Bookability (Guide 8.5)

BEGIN;

-- 1. Create RESTRICTED_DATE_TYPE_SELECT lookup table
CREATE TABLE IF NOT EXISTS fs.restricted_date_type_select (
    restricted_date_type_code VARCHAR(30) PRIMARY KEY,
    type_name VARCHAR(80),
    description TEXT,
    blocks_outright BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    sort_order INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id UUID,
    updated_by_user_id UUID
);

-- Seed restricted date types
INSERT INTO fs.restricted_date_type_select (restricted_date_type_code, type_name, description, blocks_outright, is_active, sort_order)
VALUES
  ('HOLIDAY', 'Holiday', 'Days the club does not hand over or receive vehicles (e.g. Christmas)', TRUE, TRUE, 1),
  ('CLUB_CLOSURE', 'Club Closure', 'Club facility closed for maintenance or staff training', TRUE, TRUE, 2),
  ('SPECIAL_EVENT', 'Special Event', 'Track day or club gala where fleet handovers are blocked', FALSE, TRUE, 3)
ON CONFLICT (restricted_date_type_code) DO UPDATE
SET type_name = EXCLUDED.type_name,
    description = EXCLUDED.description,
    blocks_outright = EXCLUDED.blocks_outright,
    is_active = TRUE;

-- 2. Create RESERVATION_RESTRICTED_DATES table
CREATE TABLE IF NOT EXISTS fs.reservation_restricted_dates (
    reservation_restricted_date_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id UUID REFERENCES fs.branch (branch_id) ON DELETE RESTRICT,
    restricted_date_type_code VARCHAR(30) REFERENCES fs.restricted_date_type_select (restricted_date_type_code) ON DELETE RESTRICT,
    holiday_definition_id UUID,
    restriction_name VARCHAR(150),
    description TEXT,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id UUID,
    updated_by_user_id UUID
);

CREATE INDEX IF NOT EXISTS idx_reservation_restricted_dates_dates ON fs.reservation_restricted_dates (start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_reservation_restricted_dates_branch ON fs.reservation_restricted_dates (branch_id);

-- 3. Create VEHICLE_RELEASE_ROW table
CREATE TABLE IF NOT EXISTS fs.vehicle_release_row (
    vehicle_release_row_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id UUID REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT,
    sort_order INTEGER DEFAULT 1,
    duration_days INTEGER DEFAULT 14,
    minimum_podium_status_code VARCHAR(40),
    hide_from_lower_tiers BOOLEAN DEFAULT FALSE,
    applied_from_template_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id UUID,
    updated_by_user_id UUID
);

CREATE INDEX IF NOT EXISTS idx_vehicle_release_row_vehicle ON fs.vehicle_release_row (vehicle_id);

-- 4. Seed reservation_type_select (Member, Service, InternalBlock, Event)
INSERT INTO fs.reservation_type_select (reservation_type_code, name, description, sort_order, is_active)
VALUES
  ('Member',        'Member Reservation', 'Standard member reservation for leisure or driving experience', 1, TRUE),
  ('Service',       'Service Reservation', 'Vehicle service, maintenance, or repair booking', 2, TRUE),
  ('InternalBlock', 'Internal Block',      'Club operational hold, staff movement, or logistical block', 3, TRUE),
  ('Event',         'Club Event',          'Showcase, rally, photoshoot, or club marketing event', 4, TRUE)
ON CONFLICT (reservation_type_code) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = TRUE;

-- 5. Seed reservation_status_select
INSERT INTO fs.reservation_status_select (reservation_status_code, name, description, sort_order, is_active)
VALUES
  ('Tentative', 'Tentative', 'Provisional or unconfirmed hold', 1, TRUE),
  ('Confirmed', 'Confirmed', 'Guaranteed booking taking the calendar window', 2, TRUE),
  ('Held',      'Held',      'Booking placed on hold due to watch, withhold, or review', 3, TRUE),
  ('Cancelled', 'Cancelled', 'Booking cancelled by member or club', 4, TRUE),
  ('Completed', 'Completed', 'Trip finished and vehicle returned', 5, TRUE)
ON CONFLICT (reservation_status_code) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = TRUE;

-- 6. Ensure reservation_withhold_reason_select has all canonical reasons
INSERT INTO fs.reservation_withhold_reason_select (withhold_reason_code, label, is_system_placed, is_active, sort_order)
VALUES
  ('Weather',     'Weather Disruption', FALSE, TRUE, 6),
  ('SalePending', 'Sale Pending',       FALSE, TRUE, 7),
  ('Safety',      'Safety Recall/Hold', TRUE,  TRUE, 8),
  ('Marketing',   'Marketing / Promo',  FALSE, TRUE, 9),
  ('Other',       'Other Withhold',     FALSE, TRUE, 10)
ON CONFLICT (withhold_reason_code) DO UPDATE
SET label = EXCLUDED.label, is_active = TRUE;

-- 7. Seed reservation_source_type_select
INSERT INTO fs.reservation_source_type_select (source_type_code, source_type_name, description, sort_order, is_active)
VALUES
  ('MemberApp',   'Member App',       'Direct booking made by member via mobile or web app', 1, TRUE),
  ('StaffPortal', 'Staff Portal',     'Booking entered by staff member on behalf of member', 2, TRUE),
  ('System',      'System Automated', 'System generated reservation or block',               3, TRUE)
ON CONFLICT (source_type_code) DO UPDATE
SET source_type_name = EXCLUDED.source_type_name,
    description = EXCLUDED.description,
    is_active = TRUE;

-- 8. Seed reservation_status_reason_select
INSERT INTO fs.reservation_status_reason_select (
  status_reason_code, status_reason_name, applies_to_status,
  charges_cancellation_allowance, is_system_reason, requires_note, is_active, sort_order
)
VALUES
  ('WeatherHold',    'Weather Watch Hold',         'Held',      FALSE, TRUE,  FALSE, TRUE, 1),
  ('StaffHold',      'Staff Hold for Review',      'Held',      FALSE, FALSE, FALSE, TRUE, 2),
  ('ClubCancelled',  'Cancelled by Club',          'Cancelled', FALSE, TRUE,  FALSE, TRUE, 3),
  ('MemberCancelled','Cancelled by Member',        'Cancelled', TRUE,  FALSE, FALSE, TRUE, 4),
  ('WatchEscalated', 'Watch Escalated to Withhold','Cancelled', FALSE, TRUE,  FALSE, TRUE, 5)
ON CONFLICT (status_reason_code) DO UPDATE
SET status_reason_name = EXCLUDED.status_reason_name,
    applies_to_status = EXCLUDED.applies_to_status,
    charges_cancellation_allowance = EXCLUDED.charges_cancellation_allowance,
    is_active = TRUE;

COMMIT;

