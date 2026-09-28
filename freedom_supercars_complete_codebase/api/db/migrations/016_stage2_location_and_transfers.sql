-- Migration 016: Stage 2 Vehicle Location and Transfers (Guide 8.7)
-- Seeds inspection types for transfers and ensures lookup tables are populated

BEGIN;

-- 1. Seed fs.vehicle_inspection_type (Appendix D & Guide 8.7)
INSERT INTO fs.vehicle_inspection_type (inspection_type_code, label, description, is_active, sort_order)
VALUES
  ('Initial',        'Initial',        'Initial inspection during intake and acquisition', TRUE, 1),
  ('Checkout',       'Checkout',       'Inspection before vehicle leaves on a trip or use', TRUE, 2),
  ('Check-In',       'Check-In',       'Inspection when vehicle returns from a trip or use', TRUE, 3),
  ('Checkup',        'Checkup',        'Mid-trip or routine periodic checkup', TRUE, 4),
  ('Handoff',        'Handoff',        'Staff to member or member to staff handoff inspection', TRUE, 5),
  ('Transfer Out',   'Transfer Out',   'Departure inspection before branch transfer transit begins', TRUE, 6),
  ('Transfer In',    'Transfer In',    'Arrival inspection when vehicle arrives from branch transfer', TRUE, 7),
  ('TransferOut',    'Transfer Out',   'Departure inspection code alias', TRUE, 8),
  ('TransferIn',     'Transfer In',    'Arrival inspection code alias', TRUE, 9),
  ('Damage',         'Damage',         'Inspection dedicated to damage documentation', TRUE, 10),
  ('Fuel',           'Fuel',           'Fuel level reading inspection', TRUE, 11),
  ('Wheels & Tires', 'Wheels & Tires', 'Dedicated wheel and tire wear/pressure inspection', TRUE, 12),
  ('Item Left',      'Item Left',      'Inspection logging personal items left behind', TRUE, 13)
ON CONFLICT (inspection_type_code) DO UPDATE
SET label = EXCLUDED.label,
    description = EXCLUDED.description,
    is_active = TRUE,
    sort_order = EXCLUDED.sort_order;

-- 2. Ensure indexes on fs.vehicle_location
CREATE INDEX IF NOT EXISTS idx_vehicle_location_veh_dates ON fs.vehicle_location (vehicle_id, effective_from, effective_to);

-- 3. Ensure indexes on fs.vehicle_inspection_transfer
CREATE INDEX IF NOT EXISTS idx_inspection_transfer_veh_type ON fs.vehicle_inspection_transfer (vehicle_id, inspection_type_code, inspected_at DESC);

COMMIT;
