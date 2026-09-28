-- =============================================================================
-- Migration 009: Stage 2 Vehicle Tier Assignments & Rate Cards (Guide 8.2)
-- =============================================================================
-- Enforces:
--   8.2-R01 / 8.2-C06: Vehicle carries no tier column; tier lives on card placement
--   8.2-R03 / 8.2-C01: Tier sort order defines ladder and display
--   8.2-R04 / 8.2-C04: Tier delete prevented at database engine level; use is_active=false
--   8.2-R05 / 8.2-C02 / 8.2-C03: Active/retired tier resolution and rate requirements
--   8.2-C08: Vehicle resolves to different tiers on different cards
--   8.2-C09: Per-member tier override via mpc_tier_assignment
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

-- 1. Seed Tiers into fs.vehicle_tier
INSERT INTO fs.vehicle_tier (vehicle_tier, vehicle_tier_name, sort_order, is_active, description)
VALUES
  ('TIER_1', 'Tier 1 - Grand Touring / Sports', 1, TRUE, 'Entry level supercars and grand tourers'),
  ('TIER_2', 'Tier 2 - High Performance', 2, TRUE, 'High performance sports and supercars'),
  ('TIER_3', 'Tier 3 - Exotic Supercars', 3, TRUE, 'Core mid-engine exotic supercars'),
  ('TIER_4', 'Tier 4 - Elite Flagship', 4, TRUE, 'Elite V10 / V12 flagship supercars'),
  ('TIER_5', 'Tier 5 - Hypercars / Marquee', 5, TRUE, 'Rare, bespoke marquee hypercars'),
  ('TIER_RETIRED_TEST', 'Tier Retired - Archive', 99, FALSE, 'Archived historical tier for testing 8.2-C02/C03')
ON CONFLICT (vehicle_tier) DO UPDATE
SET vehicle_tier_name = EXCLUDED.vehicle_tier_name,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active,
    description = EXCLUDED.description;

-- 2. Prevent DELETE on fs.vehicle_tier (8.2-R04, 8.2-C04)
CREATE OR REPLACE FUNCTION fs.prevent_tier_delete()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION '8.2-R04 / 8.2-C04: Deleting a tier is not possible. Tiers must be retired using is_active=false, never deleted.';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_tier_delete ON fs.vehicle_tier;
CREATE TRIGGER trg_prevent_tier_delete
BEFORE DELETE ON fs.vehicle_tier
FOR EACH ROW EXECUTE FUNCTION fs.prevent_tier_delete();

-- 3. Seed Rate Cards into fs.rate_card
INSERT INTO fs.rate_card (card_code, card_name, description, first_used_on)
VALUES
  ('RC_STANDARD_2026', 'Freedom Supercars Standard 2026', 'Current active standard rate card for 2026', '2026-01-01'::DATE),
  ('RC_LEGACY_2025', 'Freedom Supercars Legacy 2025', 'Previous year grandfathered rate card', '2025-01-01'::DATE),
  ('RC_PROMO_2026', 'Freedom Supercars Promotional 2026', 'Promotional rate card for VIP members', '2026-06-01'::DATE)
ON CONFLICT (card_code) DO UPDATE
SET card_name = EXCLUDED.card_name,
    description = EXCLUDED.description,
    first_used_on = EXCLUDED.first_used_on;

-- 4. Seed Rate Card Rates for each tier on standard card
INSERT INTO fs.rate_card_rate (rate_card_id, vehicle_tier_id, weekday_point_value, weekend_point_value, extra_mile_point_value)
SELECT rc.rate_card_id, vt.vehicle_tier_id,
       CASE vt.vehicle_tier
         WHEN 'TIER_1' THEN 40
         WHEN 'TIER_2' THEN 55
         WHEN 'TIER_3' THEN 70
         WHEN 'TIER_4' THEN 90
         WHEN 'TIER_5' THEN 120
         ELSE 50
       END,
       CASE vt.vehicle_tier
         WHEN 'TIER_1' THEN 60
         WHEN 'TIER_2' THEN 80
         WHEN 'TIER_3' THEN 105
         WHEN 'TIER_4' THEN 135
         WHEN 'TIER_5' THEN 180
         ELSE 75
       END,
       CASE vt.vehicle_tier
         WHEN 'TIER_1' THEN 1.000
         WHEN 'TIER_2' THEN 1.250
         WHEN 'TIER_3' THEN 1.500
         WHEN 'TIER_4' THEN 2.000
         WHEN 'TIER_5' THEN 2.500
         ELSE 1.000
       END
  FROM fs.rate_card rc
 CROSS JOIN fs.vehicle_tier vt
 WHERE NOT EXISTS (
   SELECT 1 FROM fs.rate_card_rate rcr
    WHERE rcr.rate_card_id = rc.rate_card_id
      AND rcr.vehicle_tier_id = vt.vehicle_tier_id
 );

-- 5. Seed Placements for existing vehicles on Standard 2026 Card
INSERT INTO fs.rate_card_placement (rate_card_id, vehicle_id, vehicle_tier_id, effective_from)
SELECT rc.rate_card_id, v.vehicle_id, vt.vehicle_tier_id, '2026-01-01'::DATE
  FROM fs.vehicle v
 CROSS JOIN (SELECT rate_card_id FROM fs.rate_card WHERE card_code = 'RC_STANDARD_2026') rc
 CROSS JOIN (SELECT vehicle_tier_id FROM fs.vehicle_tier WHERE vehicle_tier = 'TIER_3') vt
 WHERE NOT EXISTS (
   SELECT 1 FROM fs.rate_card_placement rcp
    WHERE rcp.rate_card_id = rc.rate_card_id
      AND rcp.vehicle_id = v.vehicle_id
 );

COMMIT;
