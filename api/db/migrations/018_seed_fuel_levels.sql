-- Migration 018: Seed Vehicle Fuel Level Select (Appendix D)

BEGIN;

INSERT INTO fs.vehicle_fuel_level_select (fuel_level_code, label, fuel_percent, sort_order, is_active)
VALUES
  ('Full',  'Full',  100, 1, TRUE),
  ('7/8',   '7/8',   88,  2, TRUE),
  ('3/4',   '3/4',   75,  3, TRUE),
  ('5/8',   '5/8',   63,  4, TRUE),
  ('1/2',   '1/2',   50,  5, TRUE),
  ('3/8',   '3/8',   38,  6, TRUE),
  ('1/4',   '1/4',   25,  7, TRUE),
  ('1/8',   '1/8',   13,  8, TRUE),
  ('Empty', 'Empty', 0,   9, TRUE)
ON CONFLICT (fuel_level_code) DO NOTHING;

COMMIT;
