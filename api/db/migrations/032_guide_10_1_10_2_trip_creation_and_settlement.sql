-- =============================================================================
-- Migration 032: Guide 10.1 & 10.2 Trip Creation, Custody, and Settlement
-- =============================================================================

-- 1. Add 'checked_out' and 'completed' to fs.reservation_status enum if not present (outside transaction)
ALTER TYPE fs.reservation_status ADD VALUE IF NOT EXISTS 'checked_out';
ALTER TYPE fs.reservation_status ADD VALUE IF NOT EXISTS 'completed';

BEGIN;

SET search_path TO fs, public;

-- 2. Seed fs.vehicle_trip_type_select if empty
INSERT INTO fs.vehicle_trip_type_select (trip_type_code, label, description, is_revenue, posts_points, sort_order, is_active)
VALUES
  ('member',    'Member Trip',     'Standard reservation trip by an active club member', TRUE,  TRUE,  1, TRUE),
  ('service',   'Service Trip',    'Maintenance, repair, or vendor logistics trip',     FALSE, FALSE, 2, TRUE),
  ('transport', 'Branch Transfer', 'Repositioning or inter-branch transfer',             FALSE, FALSE, 3, TRUE),
  ('internal',  'Internal Use',    'Staff, marketing, or promotional club driving',      FALSE, FALSE, 4, TRUE),
  ('event',     'Club Event',      'Driving tour, track day, or club member rally',      TRUE,  FALSE, 5, TRUE)
ON CONFLICT (trip_type_code) DO UPDATE
SET is_revenue = EXCLUDED.is_revenue,
    posts_points = EXCLUDED.posts_points,
    is_active = TRUE;

-- 3. Synchronize fs.reservations into fs.vehicle_reservation so canonical FKs succeed
CREATE OR REPLACE FUNCTION fs.sync_reservation_to_vehicle_reservation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_status_code VARCHAR(40);
  v_type_code   VARCHAR(40);
BEGIN
  -- Map reservation status to reservation_status_select codes
  v_status_code := CASE NEW.status::text
    WHEN 'tentative'   THEN 'Tentative'
    WHEN 'confirmed'   THEN 'Confirmed'
    WHEN 'checked_out' THEN 'Checked Out'
    WHEN 'completed'   THEN 'Completed'
    WHEN 'cancelled'   THEN 'Cancelled'
    ELSE 'Confirmed'
  END;

  v_type_code := CASE WHEN COALESCE(NEW.is_courtesy, FALSE) THEN 'Courtesy' ELSE 'Member' END;

  -- Ensure reservation_status_select has the code
  INSERT INTO fs.reservation_status_select (reservation_status_code, name, is_active)
  VALUES (v_status_code, v_status_code, TRUE)
  ON CONFLICT (reservation_status_code) DO NOTHING;

  -- Upsert into canonical vehicle_reservation
  INSERT INTO fs.vehicle_reservation (
    vehicle_reservation_id,
    vehicle_id,
    member_id,
    member_package_id,
    reserving_branch_id,
    start_time_scheduled,
    end_time_scheduled,
    reservation_status_code,
    reservation_type_code,
    start_location_code,
    end_location_code,
    created_at,
    updated_at
  ) VALUES (
    NEW.id,
    NEW.vehicle_id,
    NEW.member_id,
    (SELECT member_package_id FROM fs.member_package WHERE member_package_id = NEW.subscription_id),
    (SELECT branch_id FROM fs.branch WHERE branch_id = (SELECT location_id FROM fs.vehicles WHERE id = NEW.vehicle_id)),
    NEW.pickup_at,
    NEW.return_at,
    v_status_code,
    'Member',
    NULL,
    NULL,
    NEW.created_at,
    now()
  )
  ON CONFLICT (vehicle_reservation_id) DO UPDATE
  SET vehicle_id = EXCLUDED.vehicle_id,
      member_id = EXCLUDED.member_id,
      start_time_scheduled = EXCLUDED.start_time_scheduled,
      end_time_scheduled = EXCLUDED.end_time_scheduled,
      reservation_status_code = EXCLUDED.reservation_status_code,
      updated_at = now();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_reservation_to_canonical ON fs.reservations;
CREATE TRIGGER trg_sync_reservation_to_canonical
AFTER INSERT OR UPDATE ON fs.reservations
FOR EACH ROW EXECUTE FUNCTION fs.sync_reservation_to_vehicle_reservation();

-- Populate existing reservations into fs.vehicle_reservation
INSERT INTO fs.reservation_status_select (reservation_status_code, name, is_active)
VALUES ('Tentative', 'Tentative', TRUE),
       ('Confirmed', 'Confirmed', TRUE),
       ('Checked Out', 'Checked Out', TRUE),
       ('Completed', 'Completed', TRUE),
       ('Cancelled', 'Cancelled', TRUE)
ON CONFLICT (reservation_status_code) DO NOTHING;

INSERT INTO fs.vehicle_reservation (
  vehicle_reservation_id,
  vehicle_id,
  member_id,
  member_package_id,
  reserving_branch_id,
  start_time_scheduled,
  end_time_scheduled,
  reservation_status_code,
  reservation_type_code,
  start_location_code,
  end_location_code,
  created_at,
  updated_at
)
SELECT
  r.id,
  r.vehicle_id,
  r.member_id,
  (SELECT member_package_id FROM fs.member_package WHERE member_package_id = r.subscription_id),
  (SELECT branch_id FROM fs.branch WHERE branch_id = v.location_id),
  r.pickup_at,
  r.return_at,
  CASE r.status::text
    WHEN 'tentative'   THEN 'Tentative'
    WHEN 'confirmed'   THEN 'Confirmed'
    WHEN 'checked_out' THEN 'Checked Out'
    WHEN 'completed'   THEN 'Completed'
    WHEN 'cancelled'   THEN 'Cancelled'
    ELSE 'Confirmed'
  END,
  'Member',
  NULL,
  NULL,
  r.created_at,
  r.updated_at
FROM fs.reservations r
LEFT JOIN fs.vehicles v ON v.id = r.vehicle_id
ON CONFLICT (vehicle_reservation_id) DO NOTHING;

COMMIT;
