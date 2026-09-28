-- Migration 013: Stage 2 Podium Status Seeds (Appendix D & Guide 6.13 / 8.5 / 8.6)

BEGIN;

INSERT INTO fs.podium_status_select (podium_status_code, podium_status_name, description, laps_required, sort_order, is_active)
VALUES
  ('SILVER',   'Silver',   'Silver Podium Status',                   10,  1, TRUE),
  ('GOLD',     'Gold',     'Gold Podium Status',                     25,  2, TRUE),
  ('PLATINUM', 'Platinum', 'Platinum Podium Status',                 50,  3, TRUE),
  ('BLACK',    'Black',    'Black Podium Status (Highest level)',    100, 4, TRUE)
ON CONFLICT (podium_status_code) DO UPDATE
SET podium_status_name = EXCLUDED.podium_status_name,
    description = EXCLUDED.description,
    laps_required = EXCLUDED.laps_required,
    sort_order = EXCLUDED.sort_order,
    is_active = TRUE;

COMMIT;
