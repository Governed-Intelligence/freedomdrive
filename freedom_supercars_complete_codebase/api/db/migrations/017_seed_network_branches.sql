-- Migration 017: Seed Network Branches (DFW, ATX, MIA)

BEGIN;

INSERT INTO fs.locations (code, name, address_line1, city, state, postal_code, phone, email, timezone, opened_on)
VALUES
  ('DFW', 'Freedom Supercars Dallas-Fort Worth', '1234 Motorway Blvd', 'Dallas', 'TX', '75201', '214-555-0199', 'dfw@freedomsupercars.com', 'America/Chicago', '2015-01-01'),
  ('ATX', 'Freedom Supercars Austin', '500 Congress Ave', 'Austin', 'TX', '78701', '512-555-0188', 'atx@freedomsupercars.com', 'America/Chicago', '2018-01-01'),
  ('MIA', 'Freedom Supercars Miami', '1000 Ocean Dr', 'Miami', 'FL', '33139', '305-555-0177', 'mia@freedomsupercars.com', 'America/New_York', '2020-01-01')
ON CONFLICT (code) DO NOTHING;

INSERT INTO fs.branch (
  branch_code, branch_name, branch_type, time_zone,
  address_physical, city_physical, state_physical, zip_physical, is_active
)
VALUES
  ('DFW', 'Freedom Supercars Dallas-Fort Worth', 'Main'::fs.branch_branch_type_enum, 'America/Chicago', '1234 Motorway Blvd', 'Dallas', 'TX', '75201', TRUE),
  ('ATX', 'Freedom Supercars Austin', 'Satellite'::fs.branch_branch_type_enum, 'America/Chicago', '500 Congress Ave', 'Austin', 'TX', '78701', TRUE),
  ('MIA', 'Freedom Supercars Miami', 'Satellite'::fs.branch_branch_type_enum, 'America/New_York', '1000 Ocean Dr', 'Miami', 'FL', '33139', TRUE)
ON CONFLICT (branch_code) DO NOTHING;

COMMIT;
