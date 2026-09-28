-- Migration 015: Seed fs.target_table_select for polymorphic task/document/form links

BEGIN;

INSERT INTO fs.target_table_select (target_table_code, display_name, allows_document_link, allows_task_link, allows_form_target, sort_order, is_active)
VALUES
  ('vehicle',             'Vehicle',             TRUE, TRUE, TRUE, 1,  TRUE),
  ('VEHICLE',             'Vehicle',             TRUE, TRUE, TRUE, 2,  TRUE),
  ('member',              'Member',              TRUE, TRUE, TRUE, 3,  TRUE),
  ('MEMBER',              'Member',              TRUE, TRUE, TRUE, 4,  TRUE),
  ('vehicle_reservation', 'Vehicle Reservation', TRUE, TRUE, TRUE, 5,  TRUE),
  ('reservation',         'Reservation',         TRUE, TRUE, TRUE, 6,  TRUE),
  ('branch',              'Branch',              TRUE, TRUE, TRUE, 7,  TRUE),
  ('incident',            'Incident',            TRUE, TRUE, TRUE, 8,  TRUE),
  ('user',                'User',                TRUE, TRUE, TRUE, 9,  TRUE),
  ('contract',            'Contract',            TRUE, TRUE, TRUE, 10, TRUE),
  ('lead',                'Lead',                TRUE, TRUE, TRUE, 11, TRUE),
  ('invoice',             'Invoice',             TRUE, TRUE, TRUE, 12, TRUE),
  ('payment',             'Payment',             TRUE, TRUE, TRUE, 13, TRUE),
  ('task',                'Task',                TRUE, TRUE, TRUE, 14, TRUE)
ON CONFLICT (target_table_code) DO NOTHING;

COMMIT;
