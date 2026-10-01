-- =============================================================================
-- Migration 034: Guide 10.3 (Trip Stories), Guide 10.4 (Service Trips),
-- and Guide 10.5 (Toll Transactions)
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

-- -----------------------------------------------------------------------------
-- 1. Member Charge Types (Guide 10.4 & 10.5)
-- -----------------------------------------------------------------------------
INSERT INTO fs.member_charge_type (charge_type_code, charge_type_name, charge_description, sort_order, is_active)
VALUES
  ('TOLL',     'Toll Charges',         'Highway, expressway and bridge tolls incurred during trip', 6, TRUE),
  ('SERVICE',  'Service & Maintenance', 'Vehicle service, maintenance, or repair recharge',         7, TRUE)
ON CONFLICT (charge_type_code) DO UPDATE
SET charge_type_name = EXCLUDED.charge_type_name,
    charge_description = EXCLUDED.charge_description,
    is_active = TRUE;

-- -----------------------------------------------------------------------------
-- 2. Toll Authorities (Guide 10.5)
-- -----------------------------------------------------------------------------
INSERT INTO fs.toll_authority_select (authority_code, authority_name, sort_order, is_active)
VALUES
  ('HCTRA',   'Harris County Toll Road Authority (EZ TAG)',         1,  TRUE),
  ('NTTA',    'North Texas Tollway Authority (TollTag)',            2,  TRUE),
  ('TxTag',   'Texas Department of Transportation (TxTag)',         3,  TRUE),
  ('SunPass', 'Florida Department of Transportation (SunPass)',     4,  TRUE),
  ('E-ZPass', 'E-ZPass Interagency Group',                         5,  TRUE),
  ('K-Tag',   'Kansas Turnpike Authority (K-TAG)',                  6,  TRUE),
  ('Pikepass','Oklahoma Turnpike Authority (Pikepass)',             7,  TRUE),
  ('FasTrak', 'California FasTrak',                                 8,  TRUE),
  ('OTHER',   'Other Toll Authority / Out-of-Network',              99, TRUE)
ON CONFLICT (authority_code) DO UPDATE
SET authority_name = EXCLUDED.authority_name,
    sort_order = EXCLUDED.sort_order,
    is_active = TRUE;

-- -----------------------------------------------------------------------------
-- 3. Service Categories, Types & Reasons (Guide 10.4)
-- -----------------------------------------------------------------------------
INSERT INTO fs.service_category (service_category_code, service_category_name, description, is_active, sort_order)
VALUES
  ('maintenance', 'Routine Maintenance',          'Regular scheduled preventive servicing',    TRUE, 1),
  ('repair',      'Mechanical / Body Repair',     'Mechanical, structural, or body repair',     TRUE, 2),
  ('inspection',  'Safety & Compliance Check',    'State, pre-track, or safety inspections',   TRUE, 3),
  ('detailing',   'Detailing & Preservation',     'Paint correction, PPF, ceramic detailing',  TRUE, 4),
  ('recall',      'Manufacturer Recall',          'OEM safety bulletin or recall campaign',    TRUE, 5)
ON CONFLICT (service_category_code) DO UPDATE
SET service_category_name = EXCLUDED.service_category_name,
    description = EXCLUDED.description,
    is_active = TRUE;

INSERT INTO fs.vehicle_service_type (service_type_code, service_category_code, service_type_name, description, is_active, sort_order)
VALUES
  ('scheduled',   'maintenance', 'Scheduled Maintenance',   'Factory maintenance interval check',   TRUE, 1),
  ('unscheduled', 'repair',      'Unscheduled Repair',      'Unplanned fix or component repair',     TRUE, 2),
  ('warranty',    'repair',      'Warranty Claim Service',  'Work covered under OEM/3rd party warranty', TRUE, 3),
  ('recall',      'recall',      'Safety Recall Service',   'Official manufacturer campaign work',   TRUE, 4),
  ('inspection',  'inspection',  'Periodic Inspection',     'State safety, emissions, or track tech',TRUE, 5),
  ('cosmetic',    'detailing',   'Cosmetic Detailing',      'Interior/exterior deep restorative prep', TRUE, 6)
ON CONFLICT (service_type_code) DO UPDATE
SET service_type_name = EXCLUDED.service_type_name,
    service_category_code = EXCLUDED.service_category_code,
    description = EXCLUDED.description,
    is_active = TRUE;

INSERT INTO fs.service_reason_select (service_reason_code, name, description, sort_order, is_active)
VALUES
  ('oil_change',       'Engine Oil & Filter Service',          'Annual or mileage lubricant change',          1, TRUE),
  ('brake_service',    'Brake Pads & Rotors Replacement',      'Brake pad or carbon ceramic maintenance',    2, TRUE),
  ('tire_replacement', 'Tire Mount & High-Speed Balancing',    'Tire replacement due to wear or track use',   3, TRUE),
  ('damage_repair',    'Curb / Body Damage Remediation',       'Repairs from incident or cosmetic road rash', 4, TRUE),
  ('electrical',       'Sensor / ECU Diagnostic',              'Electronic sensor and fault remediation',     5, TRUE),
  ('annual_service',   'Factory Annual Service',               'Comprehensive OEM factory scheduled service', 6, TRUE),
  ('other',            'Other Specialized Shop Work',          'Miscellaneous authorized service work',       7, TRUE)
ON CONFLICT (service_reason_code) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = TRUE;

-- -----------------------------------------------------------------------------
-- 4. Trip Story Prompts (Guide 10.3)
-- -----------------------------------------------------------------------------
INSERT INTO fs.member_trip_story_prompt (prompt_code, prompt_text, help_text, sort_order, is_active)
VALUES
  ('HIGHLIGHT', 'What was the highlight or defining moment of this drive?', 
   'Describe the standout moment behind the wheel or during your trip.', 1, TRUE),
  ('HANDLING',  'How did the vehicle perform and handle on your route?', 
   'Your impressions of steering response, acceleration, exhaust note, and road manners.', 2, TRUE),
  ('ROUTE',     'What favorite routes, roads, or destinations did you explore?', 
   'Scenic byways, hill country loops, coastal roads, or great dining/scenic stops.', 3, TRUE),
  ('TIPS',      'Any advice, drive modes, or tips for the next member driving this supercar?', 
   'Cabin features, luggage tips, preferred drive modes, or recommended road settings.', 4, TRUE)
ON CONFLICT (prompt_code) DO UPDATE
SET prompt_text = EXCLUDED.prompt_text,
    help_text = EXCLUDED.help_text,
    sort_order = EXCLUDED.sort_order,
    is_active = TRUE;

-- -----------------------------------------------------------------------------
-- 5. Trip Story Schema Adjustments (Guide 10.3)
-- -----------------------------------------------------------------------------
-- Add direct cover_photo_url on fs.member_trip_story
ALTER TABLE fs.member_trip_story ADD COLUMN IF NOT EXISTS cover_photo_url TEXT;

-- Enforce unique constraint for autosave upserts on answers: (member_trip_story_id, member_trip_story_prompt_id)
CREATE UNIQUE INDEX IF NOT EXISTS uq_member_trip_story_answer_story_prompt 
  ON fs.member_trip_story_answer (member_trip_story_id, member_trip_story_prompt_id);

-- -----------------------------------------------------------------------------
-- 6. Toll Deduplication Index (Guide 10.5 Developer Note 2)
-- -----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicle_toll_transaction_authority_tag_time 
  ON fs.vehicle_toll_transaction (toll_authority_code, toll_tag, transaction_at);

-- -----------------------------------------------------------------------------
-- 7. Update canonical fs.trips VIEW with Service Trip Details
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW fs.trips AS
SELECT
  t.vehicle_trip_id,
  t.vehicle_trip_id                         AS id,
  t.vehicle_reservation_id,
  t.vehicle_reservation_id                  AS reservation_id,
  t.vehicle_id,
  t.trip_type_code,
  t.start_time_actual,
  t.end_time_actual,
  t.odometer_start_id,
  t.odometer_end_id,
  t.miles_driven,
  t.fuel_start_percent,
  t.fuel_end_percent,
  t.extra_miles,
  t.extra_miles_reason,
  t.pay_vop_use,
  t.condition_signature_url,
  t.condition_return_signature_url,
  t.condition_snapshot,
  t.condition_return_snapshot,
  -- Member trip details
  tm.member_id,
  tm.member_package_id,
  tm.branch_id,
  tm.start_type,
  tm.return_type,
  tm.miles_member,
  tm.miles_member_adjustment,
  tm.miles_member_adjustment_reason,
  tm.vehicle_tier_snapshot,
  tm.weekday_point_value_snapshot,
  tm.weekend_point_value_snapshot,
  tm.extra_mile_point_value_snapshot,
  tm.included_miles_snapshot,
  tm.overage_miles_snapshot,
  tm.base_points,
  tm.extra_mileage_points,
  tm.total_points,
  tm.calculation_version,
  tm.calculation_detail,
  -- Service trip companion details (Guide 10.4)
  ts.vendor_id                              AS service_vendor_id,
  vdr.name                                  AS service_vendor_name,
  ts.service_category_code,
  ts.service_type_code,
  ts.service_reason_code,
  ts.service_cost,
  ts.billed_member_id                       AS service_billed_member_id,
  ts.billed_vehicle_partner_id              AS service_billed_vehicle_partner_id,
  ts.billed_amount                          AS service_billed_amount,
  ts.warranty_claim_reference,
  ts.service_notes,
  -- Vehicle and reservation metadata
  vm.model_name                             AS vehicle_model,
  m.name                                    AS vehicle_make,
  v.license_plate,
  r.confirmation_code,
  t.created_at,
  t.updated_at
FROM fs.vehicle_trip t
LEFT JOIN fs.vehicle_trip_member tm ON tm.vehicle_trip_id = t.vehicle_trip_id
LEFT JOIN fs.vehicle_trip_service ts ON ts.vehicle_trip_id = t.vehicle_trip_id
LEFT JOIN fs.vendor vdr ON vdr.vendor_id = ts.vendor_id
LEFT JOIN fs.vehicles v ON v.id = t.vehicle_id
LEFT JOIN fs.vehicle_models vm ON vm.id = v.model_id
LEFT JOIN fs.manufacturers m ON m.id = vm.manufacturer_id
LEFT JOIN fs.reservations r ON r.id = t.vehicle_reservation_id;

-- -----------------------------------------------------------------------------
-- 8. Grant Permissions
-- -----------------------------------------------------------------------------
GRANT SELECT ON fs.trips TO PUBLIC;
GRANT ALL ON fs.member_charge_type TO PUBLIC;
GRANT ALL ON fs.toll_authority_select TO PUBLIC;
GRANT ALL ON fs.service_category TO PUBLIC;
GRANT ALL ON fs.vehicle_service_type TO PUBLIC;
GRANT ALL ON fs.service_reason_select TO PUBLIC;
GRANT ALL ON fs.member_trip_story_prompt TO PUBLIC;
GRANT ALL ON fs.member_trip_story TO PUBLIC;
GRANT ALL ON fs.member_trip_story_answer TO PUBLIC;
GRANT ALL ON fs.vehicle_trip_service TO PUBLIC;
GRANT ALL ON fs.vehicle_toll_transaction TO PUBLIC;
GRANT ALL ON fs.branch_toll_source TO PUBLIC;

COMMIT;
