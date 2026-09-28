-- =============================================================================
-- Migration 029: Allow 0 points for courtesy bookings
-- Required for Guide 9.2-R10, 9.2-C16 (Courtesy bookings consume 0 points)
-- =============================================================================

ALTER TABLE fs.reservations
  DROP CONSTRAINT IF EXISTS res_points_positive;

ALTER TABLE fs.reservations
  ADD CONSTRAINT res_points_positive
  CHECK (total_points_cost >= 0);
