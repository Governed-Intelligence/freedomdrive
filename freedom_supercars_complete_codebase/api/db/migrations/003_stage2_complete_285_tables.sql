-- =============================================================================
-- FREEDOM SUPERCARS — Stage 2 Complete 285-Table Database Schema
-- =============================================================================
-- Version:     3.0.0 (Authoritative 08-12-2026 Stage 2 Knowledge Base Specification)
-- Tables:      285 tables across 23 domains
-- Enums:       126 enum types
-- Foreign Keys: 1,146 referential integrity constraints
-- Coexistence: Fully non-destructive with existing fs schema operational tables
-- =============================================================================

BEGIN;

-- Ensure required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "citext";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE SCHEMA IF NOT EXISTS fs;
SET search_path TO fs, public;

-- Safely rename legacy MVP reservation_status_history if it exists to allow canonical table
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'fs' AND table_name = 'reservation_status_history') THEN
    -- Check if it is the legacy table (with column 'previous_status')
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'fs' AND table_name = 'reservation_status_history' AND column_name = 'previous_status') THEN
      ALTER TABLE fs.reservation_status_history RENAME TO reservation_status_history_legacy;
    END IF;
  END IF;
END $$;

-- =============================================================================
-- 1. ENUM TYPES (126 types)
-- =============================================================================
DO $$ BEGIN CREATE TYPE fs.audit_log_action_enum AS ENUM ('Insert', 'Update', 'Delete', 'View', 'Trigger', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.automation_action_action_type_enum AS ENUM ('Create Task', 'Send Notification', 'Send Webhook', 'Update Record', 'Create Event Log', 'Trigger Rule', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.automation_execution_log_status_enum AS ENUM ('Success', 'Failed', 'Skipped'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.automation_rule_mode_enum AS ENUM ('Event', 'Schedule'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.branch_branch_type_enum AS ENUM ('Main', 'Satellite', 'Partner'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.branch_phone_branch_phone_type_enum AS ENUM ('Main', 'Sales', 'Member Line', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.corporate_account_contact_contact_phone_type_enum AS ENUM ('Home', 'Work', 'Mobile', 'Assistant', 'Family', 'Emergency', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.event_cost_style_enum AS ENUM ('Dollars', 'Points'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.event_partner_role_enum AS ENUM ('Sponsor', 'Caterer', 'Photographer', 'Entertainment', 'Floral', 'Decor', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.event_registration_status_enum AS ENUM ('Registered', 'Attended', 'Canceled', 'Waitlisted'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.export_job_status_enum AS ENUM ('Awaiting Approval', 'Queued', 'Running', 'Completed', 'Failed', 'Cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.export_schedule_delivery_method_enum AS ENUM ('Email', 'Store Only'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.export_schedule_recurrence_enum AS ENUM ('Daily', 'Weekly', 'Monthly', 'Quarterly', 'Annually', 'Custom'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.export_schedule_relative_period_enum AS ENUM ('Previous Day', 'Previous Week', 'Previous Month', 'Previous Quarter', 'Previous Year', 'Week To Date', 'Month To Date', 'Quarter To Date', 'Year To Date'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.form_card_applies_to_enum AS ENUM ('Vehicle', 'Member', 'Vendor', 'Event', 'System', 'Branch', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.form_card_card_type_enum AS ENUM ('multi-check', 'single-check', 'dropdown', 'text', 'photo', 'signature'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.form_defect_status_enum AS ENUM ('Open', 'In Progress', 'Resolved'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.form_form_scope_enum AS ENUM ('Vehicle', 'Member', 'Vendor', 'Event', 'System', 'Branch', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.form_response_status_enum AS ENUM ('In Progress', 'Completed', 'Failed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.geofence_boundary_shape_enum AS ENUM ('Circle', 'Polygon'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.geofence_geofence_type_enum AS ENUM ('Branch Arrival', 'Prohibited Area', 'Point of Interest'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.holiday_definition_recurrence_type_enum AS ENUM ('Fixed Date', 'Nth Weekday', 'Manual'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.integration_configuration_data_type_enum AS ENUM ('text', 'integer', 'json'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.integration_event_log_direction_enum AS ENUM ('inbound', 'outbound'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.integration_event_log_status_enum AS ENUM ('Success', 'Failed', 'Retry'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.lap_rule_earn_frequency_enum AS ENUM ('Every Occurrence', 'Once Per Member', 'Once Per Subject'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.lap_rule_lifetime_basis_enum AS ENUM ('Never', 'After a Period'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_address_member_address_location_enum AS ENUM ('Home', 'Work', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_address_member_address_style_enum AS ENUM ('Home', 'Townhome', 'Apartment/Condo', 'High-Rise', 'Hotel', 'Office Tower', 'Stand-Alone Building', 'Retail Storefront', 'Industrial/Warehouse', 'Medical/Healthcare', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_address_member_address_type_enum AS ENUM ('Physical', 'Mailing', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_car_service_status_enum AS ENUM ('Scheduled', 'In Progress', 'Completed', 'Cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_car_stay_status_enum AS ENUM ('Scheduled', 'Received', 'Checked In', 'Completed', 'Cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_charge_charge_style_enum AS ENUM ('Dollars', 'Points'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_charge_payment_status_enum AS ENUM ('Awaiting Approval', 'Pending', 'Invoiced', 'Paid', 'Voided', 'Refunded', 'Written Off'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_email_member_email_type_enum AS ENUM ('Home', 'Work', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_insurance_policy_verification_status_enum AS ENUM ('Verified', 'Not Verified', 'Pending'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_lifecycle_status_enum AS ENUM ('Pending', 'Active', 'Inactive', 'Former', 'Voided'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_note_interaction_type_enum AS ENUM ('Call', 'Email', 'Text', 'Visit', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_package_customization_effective_package_mode_enum AS ENUM ('First Year (Period)', 'Current Year (Period)', 'Every Year (Period)', 'Custom'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_package_participant_perks_mode_enum AS ENUM ('Pool', 'Split'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_package_participant_points_mode_enum AS ENUM ('Pool', 'Split'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_package_points_accrual_mode_enum AS ENUM ('Standard', 'Full'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_package_status_enum AS ENUM ('Draft', 'Active', 'Suspended', 'Paused', 'Closed', 'Cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_payment_schedule_frequency_enum AS ENUM ('Annual', 'Monthly', 'Quarterly', 'Custom'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_perk_credit_approval_status_enum AS ENUM ('Awaiting Approval', 'Approved', 'Not Required', 'Rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_perk_ledger_entry_type_enum AS ENUM ('Credit Allocation', 'Credit Promo', 'Charge Reservation', 'Expiry', 'Reversal'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_phone_member_phone_type_enum AS ENUM ('Home', 'Work', 'Mobile', 'Assistant', 'Family', 'Emergency', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_point_credit_approval_status_enum AS ENUM ('Awaiting Approval', 'Approved', 'Not Required', 'Rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_points_carryover_account_type_enum AS ENUM ('A_Next_Year', 'B_Year_After_Next'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_points_ledger_entry_type_enum AS ENUM ('Charge Reservation', 'Credit Allocation', 'Credit Perk', 'Credit Promo', 'Reversal', 'Carryover'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.member_relationship_relationship_type_enum AS ENUM ('Spouse', 'Family Member', 'Business Associate', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.membership_level_bookings_avg_days_per_reservation_enum AS ENUM ('2.0', '1.5', '1.0'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.membership_level_points_caps_rollover_policy_enum AS ENUM ('None', 'Standard', 'Full'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.membership_level_status_enum AS ENUM ('Draft', 'Active', 'Archived'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.mpc_branch_access_action_enum AS ENUM ('Add', 'Remove'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.mpc_vehicle_tier_access_action_enum AS ENUM ('Add', 'Remove'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.notification_channel_enum AS ENUM ('Email', 'SMS', 'Push', 'In App', 'Webhook'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.notification_delivery_log_bounce_type_enum AS ENUM ('Hard', 'Soft'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.notification_delivery_log_status_enum AS ENUM ('Queued', 'Sent', 'Delivered', 'Bounced', 'Failed', 'Canceled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.notification_preference_category_enum AS ENUM ('Reservation', 'Membership', 'Vehicle', 'Event', 'Task', 'Vendor', 'System', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.notification_preference_channel_enum AS ENUM ('Email', 'SMS', 'Push', 'In App', 'Webhook'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.notification_status_enum AS ENUM ('Queued', 'Sent', 'Delivered', 'Bounced', 'Failed', 'Canceled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.notification_template_category_enum AS ENUM ('Reservation', 'Membership', 'Vehicle', 'Event', 'Task', 'Vendor', 'System', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.notification_template_channel_enum AS ENUM ('Email', 'SMS', 'Push', 'In App', 'Webhook'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.report_job_report_category_enum AS ENUM ('Reservation', 'Membership', 'Vehicle', 'Event', 'System', 'Task', 'Vendor', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.report_job_status_enum AS ENUM ('Queued', 'Running', 'Completed', 'Failed', 'Cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.report_schedule_delivery_method_enum AS ENUM ('Email', 'Store Only'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.report_schedule_recurrence_enum AS ENUM ('Daily', 'Weekly', 'Monthly', 'Quarterly', 'Annually', 'Custom'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.report_schedule_relative_period_enum AS ENUM ('Previous Day', 'Previous Week', 'Previous Month', 'Previous Quarter', 'Previous Year', 'Week To Date', 'Month To Date', 'Quarter To Date', 'Year To Date'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.reservation_location_select_location_category_enum AS ENUM ('Branch', 'Offsite', 'Hotel', 'Partner', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.reservation_rule_rule_category_enum AS ENUM ('Member Policy', 'Level Policy', 'Vehicle Policy', 'System Policy', 'Event Policy'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.reservation_rule_rule_type_enum AS ENUM ('Limit', 'Block', 'Notice', 'Validation'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.retention_policy_retention_basis_enum AS ENUM ('Never', 'After a Period'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.staff_email_staff_email_type_enum AS ENUM ('Work', 'Personal', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.staff_employment_status_enum AS ENUM ('Pending', 'Active', 'On Leave', 'Suspended', 'Withdrawn', 'Former'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.staff_phone_staff_phone_type_enum AS ENUM ('Home', 'Work', 'Mobile', 'Assistant', 'Family', 'Emergency', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.task_audit_log_action_enum AS ENUM ('Create', 'Update', 'Status Change', 'Assign', 'Comment', 'Attachment Added', 'Auto Close', 'Reopen', 'Delete', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.user_device_permission_calendar_enum AS ENUM ('Not Requested', 'Granted', 'Denied'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.user_device_permission_camera_enum AS ENUM ('Not Requested', 'Granted', 'Denied'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.user_device_permission_location_enum AS ENUM ('Not Requested', 'Granted Always', 'Granted While In Use', 'Denied'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.user_device_permission_push_enum AS ENUM ('Not Requested', 'Granted', 'Denied'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.user_device_platform_enum AS ENUM ('iOS', 'Android'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_access_exclusion_exclusion_source_enum AS ENUM ('Owner Request', 'Club Decision'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_accessories_number_keys_enum AS ENUM ('1', '2', '3', '4'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_attachment_retention_policy_retention_action_enum AS ENUM ('Archive', 'Delete', 'Keep'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_description_body_style_enum AS ENUM ('Coupe', 'Convertible', 'Sedan', 'SUV', 'Truck', 'Wagon', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_description_doors_enum AS ENUM ('2', '3', '4', '5'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_description_engine_enum AS ENUM ('Electric', 'Hybrid', '4-Cylinder', '6-Cylinder', '8-Cylinder', '10-Cylinder', '12-Cylinder'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_description_seats_enum AS ENUM ('2', '4', '5', '6', '7', '8'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_description_transmission_enum AS ENUM ('Automatic', 'Manual'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_description_trunk_size_enum AS ENUM ('None', 'X-Small', 'Small', 'Medium', 'Large', 'X-Large'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_event_attachment_attachment_type_enum AS ENUM ('Photo', 'Document', 'Video', 'Report', 'Receipt', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_event_attachment_retention_action_enum AS ENUM ('Archive', 'Delete', 'Keep'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_event_log_event_role_enum AS ENUM ('Member', 'Staff', 'System', 'Automation', 'Admin', 'Vendor'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_event_log_event_type_enum AS ENUM ('Reservation', 'Trip', 'Inspection', 'Service', 'Status', 'Incident', 'Admin', 'Documentation'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_financing_lifecycle_finance_type_enum AS ENUM ('Cash', 'Loan', 'Lease', 'Floorplan', 'VOP', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_fleet_stage_enum AS ENUM ('Incoming', 'Intake', 'Fleet', 'Retired'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_inspection_checkup_driver_front_tread_depth_enum AS ENUM ('2/32', '3/32', '4/32', '5/32', '6/32', '7/32', '8/32', '9/32', '10/32', '11/32'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_inspection_checkup_driver_rear_tread_depth_enum AS ENUM ('2/32', '3/32', '4/32', '5/32', '6/32', '7/32', '8/32', '9/32', '10/32', '11/32'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_inspection_checkup_passenger_front_tread_depth_enum AS ENUM ('2/32', '3/32', '4/32', '5/32', '6/32', '7/32', '8/32', '9/32', '10/32', '11/32'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_inspection_checkup_passenger_rear_tread_depth_enum AS ENUM ('2/32', '3/32', '4/32', '5/32', '6/32', '7/32', '8/32', '9/32', '10/32', '11/32'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_inspection_damage_severity_enum AS ENUM ('Minor', 'Moderate', 'Major', 'Critical'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_inspection_issue_severity_enum AS ENUM ('Minor', 'Moderate', 'Major', 'Critical'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_inspection_wheels_tires_driver_front_tread_depth_enum AS ENUM ('2/32', '3/32', '4/32', '5/32', '6/32', '7/32', '8/32', '9/32', '10/32', '11/32'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_inspection_wheels_tires_driver_rear_tread_depth_enum AS ENUM ('2/32', '3/32', '4/32', '5/32', '6/32', '7/32', '8/32', '9/32', '10/32', '11/32'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_inspection_wheels_tires_passenger_front_tread_depth_enum AS ENUM ('2/32', '3/32', '4/32', '5/32', '6/32', '7/32', '8/32', '9/32', '10/32', '11/32'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_inspection_wheels_tires_passenger_rear_tread_depth_enum AS ENUM ('2/32', '3/32', '4/32', '5/32', '6/32', '7/32', '8/32', '9/32', '10/32', '11/32'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_odometer_log_quality_flag_enum AS ENUM ('Good', 'Estimated', 'Corrected', 'Invalid'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_partner_contact_contact_phone_type_enum AS ENUM ('Home', 'Work', 'Mobile', 'Assistant', 'Family', 'Emergency', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_qualification_expiry_basis_enum AS ENUM ('Never', 'After a Period'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_reservation_created_by_user_role_enum AS ENUM ('Member', 'Staff', 'System', 'Automation', 'Admin', 'Vendor'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_reservation_return_type_enum AS ENUM ('Return', 'Collection'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_reservation_start_type_enum AS ENUM ('Pickup', 'Delivery'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_spec_gps_type_enum AS ENUM ('OBDII', 'Y-Adapter', 'Hardwire', 'Other', 'None'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_toll_transaction_match_status_enum AS ENUM ('Unmatched', 'Matched', 'Disputed', 'Excluded'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_trip_extra_miles_reason_enum AS ENUM ('Fuel', 'Service', 'Delivery', 'Transport', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_trip_member_return_type_enum AS ENUM ('Return', 'Collection'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_trip_member_start_type_enum AS ENUM ('Pickup', 'Delivery'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vehicle_trip_pay_vop_use_enum AS ENUM ('Earning', 'Not Earning', 'Undetermined'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vendor_contact_contact_phone_type_enum AS ENUM ('Home', 'Work', 'Mobile', 'Assistant', 'Family', 'Emergency', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vop_payout_log_entry_direction_enum AS ENUM ('Credit', 'Charge'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vop_payout_log_entry_type_enum AS ENUM ('VOP Day', 'VOP Mile', 'VOP Plan Fee', 'VOP Service', 'VOP Fuel', 'VOP Toll', 'VOP Prepaid TopUp', 'VOP Prepaid Recoup', 'VOP Amount', 'Other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vop_payout_period_status_enum AS ENUM ('Open', 'Closed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.vop_plan_status_enum AS ENUM ('Active', 'Pending', 'Suspended', 'Ended'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.webhook_delivery_log_status_enum AS ENUM ('Success', 'Failed', 'Retry'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fs.webhook_inbound_status_enum AS ENUM ('Pending', 'Processed', 'Failed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =============================================================================
-- 2. TABLES (285 tables across 23 domains)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- DOMAIN: AUTOMATIONS
-- -----------------------------------------------------------------------------

-- Table: AUTOMATION_ACTION (Defines actions taken when an automation rule’s conditions are met.)
CREATE TABLE IF NOT EXISTS fs.automation_action (
    automation_action_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id                             UUID,
    action_type                         fs.automation_action_action_type_enum,
    task_template_id                    UUID,
    notification_template_id            UUID,
    webhook_id                          UUID,
    delay_seconds                       INTEGER,
    due_offset_minutes                  INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.automation_action IS 'Defines actions taken when an automation rule’s conditions are met.';

-- Table: AUTOMATION_CONDITION (Defines the specific conditions that must be met for an automation rule to trigg)
CREATE TABLE IF NOT EXISTS fs.automation_condition (
    automation_condition_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id                             UUID,
    condition_group_id                  UUID,
    logical_operator                    VARCHAR(10),
    "column"                            VARCHAR(120),
    operator                            VARCHAR(20),
    value                               VARCHAR(120),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.automation_condition IS 'Defines the specific conditions that must be met for an automation rule to trigger.';

-- Table: AUTOMATION_EXECUTION_LOG (Records each time an automation rule executes, including context, results, and s)
CREATE TABLE IF NOT EXISTS fs.automation_execution_log (
    automation_execution_log_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id                             UUID,
    action_id                           UUID,
    trigger_context                     JSONB,
    status                              fs.automation_execution_log_status_enum,
    error_message                       TEXT,
    executed_at                         TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.automation_execution_log IS 'Records each time an automation rule executes, including context, results, and status for auditing and troubleshooting.';

-- Table: AUTOMATION_RULE (Defines automation rules that create or update tasks.)
CREATE TABLE IF NOT EXISTS fs.automation_rule (
    automation_rule_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    automation_rule_name                VARCHAR(120) UNIQUE,
    scope                               VARCHAR(60),
    mode                                fs.automation_rule_mode_enum,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.automation_rule IS 'Defines automation rules that create or update tasks.';

-- Table: SCHEDULED_JOB (Tracks when scheduled automation rules should run.)
CREATE TABLE IF NOT EXISTS fs.scheduled_job (
    scheduled_job_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id                             UUID,
    scheduled_for                       TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    report_schedule_id                  UUID
);
COMMENT ON TABLE fs.scheduled_job IS 'Tracks when scheduled automation rules should run.';

-- -----------------------------------------------------------------------------
-- DOMAIN: BRANCH MANAGEMENT
-- -----------------------------------------------------------------------------

-- Table: BRANCH (This table contains branch information such as corporate filing info, mailing an)
CREATE TABLE IF NOT EXISTS fs.branch (
    branch_id                           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_code                         VARCHAR(20) UNIQUE,
    branch_name                         VARCHAR(100),
    branch_type                         fs.branch_branch_type_enum,
    time_zone                           VARCHAR(64),
    daily_open_time                     TIME,
    daily_close_time                    TIME,
    branch_email                        VARCHAR(120),
    address_mail                        VARCHAR(200),
    city_mail                           VARCHAR(100),
    state_mail                          VARCHAR(2),
    zip_mail                            VARCHAR(10),
    address_physical                    VARCHAR(200),
    city_physical                       VARCHAR(100),
    state_physical                      VARCHAR(2),
    zip_physical                        VARCHAR(10),
    tax_id                              VARCHAR(32),
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.branch IS 'This table contains branch information such as corporate filing info, mailing and physical addresses, phone number, business hours, tax ID, and time zone.';

-- Table: BRANCH_DELIVERY_RATE (What a delivery costs at this branch once a member has used the complimentary de)
CREATE TABLE IF NOT EXISTS fs.branch_delivery_rate (
    branch_delivery_rate_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id                           UUID,
    effective_from                      DATE,
    effective_to                        DATE,
    base_fee                            NUMERIC(12,2),
    per_mile_rate                       NUMERIC(12,2),
    included_radius_miles               INTEGER,
    max_distance_miles                  INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.branch_delivery_rate IS 'What a delivery costs at this branch once a member has used the complimentary deliveries their plan includes. Effective-dated rather than edited, so an old quote stays explainable.';

-- Table: BRANCH_PHONE (This table Stores one or more phone numbers associated with each branch.)
CREATE TABLE IF NOT EXISTS fs.branch_phone (
    branch_phone_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id                           UUID,
    branch_phone                        VARCHAR(20),
    branch_phone_type                   fs.branch_phone_branch_phone_type_enum,
    branch_phone_note                   VARCHAR(200),
    branch_phone_active                 BOOLEAN,
    is_primary                          BOOLEAN,
    effective_from                      TIMESTAMPTZ,
    effective_to                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.branch_phone IS 'This table Stores one or more phone numbers associated with each branch.';

-- Table: BRANCH_TOLL_SOURCE (Where a branch gets its tolls: the authority, the connector it arrives through, )
CREATE TABLE IF NOT EXISTS fs.branch_toll_source (
    branch_toll_source_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id                           UUID,
    toll_authority_code                 VARCHAR(20),
    integration_provider_id             UUID,
    arrival_method                      VARCHAR(80),
    expected_frequency                  VARCHAR(40),
    last_import_at                      TIMESTAMPTZ,
    last_import_batch_id                VARCHAR(60),
    is_active                           BOOLEAN,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.branch_toll_source IS 'Where a branch gets its tolls: the authority, the connector it arrives through, how often to expect it, and when it last arrived, so a feed that stops is visible rather than silent.';

-- Table: GEOFENCE (A named geographic boundary the platform watches: a branch arrival boundary or a)
CREATE TABLE IF NOT EXISTS fs.geofence (
    geofence_id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    geofence_name                       VARCHAR(120) UNIQUE,
    geofence_type                       fs.geofence_geofence_type_enum,
    branch_id                           UUID,
    boundary_shape                      fs.geofence_boundary_shape_enum,
    center_latitude                     NUMERIC(9,6),
    center_longitude                    NUMERIC(9,6),
    radius_meters                       INTEGER,
    polygon_points                      TEXT,
    alert_on_enter                      BOOLEAN,
    alert_on_exit                       BOOLEAN,
    effective_from                      DATE,
    effective_to                        DATE,
    is_active                           BOOLEAN,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.geofence IS 'A named geographic boundary the platform watches: a branch arrival boundary or a prohibited area.';

-- Table: MEMBER_BRANCH_ACCESS (Branches a member may book at, defined at the membership level and resolved at t)
CREATE TABLE IF NOT EXISTS fs.member_branch_access (
    member_branch_access_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_id                 UUID,
    branch_id                           UUID,
    granted_at                          TIMESTAMPTZ,
    granted_by_user_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    revoked_at                          TIMESTAMPTZ,
    revoked_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_branch_access IS 'Branches a member may book at, defined at the membership level and resolved at the package.';

-- Table: STAFF_BRANCH_ACCESS (Branches a staff member may operate within. Staff capacity only; member and vend)
CREATE TABLE IF NOT EXISTS fs.staff_branch_access (
    staff_branch_access_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id                            UUID,
    branch_id                           UUID,
    granted_at                          TIMESTAMPTZ,
    granted_by_user_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    revoked_at                          TIMESTAMPTZ,
    revoked_by_user_id                  UUID
);
COMMENT ON TABLE fs.staff_branch_access IS 'Branches a staff member may operate within. Staff capacity only; member and vendor branch reach are held separately and never blend.';

-- Table: VENDOR_BRANCH_ACCESS (Branches a vendor company may service. Vendor capacity only; a vendor contact in)
CREATE TABLE IF NOT EXISTS fs.vendor_branch_access (
    vendor_branch_access_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id                           UUID,
    branch_id                           UUID,
    granted_at                          TIMESTAMPTZ,
    granted_by_user_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    revoked_at                          TIMESTAMPTZ,
    revoked_by_user_id                  UUID
);
COMMENT ON TABLE fs.vendor_branch_access IS 'Branches a vendor company may service. Vendor capacity only; a vendor contact inherits the reach of the company they belong to.';

-- -----------------------------------------------------------------------------
-- DOMAIN: DOCUMENT LIBRARY
-- -----------------------------------------------------------------------------

-- Table: AUDIT_LOG (Records actions taken on documents in the Document Library. Security events are )
CREATE TABLE IF NOT EXISTS fs.audit_log (
    audit_log_id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id                         UUID,
    actor_user_id                       UUID,
    action                              fs.audit_log_action_enum,
    ip_address                          INET,
    notes                               TEXT,
    occurred_at                         TIMESTAMPTZ
);
COMMENT ON TABLE fs.audit_log IS 'Records actions taken on documents in the Document Library. Security events are recorded separately in access_log.';

-- Table: DOCUMENT (Stores uploaded files and their metadata.)
CREATE TABLE IF NOT EXISTS fs.document (
    document_id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_type_code                  VARCHAR(40),
    uploaded_by_user_id                 UUID,
    uploaded_at                         TIMESTAMPTZ,
    filename                            VARCHAR(255),
    content_type                        VARCHAR(120),
    size_bytes                          BIGINT,
    storage_key                         VARCHAR(255),
    checksum_sha256                     VARCHAR(64),
    name                                VARCHAR(160),
    description                         TEXT,
    visibility                          VARCHAR(20),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.document IS 'Stores uploaded files and their metadata.';

-- Table: DOCUMENT_CATEGORY (Defines top-level categories that documents belong to (extensible).)
CREATE TABLE IF NOT EXISTS fs.document_category (
    document_category_code              VARCHAR(40) PRIMARY KEY,
    document_category_name              VARCHAR(120) UNIQUE,
    description                         TEXT,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.document_category IS 'Defines top-level categories that documents belong to (extensible).';

-- Table: DOCUMENT_LINK (Connects documents to specific entities (Member, Staff, Vehicle, Event, Branch).)
CREATE TABLE IF NOT EXISTS fs.document_link (
    document_link_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id                         UUID,
    document_category_code              VARCHAR(40),
    target_table                        VARCHAR(60),
    target_id                           UUID,
    is_primary                          BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.document_link IS 'Connects documents to specific entities (Member, Staff, Vehicle, Event, Branch).';

-- Table: DOCUMENT_RETENTION (Applies a retention policy to a document; the purge date is computed at upload a)
CREATE TABLE IF NOT EXISTS fs.document_retention (
    document_id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id                           UUID,
    purge_on                            DATE,
    legal_hold                          BOOLEAN,
    legal_hold_reason                   TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.document_retention IS 'Applies a retention policy to a document; the purge date is computed at upload and stored.';

-- Table: DOCUMENT_TAG (Links tags to specific documents (many-to-many).)
CREATE TABLE IF NOT EXISTS fs.document_tag (
    document_id                         UUID,
    tag_id                              UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    CONSTRAINT pk_document_tag PRIMARY KEY (document_id, tag_id)
);
COMMENT ON TABLE fs.document_tag IS 'Links tags to specific documents (many-to-many).';

-- Table: DOCUMENT_TYPE (Specifies rules and details for each type of document within a category.)
CREATE TABLE IF NOT EXISTS fs.document_type (
    document_category_code              VARCHAR(40),
    document_type_name                  VARCHAR(120),
    document_type_code                  VARCHAR(40) PRIMARY KEY,
    is_required                         BOOLEAN,
    member_visible_by_default           BOOLEAN,
    allowed_mime                        JSONB,
    max_files_per_entity                INTEGER,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.document_type IS 'Specifies rules and details for each type of document within a category.';

-- Table: DOCUMENT_VERSION (Tracks versions of a document over time.)
CREATE TABLE IF NOT EXISTS fs.document_version (
    document_version_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id                         UUID,
    version_number                      INTEGER,
    storage_key                         VARCHAR(255),
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.document_version IS 'Tracks versions of a document over time.';

-- Table: RETENTION_POLICY (Defines retention duration and legal hold options.)
CREATE TABLE IF NOT EXISTS fs.retention_policy (
    retention_policy_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retention_policy_name               VARCHAR(120) UNIQUE,
    keep_days                           INTEGER,
    retention_basis                     fs.retention_policy_retention_basis_enum,
    allow_legal_hold                    BOOLEAN,
    notes                               TEXT,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.retention_policy IS 'Defines retention duration and legal hold options.';

-- Table: TAG (Reusable labels that can be applied to documents for organization and search.)
CREATE TABLE IF NOT EXISTS fs.tag (
    tag_id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tag_name                            VARCHAR(80) UNIQUE,
    description                         TEXT,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.tag IS 'Reusable labels that can be applied to documents for organization and search.';

-- -----------------------------------------------------------------------------
-- DOMAIN: EVENTS
-- -----------------------------------------------------------------------------

-- Table: EVENT (Stores core information for each member event including scheduling, capacity, an)
CREATE TABLE IF NOT EXISTS fs.event (
    event_id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_title                         VARCHAR(200),
    description                         TEXT,
    event_type_code                     VARCHAR(40),
    start_time                          TIMESTAMPTZ,
    end_time                            TIMESTAMPTZ,
    start_date                          DATE,
    end_date                            DATE,
    multi_day_flag                      BOOLEAN,
    branch_list_json                    JSONB,
    rsvp_deadline                       TIMESTAMPTZ,
    location                            VARCHAR(200),
    capacity                            INTEGER,
    is_member_only                      BOOLEAN,
    max_guests_per_member               INTEGER,
    cost_style                          fs.event_cost_style_enum,
    cost_amount                         NUMERIC(10,2),
    complimentary_count                 INTEGER,
    image_url                           VARCHAR(255),
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.event IS 'Stores core information for each member event including scheduling, capacity, and visibility settings.';

-- Table: EVENT_GUEST (Captures detailed guest information linked to an event registration. Supports un)
CREATE TABLE IF NOT EXISTS fs.event_guest (
    event_guest_id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_registration_id               UUID,
    guest_name                          VARCHAR(120),
    guest_email                         VARCHAR(120),
    guest_phone                         VARCHAR(20),
    checked_in                          BOOLEAN,
    checked_in_at                       TIMESTAMPTZ,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.event_guest IS 'Captures detailed guest information linked to an event registration. Supports unlimited guests per member registration and enables attendance tracking.';

-- Table: EVENT_PARTNER (Stores vendor or sponsor associations for each event. Enables tracking of servic)
CREATE TABLE IF NOT EXISTS fs.event_partner (
    event_partner_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id                            UUID,
    vendor_id                           UUID,
    role                                fs.event_partner_role_enum,
    is_primary                          BOOLEAN,
    notes                               TEXT,
    granted_at                          TIMESTAMPTZ,
    granted_by_user_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.event_partner IS 'Stores vendor or sponsor associations for each event. Enables tracking of service providers and partners such as caterers, photographers, or brand sponsors.';

-- Table: EVENT_REGISTRATION (Stores member RSVP data, guest counts, and attendance tracking for each event.)
CREATE TABLE IF NOT EXISTS fs.event_registration (
    event_registration_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id                            UUID,
    member_id                           UUID,
    guest_count                         INTEGER,
    status                              fs.event_registration_status_enum,
    notes                               TEXT,
    registered_at                       TIMESTAMPTZ,
    is_waitlisted                       BOOLEAN,
    waitlist_position                   SMALLINT,
    waitlisted_at                       TIMESTAMPTZ,
    promoted_at                         TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.event_registration IS 'Stores member RSVP data, guest counts, and attendance tracking for each event.';

-- Table: EVENT_TYPE_SELECT (Lookup table defining event types for classification and filtering.)
CREATE TABLE IF NOT EXISTS fs.event_type_select (
    event_type_code                     VARCHAR(40) PRIMARY KEY,
    event_type_name                     VARCHAR(100),
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.event_type_select IS 'Lookup table defining event types for classification and filtering.';

-- -----------------------------------------------------------------------------
-- DOMAIN: FORMS BUILDER
-- -----------------------------------------------------------------------------

-- Table: FORM (Stores the main details for each custom form created.)
CREATE TABLE IF NOT EXISTS fs.form (
    form_id                             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_name                           VARCHAR(100) UNIQUE,
    form_scope                          fs.form_form_scope_enum,
    target_table                        VARCHAR(60),
    description                         TEXT,
    requires_signature                  BOOLEAN,
    requires_vehicle                    BOOLEAN,
    requires_member                     BOOLEAN,
    no_defect_condition_code            VARCHAR(30),
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.form IS 'Stores the main details for each custom form created.';

-- Table: FORM_CARD (Cards define what kind of input is needed (checklist, photo, dropdown, etc.) and)
CREATE TABLE IF NOT EXISTS fs.form_card (
    form_card_id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_id                             UUID,
    card_title                          VARCHAR(150),
    card_type                           fs.form_card_card_type_enum,
    applies_to                          fs.form_card_applies_to_enum,
    is_required                         BOOLEAN,
    has_photo_reference                 BOOLEAN,
    sort_order                          INTEGER,
    defect_triggers_task                BOOLEAN,
    notification_on_fail                BOOLEAN,
    photo_reference_url                 VARCHAR(255),
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.form_card IS 'Cards define what kind of input is needed (checklist, photo, dropdown, etc.) and whether it’s required before submitting the form.';

-- Table: FORM_CARD_OPTION (Stores selectable dropdown options for cards that use the 'dropdown' type. Allow)
CREATE TABLE IF NOT EXISTS fs.form_card_option (
    form_card_option_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_card_id                        UUID,
    option_label                        VARCHAR(100),
    option_value                        VARCHAR(50),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.form_card_option IS 'Stores selectable dropdown options for cards that use the ''dropdown'' type. Allows the Form Builder to dynamically load and manage dropdown selections for each card without hardcoding values.';

-- Table: FORM_CARD_POINT (Lists each individual checklist item under a card. These points allow detailed p)
CREATE TABLE IF NOT EXISTS fs.form_card_point (
    form_card_point_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_card_id                        UUID,
    point_label                         VARCHAR(150),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.form_card_point IS 'Lists each individual checklist item under a card. These points allow detailed pass/fail tracking within a section.';

-- Table: FORM_DEFECT (Automatically created when a checklist item or card fails during an inspection.)
CREATE TABLE IF NOT EXISTS fs.form_defect (
    form_defect_id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_response_point_id              UUID,
    vehicle_id                          UUID,
    defect_description                  TEXT,
    photo_url                           VARCHAR(255),
    status                              fs.form_defect_status_enum,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at                         TIMESTAMPTZ,
    resolved_by                         UUID
);
COMMENT ON TABLE fs.form_defect IS 'Automatically created when a checklist item or card fails during an inspection.';

-- Table: FORM_MAPPING (Defines how fields collected in dynamic forms map to relational database targets)
CREATE TABLE IF NOT EXISTS fs.form_mapping (
    form_mapping_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_id                             UUID,
    json_key                            VARCHAR(120),
    target_table                        VARCHAR(60),
    target_column                       VARCHAR(80),
    data_type                           VARCHAR(40),
    is_required                         BOOLEAN,
    transform_rule                      VARCHAR(120),
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.form_mapping IS 'Defines how fields collected in dynamic forms map to relational database targets for core operational forms..';

-- Table: FORM_RESPONSE (Captures one completed form submission by a user. Every time someone performs an)
CREATE TABLE IF NOT EXISTS fs.form_response (
    form_response_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_id                             UUID,
    user_id                             UUID,
    branch_id                           UUID,
    vehicle_id                          UUID,
    member_id                           UUID,
    started_at                          TIMESTAMPTZ,
    completed_at                        TIMESTAMPTZ,
    status                              fs.form_response_status_enum,
    signature_image_url                 VARCHAR(255),
    defect_count                        INTEGER
);
COMMENT ON TABLE fs.form_response IS 'Captures one completed form submission by a user. Every time someone performs an inspection or fills out a process form, a new record is created here.';

-- Table: FORM_RESPONSE_CARD (Stores the results for each card within a submitted form.)
CREATE TABLE IF NOT EXISTS fs.form_response_card (
    form_response_card_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_response_id                    UUID,
    form_card_id                        UUID,
    result_value                        VARCHAR(255),
    is_pass                             BOOLEAN,
    comments                            TEXT,
    photo_url                           VARCHAR(255),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE fs.form_response_card IS 'Stores the results for each card within a submitted form.';

-- Table: FORM_RESPONSE_POINT (Stores the individual results for each checklist item under a card. This is wher)
CREATE TABLE IF NOT EXISTS fs.form_response_point (
    form_response_point_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_response_card_id               UUID,
    form_card_point_id                  UUID,
    is_pass                             BOOLEAN,
    comments                            TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE fs.form_response_point IS 'Stores the individual results for each checklist item under a card. This is where the system tracks whether each point passed or failed and includes any notes or comments added.';

-- -----------------------------------------------------------------------------
-- DOMAIN: INTEGRATIONS
-- -----------------------------------------------------------------------------

-- Table: INTEGRATION_CONFIGURATION (Holds customizable configuration values (base URLs, regions, timeout settings, e)
CREATE TABLE IF NOT EXISTS fs.integration_configuration (
    integration_configuration_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id                         UUID,
    config_key                          VARCHAR(60),
    config_value                        TEXT,
    data_type                           fs.integration_configuration_data_type_enum,
    is_sensitive                        BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.integration_configuration IS 'Holds customizable configuration values (base URLs, regions, timeout settings, etc.) for each integration provider.';

-- Table: INTEGRATION_CREDENTIAL (Stores authentication details for accessing integration providers.)
CREATE TABLE IF NOT EXISTS fs.integration_credential (
    integration_credential_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id                         UUID,
    user_id                             UUID,
    api_key                             VARCHAR(255),
    token                               VARCHAR(255),
    oauth_data                          JSONB,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.integration_credential IS 'Stores authentication details for accessing integration providers.';

-- Table: INTEGRATION_EVENT_LOG (Captures all outbound and inbound integration executions, including request payl)
CREATE TABLE IF NOT EXISTS fs.integration_event_log (
    integration_event_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id                         UUID,
    webhook_id                          UUID,
    direction                           fs.integration_event_log_direction_enum,
    endpoint                            VARCHAR(255),
    request_payload                     JSONB,
    response_payload                    JSONB,
    status_code                         INTEGER,
    status                              fs.integration_event_log_status_enum,
    duration_ms                         INTEGER,
    executed_at                         TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.integration_event_log IS 'Captures all outbound and inbound integration executions, including request payloads, responses, timing, and status codes.';

-- Table: INTEGRATION_MAPPING_RULE (Provides translation rules for importing or exporting structured data between th)
CREATE TABLE IF NOT EXISTS fs.integration_mapping_rule (
    integration_mapping_rule_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id                         UUID,
    source_field                        VARCHAR(100),
    target_field                        VARCHAR(100),
    transformation                      VARCHAR(255),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.integration_mapping_rule IS 'Provides translation rules for importing or exporting structured data between the application and external systems.';

-- Table: INTEGRATION_PROVIDER (Catalog of external services the platform can integrate with and includes heartb)
CREATE TABLE IF NOT EXISTS fs.integration_provider (
    integration_provider_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_provider_name           VARCHAR(120) UNIQUE,
    provider_type                       VARCHAR(60),
    connection_requirements             TEXT,
    is_active                           BOOLEAN,
    last_health_check_at                TIMESTAMPTZ,
    health_status                       VARCHAR(20),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.integration_provider IS 'Catalog of external services the platform can integrate with and includes heartbeat tracking to monitor provider availability.';

-- Table: WEBHOOK (Defines outbound webhook endpoints for pushing data to external systems.)
CREATE TABLE IF NOT EXISTS fs.webhook (
    webhook_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    webhook_name                        VARCHAR(120) UNIQUE,
    target_url                          VARCHAR(255) UNIQUE,
    secret                              VARCHAR(255),
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.webhook IS 'Defines outbound webhook endpoints for pushing data to external systems.';

-- Table: WEBHOOK_DELIVERY_LOG (Logs every webhook attempt, response, and retry. Enables visibility into webhook)
CREATE TABLE IF NOT EXISTS fs.webhook_delivery_log (
    webhook_delivery_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    webhook_id                          UUID,
    event_code                          VARCHAR(100),
    payload                             JSONB,
    response_code                       INTEGER,
    response_body                       TEXT,
    attempt_count                       INTEGER,
    status                              fs.webhook_delivery_log_status_enum,
    executed_at                         TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE fs.webhook_delivery_log IS 'Logs every webhook attempt, response, and retry. Enables visibility into webhook reliability and supports automated retry or alerting mechanisms.';

-- Table: WEBHOOK_EVENT_SUBSCRIPTION (Stores one row per event code a webhook subscribes to.)
CREATE TABLE IF NOT EXISTS fs.webhook_event_subscription (
    webhook_event_subscription_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    webhook_id                          UUID,
    event_code                          VARCHAR(100),
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.webhook_event_subscription IS 'Stores one row per event code a webhook subscribes to.';

-- Table: WEBHOOK_INBOUND (Captures incoming webhook calls from external services.)
CREATE TABLE IF NOT EXISTS fs.webhook_inbound (
    webhook_inbound_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id                         UUID,
    event_code                          VARCHAR(100),
    provider_event_id                   VARCHAR(120),
    payload                             JSONB,
    received_at                         TIMESTAMPTZ,
    status                              fs.webhook_inbound_status_enum,
    response_message                    TEXT,
    processed_at                        TIMESTAMPTZ,
    attempt_count                       INTEGER,
    last_error                          TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE fs.webhook_inbound IS 'Captures incoming webhook calls from external services.';

-- -----------------------------------------------------------------------------
-- DOMAIN: MEMBER CARS
-- -----------------------------------------------------------------------------

-- Table: MEMBER_CAR (Master record of all personal cars owned by members. Tracks identifying informat)
CREATE TABLE IF NOT EXISTS fs.member_car (
    member_car_id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    year                                VARCHAR(4),
    make                                VARCHAR(40),
    model                               VARCHAR(40),
    color                               VARCHAR(40),
    vin                                 VARCHAR(17),
    license_plate                       VARCHAR(15),
    photo_document_id                   UUID,
    is_active                           BOOLEAN,
    last_detail_date                    DATE,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_car IS 'Master record of all personal cars owned by members. Tracks identifying information, ownership status, last detail date, and photo reference.';

-- Table: MEMBER_CAR_SERVICE (Tracks each detailing, wash, or service performed on a member’s personal car whi)
CREATE TABLE IF NOT EXISTS fs.member_car_service (
    member_car_service_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_car_stay_id                  UUID,
    member_car_id                       UUID,
    member_charge_id                    UUID,
    member_car_service_type_code        VARCHAR(20),
    start_time_actual                   TIMESTAMPTZ,
    end_time_actual                     TIMESTAMPTZ,
    status                              fs.member_car_service_status_enum,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_car_service IS 'Tracks each detailing, wash, or service performed on a member’s personal car while it is on-site. Created automatically when service begins or manually by staff.';

-- Table: MEMBER_CAR_SERVICE_TYPE (Lookup of the services performed on a member's own car during a stay, and which )
CREATE TABLE IF NOT EXISTS fs.member_car_service_type (
    member_car_service_type_code        VARCHAR(20) PRIMARY KEY,
    label                               VARCHAR(50) UNIQUE,
    description                         TEXT,
    is_courtesy                         BOOLEAN,
    updates_last_detail_date            BOOLEAN,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_car_service_type IS 'Lookup of the services performed on a member''s own car during a stay, and which are free.';

-- Table: MEMBER_CAR_STAY (One stay of a member's personal car with the club: custody, check-in and check-o)
CREATE TABLE IF NOT EXISTS fs.member_car_stay (
    member_car_stay_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_car_id                       UUID,
    member_id                           UUID,
    vehicle_reservation_id              UUID,
    sync_with_reservation_flag          BOOLEAN,
    start_time_scheduled                TIMESTAMPTZ,
    start_time_actual                   TIMESTAMPTZ,
    end_time_scheduled                  TIMESTAMPTZ,
    end_time_actual                     TIMESTAMPTZ,
    status                              fs.member_car_stay_status_enum,
    task_id                             UUID,
    parking_location                    VARCHAR(40),
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_car_stay IS 'One stay of a member''s personal car with the club: custody, check-in and check-out, and reservation sync.';

-- -----------------------------------------------------------------------------
-- DOMAIN: MEMBER MANAGEMENT
-- -----------------------------------------------------------------------------

-- Table: BENEFIT_ADJUSTMENT_KIND_SELECT (Defines how a Podium Status benefit applies against the plan value. Rows are add)
CREATE TABLE IF NOT EXISTS fs.benefit_adjustment_kind_select (
    benefit_adjustment_kind_code        VARCHAR(40) PRIMARY KEY,
    benefit_adjustment_kind_name        VARCHAR(120) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.benefit_adjustment_kind_select IS 'Defines how a Podium Status benefit applies against the plan value. Rows are added through administration.';

-- Table: BENEFIT_TARGET_SELECT (Defines the parts of the member experience a Podium Status benefit can adjust. R)
CREATE TABLE IF NOT EXISTS fs.benefit_target_select (
    benefit_target_code                 VARCHAR(40) PRIMARY KEY,
    benefit_target_name                 VARCHAR(120) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.benefit_target_select IS 'Defines the parts of the member experience a Podium Status benefit can adjust. Rows are added through administration as new benefit targets are introduced.';

-- Table: CORPORATE_ACCOUNT (Stores corporate membership accounts: the contracting and billing entity for cor)
CREATE TABLE IF NOT EXISTS fs.corporate_account (
    corporate_account_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_name                        VARCHAR(160) UNIQUE,
    tax_id                              VARCHAR(20),
    home_branch_id                      UUID,
    billing_address_line1               VARCHAR(200),
    billing_address_line2               VARCHAR(100),
    billing_city                        VARCHAR(100),
    billing_state                       VARCHAR(2),
    billing_postal_code                 VARCHAR(10),
    is_active                           BOOLEAN,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.corporate_account IS 'Stores corporate membership accounts: the contracting and billing entity for corporate memberships.';

-- Table: CORPORATE_ACCOUNT_CONTACT (Stores contact information for one or more individuals per corporate account.)
CREATE TABLE IF NOT EXISTS fs.corporate_account_contact (
    corporate_account_contact_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    corporate_account_id                UUID,
    contact_name                        VARCHAR(120),
    preferred_name                      VARCHAR(80),
    contact_role                        VARCHAR(80),
    contact_phone                       VARCHAR(20),
    contact_phone_type                  fs.corporate_account_contact_contact_phone_type_enum,
    contact_email                       VARCHAR(120),
    is_primary                          BOOLEAN,
    contact_active                      BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.corporate_account_contact IS 'Stores contact information for one or more individuals per corporate account.';

-- Table: FEEDBACK_RATING_SCALE (Defines the rating scales to use in feedback (e.g., Good/Bad or 1–5). Controls v)
CREATE TABLE IF NOT EXISTS fs.feedback_rating_scale (
    scale_code                          VARCHAR(20) PRIMARY KEY,
    label                               VARCHAR(50),
    description                         TEXT,
    min_value                           INTEGER,
    max_value                           INTEGER,
    labels_json                         TEXT,
    active                              BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.feedback_rating_scale IS 'Defines the rating scales to use in feedback (e.g., Good/Bad or 1–5). Controls valid ranges and display labels so surveys stay consistent.';

-- Table: INDUSTRY_SELECT (Lists the industries a member profile can be assigned to.)
CREATE TABLE IF NOT EXISTS fs.industry_select (
    industry_code                       VARCHAR(40) PRIMARY KEY,
    industry_name                       VARCHAR(120) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.industry_select IS 'Lists the industries a member profile can be assigned to.';

-- Table: INSURANCE_CARRIER_SELECT (Lists approved insurance carriers for member policies.)
CREATE TABLE IF NOT EXISTS fs.insurance_carrier_select (
    carrier_code                        VARCHAR(40) PRIMARY KEY,
    carrier_name                        VARCHAR(120) UNIQUE,
    carrier_phone                       VARCHAR(20),
    website_url                         VARCHAR(200),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.insurance_carrier_select IS 'Lists approved insurance carriers for member policies.';

-- Table: INSURANCE_COVERAGE_SELECT (List of allowable insurance coverages to be selected when adding an insurance co)
CREATE TABLE IF NOT EXISTS fs.insurance_coverage_select (
    insurance_coverage_code             VARCHAR(40) PRIMARY KEY,
    insurance_coverage_name             VARCHAR(40) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.insurance_coverage_select IS 'List of allowable insurance coverages to be selected when adding an insurance coverage.';

-- Table: INSURANCE_TYPE_SELECT (List of allowable insurance types to be selected when adding an insurance covera)
CREATE TABLE IF NOT EXISTS fs.insurance_type_select (
    insurance_type_code                 VARCHAR(40) PRIMARY KEY,
    insurance_type_name                 VARCHAR(40) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.insurance_type_select IS 'List of allowable insurance types to be selected when adding an insurance coverage.';

-- Table: LAP_RULE (Defines what earns Laps, how many, how often, and how long they last.)
CREATE TABLE IF NOT EXISTS fs.lap_rule (
    lap_rule_id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lap_rule_code                       VARCHAR(40) UNIQUE,
    lap_rule_name                       VARCHAR(120),
    lap_value                           INTEGER,
    earn_frequency                      fs.lap_rule_earn_frequency_enum,
    subject_type                        VARCHAR(40),
    lap_lifetime_months                 SMALLINT,
    lifetime_basis                      fs.lap_rule_lifetime_basis_enum,
    description                         TEXT,
    is_active                           BOOLEAN,
    start_date                          DATE,
    end_date                            DATE,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.lap_rule IS 'Defines what earns Laps, how many, how often, and how long they last.';

-- Table: MEMBER (Profile linked to users who are members. Stores personal and contact details.)
CREATE TABLE IF NOT EXISTS fs.member (
    member_id                           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_seq                          INTEGER UNIQUE,
    member_number                       VARCHAR(20) UNIQUE,
    user_id                             UUID UNIQUE,
    home_branch_id                      UUID,
    first_name                          VARCHAR(100),
    middle_name                         VARCHAR(100),
    last_name                           VARCHAR(100),
    preferred_name                      VARCHAR(80),
    license_number                      VARCHAR(32),
    license_state                       VARCHAR(2),
    license_expires_on                  DATE,
    date_of_birth                       DATE,
    member_since                        DATE,
    podium_status                       VARCHAR(40),
    lifecycle_status                    fs.member_lifecycle_status_enum,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member IS 'Profile linked to users who are members. Stores personal and contact details.';

-- Table: MEMBER_ADDRESS (Stores one or more addresses per member, typed by purpose, location, and dwellin)
CREATE TABLE IF NOT EXISTS fs.member_address (
    member_address_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    member_address                      VARCHAR(200),
    member_address2                     VARCHAR(100),
    member_city                         VARCHAR(100),
    member_state                        VARCHAR(2),
    member_zip                          VARCHAR(10),
    member_country                      VARCHAR(2),
    member_address_type                 fs.member_address_member_address_type_enum,
    member_address_location             fs.member_address_member_address_location_enum,
    member_address_style                fs.member_address_member_address_style_enum,
    member_address_note                 VARCHAR(200),
    member_address_active               BOOLEAN,
    effective_from                      TIMESTAMPTZ,
    effective_to                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_address IS 'Stores one or more addresses per member, typed by purpose, location, and dwelling style, with effective dating. A replaced address is dated closed rather than edited in place.';

-- Table: MEMBER_BRANCH_HISTORY (Tracks each member's home branch assignment over time; the row with a NULL effec)
CREATE TABLE IF NOT EXISTS fs.member_branch_history (
    member_branch_history_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    branch_id                           UUID,
    effective_from                      DATE,
    effective_to                        DATE,
    reason                              VARCHAR(200),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_branch_history IS 'Tracks each member''s home branch assignment over time; the row with a NULL effective_to is the current assignment.';

-- Table: MEMBER_CHARGE (Tracks charges assigned to members.)
CREATE TABLE IF NOT EXISTS fs.member_charge (
    member_charge_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    vehicle_trip_id                     UUID,
    reservation_id                      UUID,
    service_trip_id                     UUID,
    vehicle_id                          UUID,
    charge_type_code                    VARCHAR(40),
    charge_style                        fs.member_charge_charge_style_enum,
    charge_amount                       NUMERIC(12,2),
    description                         TEXT,
    payment_status                      fs.member_charge_payment_status_enum,
    approved_at                         TIMESTAMPTZ,
    approved_by_user_id                 UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_charge IS 'Tracks charges assigned to members.';

-- Table: MEMBER_CHARGE_TYPE (List of allowable charge types to be selected when adding a member charge.)
CREATE TABLE IF NOT EXISTS fs.member_charge_type (
    charge_type_code                    VARCHAR(40) PRIMARY KEY,
    charge_type_name                    VARCHAR(40) UNIQUE,
    charge_description                  TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_charge_type IS 'List of allowable charge types to be selected when adding a member charge.';

-- Table: MEMBER_DATE (Stores optional/special dates for a member (e.g., spouse birthday, child birthda)
CREATE TABLE IF NOT EXISTS fs.member_date (
    member_date_id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    date_type_code                      VARCHAR(40),
    date_value                          DATE,
    notes                               TEXT,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_date IS 'Stores optional/special dates for a member (e.g., spouse birthday, child birthday, anniversary).';

-- Table: MEMBER_DATE_TYPE (Defines the types of special dates staff can record for members.)
CREATE TABLE IF NOT EXISTS fs.member_date_type (
    date_type_code                      VARCHAR(40) PRIMARY KEY,
    date_type_name                      VARCHAR(120) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_date_type IS 'Defines the types of special dates staff can record for members.';

-- Table: MEMBER_EMAIL (Stores one or more email addresses per member with type, subscription flags, ver)
CREATE TABLE IF NOT EXISTS fs.member_email (
    member_email_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    email                               CITEXT UNIQUE,
    member_email_type                   fs.member_email_member_email_type_enum,
    member_email_note                   VARCHAR(200),
    is_primary                          BOOLEAN,
    account_opt_in                      BOOLEAN,
    vehicle_opt_in                      BOOLEAN,
    marketing_opt_in                    BOOLEAN,
    member_email_active                 BOOLEAN,
    effective_from                      TIMESTAMPTZ,
    effective_to                        TIMESTAMPTZ,
    verified                            BOOLEAN,
    verified_at                         TIMESTAMPTZ,
    verified_method                     VARCHAR(20),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_email IS 'Stores one or more email addresses per member with type, subscription flags, verification metadata, and effective dating. A replaced address is dated closed rather than edited in place.';

-- Table: MEMBER_FEEDBACK (Stores member’s satisfaction feedback about a specific subject (such as a finish)
CREATE TABLE IF NOT EXISTS fs.member_feedback (
    member_feedback_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    vehicle_trip_id                     UUID UNIQUE,
    event_id                            UUID UNIQUE,
    rating_scale_code                   VARCHAR(20),
    rating_value                        INTEGER,
    comment_text                        TEXT,
    collected_channel                   VARCHAR(20),
    responded_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_feedback IS 'Stores member’s satisfaction feedback about a specific subject (such as a finished vehicle trip or an event).';

-- Table: MEMBER_GARAGE_ITEM (Stores one vehicle a member has chosen to display in their garage, either a car )
CREATE TABLE IF NOT EXISTS fs.member_garage_item (
    member_garage_item_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    member_car_id                       UUID,
    vehicle_id                          UUID,
    cover_document_id                   UUID,
    caption                             VARCHAR(300),
    sort_order                          INTEGER,
    is_visible                          BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_garage_item IS 'Stores one vehicle a member has chosen to display in their garage, either a car of their own or a club vehicle.';

-- Table: MEMBER_INSURANCE_COVERAGE (Coverage lines under a member's insurance policy: type, coverage, and amount.)
CREATE TABLE IF NOT EXISTS fs.member_insurance_coverage (
    coverage_id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id                           UUID,
    insurance_type_code                 VARCHAR(40),
    insurance_coverage_code             VARCHAR(40),
    coverage_amount                     NUMERIC(12,2),
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_insurance_coverage IS 'Coverage lines under a member''s insurance policy: type, coverage, and amount.';

-- Table: MEMBER_INSURANCE_POLICY (Stores insurance policy information for members.)
CREATE TABLE IF NOT EXISTS fs.member_insurance_policy (
    member_insurance_policy_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    insured_name                        VARCHAR(160),
    named_drivers                       VARCHAR(160),
    carrier_code                        VARCHAR(40),
    carrier_phone                       VARCHAR(20),
    policy_number                       VARCHAR(80),
    agent_name                          VARCHAR(120),
    agent_phone                         VARCHAR(20),
    effective_on                        DATE,
    expires_on                          DATE,
    notes                               TEXT,
    verified_at                         TIMESTAMPTZ,
    verification_status                 fs.member_insurance_policy_verification_status_enum,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_insurance_policy IS 'Stores insurance policy information for members.';

-- Table: MEMBER_LAP (Attributed ledger of Lap earning events. Each row carries its own expiry, snapsh)
CREATE TABLE IF NOT EXISTS fs.member_lap (
    member_lap_id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    units                               INTEGER,
    expires_on                          DATE,
    subject_id                          UUID,
    lap_rule_id                         UUID,
    description                         TEXT,
    earned_at                           TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_lap IS 'Attributed ledger of Lap earning events. Each row carries its own expiry, snapshotted from the rule at the moment of earning.';

-- Table: MEMBER_NOTE (Keeps correspondence and notes related to members.)
CREATE TABLE IF NOT EXISTS fs.member_note (
    member_note_id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    note                                TEXT,
    is_internal                         BOOLEAN,
    interaction_type                    fs.member_note_interaction_type_enum,
    requested_contact_user_id           UUID,
    follow_up_flag                      BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_note IS 'Keeps correspondence and notes related to members.';

-- Table: MEMBER_NOTE_CATEGORY (Lookup table defining categories for member notes and interactions.)
CREATE TABLE IF NOT EXISTS fs.member_note_category (
    member_note_category_code           VARCHAR(40) PRIMARY KEY,
    category_name                       VARCHAR(120) UNIQUE,
    description                         TEXT,
    route_to_role                       VARCHAR(60),
    auto_task_flag                      BOOLEAN,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_note_category IS 'Lookup table defining categories for member notes and interactions.';

-- Table: MEMBER_NOTE_CATEGORY_LINK (Connects a member note to every category it carries; a note can hold several cat)
CREATE TABLE IF NOT EXISTS fs.member_note_category_link (
    member_note_category_link_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_note_id                      UUID,
    member_note_category_code           VARCHAR(40),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_note_category_link IS 'Connects a member note to every category it carries; a note can hold several categories at once.';

-- Table: MEMBER_PACKAGE (The period hub — one row per membership period for a member, with no overlapping)
CREATE TABLE IF NOT EXISTS fs.member_package (
    member_package_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    membership_level_id                 UUID,
    corporate_account_id                UUID,
    package_number                      INTEGER,
    status                              fs.member_package_status_enum,
    suspended_at                        TIMESTAMPTZ,
    suspension_reason                   TEXT,
    start_date                          DATE,
    end_date                            DATE,
    extended_to                         DATE,
    extension_reason                    TEXT,
    points_accrual_mode                 fs.member_package_points_accrual_mode_enum,
    activated_at                        TIMESTAMPTZ,
    allocation_points                   INTEGER,
    carry_forward_points_in             INTEGER,
    free_pass_weekends                  INTEGER,
    daily_miles                         INTEGER,
    annual_miles                        INTEGER,
    base_level_annual_points            INTEGER,
    base_level_advance_points_percent   NUMERIC(5,2),
    base_level_advance_points_limit     INTEGER,
    renewal_processed_at                TIMESTAMPTZ,
    notes                               TEXT,
    renewal_notice_given_at             TIMESTAMPTZ,
    renewal_notice_withdrawn_at         TIMESTAMPTZ,
    renewal_notice_note                 TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_package IS 'The period hub — one row per membership period for a member, with no overlapping dates.';

-- Table: MEMBER_PACKAGE_CUSTOMIZATION (Stores per-member package customizations and their effective package scope.)
CREATE TABLE IF NOT EXISTS fs.member_package_customization (
    member_package_customization_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    label                               VARCHAR(120),
    effective_package_mode              fs.member_package_customization_effective_package_mode_enum,
    package_start_number                SMALLINT,
    package_end_number                  SMALLINT,
    effective_from                      DATE,
    effective_to                        DATE,
    is_active                           BOOLEAN,
    overrides_json                      JSONB,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_package_customization IS 'Stores per-member package customizations and their effective package scope.';

-- Table: MEMBER_PACKAGE_HOLD (A discretionary hold pausing a membership period, granted as an exception.)
CREATE TABLE IF NOT EXISTS fs.member_package_hold (
    member_package_hold_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_package_id                   UUID,
    hold_start_date                     DATE,
    planned_resume_date                 DATE,
    actual_resume_date                  DATE,
    months_paused                       SMALLINT,
    hold_reason                         TEXT,
    authorized_by_user_id               UUID,
    authorized_at                       TIMESTAMPTZ,
    reminder_task_id                    UUID,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_package_hold IS 'A discretionary hold pausing a membership period, granted as an exception.';

-- Table: MEMBER_PACKAGE_PARTICIPANT (The members on a package and whether each pools or splits points and perks, with)
CREATE TABLE IF NOT EXISTS fs.member_package_participant (
    member_package_participant_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_package_id                   UUID,
    member_id                           UUID,
    is_primary                          BOOLEAN,
    participant_type                    VARCHAR(40),
    points_mode                         fs.member_package_participant_points_mode_enum,
    perks_mode                          fs.member_package_participant_perks_mode_enum,
    points_share_percent                NUMERIC(5,2),
    perks_share_percent                 NUMERIC(5,2),
    effective_start                     DATE,
    effective_end                       DATE,
    is_active                           BOOLEAN,
    notes                               TEXT,
    granted_at                          TIMESTAMPTZ,
    granted_by_user_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_package_participant IS 'The members on a package and whether each pools or splits points and perks, with effective dates.';

-- Table: MEMBER_PACKAGE_RATE (The authoritative pricing pointer, which Rate Card prices this package’s trips, )
CREATE TABLE IF NOT EXISTS fs.member_package_rate (
    member_package_rate_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_package_id                   UUID,
    rate_card_id                        UUID,
    effective_from                      DATE,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_package_rate IS 'The authoritative pricing pointer, which Rate Card prices this package’s trips, from a given date. Seeded from the Membership Series default at activation.';

-- Table: MEMBER_PAYMENT_SCHEDULE (Defines how membership dues are structured for a package. Accrual follows this b)
CREATE TABLE IF NOT EXISTS fs.member_payment_schedule (
    member_payment_schedule_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_package_id                   UUID,
    amount_total                        NUMERIC(12,2),
    frequency                           fs.member_payment_schedule_frequency_enum,
    installment_count                   SMALLINT,
    start_due_date                      DATE,
    status                              VARCHAR(20),
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_payment_schedule IS 'Defines how membership dues are structured for a package. Accrual follows this by default but may be overridden.';

-- Table: MEMBER_PHONE (Stores one or more phone numbers per member with type, opt-in, and verification )
CREATE TABLE IF NOT EXISTS fs.member_phone (
    member_phone_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    member_phone                        VARCHAR(20),
    member_phone_type                   fs.member_phone_member_phone_type_enum,
    member_phone_note                   VARCHAR(200),
    member_phone_active                 BOOLEAN,
    is_primary                          BOOLEAN,
    sms_opt_in                          BOOLEAN,
    effective_from                      TIMESTAMPTZ,
    effective_to                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_phone IS 'Stores one or more phone numbers per member with type, opt-in, and verification confirmation.';

-- Table: MEMBER_PROFILE (Stores the directory details staff keep about a member, such as their photo, pro)
CREATE TABLE IF NOT EXISTS fs.member_profile (
    member_profile_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID UNIQUE,
    photo_document_id                   UUID,
    profession                          VARCHAR(120),
    employer                            VARCHAR(160),
    job_title                           VARCHAR(120),
    business_description                TEXT,
    industry_code                       VARCHAR(40),
    alma_mater                          VARCHAR(160),
    shirt_size                          VARCHAR(20),
    preferred_greeting                  VARCHAR(80),
    referred_by_member_id               UUID,
    referred_by_note                    VARCHAR(200),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_profile IS 'Stores the directory details staff keep about a member, such as their photo, profession, employer, and industry.';

-- Table: MEMBER_RELATIONSHIP (Stores links between members with defined relationship types, effective-dated. A)
CREATE TABLE IF NOT EXISTS fs.member_relationship (
    member_relationship_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    related_member_id                   UUID,
    relationship_type                   fs.member_relationship_relationship_type_enum,
    effective_start                     DATE,
    effective_end                       DATE,
    end_reason                          VARCHAR(200),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_relationship IS 'Stores links between members with defined relationship types, effective-dated. A relationship that ends is dated closed rather than deleted, so history and past correspondence remain explicable.';

-- Table: MEMBER_TRIP_STORY (Stores a member’s written account of one vehicle trip, including its title and i)
CREATE TABLE IF NOT EXISTS fs.member_trip_story (
    member_trip_story_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_trip_id                     UUID UNIQUE,
    member_id                           UUID,
    story_title                         VARCHAR(200),
    introduction                        TEXT,
    cover_document_id                   UUID,
    visibility                          VARCHAR(40),
    started_at                          TIMESTAMPTZ,
    last_saved_at                       TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_trip_story IS 'Stores a member’s written account of one vehicle trip, including its title and introduction.';

-- Table: MEMBER_TRIP_STORY_ANSWER (Stores one answer to one prompt, keeping what the member wrote separately from a)
CREATE TABLE IF NOT EXISTS fs.member_trip_story_answer (
    member_trip_story_answer_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_trip_story_id                UUID,
    member_trip_story_prompt_id         UUID,
    answer_text                         TEXT,
    assisted_text                       TEXT,
    assisted_at                         TIMESTAMPTZ,
    uses_assisted                       BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_trip_story_answer IS 'Stores one answer to one prompt, keeping what the member wrote separately from any assisted version.';

-- Table: MEMBER_TRIP_STORY_PROMPT (Defines the questions a member is asked about a trip, so the club can change the)
CREATE TABLE IF NOT EXISTS fs.member_trip_story_prompt (
    member_trip_story_prompt_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_code                         VARCHAR(40) UNIQUE,
    prompt_text                         VARCHAR(200) UNIQUE,
    help_text                           VARCHAR(300),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_trip_story_prompt IS 'Defines the questions a member is asked about a trip, so the club can change them without a code change.';

-- Table: PARTICIPANT_TYPE_SELECT (Defines the participants in a member’s package, including the primary member, sp)
CREATE TABLE IF NOT EXISTS fs.participant_type_select (
    participant_type_code               VARCHAR(40) PRIMARY KEY,
    participant_type_name               VARCHAR(100),
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.participant_type_select IS 'Defines the participants in a member’s package, including the primary member, spouse, children, or associates. Supports effective dating and role-based participant types.';

-- Table: PODIUM_STATUS_BENEFIT (Defines the benefits granted by each Podium Status.)
CREATE TABLE IF NOT EXISTS fs.podium_status_benefit (
    podium_status_benefit_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    podium_status_code                  VARCHAR(40),
    benefit_target                      VARCHAR(40),
    adjustment_kind                     VARCHAR(40),
    adjustment_value                    NUMERIC(12,2),
    adjustment_ref_code                 VARCHAR(40),
    description                         VARCHAR(200),
    is_active                           BOOLEAN,
    start_date                          DATE,
    end_date                            DATE,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.podium_status_benefit IS 'Defines the benefits granted by each Podium Status.';

-- Table: PODIUM_STATUS_SELECT (Defines allowable Podium Status levels and the Laps each requires. Status is eva)
CREATE TABLE IF NOT EXISTS fs.podium_status_select (
    podium_status_code                  VARCHAR(40) PRIMARY KEY,
    podium_status_name                  VARCHAR(120) UNIQUE,
    description                         TEXT,
    laps_required                       INTEGER,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.podium_status_select IS 'Defines allowable Podium Status levels and the Laps each requires. Status is evaluated from the Lap ledger and can move up or down; it is not a high-water mark.';

-- -----------------------------------------------------------------------------
-- DOMAIN: MEMBERSHIP LEVELS
-- -----------------------------------------------------------------------------

-- Table: BOOKING_TYPE_SELECT (List of allowable booking rule types that may be customized in MPC_BOOKINGS.)
CREATE TABLE IF NOT EXISTS fs.booking_type_select (
    booking_type_code                   VARCHAR(40) PRIMARY KEY,
    booking_type_name                   VARCHAR(100),
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.booking_type_select IS 'List of allowable booking rule types that may be customized in MPC_BOOKINGS.';

-- Table: MEMBERSHIP_LEVEL (Stores the catalog of available membership levels.)
CREATE TABLE IF NOT EXISTS fs.membership_level (
    membership_level_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_series_id                UUID,
    membership_series_code              VARCHAR(40),
    plan_code                           VARCHAR(40) UNIQUE,
    membership_level_type_code          VARCHAR(40),
    membership_level_name               VARCHAR(120) UNIQUE,
    description                         TEXT,
    status                              fs.membership_level_status_enum,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.membership_level IS 'Stores the catalog of available membership levels.';

-- Table: MEMBERSHIP_LEVEL_BOOKINGS (Defines booking rules for each membership level.)
CREATE TABLE IF NOT EXISTS fs.membership_level_bookings (
    membership_level_bookings_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_id                 UUID,
    simultaneous_bookings               INTEGER,
    reservation_window_days             INTEGER,
    advance_reservations                INTEGER,
    max_reservations_month              INTEGER,
    max_reservations_year               INTEGER,
    reservation_cancellations           INTEGER,
    advance_reservation_extra_days      INTEGER,
    max_active_reservations             INTEGER,
    booking_points_divisor              INTEGER,
    avg_days_per_reservation            fs.membership_level_bookings_avg_days_per_reservation_enum,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.membership_level_bookings IS 'Defines booking rules for each membership level.';

-- Table: MEMBERSHIP_LEVEL_BRANCH_AVAILABILITY (Branches where a membership level may be offered, sold, or renewed. Sales availa)
CREATE TABLE IF NOT EXISTS fs.membership_level_branch_availability (
    membership_level_branch_availability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_id                 UUID,
    branch_id                           UUID,
    granted_at                          TIMESTAMPTZ,
    granted_by_user_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    revoked_at                          TIMESTAMPTZ,
    revoked_by_user_id                  UUID
);
COMMENT ON TABLE fs.membership_level_branch_availability IS 'Branches where a membership level may be offered, sold, or renewed. Sales availability only; it never affects what an existing member may book, and it never affects existing member terms.';

-- Table: MEMBERSHIP_LEVEL_FREE_PASS (Defines the level’s Free Pass Weekend configuration (quantity + redemption const)
CREATE TABLE IF NOT EXISTS fs.membership_level_free_pass (
    membership_level_free_pass_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_id                 UUID,
    free_pass_total_quantity            INTEGER,
    tier_max_id                         UUID,
    book_hours_before_reservation       INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.membership_level_free_pass IS 'Defines the level’s Free Pass Weekend configuration (quantity + redemption constraints).';

-- Table: MEMBERSHIP_LEVEL_MILEAGE (Specifies mileage rules for a level.)
CREATE TABLE IF NOT EXISTS fs.membership_level_mileage (
    membership_level_mileage_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_id                 UUID,
    daily_miles                         INTEGER,
    annual_miles                        INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.membership_level_mileage IS 'Specifies mileage rules for a level.';

-- Table: MEMBERSHIP_LEVEL_PERKS (Lists special benefits that come with a level.)
CREATE TABLE IF NOT EXISTS fs.membership_level_perks (
    membership_level_perks_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_id                 UUID,
    free_pass_weekends                  INTEGER,
    comp_deliveries                     INTEGER,
    spouse_included                     BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.membership_level_perks IS 'Lists special benefits that come with a level.';

-- Table: MEMBERSHIP_LEVEL_POINTS_CAPS (Defines the points system and carryover rules for a membership level, including )
CREATE TABLE IF NOT EXISTS fs.membership_level_points_caps (
    membership_level_points_caps_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_id                 UUID,
    allocation_annual                   INTEGER,
    rollover_policy                     fs.membership_level_points_caps_rollover_policy_enum,
    monthly_cap_base                    INTEGER,
    monthly_cap_percent                 NUMERIC(5,2),
    monthly_cap_max                     INTEGER,
    points_beyond_accrual_percent       NUMERIC(5,2),
    carry_forward_max_per_year          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.membership_level_points_caps IS 'Defines the points system and carryover rules for a membership level, including annual allocations, rollover policy, and carryover caps.';

-- Table: MEMBERSHIP_LEVEL_PRICING (Dues and fee pricing for each membership level, optionally varied by branch and )
CREATE TABLE IF NOT EXISTS fs.membership_level_pricing (
    membership_level_pricing_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_id                 UUID,
    branch_id                           UUID,
    effective_from                      DATE,
    app_fee                             NUMERIC(12,2),
    joining_fee                         NUMERIC(12,2),
    monthly_dues                        NUMERIC(12,2),
    annual_dues                         NUMERIC(12,2),
    fuel_markup_percent                 NUMERIC(5,2),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.membership_level_pricing IS 'Dues and fee pricing for each membership level, optionally varied by branch and dated so an increase can be entered in advance.';

-- Table: MEMBERSHIP_LEVEL_TYPE_SELECT (List of allowable level types that are used to provide classification structure )
CREATE TABLE IF NOT EXISTS fs.membership_level_type_select (
    membership_level_type_code          VARCHAR(40) PRIMARY KEY,
    membership_level_type_name          VARCHAR(120) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.membership_level_type_select IS 'List of allowable level types that are used to provide classification structure for membership levels.';

-- Table: MEMBERSHIP_SERIES (Defines membership seriesing for membership levels that share identical tier and)
CREATE TABLE IF NOT EXISTS fs.membership_series (
    membership_series_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_series_code              VARCHAR(40) UNIQUE,
    membership_series_name              VARCHAR(120),
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.membership_series IS 'Defines membership seriesing for membership levels that share identical tier and point mapping logic.';

-- Table: MEMBERSHIP_SERIES_RATE_CARD (Dated default link giving each Membership Series its rate card; new packages see)
CREATE TABLE IF NOT EXISTS fs.membership_series_rate_card (
    membership_series_rate_card_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_series_id                UUID,
    rate_card_id                        UUID,
    effective_from                      DATE,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.membership_series_rate_card IS 'Dated default link giving each Membership Series its rate card; new packages seed their pointer from here. Multiple Series can share one card (FSC 2024 and FSC 2026 do).';

-- Table: MILEAGE_TYPE_SELECT (List of allowable mileage types that may be customized in MPC_MILEAGE.)
CREATE TABLE IF NOT EXISTS fs.mileage_type_select (
    mileage_type_code                   VARCHAR(40) PRIMARY KEY,
    mileage_type_name                   VARCHAR(100),
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.mileage_type_select IS 'List of allowable mileage types that may be customized in MPC_MILEAGE.';

-- Table: MPC_BOOKINGS (Overrides for MEMBERSHIP_LEVEL_BOOKINGS at the customization level. MPC rows are)
CREATE TABLE IF NOT EXISTS fs.mpc_bookings (
    mpc_bookings_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    membership_level_id                 UUID,
    booking_type                        VARCHAR(40),
    add_value                           INTEGER,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.mpc_bookings IS 'Overrides for MEMBERSHIP_LEVEL_BOOKINGS at the customization level. MPC rows are immutable.';

-- Table: MPC_BRANCH_ACCESS (Adjusts a member’s branch access for a customization, adding or removing a branc)
CREATE TABLE IF NOT EXISTS fs.mpc_branch_access (
    mpc_branch_access_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_package_customization_id     UUID,
    branch_id                           UUID,
    action                              fs.mpc_branch_access_action_enum,
    granted_at                          TIMESTAMPTZ,
    granted_by_user_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.mpc_branch_access IS 'Adjusts a member’s branch access for a customization, adding or removing a branch from what the membership level allows.';

-- Table: MPC_FREE_PASS (Member-specific overrides to the membership_level_free_pass configuration for a )
CREATE TABLE IF NOT EXISTS fs.mpc_free_pass (
    mpc_free_pass_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mpc_id                              UUID,
    free_pass_total_qty_override        INTEGER,
    tier_max_id_override                UUID,
    book_hours_before_reservation_override INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.mpc_free_pass IS 'Member-specific overrides to the membership_level_free_pass configuration for a specific member package. MPC rows are immutable.';

-- Table: MPC_MILEAGE (Handles customizations to mileage allowances for specific members. MPC rows are )
CREATE TABLE IF NOT EXISTS fs.mpc_mileage (
    mpc_mileage_id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    membership_level_id                 UUID,
    mileage_type                        VARCHAR(40),
    override_value                      INTEGER,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.mpc_mileage IS 'Handles customizations to mileage allowances for specific members. MPC rows are immutable.';

-- Table: MPC_PERKS (Stores custom perk adjustments for a member’s package, such as extra free pass w)
CREATE TABLE IF NOT EXISTS fs.mpc_perks (
    mpc_perks_id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    membership_level_id                 UUID,
    perk_type                           VARCHAR(40),
    add_value                           INTEGER,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.mpc_perks IS 'Stores custom perk adjustments for a member’s package, such as extra free pass weekends or complimentary deliveries. Supports overrides and bonuses with defined duration.';

-- Table: MPC_POINTS_AND_CAPS (Point and cap adjustments for a member package: monthly cap, carry-forward, allo)
CREATE TABLE IF NOT EXISTS fs.mpc_points_and_caps (
    mpc_points_and_caps_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    membership_level_id                 UUID,
    points_cap_type                     VARCHAR(40),
    add_value                           INTEGER,
    set_value                           VARCHAR(20),
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.mpc_points_and_caps IS 'Point and cap adjustments for a member package: monthly cap, carry-forward, allocation bonuses, and the spend-ahead percentage.';

-- Table: MPC_PRICING (Overrides for MEMBERSHIP_LEVEL_PRICING at the customization level. MPC rows are )
CREATE TABLE IF NOT EXISTS fs.mpc_pricing (
    mpc_pricing_id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    membership_level_id                 UUID,
    pricing_type                        VARCHAR(40),
    override_value                      NUMERIC(12,2),
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.mpc_pricing IS 'Overrides for MEMBERSHIP_LEVEL_PRICING at the customization level. MPC rows are immutable.';

-- Table: MPC_TIER_ASSIGNMENT (Allows member-specific overrides for vehicle tier assignment. MPC rows are immut)
CREATE TABLE IF NOT EXISTS fs.mpc_tier_assignment (
    mpc_tier_assignment_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_package_customization_id     UUID,
    vehicle_id                          UUID,
    vehicle_tier_id_override            UUID,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.mpc_tier_assignment IS 'Allows member-specific overrides for vehicle tier assignment. MPC rows are immutable.';

-- Table: MPC_TIER_POINT_RATE (Allows member-specific overrides for tier point values (weekday, weekend, extra-)
CREATE TABLE IF NOT EXISTS fs.mpc_tier_point_rate (
    mpc_tier_point_rate_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_package_customization_id     UUID,
    vehicle_tier_id                     UUID,
    weekday_point_value_override        INTEGER,
    weekend_point_value_override        INTEGER,
    extra_mile_point_value_override     NUMERIC(6,3),
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.mpc_tier_point_rate IS 'Allows member-specific overrides for tier point values (weekday, weekend, extra-mile). MPC rows are immutable.';

-- Table: MPC_VEHICLE_TIER_ACCESS (Adjust vehicle tier access for a customization (add/remove). MPC rows are immuta)
CREATE TABLE IF NOT EXISTS fs.mpc_vehicle_tier_access (
    mpc_vehicle_tier_access_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_package_customization_id     UUID,
    vehicle_tier_id                     UUID,
    action                              fs.mpc_vehicle_tier_access_action_enum,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.mpc_vehicle_tier_access IS 'Adjust vehicle tier access for a customization (add/remove). MPC rows are immutable.';

-- Table: PERK_TYPE_SELECT (List of allowable perk types for levels, customizations, and member ledgers.)
CREATE TABLE IF NOT EXISTS fs.perk_type_select (
    perk_type_code                      VARCHAR(40) PRIMARY KEY,
    perk_type_name                      VARCHAR(100),
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.perk_type_select IS 'List of allowable perk types for levels, customizations, and member ledgers.';

-- Table: POINTS_CAP_TYPE_SELECT (List of allowable points cap types that may be customized in MPC_POINTS_AND_CAPS)
CREATE TABLE IF NOT EXISTS fs.points_cap_type_select (
    points_cap_type_code                VARCHAR(40) PRIMARY KEY,
    points_cap_type_name                VARCHAR(100),
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.points_cap_type_select IS 'List of allowable points cap types that may be customized in MPC_POINTS_AND_CAPS.';

-- Table: PRICING_TYPE_SELECT (List of allowable pricing types that may be customized in MPC_PRICING.)
CREATE TABLE IF NOT EXISTS fs.pricing_type_select (
    pricing_type_code                   VARCHAR(40) PRIMARY KEY,
    pricing_type_name                   VARCHAR(100),
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.pricing_type_select IS 'List of allowable pricing types that may be customized in MPC_PRICING.';

-- Table: RATE_CARD (A tier rate card, the club's price list for vehicle usage. Append-only once in u)
CREATE TABLE IF NOT EXISTS fs.rate_card (
    rate_card_id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_code                           VARCHAR(20) UNIQUE,
    card_name                           VARCHAR(100),
    description                         TEXT,
    first_used_on                       DATE,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.rate_card IS 'A tier rate card, the club''s price list for vehicle usage. Append-only once in use.';

-- Table: RATE_CARD_PLACEMENT (Tier placements per card: which vehicle sits in which tier, on which card. A veh)
CREATE TABLE IF NOT EXISTS fs.rate_card_placement (
    rate_card_placement_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rate_card_id                        UUID,
    vehicle_id                          UUID,
    vehicle_tier_id                     UUID,
    effective_from                      DATE,
    effective_to                        DATE,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.rate_card_placement IS 'Tier placements per card: which vehicle sits in which tier, on which card. A vehicle holds at most one placement per card, and a placement on a card in use is permanent.';

-- Table: RATE_CARD_RATE (Point values per card, tier, and season. Rates for a tier the card does not yet )
CREATE TABLE IF NOT EXISTS fs.rate_card_rate (
    rate_card_rate_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rate_card_id                        UUID,
    vehicle_tier_id                     UUID,
    rate_card_season_id                 UUID,
    weekday_point_value                 INTEGER,
    weekend_point_value                 INTEGER,
    extra_mile_point_value              NUMERIC(6,3),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.rate_card_rate IS 'Point values per card, tier, and season. Rates for a tier the card does not yet price may be added to a card in use; existing rates are permanent.';

-- Table: RATE_CARD_SEASON (Optional seasons for a rate card, one-to-many. Zero rows means the card is flat )
CREATE TABLE IF NOT EXISTS fs.rate_card_season (
    rate_card_season_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rate_card_id                        UUID,
    season_name                         VARCHAR(40),
    start_month                         SMALLINT,
    start_day                           SMALLINT,
    end_month                           SMALLINT,
    end_day                             SMALLINT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.rate_card_season IS 'Optional seasons for a rate card, one-to-many. Zero rows means the card is flat (the default — no seasonal adjustment).';

-- Table: VEHICLE_TIER (Defines the available vehicle tier levels in the system.)
CREATE TABLE IF NOT EXISTS fs.vehicle_tier (
    vehicle_tier_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_tier                        VARCHAR(60) UNIQUE,
    vehicle_tier_name                   VARCHAR(120),
    is_active                           BOOLEAN,
    description                         TEXT,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_tier IS 'Defines the available vehicle tier levels in the system.';

-- Table: VEHICLE_TIER_ACCESS (Defines which vehicle tiers are available within each level (tier availability),)
CREATE TABLE IF NOT EXISTS fs.vehicle_tier_access (
    vehicle_tier_access_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_id                 UUID,
    vehicle_tier_id                     UUID,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_tier_access IS 'Defines which vehicle tiers are available within each level (tier availability), not individual vehicle assignments.';

-- -----------------------------------------------------------------------------
-- DOMAIN: NOTIFICATIONS
-- -----------------------------------------------------------------------------

-- Table: NOTIFICATION (Records actual notification events sent by the system.)
CREATE TABLE IF NOT EXISTS fs.notification (
    notification_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id                         UUID,
    recipient_user_id                   UUID,
    channel                             fs.notification_channel_enum,
    status                              fs.notification_status_enum,
    sent_at                             TIMESTAMPTZ,
    related_record_id                   UUID,
    error_message                       TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    sent_subject                        TEXT,
    sent_body                           TEXT
);
COMMENT ON TABLE fs.notification IS 'Records actual notification events sent by the system.';

-- Table: NOTIFICATION_DELIVERY_LOG (Captures detailed delivery feedback from external messaging providers. A hard bo)
CREATE TABLE IF NOT EXISTS fs.notification_delivery_log (
    delivery_id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id                     UUID,
    provider                            UUID,
    provider_message_id                 VARCHAR(80),
    status                              fs.notification_delivery_log_status_enum,
    bounce_type                         fs.notification_delivery_log_bounce_type_enum,
    status_detail                       TEXT,
    logged_at                           TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.notification_delivery_log IS 'Captures detailed delivery feedback from external messaging providers. A hard bounce recorded here deactivates the contact point it was sent to; a soft bounce does not.';

-- Table: NOTIFICATION_PREFERENCE (Defines each member’s opt-in status for specific notification categories and del)
CREATE TABLE IF NOT EXISTS fs.notification_preference (
    notification_preference_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    category                            fs.notification_preference_category_enum,
    channel                             fs.notification_preference_channel_enum,
    is_enabled                          BOOLEAN,
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by_user_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID
);
COMMENT ON TABLE fs.notification_preference IS 'Defines each member’s opt-in status for specific notification categories and delivery channels..';

-- Table: NOTIFICATION_TEMPLATE (Holds reusable message templates for system notifications.)
CREATE TABLE IF NOT EXISTS fs.notification_template (
    notification_template_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_template_name          VARCHAR(120),
    category                            fs.notification_template_category_enum,
    channel                             fs.notification_template_channel_enum,
    subject                             VARCHAR(200),
    body                                TEXT,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.notification_template IS 'Holds reusable message templates for system notifications.';

-- Table: NOTIFICATION_TEMPLATE_VARIABLE (Specifies which dynamic placeholders can be safely used within each template.)
CREATE TABLE IF NOT EXISTS fs.notification_template_variable (
    template_variable_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id                         UUID,
    variable_name                       VARCHAR(80),
    variable_description                TEXT,
    is_required                         BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.notification_template_variable IS 'Specifies which dynamic placeholders can be safely used within each template.';

-- -----------------------------------------------------------------------------
-- DOMAIN: POINT TRACKING
-- -----------------------------------------------------------------------------

-- Table: CREDIT_REASON_TYPE (Lookup table defining structured reasons for granting member credits (points or )
CREATE TABLE IF NOT EXISTS fs.credit_reason_type (
    credit_reason_type_code             VARCHAR(40) PRIMARY KEY,
    reason_name                         VARCHAR(120) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.credit_reason_type IS 'Lookup table defining structured reasons for granting member credits (points or perks).';

-- Table: MEMBER_PERK_CREDIT (Records one-time perk credits granted to members (e.g., free pass weekends, comp)
CREATE TABLE IF NOT EXISTS fs.member_perk_credit (
    member_perk_credit_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    perk_type                           VARCHAR(40),
    quantity                            INTEGER,
    credit_reason_type_code             VARCHAR(40),
    description                         TEXT,
    approval_status                     fs.member_perk_credit_approval_status_enum,
    approved_at                         TIMESTAMPTZ,
    approved_by_user_id                 UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_perk_credit IS 'Records one-time perk credits granted to members (e.g., free pass weekends, complimentary deliveries). Posts immediately to the member_perk_ledger.';

-- Table: MEMBER_PERK_LEDGER (Unified ledger for non-point perks: FPW, complimentary deliveries, cancellation )
CREATE TABLE IF NOT EXISTS fs.member_perk_ledger (
    member_perk_ledger_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    vehicle_trip_id                     UUID,
    perk_type                           VARCHAR(40),
    change_amount                       INTEGER,
    entry_type                          fs.member_perk_ledger_entry_type_enum,
    reservation_id                      UUID,
    member_package_participant_id       UUID,
    occurred_at                         TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_perk_ledger IS 'Unified ledger for non-point perks: FPW, complimentary deliveries, cancellation allowance.';

-- Table: MEMBER_POINT_CREDIT (Records one-time point credits granted to members. Posts immediately to the memb)
CREATE TABLE IF NOT EXISTS fs.member_point_credit (
    member_point_credit_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    units                               INTEGER,
    credit_reason_type_code             VARCHAR(40),
    description                         TEXT,
    approval_status                     fs.member_point_credit_approval_status_enum,
    approved_at                         TIMESTAMPTZ,
    approved_by_user_id                 UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_point_credit IS 'Records one-time point credits granted to members. Posts immediately to the member_points_ledger.';

-- Table: MEMBER_POINTS_CARRYOVER (Tracks how unused points from one membership package are scheduled to be allocat)
CREATE TABLE IF NOT EXISTS fs.member_points_carryover (
    carryover_id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    source_package_id                   UUID,
    allocation_package_id               UUID,
    points_amount                       INTEGER,
    account_type                        fs.member_points_carryover_account_type_enum,
    overflow_amount                     INTEGER,
    capped_flag                         BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_points_carryover IS 'Tracks how unused points from one membership package are scheduled to be allocated as carryover in future packages under the A/B split rules.';

-- Table: MEMBER_POINTS_LEDGER (Tracks all point transactions for each member.)
CREATE TABLE IF NOT EXISTS fs.member_points_ledger (
    member_points_ledger_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    vehicle_trip_id                     UUID,
    reservation_id                      UUID,
    points_change                       INTEGER,
    source                              VARCHAR(40),
    description                         TEXT,
    entry_type                          fs.member_points_ledger_entry_type_enum,
    reservation_perk_application_id     UUID,
    member_package_participant_id       UUID,
    occurred_at                         TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.member_points_ledger IS 'Tracks all point transactions for each member.';

-- -----------------------------------------------------------------------------
-- DOMAIN: REPORTING & EXPORTS
-- -----------------------------------------------------------------------------

-- Table: EXPORT_DESTINATION_SELECT (Where an export goes. Seeded with Download, Email, and Interface.)
CREATE TABLE IF NOT EXISTS fs.export_destination_select (
    export_destination_code             VARCHAR(40) PRIMARY KEY,
    export_destination_name             VARCHAR(80),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.export_destination_select IS 'Where an export goes. Seeded with Download, Email, and Interface.';

-- Table: EXPORT_FORMAT_SELECT (File formats an export can produce. Seeded with CSV, Excel, PDF, and Print.)
CREATE TABLE IF NOT EXISTS fs.export_format_select (
    export_format_code                  VARCHAR(40) PRIMARY KEY,
    export_format_name                  VARCHAR(80),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.export_format_select IS 'File formats an export can produce. Seeded with CSV, Excel, PDF, and Print.';

-- Table: EXPORT_JOB (Tracks bulk data exports.)
CREATE TABLE IF NOT EXISTS fs.export_job (
    export_job_id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dataset_type                        VARCHAR(120),
    filters                             JSONB,
    requested_by_user_id                UUID,
    status                              fs.export_job_status_enum,
    file_reference                      VARCHAR(255),
    export_template_id                  UUID,
    export_format_code                  VARCHAR(40),
    export_destination_code             VARCHAR(40),
    approved_at                         TIMESTAMPTZ,
    approved_by_user_id                 UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE fs.export_job IS 'Tracks bulk data exports.';

-- Table: EXPORT_SCHEDULE (A saved export set to run on a cadence, mirroring REPORT_SCHEDULE.)
CREATE TABLE IF NOT EXISTS fs.export_schedule (
    export_schedule_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    export_template_id                  UUID,
    schedule_name                       VARCHAR(120),
    recurrence                          fs.export_schedule_recurrence_enum,
    recurrence_detail                   VARCHAR(120),
    custom_anchor_date                  DATE,
    run_time_local                      TIME,
    relative_period                     fs.export_schedule_relative_period_enum,
    filters                             JSONB,
    fan_out_by_branch                   BOOLEAN,
    delivery_method                     fs.export_schedule_delivery_method_enum,
    last_run_at                         TIMESTAMPTZ,
    next_run_at                         TIMESTAMPTZ,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.export_schedule IS 'A saved export set to run on a cadence, mirroring REPORT_SCHEDULE.';

-- Table: EXPORT_SCHEDULE_RECIPIENT (One standing recipient of a scheduled export, held as a real user reference. A r)
CREATE TABLE IF NOT EXISTS fs.export_schedule_recipient (
    export_schedule_recipient_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    export_schedule_id                  UUID,
    user_id                             UUID,
    removed_at                          TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.export_schedule_recipient IS 'One standing recipient of a scheduled export, held as a real user reference. A recipient is removed by dating the row, never by deleting it.';

-- Table: EXPORT_TEMPLATE (A saved definition of a recurring export: dataset, columns, format, and destinat)
CREATE TABLE IF NOT EXISTS fs.export_template (
    export_template_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_name                       VARCHAR(120),
    description                         TEXT,
    dataset_type                        VARCHAR(120),
    included_columns                    JSONB,
    export_format_code                  VARCHAR(40),
    export_destination_code             VARCHAR(40),
    required_permission_code            VARCHAR(120),
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.export_template IS 'A saved definition of a recurring export: dataset, columns, format, and destination.';

-- Table: REPORT_DEFINITION (The registry of reports the platform provides: what each answers, who it is for,)
CREATE TABLE IF NOT EXISTS fs.report_definition (
    report_definition_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_code                         VARCHAR(40) UNIQUE,
    report_name                         VARCHAR(150),
    question_answered                   TEXT,
    audience                            VARCHAR(80),
    domain                              VARCHAR(60),
    primary_tables                      TEXT,
    required_permission_code            VARCHAR(120),
    is_schedulable                      BOOLEAN,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.report_definition IS 'The registry of reports the platform provides: what each answers, who it is for, and the permission that gates it.';

-- Table: REPORT_JOB (Tracks generated reports requested by staff.)
CREATE TABLE IF NOT EXISTS fs.report_job (
    report_job_id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_type                         VARCHAR(120),
    report_category                     fs.report_job_report_category_enum,
    parameters                          JSONB,
    requested_by_user_id                UUID,
    status                              fs.report_job_status_enum,
    file_reference                      VARCHAR(255),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at                        TIMESTAMPTZ
);
COMMENT ON TABLE fs.report_job IS 'Tracks generated reports requested by staff.';

-- Table: REPORT_SCHEDULE (A saved report set to run on a cadence, delivering to named recipients.)
CREATE TABLE IF NOT EXISTS fs.report_schedule (
    report_schedule_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_definition_id                UUID,
    schedule_name                       VARCHAR(120) UNIQUE,
    recurrence                          fs.report_schedule_recurrence_enum,
    recurrence_detail                   VARCHAR(60),
    custom_anchor_date                  DATE,
    run_time_local                      TIME,
    relative_period                     fs.report_schedule_relative_period_enum,
    parameters                          JSONB,
    fan_out_by_branch                   BOOLEAN,
    recipient_user_ids                  JSONB,
    delivery_method                     fs.report_schedule_delivery_method_enum,
    last_run_at                         TIMESTAMPTZ,
    next_run_at                         TIMESTAMPTZ,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.report_schedule IS 'A saved report set to run on a cadence, delivering to named recipients.';

-- -----------------------------------------------------------------------------
-- DOMAIN: SHADOW TABLES
-- -----------------------------------------------------------------------------

-- Table: CORPORATE_ACCOUNT_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.corporate_account_shadow (
    account_name                        VARCHAR(160),
    tax_id                              VARCHAR(20),
    home_branch_id                      UUID,
    billing_address_line1               VARCHAR(200),
    billing_address_line2               VARCHAR(100),
    billing_city                        VARCHAR(100),
    billing_state                       VARCHAR(2),
    billing_postal_code                 VARCHAR(10),
    is_active                           BOOLEAN,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    corporate_account_id                UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.corporate_account_shadow IS 'Shadow Table.';

-- Table: MEMBER_PACKAGE_CUSTOMIZATION_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.member_package_customization_shadow (
    member_id                           UUID,
    label                               VARCHAR(120),
    effective_package_mode              fs.member_package_customization_effective_package_mode_enum,
    package_start_number                SMALLINT,
    package_end_number                  SMALLINT,
    effective_from                      DATE,
    effective_to                        DATE,
    is_active                           BOOLEAN,
    overrides_json                      JSONB,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_package_customization_id     UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.member_package_customization_shadow IS 'Shadow Table.';

-- Table: MEMBER_PACKAGE_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.member_package_shadow (
    member_package_id                   UUID,
    member_id                           UUID,
    membership_level_id                 UUID,
    corporate_account_id                UUID,
    package_number                      INTEGER,
    status                              fs.member_package_status_enum,
    start_date                          DATE,
    end_date                            DATE,
    extended_to                         DATE,
    extension_reason                    TEXT,
    points_accrual_mode                 fs.member_package_points_accrual_mode_enum,
    activated_at                        TIMESTAMPTZ,
    allocation_points                   INTEGER,
    carry_forward_points_in             INTEGER,
    free_pass_weekends                  INTEGER,
    daily_miles                         INTEGER,
    annual_miles                        INTEGER,
    base_level_annual_points            INTEGER,
    base_level_advance_points_percent   NUMERIC(5,2),
    base_level_advance_points_limit     INTEGER,
    renewal_processed_at                TIMESTAMPTZ,
    renewal_notice_given_at             TIMESTAMPTZ,
    renewal_notice_withdrawn_at         TIMESTAMPTZ,
    renewal_notice_note                 TEXT,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    suspended_at                        TIMESTAMPTZ,
    suspension_reason                   TEXT,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.member_package_shadow IS 'Shadow Table.';

-- Table: MEMBER_PAYMENT_SCHEDULE_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.member_payment_schedule_shadow (
    member_package_id                   UUID,
    amount_total                        NUMERIC(12,2),
    frequency                           fs.member_payment_schedule_frequency_enum,
    installment_count                   SMALLINT,
    start_due_date                      DATE,
    status                              VARCHAR(20),
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_payment_schedule_id          UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.member_payment_schedule_shadow IS 'Shadow Table.';

-- Table: MEMBER_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.member_shadow (
    member_seq                          INTEGER,
    member_number                       VARCHAR(20),
    user_id                             UUID,
    home_branch_id                      UUID,
    first_name                          VARCHAR(100),
    middle_name                         VARCHAR(100),
    last_name                           VARCHAR(100),
    preferred_name                      VARCHAR(80),
    license_number                      VARCHAR(32),
    license_state                       VARCHAR(2),
    license_expires_on                  DATE,
    date_of_birth                       DATE,
    member_since                        DATE,
    podium_status                       VARCHAR(40),
    lifecycle_status                    fs.member_lifecycle_status_enum,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.member_shadow IS 'Shadow Table.';

-- Table: MEMBERSHIP_LEVEL_BOOKINGS_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.membership_level_bookings_shadow (
    membership_level_id                 UUID,
    simultaneous_bookings               INTEGER,
    reservation_window_days             INTEGER,
    advance_reservations                INTEGER,
    max_reservations_month              INTEGER,
    max_reservations_year               INTEGER,
    reservation_cancellations           INTEGER,
    advance_reservation_extra_days      INTEGER,
    max_active_reservations             INTEGER,
    booking_points_divisor              INTEGER,
    avg_days_per_reservation            fs.membership_level_bookings_avg_days_per_reservation_enum,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_bookings_id        UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.membership_level_bookings_shadow IS 'Shadow Table.';

-- Table: MEMBERSHIP_LEVEL_FREE_PASS_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.membership_level_free_pass_shadow (
    membership_level_id                 UUID,
    free_pass_total_quantity            INTEGER,
    tier_max_id                         UUID,
    book_hours_before_reservation       INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_free_pass_id       UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.membership_level_free_pass_shadow IS 'Shadow Table.';

-- Table: MEMBERSHIP_LEVEL_MILEAGE_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.membership_level_mileage_shadow (
    membership_level_id                 UUID,
    daily_miles                         INTEGER,
    annual_miles                        INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_mileage_id         UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.membership_level_mileage_shadow IS 'Shadow Table.';

-- Table: MEMBERSHIP_LEVEL_PERKS_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.membership_level_perks_shadow (
    membership_level_id                 UUID,
    free_pass_weekends                  INTEGER,
    comp_deliveries                     INTEGER,
    spouse_included                     BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_perks_id           UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.membership_level_perks_shadow IS 'Shadow Table.';

-- Table: MEMBERSHIP_LEVEL_POINTS_CAPS_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.membership_level_points_caps_shadow (
    membership_level_id                 UUID,
    allocation_annual                   INTEGER,
    rollover_policy                     fs.membership_level_points_caps_rollover_policy_enum,
    monthly_cap_base                    INTEGER,
    monthly_cap_percent                 NUMERIC(5,2),
    monthly_cap_max                     INTEGER,
    points_beyond_accrual_percent       NUMERIC(5,2),
    carry_forward_max_per_year          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_points_caps_id     UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.membership_level_points_caps_shadow IS 'Shadow Table.';

-- Table: MEMBERSHIP_LEVEL_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.membership_level_shadow (
    membership_series_id                UUID,
    membership_series_code              VARCHAR(40),
    plan_code                           VARCHAR(40),
    membership_level_type_code          VARCHAR(40),
    membership_level_name               VARCHAR(120),
    description                         TEXT,
    status                              fs.membership_level_status_enum,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_level_id                 UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.membership_level_shadow IS 'Shadow Table.';

-- Table: ROLE_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.role_shadow (
    role_name                           VARCHAR(80),
    description                         TEXT,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    is_system                           BOOLEAN,
    is_active                           BOOLEAN,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id                             UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.role_shadow IS 'Shadow Table.';

-- Table: STAFF_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.staff_shadow (
    user_id                             UUID,
    employment_status                   fs.staff_employment_status_enum,
    home_branch_id                      UUID,
    job_title                           VARCHAR(120),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    first_name                          VARCHAR(80),
    last_name                           VARCHAR(80),
    preferred_name                      VARCHAR(80),
    license_number                      VARCHAR(32),
    license_state                       VARCHAR(2),
    license_expires_on                  DATE,
    date_of_birth                       DATE,
    notes                               TEXT,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id                            UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.staff_shadow IS 'Shadow Table.';

-- Table: USER_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.user_shadow (
    user_email                          CITEXT,
    password_hash                       TEXT,
    password_changed_at                 TIMESTAMPTZ,
    failed_attempt_count                INTEGER,
    last_failed_attempt_at              TIMESTAMPTZ,
    lockout_until                       TIMESTAMPTZ,
    mfa_enabled                         BOOLEAN,
    mfa_method_code                     VARCHAR(40),
    mfa_enrolled_at                     TIMESTAMPTZ,
    mfa_secret_encrypted                TEXT,
    default_view_code                   VARCHAR(40),
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    user_handle                         CITEXT,
    pending_email                       CITEXT,
    pending_email_requested_at          TIMESTAMPTZ,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                             UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.user_shadow IS 'Shadow Table.';

-- Table: VEHICLE_FINANCING_LIFECYCLE_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.vehicle_financing_lifecycle_shadow (
    vehicle_id                          UUID,
    finance_type                        fs.vehicle_financing_lifecycle_finance_type_enum,
    finance_term_months                 INTEGER,
    lender_lessor                       VARCHAR(160),
    guarantor                           VARCHAR(160),
    purchase_date                       DATE,
    purchase_price                      INTEGER,
    end_target_date                     DATE,
    end_target_mileage                  INTEGER,
    end_target_value                    INTEGER,
    sale_date                           DATE,
    sale_price                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    end_date_is_committed               BOOLEAN,
    end_commitment_note                 VARCHAR(200),
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_financing_lifecycle_id      UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.vehicle_financing_lifecycle_shadow IS 'Shadow Table.';

-- Table: VEHICLE_PARTNER_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.vehicle_partner_shadow (
    business_name                       VARCHAR(120),
    address_line1                       VARCHAR(200),
    address_line2                       VARCHAR(100),
    city                                VARCHAR(100),
    state                               VARCHAR(2),
    postal_code                         VARCHAR(10),
    partner_tax_id                      VARCHAR(20),
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_partner_id                  UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.vehicle_partner_shadow IS 'Shadow Table.';

-- Table: VEHICLE_REGISTRATION_WARRANTY_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.vehicle_registration_warranty_shadow (
    vehicle_id                          UUID,
    registration_state                  VARCHAR(2),
    temp_license_plate                  VARCHAR(15),
    license_plate                       VARCHAR(15),
    toll_tag                            VARCHAR(30),
    registration_expires_on             DATE,
    inspection_expires_on               DATE,
    warranty_end                        DATE,
    warranty_company                    VARCHAR(120),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_registration_warranty_id    UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.vehicle_registration_warranty_shadow IS 'Shadow Table.';

-- Table: VEHICLE_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.vehicle_shadow (
    vin                                 VARCHAR(17),
    vehicle_make_code                   VARCHAR(40),
    model                               VARCHAR(80),
    trim                                VARCHAR(40),
    vehicle_name                        VARCHAR(160),
    year                                VARCHAR(4),
    exterior_color                      VARCHAR(40),
    exterior_color_short                VARCHAR(40),
    interior_color                      VARCHAR(40),
    paint_code_1                        VARCHAR(40),
    paint_code_2                        VARCHAR(40),
    condition_code                      VARCHAR(30),
    condition_since                     TIMESTAMPTZ,
    home_branch_id                      UUID,
    launch_date                         DATE,
    expected_arrival_date               DATE,
    arrival_date                        DATE,
    notes                               TEXT,
    fleet_stage                         fs.vehicle_fleet_stage_enum,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.vehicle_shadow IS 'Shadow Table.';

-- Table: VEHICLE_TIER_ACCESS_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.vehicle_tier_access_shadow (
    membership_level_id                 UUID,
    vehicle_tier_id                     UUID,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_tier_access_id              UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.vehicle_tier_access_shadow IS 'Shadow Table.';

-- Table: VENDOR_SHADOW (Shadow Table.)
CREATE TABLE IF NOT EXISTS fs.vendor_shadow (
    vendor_name                         VARCHAR(160),
    home_branch_id                      UUID,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    vendor_type_code                    VARCHAR(40),
    vendor_email                        VARCHAR(120),
    vendor_phone                        VARCHAR(20),
    address_line1                       VARCHAR(200),
    address_line2                       VARCHAR(100),
    city                                VARCHAR(100),
    state                               VARCHAR(2),
    postal_code                         VARCHAR(10),
    website_url                         VARCHAR(200),
    vendor_tax_id                       VARCHAR(20),
    i9_verified                         BOOLEAN,
    insurance_certificate_exp           DATE,
    w9_on_file                          BOOLEAN,
    notes                               TEXT,
    version_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id                           UUID,
    valid_from                          TIMESTAMPTZ,
    valid_to                            TIMESTAMPTZ,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ,
    change_reason                       TEXT
);
COMMENT ON TABLE fs.vendor_shadow IS 'Shadow Table.';

-- -----------------------------------------------------------------------------
-- DOMAIN: STAFF MANAGEMENT
-- -----------------------------------------------------------------------------

-- Table: STAFF (Profile linked to users who are staff members. Stores personal and job details, )
CREATE TABLE IF NOT EXISTS fs.staff (
    staff_id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                             UUID,
    employment_status                   fs.staff_employment_status_enum,
    home_branch_id                      UUID,
    job_title                           VARCHAR(120),
    first_name                          VARCHAR(80),
    last_name                           VARCHAR(80),
    preferred_name                      VARCHAR(80),
    license_number                      VARCHAR(32),
    license_state                       VARCHAR(2),
    license_expires_on                  DATE,
    date_of_birth                       DATE,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.staff IS 'Profile linked to users who are staff members. Stores personal and job details, and the employment standing that governs staff-side access.';

-- Table: STAFF_EMAIL (This table Stores one or more email addresses associated with each staff member.)
CREATE TABLE IF NOT EXISTS fs.staff_email (
    staff_email_id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id                            UUID,
    staff_email                         VARCHAR(120),
    staff_email_type                    fs.staff_email_staff_email_type_enum,
    staff_email_note                    VARCHAR(200),
    staff_email_active                  BOOLEAN,
    is_primary                          BOOLEAN,
    is_club_issued                      BOOLEAN,
    is_directory_visible                BOOLEAN,
    effective_from                      TIMESTAMPTZ,
    effective_to                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.staff_email IS 'This table Stores one or more email addresses associated with each staff member.';

-- Table: STAFF_PHONE (This table Stores one or more phone numbers associated with each staff member.)
CREATE TABLE IF NOT EXISTS fs.staff_phone (
    staff_phone_id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id                            UUID,
    staff_phone                         VARCHAR(20),
    staff_phone_type                    fs.staff_phone_staff_phone_type_enum,
    staff_phone_note                    VARCHAR(200),
    staff_phone_active                  BOOLEAN,
    is_primary                          BOOLEAN,
    is_club_issued                      BOOLEAN,
    is_directory_visible                BOOLEAN,
    effective_from                      TIMESTAMPTZ,
    effective_to                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.staff_phone IS 'This table Stores one or more phone numbers associated with each staff member.';

-- -----------------------------------------------------------------------------
-- DOMAIN: SYSTEM REFERENCE
-- -----------------------------------------------------------------------------

-- Table: DAY_OF_MONTH_SELECT (Shared calendar list of days of the month for scheduling pickers. 1st through 28)
CREATE TABLE IF NOT EXISTS fs.day_of_month_select (
    day_of_month_code                   VARCHAR(8) PRIMARY KEY,
    day_of_month_label                  VARCHAR(20) UNIQUE,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.day_of_month_select IS 'Shared calendar list of days of the month for scheduling pickers. 1st through 28th plus Last Day, so a chosen day always exists in every month.';

-- Table: DAY_OF_WEEK_SELECT (Shared calendar list of the days of the week for scheduling pickers.)
CREATE TABLE IF NOT EXISTS fs.day_of_week_select (
    day_of_week_code                    VARCHAR(12) PRIMARY KEY,
    day_of_week_label                   VARCHAR(20) UNIQUE,
    iso_number                          SMALLINT UNIQUE,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.day_of_week_select IS 'Shared calendar list of the days of the week for scheduling pickers.';

-- Table: HOLIDAY_DEFINITION (The club’s recurring holidays, defined once and generating a restricted date for)
CREATE TABLE IF NOT EXISTS fs.holiday_definition (
    holiday_definition_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    holiday_name                        VARCHAR(120),
    branch_id                           UUID,
    recurrence_type                     fs.holiday_definition_recurrence_type_enum,
    fixed_month                         SMALLINT,
    fixed_day                           SMALLINT,
    nth_occurrence                      SMALLINT,
    weekday                             SMALLINT,
    span_days                           SMALLINT,
    restricted_date_type_code           VARCHAR(30),
    generate_years_ahead                SMALLINT,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.holiday_definition IS 'The club’s recurring holidays, defined once and generating a restricted date for each year. Definitions are not read when a reservation is booked; the generated restricted dates are.';

-- Table: MONTH_SELECT (Shared calendar list of the months of the year for scheduling pickers.)
CREATE TABLE IF NOT EXISTS fs.month_select (
    month_code                          VARCHAR(12) PRIMARY KEY,
    month_label                         VARCHAR(20) UNIQUE,
    month_number                        SMALLINT UNIQUE,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.month_select IS 'Shared calendar list of the months of the year for scheduling pickers.';

-- Table: PLATFORM_SETTING (A club-set value the software reads rather than hard-codes: a number, a limit, a)
CREATE TABLE IF NOT EXISTS fs.platform_setting (
    platform_setting_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    setting_code                        VARCHAR(60) UNIQUE,
    setting_name                        VARCHAR(120),
    setting_value                       VARCHAR(255),
    description                         TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.platform_setting IS 'A club-set value the software reads rather than hard-codes: a number, a limit, a switch. Each setting is a row, so a new one needs no schema change. The seeded settings and their shipping values are listed in the workbook.';

-- Table: RESTRICTED_DATE_TYPE_SELECT (The kinds of restricted date and how each behaves.)
CREATE TABLE IF NOT EXISTS fs.restricted_date_type_select (
    restricted_date_type_code           VARCHAR(30) PRIMARY KEY,
    type_name                           VARCHAR(80),
    description                         TEXT,
    blocks_outright                     BOOLEAN,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.restricted_date_type_select IS 'The kinds of restricted date and how each behaves.';

-- Table: STATE_SELECT (Provides standardized list of states and provinces.)
CREATE TABLE IF NOT EXISTS fs.state_select (
    state_code                          VARCHAR(2) PRIMARY KEY,
    state_name                          VARCHAR(80) UNIQUE,
    country_code                        VARCHAR(2),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.state_select IS 'Provides standardized list of states and provinces.';

-- Table: TARGET_TABLE_SELECT (Registry of tables a polymorphic reference may point at, with flags saying wheth)
CREATE TABLE IF NOT EXISTS fs.target_table_select (
    target_table_code                   VARCHAR(60) PRIMARY KEY,
    display_name                        VARCHAR(120),
    allows_document_link                BOOLEAN,
    allows_task_link                    BOOLEAN,
    allows_form_target                  BOOLEAN,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.target_table_select IS 'Registry of tables a polymorphic reference may point at, with flags saying whether each may take a document link, a task link, or a built form. Seeded with the fourteen linkable tables.';

-- Table: TIMEZONE_SELECT (The time zones a branch may be set to.)
CREATE TABLE IF NOT EXISTS fs.timezone_select (
    timezone_code                       VARCHAR(64) PRIMARY KEY,
    timezone_label                      VARCHAR(120) UNIQUE,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.timezone_select IS 'The time zones a branch may be set to.';

-- -----------------------------------------------------------------------------
-- DOMAIN: TASK MANAGEMENT
-- -----------------------------------------------------------------------------

-- Table: TASK (Stores each task assigned to staff or to a vendor, including title, description,)
CREATE TABLE IF NOT EXISTS fs.task (
    task_id                             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_title                          VARCHAR(200),
    description                         TEXT,
    task_status_code                    VARCHAR(40),
    task_priority_code                  VARCHAR(40),
    task_type_code                      VARCHAR(40),
    assigned_to_user_id                 UUID,
    due_date                            TIMESTAMPTZ,
    started_at                          TIMESTAMPTZ,
    viewed_at                           TIMESTAMPTZ,
    completed_at                        TIMESTAMPTZ,
    cancelled_at                        TIMESTAMPTZ,
    escalation_level                    INTEGER,
    escalated_at                        TIMESTAMPTZ,
    due_date_original                   TIMESTAMPTZ,
    due_date_change_count               INTEGER,
    cancelled_reason                    TEXT,
    cancelled_by_user_id                UUID,
    is_active                           BOOLEAN,
    assigned_at                         TIMESTAMPTZ,
    assigned_by_user_id                 UUID,
    verified_flag                       BOOLEAN,
    verified_by_user_id                 UUID,
    verified_at                         TIMESTAMPTZ,
    verification_notes                  TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    snooze_until                        DATE,
    snooze_reason                       TEXT
);
COMMENT ON TABLE fs.task IS 'Stores each task assigned to staff or to a vendor, including title, description, status, and due dates.';

-- Table: TASK_ASSIGNMENT (Links a task to multiple users if more than one is assigned and identifies the p)
CREATE TABLE IF NOT EXISTS fs.task_assignment (
    task_assignment_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id                             UUID,
    user_id                             UUID,
    role_id                             UUID,
    branch_id                           UUID,
    is_primary                          BOOLEAN,
    assigned_at                         TIMESTAMPTZ,
    assigned_by_user_id                 UUID,
    unassigned_at                       TIMESTAMPTZ,
    assignment_note                     TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_assignment IS 'Links a task to multiple users if more than one is assigned and identifies the primary assignee.';

-- Table: TASK_AUDIT_LOG (Records all important actions taken on a task.)
CREATE TABLE IF NOT EXISTS fs.task_audit_log (
    task_audit_id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id                             UUID,
    actor_user_id                       UUID,
    action                              fs.task_audit_log_action_enum,
    notes                               TEXT,
    acted_at                            TIMESTAMPTZ
);
COMMENT ON TABLE fs.task_audit_log IS 'Records all important actions taken on a task.';

-- Table: TASK_CHECKLIST_ITEM (Breaks down a task into smaller checklist items.)
CREATE TABLE IF NOT EXISTS fs.task_checklist_item (
    task_checklist_item_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id                             UUID,
    description                         VARCHAR(200),
    is_completed                        BOOLEAN,
    assigned_to_user_id                 UUID,
    sort_order                          SMALLINT,
    depends_on_item_id                  UUID,
    completed_at                        TIMESTAMPTZ,
    completed_by_user_id                UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_checklist_item IS 'Breaks down a task into smaller checklist items.';

-- Table: TASK_COMMENT (Comments on a task. Each comment is marked internal or shared, so staff can talk)
CREATE TABLE IF NOT EXISTS fs.task_comment (
    task_comment_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id                             UUID,
    user_id                             UUID,
    comment                             TEXT,
    is_internal                         BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE fs.task_comment IS 'Comments on a task. Each comment is marked internal or shared, so staff can talk to each other without an assigned vendor reading it.';

-- Table: TASK_DEPENDENCY (Defines dependencies between tasks.)
CREATE TABLE IF NOT EXISTS fs.task_dependency (
    task_dependency_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id                             UUID,
    depends_on_task_id                  UUID,
    assigned_at                         TIMESTAMPTZ,
    assigned_by_user_id                 UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_dependency IS 'Defines dependencies between tasks.';

-- Table: TASK_ESCALATION_LOG (Records each time an overdue task moves up an escalation path.)
CREATE TABLE IF NOT EXISTS fs.task_escalation_log (
    task_escalation_log_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id                             UUID,
    task_escalation_path_level_id       UUID,
    role_id                             UUID,
    escalated_to_user_id                UUID,
    escalated_at                        TIMESTAMPTZ,
    hours_overdue                       INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_escalation_log IS 'Records each time an overdue task moves up an escalation path.';

-- Table: TASK_ESCALATION_PATH (Defines the routes overdue work follows, each an ordered list of roles.)
CREATE TABLE IF NOT EXISTS fs.task_escalation_path (
    task_escalation_path_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_escalation_path_code           VARCHAR(40) UNIQUE,
    task_escalation_path_name           VARCHAR(120),
    description                         TEXT,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_escalation_path IS 'Defines the routes overdue work follows, each an ordered list of roles.';

-- Table: TASK_ESCALATION_PATH_LEVEL (Defines one step on an escalation path, giving its position in the order and the)
CREATE TABLE IF NOT EXISTS fs.task_escalation_path_level (
    task_escalation_path_level_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_escalation_path_id             UUID,
    level_number                        INTEGER,
    role_id                             UUID,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_escalation_path_level IS 'Defines one step on an escalation path, giving its position in the order and the role that sits there.';

-- Table: TASK_LINK (Links a task to other entities such as Vehicle, Reservation, Member, or Event.)
CREATE TABLE IF NOT EXISTS fs.task_link (
    task_link_id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id                             UUID,
    target_table                        VARCHAR(60),
    target_id                           UUID,
    is_primary                          BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_link IS 'Links a task to other entities such as Vehicle, Reservation, Member, or Event.';

-- Table: TASK_PRIORITY (Lists priority levels used to rank tasks.)
CREATE TABLE IF NOT EXISTS fs.task_priority (
    task_priority_code                  VARCHAR(40) PRIMARY KEY,
    task_priority_name                  VARCHAR(40) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_priority IS 'Lists priority levels used to rank tasks.';

-- Table: TASK_STATUS (Defines allowed states for tasks.)
CREATE TABLE IF NOT EXISTS fs.task_status (
    task_status_code                    VARCHAR(40) PRIMARY KEY,
    task_status_name                    VARCHAR(40) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_status IS 'Defines allowed states for tasks.';

-- Table: TASK_TAG (Links tags to specific tasks.)
CREATE TABLE IF NOT EXISTS fs.task_tag (
    task_tag_id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id                             UUID,
    tag                                 VARCHAR(60),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_tag IS 'Links tags to specific tasks.';

-- Table: TASK_TEMPLATE (Stores reusable templates for recurring or automated tasks. Each template define)
CREATE TABLE IF NOT EXISTS fs.task_template (
    task_template_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_name                       VARCHAR(120) UNIQUE,
    description                         TEXT,
    default_task_type_code              VARCHAR(40),
    default_priority_code               VARCHAR(40),
    default_due_offset_minutes          INTEGER,
    default_assignee_user_id            UUID,
    checklist_json                      JSONB,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_template IS 'Stores reusable templates for recurring or automated tasks. Each template defines default title, description, priority, and checklist items.';

-- Table: TASK_TEMPLATE_STEP (One step of a multi-step template - the task it creates when the template is sta)
CREATE TABLE IF NOT EXISTS fs.task_template_step (
    task_template_step_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_template_id                    UUID,
    step_number                         INTEGER,
    step_name                           VARCHAR(120),
    description                         TEXT,
    default_task_type_code              VARCHAR(40),
    default_priority_code               VARCHAR(40),
    default_due_offset_minutes          INTEGER,
    default_assignee_user_id            UUID,
    checklist_json                      JSONB,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_template_step IS 'One step of a multi-step template - the task it creates when the template is stamped.';

-- Table: TASK_TEMPLATE_STEP_DEPENDENCY (A dependency between two steps of the same template; one row per predecessor.)
CREATE TABLE IF NOT EXISTS fs.task_template_step_dependency (
    task_template_step_dependency_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_template_step_id               UUID,
    depends_on_step_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_template_step_dependency IS 'A dependency between two steps of the same template; one row per predecessor.';

-- Table: TASK_TYPE_SELECT (Defines standard task categories (e.g., Cleaning, Maintenance, Event, Admin) for)
CREATE TABLE IF NOT EXISTS fs.task_type_select (
    task_type_code                      VARCHAR(40) PRIMARY KEY,
    task_type_name                      VARCHAR(120),
    description                         TEXT,
    requires_verification               BOOLEAN,
    task_escalation_path_id             UUID,
    due_basis                           VARCHAR(40),
    due_offset_minutes                  INTEGER,
    due_time_of_day                     TIME,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.task_type_select IS 'Defines standard task categories (e.g., Cleaning, Maintenance, Event, Admin) for organization and filtering.';

-- -----------------------------------------------------------------------------
-- DOMAIN: USERS, ROLES & PERMISSIONS
-- -----------------------------------------------------------------------------

-- Table: ACCESS_EVENT_TYPE_SELECT (Kinds of event recorded in the access log. Seeded with Successful sign-in, Faile)
CREATE TABLE IF NOT EXISTS fs.access_event_type_select (
    access_event_type_code              VARCHAR(40) PRIMARY KEY,
    access_event_type_name              VARCHAR(80),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.access_event_type_select IS 'Kinds of event recorded in the access log. Seeded with Successful sign-in, Failed sign-in, Blocked attempt, and Export.';

-- Table: ACCESS_LOG (Security events: successful sign-ins, failed sign-ins, blocked attempts, and exp)
CREATE TABLE IF NOT EXISTS fs.access_log (
    access_log_id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    access_event_type_code              VARCHAR(40),
    occurred_at                         TIMESTAMPTZ,
    user_id                             UUID,
    attempted_identifier                VARCHAR(255),
    source_ip                           VARCHAR(45),
    user_agent                          VARCHAR(400),
    branch_id                           UUID,
    permission_code                     VARCHAR(120),
    outcome_detail                      VARCHAR(200),
    attempt_count                       INTEGER,
    export_entity_type                  VARCHAR(60),
    export_record_count                 INTEGER,
    export_filter_summary               VARCHAR(400),
    export_format_code                  VARCHAR(40),
    export_destination_code             VARCHAR(40),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE fs.access_log IS 'Security events: successful sign-ins, failed sign-ins, blocked attempts, and exports. Append-only, so rows are never updated and the table carries no shadow.';

-- Table: MFA_METHOD_SELECT (Second-step methods available at sign-in. Seeded with Authenticator app and Text)
CREATE TABLE IF NOT EXISTS fs.mfa_method_select (
    mfa_method_code                     VARCHAR(40) PRIMARY KEY,
    mfa_method_name                     VARCHAR(80),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.mfa_method_select IS 'Second-step methods available at sign-in. Seeded with Authenticator app and Text message.';

-- Table: PERMISSION (Lists specific actions that can be performed in the system.)
CREATE TABLE IF NOT EXISTS fs.permission (
    permission_id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    permission_code                     VARCHAR(120) UNIQUE,
    permission_name                     VARCHAR(160),
    description                         TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.permission IS 'Lists specific actions that can be performed in the system.';

-- Table: ROLE (Roles group users by responsibility, like job titles. Standard roles ship with t)
CREATE TABLE IF NOT EXISTS fs.role (
    role_id                             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_name                           VARCHAR(80) UNIQUE,
    description                         TEXT,
    is_system                           BOOLEAN,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.role IS 'Roles group users by responsibility, like job titles. Standard roles ship with the platform; the club may add custom roles.';

-- Table: ROLE_PERMISSION (Links roles to their permissions.)
CREATE TABLE IF NOT EXISTS fs.role_permission (
    role_id                             UUID,
    permission_id                       UUID,
    granted_at                          TIMESTAMPTZ,
    granted_by_user_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    revoked_at                          TIMESTAMPTZ,
    revoked_by_user_id                  UUID,
    CONSTRAINT pk_role_permission PRIMARY KEY (role_id, permission_id)
);
COMMENT ON TABLE fs.role_permission IS 'Links roles to their permissions.';

-- Table: USER (Users are the individuals who log in to the system. Holds the sign-in credential)
CREATE TABLE IF NOT EXISTS fs."user" (
    user_id                             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_handle                         CITEXT UNIQUE,
    user_email                          CITEXT UNIQUE,
    pending_email                       CITEXT,
    pending_email_requested_at          TIMESTAMPTZ,
    password_hash                       TEXT,
    password_changed_at                 TIMESTAMPTZ,
    failed_attempt_count                INTEGER,
    last_failed_attempt_at              TIMESTAMPTZ,
    lockout_until                       TIMESTAMPTZ,
    mfa_enabled                         BOOLEAN,
    mfa_method_code                     VARCHAR(40),
    mfa_enrolled_at                     TIMESTAMPTZ,
    mfa_secret_encrypted                TEXT,
    default_view_code                   VARCHAR(40),
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs."user" IS 'Users are the individuals who log in to the system. Holds the sign-in credentials, the authentication state, and which area of the app opens first.';

-- Table: USER_DEVICE (An installed mobile application belonging to a user - one row per device per use)
CREATE TABLE IF NOT EXISTS fs.user_device (
    user_device_id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                             UUID,
    platform                            fs.user_device_platform_enum,
    device_label                        VARCHAR(120),
    device_model                        VARCHAR(80),
    os_version                          VARCHAR(40),
    app_version                         VARCHAR(40),
    push_token                          VARCHAR(255),
    push_token_updated_at               TIMESTAMPTZ,
    permission_location                 fs.user_device_permission_location_enum,
    permission_push                     fs.user_device_permission_push_enum,
    permission_calendar                 fs.user_device_permission_calendar_enum,
    permission_camera                   fs.user_device_permission_camera_enum,
    wallet_pass_serial                  VARCHAR(120),
    last_seen_at                        TIMESTAMPTZ,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.user_device IS 'An installed mobile application belonging to a user - one row per device per user, so somebody with a phone and a tablet has two.';

-- Table: USER_MFA_RECOVERY_CODE (One-time codes that let a person back in when their second-step device is unavai)
CREATE TABLE IF NOT EXISTS fs.user_mfa_recovery_code (
    user_mfa_recovery_code_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                             UUID,
    code_hash                           TEXT,
    used_at                             TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.user_mfa_recovery_code IS 'One-time codes that let a person back in when their second-step device is unavailable. Stored hashed and single-use.';

-- Table: USER_ROLE (Connects users to their roles.)
CREATE TABLE IF NOT EXISTS fs.user_role (
    user_id                             UUID,
    role_id                             UUID,
    is_primary                          BOOLEAN,
    granted_at                          TIMESTAMPTZ,
    granted_by_user_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    revoked_at                          TIMESTAMPTZ,
    revoked_by_user_id                  UUID,
    CONSTRAINT pk_user_role PRIMARY KEY (user_id, role_id)
);
COMMENT ON TABLE fs.user_role IS 'Connects users to their roles.';

-- Table: USER_TRUSTED_DEVICE (Devices a person has chosen to remember, so the second step is not asked for eve)
CREATE TABLE IF NOT EXISTS fs.user_trusted_device (
    user_trusted_device_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                             UUID,
    device_token_hash                   TEXT,
    device_label                        VARCHAR(120),
    first_trusted_at                    TIMESTAMPTZ,
    last_seen_at                        TIMESTAMPTZ,
    expires_at                          TIMESTAMPTZ,
    absolute_expires_at                 TIMESTAMPTZ,
    revoked_at                          TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.user_trusted_device IS 'Devices a person has chosen to remember, so the second step is not asked for every time. Trust rolls forward 30 days from each sign-in and ends absolutely at six months.';

-- Table: USER_VIEW_SELECT (Areas of the application a person can land in after signing in. Seeded with Staf)
CREATE TABLE IF NOT EXISTS fs.user_view_select (
    user_view_code                      VARCHAR(40) PRIMARY KEY,
    user_view_name                      VARCHAR(80),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.user_view_select IS 'Areas of the application a person can land in after signing in. Seeded with Staff, Member, and Vendor.';

-- -----------------------------------------------------------------------------
-- DOMAIN: VEHICLE INSPECTIONS
-- -----------------------------------------------------------------------------

-- Table: VEHICLE_INSPECTION (Captures the history of all vehicle inspections with photos.)
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection (
    inspection_id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_event_id                    UUID,
    vehicle_id                          UUID,
    inspection_type                     VARCHAR(20),
    vehicle_odometer_id                 UUID,
    photos_json                         JSONB,
    notes                               TEXT,
    source_type_code                    VARCHAR(40),
    source_id                           UUID,
    inspector_user_id                   UUID,
    inspected_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection IS 'Captures the history of all vehicle inspections with photos.';

-- Table: VEHICLE_INSPECTION_CHECKIN (Captures full post-trip inspection results and condition details for vehicles re)
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection_checkin (
    inspection_checkin_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_event_id                    UUID,
    vehicle_id                          UUID,
    reservation_id                      UUID,
    bumper_front_nose_ok                BOOLEAN,
    bumper_rear_diffuser_ok             BOOLEAN,
    wheels_tires_rf_ok                  BOOLEAN,
    wheels_tires_rr_ok                  BOOLEAN,
    wheels_tires_lf_ok                  BOOLEAN,
    wheels_tires_lr_ok                  BOOLEAN,
    windshield_ok                       BOOLEAN,
    windows_ok                          BOOLEAN,
    key_fob_ok                          BOOLEAN,
    dashboard_no_warning_lights_ok      BOOLEAN,
    interior_seats_ok                   BOOLEAN,
    interior_console_ok                 BOOLEAN,
    interior_floorboards_ok             BOOLEAN,
    dash_controls_ok                    BOOLEAN,
    empty_trunk_ok                      BOOLEAN,
    empty_console_ok                    BOOLEAN,
    empty_visor_ok                      BOOLEAN,
    empty_pockets_ok                    BOOLEAN,
    vehicle_odometer_id                 UUID,
    fuel_level_percent                  SMALLINT,
    inspection_notes                    TEXT,
    inspector_user_id                   UUID,
    inspected_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection_checkin IS 'Captures full post-trip inspection results and condition details for vehicles returned by members.';

-- Table: VEHICLE_INSPECTION_CHECKOUT (Captures full pre-trip inspection results and cleanliness verification before ve)
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection_checkout (
    inspection_checkout_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_event_id                    UUID,
    vehicle_id                          UUID,
    reservation_id                      UUID,
    exterior_clean_wheels_ok            BOOLEAN,
    exterior_clean_paint_ok             BOOLEAN,
    exterior_clean_windows_ok           BOOLEAN,
    interior_clean_doors_ok             BOOLEAN,
    interior_clean_vacuumed_ok          BOOLEAN,
    interior_clean_console_ok           BOOLEAN,
    dashboard_no_warning_lights_ok      BOOLEAN,
    check_valid_registration_ok         BOOLEAN,
    check_key_fob_ok                    BOOLEAN,
    final_reset_trip_odometer_ok        BOOLEAN,
    final_set_lights_auto_ok            BOOLEAN,
    final_set_radio_off_ok              BOOLEAN,
    final_seat_position_ok              BOOLEAN,
    vehicle_odometer_id                 UUID,
    fuel_level_percent                  SMALLINT,
    inspection_notes                    TEXT,
    inspector_user_id                   UUID,
    inspected_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection_checkout IS 'Captures full pre-trip inspection results and cleanliness verification before vehicle handoff to members.';

-- Table: VEHICLE_INSPECTION_CHECKUP (Semiannual up-close inspection of condition, wear, and finish, paired with enhan)
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection_checkup (
    inspection_checkup_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inspection_id                       UUID,
    vehicle_id                          UUID,
    exterior_paint_finish_ok            BOOLEAN,
    exterior_trim_ok                    BOOLEAN,
    windshield_ok                       BOOLEAN,
    windows_ok                          BOOLEAN,
    dashboard_no_warning_lights_ok      BOOLEAN,
    interior_seats_ok                   BOOLEAN,
    interior_carpets_ok                 BOOLEAN,
    interior_trim_ok                    BOOLEAN,
    wheels_tires_rf_ok                  BOOLEAN,
    wheels_tires_rr_ok                  BOOLEAN,
    wheels_tires_lf_ok                  BOOLEAN,
    wheels_tires_lr_ok                  BOOLEAN,
    driver_front_tread_depth            fs.vehicle_inspection_checkup_driver_front_tread_depth_enum,
    passenger_front_tread_depth         fs.vehicle_inspection_checkup_passenger_front_tread_depth_enum,
    driver_rear_tread_depth             fs.vehicle_inspection_checkup_driver_rear_tread_depth_enum,
    passenger_rear_tread_depth          fs.vehicle_inspection_checkup_passenger_rear_tread_depth_enum,
    brake_condition_ok                  BOOLEAN,
    brake_notes                         TEXT,
    polish_completed                    BOOLEAN,
    paint_correction_completed          BOOLEAN,
    carpet_shampoo_completed            BOOLEAN,
    interior_deep_clean_completed       BOOLEAN,
    vehicle_odometer_id                 UUID,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection_checkup IS 'Semiannual up-close inspection of condition, wear, and finish, paired with enhanced detailing.';

-- Table: VEHICLE_INSPECTION_DAMAGE (Stores damage reports logged by staff or members, including textual description )
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection_damage (
    inspection_damage_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_event_id                    UUID,
    vehicle_id                          UUID,
    reservation_id                      UUID,
    damage_description                  TEXT,
    severity                            fs.vehicle_inspection_damage_severity_enum,
    notes                               TEXT,
    inspection_issue_id                 UUID,
    source_table                        VARCHAR(60),
    source_id                           UUID,
    inspector_user_id                   UUID,
    inspected_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection_damage IS 'Stores damage reports logged by staff or members, including textual description and photo attachments.';

-- Table: VEHICLE_INSPECTION_FUEL (Logs fuel transactions optionally linked to reservations.)
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection_fuel (
    inspection_fuel_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_event_id                    UUID,
    vehicle_id                          UUID,
    reservation_id                      UUID,
    odometer_log_id                     UUID,
    fueled_at                           TIMESTAMPTZ,
    gallons                             NUMERIC(6,2),
    gallon_price                        NUMERIC(12,2),
    total_cost                          NUMERIC(12,2),
    notes                               TEXT,
    billed_member_id                    UUID,
    billed_amount                       NUMERIC(12,2),
    inspector_user_id                   UUID,
    inspected_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection_fuel IS 'Logs fuel transactions optionally linked to reservations.';

-- Table: VEHICLE_INSPECTION_INITIAL (Condition and contents inspection for a vehicle arriving into the club's care at)
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection_initial (
    vehicle_inspection_initial_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_event_id                    UUID,
    vehicle_id                          UUID,
    inspection_type_code                VARCHAR(20),
    vehicle_odometer_id                 UUID,
    vin_verified_flag                   BOOLEAN,
    registration_valid_flag             BOOLEAN,
    inspection_expiration_date          DATE,
    registration_expiration_date        DATE,
    warranty_expiration_date            DATE,
    keys_count                          SMALLINT,
    aftermarket_parts_flag              BOOLEAN,
    car_cover_included_flag             BOOLEAN,
    owner_manual_included_flag          BOOLEAN,
    trickle_charger_included_flag       BOOLEAN,
    exterior_damage_found_flag          BOOLEAN,
    interior_damage_found_flag          BOOLEAN,
    mechanical_issue_flag               BOOLEAN,
    transport_damage_flag               BOOLEAN,
    inspection_notes                    TEXT,
    inspector_user_id                   UUID,
    inspected_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection_initial IS 'Condition and contents inspection for a vehicle arriving into the club''s care at intake.';

-- Table: VEHICLE_INSPECTION_ISSUE (Stores individual issues found during inspections, linking failed checklist item)
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection_issue (
    inspection_issue_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inspection_id                       UUID,
    vehicle_id                          UUID,
    field_code                          VARCHAR(40),
    description                         TEXT,
    attachment_id                       UUID,
    task_id                             UUID,
    severity                            fs.vehicle_inspection_issue_severity_enum,
    resolved_flag                       BOOLEAN,
    resolved_at                         TIMESTAMPTZ,
    resolved_by_user_id                 UUID,
    source_table                        VARCHAR(60),
    source_id                           UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection_issue IS 'Stores individual issues found during inspections, linking failed checklist items to photos, tasks, and resolution tracking.';

-- Table: VEHICLE_INSPECTION_ITEM_LEFT (Logs items left in vehicles after member usage, including description and option)
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection_item_left (
    inspection_item_left_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_event_id                    UUID,
    vehicle_id                          UUID,
    reservation_id                      UUID,
    item_description                    TEXT,
    notes                               TEXT,
    inspection_issue_id                 UUID,
    source_table                        VARCHAR(60),
    source_id                           UUID,
    inspector_user_id                   UUID,
    inspected_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection_item_left IS 'Logs items left in vehicles after member usage, including description and optional photo attachment.';

-- Table: VEHICLE_INSPECTION_TRANSFER (Condition inspection taken at both ends of a branch transfer, so the destination)
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection_transfer (
    vehicle_inspection_transfer_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_event_id                    UUID,
    vehicle_id                          UUID,
    inspection_type_code                VARCHAR(20),
    vehicle_trip_id                     UUID,
    origin_branch_id                    UUID,
    destination_branch_id               UUID,
    vehicle_odometer_id                 UUID,
    fuel_level_code                     VARCHAR(10),
    keys_count                          SMALLINT,
    car_cover_included_flag             BOOLEAN,
    owner_manual_included_flag          BOOLEAN,
    trickle_charger_included_flag       BOOLEAN,
    exterior_damage_found_flag          BOOLEAN,
    interior_damage_found_flag          BOOLEAN,
    wheels_tires_ok_flag                BOOLEAN,
    warning_lights_flag                 BOOLEAN,
    mechanical_issue_flag               BOOLEAN,
    transport_damage_flag               BOOLEAN,
    inspection_notes                    TEXT,
    inspector_user_id                   UUID,
    inspected_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection_transfer IS 'Condition inspection taken at both ends of a branch transfer, so the destination can compare against the origin.';

-- Table: VEHICLE_INSPECTION_TYPE (Lookup of inspection types. Values live in the Enum Values and Lookup Seeds work)
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection_type (
    inspection_type_code                VARCHAR(20) PRIMARY KEY,
    label                               VARCHAR(50),
    description                         TEXT,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection_type IS 'Lookup of inspection types. Values live in the Enum Values and Lookup Seeds workbook.';

-- Table: VEHICLE_INSPECTION_WHEELS_TIRES (Stores inspection information about wheels and tires.)
CREATE TABLE IF NOT EXISTS fs.vehicle_inspection_wheels_tires (
    vehicle_inspection_wheels_tires_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_event_id                    UUID,
    vehicle_id                          UUID,
    inspection_date                     TIMESTAMPTZ,
    odometer_log_id                     UUID,
    driver_front_wheel_condition_ok     BOOLEAN,
    driver_front_tire_condition_ok      BOOLEAN,
    driver_front_tread_depth            fs.vehicle_inspection_wheels_tires_driver_front_tread_depth_enum,
    passenger_front_wheel_condition_ok  BOOLEAN,
    passenger_front_tire_condition_ok   BOOLEAN,
    passenger_front_tread_depth         fs.vehicle_inspection_wheels_tires_passenger_front_tread_depth_enum,
    driver_rear_wheel_condition_ok      BOOLEAN,
    driver_rear_tire_condition_ok       BOOLEAN,
    driver_rear_tread_depth             fs.vehicle_inspection_wheels_tires_driver_rear_tread_depth_enum,
    passenger_rear_wheel_condition_ok   BOOLEAN,
    passenger_rear_tire_condition_ok    BOOLEAN,
    passenger_rear_tread_depth          fs.vehicle_inspection_wheels_tires_passenger_rear_tread_depth_enum,
    notes                               TEXT,
    inspector_user_id                   UUID,
    inspected_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_inspection_wheels_tires IS 'Stores inspection information about wheels and tires.';

-- -----------------------------------------------------------------------------
-- DOMAIN: VEHICLE OWNER PROGRAM
-- -----------------------------------------------------------------------------

-- Table: VEHICLE_PARTNER (Stores contact info for Vehicle Lender or VOP Owner.)
CREATE TABLE IF NOT EXISTS fs.vehicle_partner (
    vehicle_partner_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_name                       VARCHAR(120),
    address_line1                       VARCHAR(200),
    address_line2                       VARCHAR(100),
    city                                VARCHAR(100),
    state                               VARCHAR(2),
    postal_code                         VARCHAR(10),
    partner_tax_id                      VARCHAR(20),
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_partner IS 'Stores contact info for Vehicle Lender or VOP Owner.';

-- Table: VEHICLE_PARTNER_CONTACT (Stores contact information for one or more individuals per vehicle partner.)
CREATE TABLE IF NOT EXISTS fs.vehicle_partner_contact (
    vehicle_partner_contact_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_partner_id                  UUID,
    contact_name                        VARCHAR(120),
    preferred_name                      VARCHAR(80),
    contact_role                        VARCHAR(80),
    contact_phone                       VARCHAR(20),
    contact_phone_type                  fs.vehicle_partner_contact_contact_phone_type_enum,
    contact_email                       VARCHAR(120),
    is_primary                          BOOLEAN,
    contact_active                      BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_partner_contact IS 'Stores contact information for one or more individuals per vehicle partner.';

-- Table: VOP_GUARANTEE_GROUP (A named set of plans belonging to one partner whose minimum guarantees are settl)
CREATE TABLE IF NOT EXISTS fs.vop_guarantee_group (
    vop_guarantee_group_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_partner_id                  UUID,
    group_name                          VARCHAR(120) UNIQUE,
    effective_from                      DATE,
    effective_to                        DATE,
    is_active                           BOOLEAN,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vop_guarantee_group IS 'A named set of plans belonging to one partner whose minimum guarantees are settled together rather than car by car. Each plan keeps its own minimum; the group changes only how they are tested.';

-- Table: VOP_GUARANTEE_GROUP_PLAN (Which plans are in a guarantee group, and when. Membership is dated rather than )
CREATE TABLE IF NOT EXISTS fs.vop_guarantee_group_plan (
    vop_guarantee_group_plan_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vop_guarantee_group_id              UUID,
    vop_plan_id                         UUID,
    effective_from                      DATE,
    effective_to                        DATE,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vop_guarantee_group_plan IS 'Which plans are in a guarantee group, and when. Membership is dated rather than edited, so a car joining or leaving is recorded.';

-- Table: VOP_PAYOUT_LOG (Append-only ledger capturing every VOP-related payout event – mileage credits, d)
CREATE TABLE IF NOT EXISTS fs.vop_payout_log (
    vop_payout_log_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    vop_plan_id                         UUID,
    vehicle_partner_id                  UUID,
    vehicle_reservation_id              UUID,
    vehicle_trip_id                     UUID,
    source_table                        VARCHAR(40),
    source_record_id                    UUID,
    entry_type                          fs.vop_payout_log_entry_type_enum,
    entry_direction                     fs.vop_payout_log_entry_direction_enum,
    entry_value                         NUMERIC(12,2),
    reason_code                         VARCHAR(40),
    description                         TEXT,
    payout_period_id                    UUID,
    processed_flag                      BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    entry_date                          DATE
);
COMMENT ON TABLE fs.vop_payout_log IS 'Append-only ledger capturing every VOP-related payout event – mileage credits, day-based deductions, service charges, goodwill, and manual adjustments.';

-- Table: VOP_PAYOUT_PERIOD (Defines payout periods and their status. An entry belongs to the period containi)
CREATE TABLE IF NOT EXISTS fs.vop_payout_period (
    payout_period_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_start_date                   DATE,
    period_end_date                     DATE,
    status                              fs.vop_payout_period_status_enum,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vop_payout_period IS 'Defines payout periods and their status. An entry belongs to the period containing the trip’s end date, the same rule member statements use, so nothing carries between periods.';

-- Table: VOP_PAYOUT_SUMMARY (Stores aggregated payout results per vehicle/VOP plan/partner for each period.)
CREATE TABLE IF NOT EXISTS fs.vop_payout_summary (
    vop_payout_summary_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payout_period_id                    UUID,
    vop_plan_id                         UUID,
    vehicle_id                          UUID,
    vehicle_partner_id                  UUID,
    base_fee_original                   NUMERIC(12,2),
    base_fee_adjusted                   NUMERIC(12,2),
    mileage_fee                         NUMERIC(12,2),
    manual_adjustments_total            NUMERIC(12,2),
    total_payout                        NUMERIC(12,2),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vop_payout_summary IS 'Stores aggregated payout results per vehicle/VOP plan/partner for each period.';

-- Table: VOP_PLAN (Vehicle Owner Program details used to calculate fees owed to owner.)
CREATE TABLE IF NOT EXISTS fs.vop_plan (
    vop_plan_id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    vehicle_partner_id                  UUID,
    base_fee_amount                     INTEGER,
    per_mile_rate                       NUMERIC(6,2),
    owner_plan_fee                      INTEGER,
    minimum_amount_per_period           INTEGER,
    exclude_vop_miles_flag              BOOLEAN,
    effective_from                      DATE,
    effective_to                        DATE,
    notes                               TEXT,
    status                              fs.vop_plan_status_enum,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vop_plan IS 'Vehicle Owner Program details used to calculate fees owed to owner.';

-- -----------------------------------------------------------------------------
-- DOMAIN: VEHICLE RESERVATIONS
-- -----------------------------------------------------------------------------

-- Table: RESERVATION_HOLD (Holds placed on a reservation. A reservation with any open hold cannot be checke)
CREATE TABLE IF NOT EXISTS fs.reservation_hold (
    reservation_hold_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_reservation_id              UUID,
    hold_reason_code                    VARCHAR(40),
    hold_note                           TEXT,
    is_system_placed                    BOOLEAN,
    placed_at                           TIMESTAMPTZ,
    placed_by_user_id                   UUID,
    released_at                         TIMESTAMPTZ,
    released_by_user_id                 UUID,
    release_note                        TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_hold IS 'Holds placed on a reservation. A reservation with any open hold cannot be checked out, though staff can still work it.';

-- Table: RESERVATION_HOLD_REASON_SELECT (Reasons a reservation can be held. Seed values live in the workbook.)
CREATE TABLE IF NOT EXISTS fs.reservation_hold_reason_select (
    hold_reason_code                    VARCHAR(40) PRIMARY KEY,
    hold_reason_name                    VARCHAR(80),
    is_system_reason                    BOOLEAN,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_hold_reason_select IS 'Reasons a reservation can be held. Seed values live in the workbook.';

-- Table: RESERVATION_LOCATION_SELECT (Defines authorized locations for reservation start and end points.)
CREATE TABLE IF NOT EXISTS fs.reservation_location_select (
    reservation_location_code           VARCHAR(40) PRIMARY KEY,
    reservation_location_name           VARCHAR(120),
    location_category                   fs.reservation_location_select_location_category_enum,
    address_line1                       VARCHAR(200),
    address_line2                       VARCHAR(100),
    city                                VARCHAR(100),
    state                               VARCHAR(2),
    postal_code                         VARCHAR(10),
    notes                               TEXT,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_location_select IS 'Defines authorized locations for reservation start and end points.';

-- Table: RESERVATION_PERK_APPLICATION (Perks applied to a member, held as credits rather than as adjustments to a trip.)
CREATE TABLE IF NOT EXISTS fs.reservation_perk_application (
    reservation_perk_application_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_id                      UUID,
    member_id                           UUID,
    perk_type                           VARCHAR(40),
    vehicle_tier_id_applied             UUID,
    points_credit_amount                INTEGER,
    applied_at                          TIMESTAMPTZ,
    last_revised_at                     TIMESTAMPTZ,
    is_final                            BOOLEAN,
    notes                               TEXT,
    is_active                           BOOLEAN,
    member_package_id                   UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_perk_application IS 'Perks applied to a member, held as credits rather than as adjustments to a trip.';

-- Table: RESERVATION_PROTECTED_PERIOD (A stretch of dates protected for the club's top statuses, per branch, with its r)
CREATE TABLE IF NOT EXISTS fs.reservation_protected_period (
    reservation_protected_period_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id                           UUID,
    period_name                         VARCHAR(120),
    start_date                          DATE,
    end_date                            DATE,
    release_at                          TIMESTAMPTZ,
    is_recurring_weekend                BOOLEAN,
    triggered_at                        TIMESTAMPTZ,
    released_at                         TIMESTAMPTZ,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_protected_period IS 'A stretch of dates protected for the club''s top statuses, per branch, with its release moment.';

-- Table: RESERVATION_PROTECTION (One vehicle protected for one period - the sixth kind of calendar commitment, pl)
CREATE TABLE IF NOT EXISTS fs.reservation_protection (
    reservation_protection_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_protected_period_id     UUID,
    vehicle_id                          UUID,
    protected_at                        TIMESTAMPTZ,
    released_at                         TIMESTAMPTZ,
    booked_reservation_id               UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_protection IS 'One vehicle protected for one period - the sixth kind of calendar commitment, placed and released by the nightly job.';

-- Table: RESERVATION_RESTRICTED_DATES (Dates on which a reservation may not start or end, though a trip may run through)
CREATE TABLE IF NOT EXISTS fs.reservation_restricted_dates (
    reservation_restricted_date_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id                           UUID,
    restricted_date_type_code           VARCHAR(30),
    holiday_definition_id               UUID,
    restriction_name                    VARCHAR(150),
    description                         TEXT,
    start_date                          DATE,
    end_date                            DATE,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_restricted_dates IS 'Dates on which a reservation may not start or end, though a trip may run through them.';

-- Table: RESERVATION_RULE (Acts as a descriptive registry used for configuration reference that defines glo)
CREATE TABLE IF NOT EXISTS fs.reservation_rule (
    reservation_rule_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_code                           VARCHAR(50) UNIQUE,
    rule_name                           VARCHAR(150),
    rule_category                       fs.reservation_rule_rule_category_enum,
    rule_type                           fs.reservation_rule_rule_type_enum,
    description                         TEXT,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_rule IS 'Acts as a descriptive registry used for configuration reference that defines global, system-wide reservation policies and rules enforced by the application layer.';

-- Table: RESERVATION_SOURCE_TYPE_SELECT (Lookup of codes that defines how or from where a reservation or trip was created)
CREATE TABLE IF NOT EXISTS fs.reservation_source_type_select (
    source_type_code                    VARCHAR(40) PRIMARY KEY,
    source_type_name                    VARCHAR(120),
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_source_type_select IS 'Lookup of codes that defines how or from where a reservation or trip was created.';

-- Table: RESERVATION_STATUS_HISTORY (Every reservation status change, with who, when, and why.)
CREATE TABLE IF NOT EXISTS fs.reservation_status_history (
    reservation_status_history_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_id                      UUID,
    status                              VARCHAR(30),
    status_reason_code                  VARCHAR(40),
    status_note                         TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_status_history IS 'Every reservation status change, with who, when, and why.';

-- Table: RESERVATION_STATUS_REASON_SELECT (Reasons a reservation changed status. Seeded with Member Request, Club Unable To)
CREATE TABLE IF NOT EXISTS fs.reservation_status_reason_select (
    status_reason_code                  VARCHAR(40) PRIMARY KEY,
    status_reason_name                  VARCHAR(80),
    applies_to_status                   VARCHAR(30),
    charges_cancellation_allowance      BOOLEAN,
    is_system_reason                    BOOLEAN,
    requires_note                       BOOLEAN,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_status_reason_select IS 'Reasons a reservation changed status. Seeded with Member Request, Club Unable To Supply, Weather, Insurance Lapse, Damage, Staff Decision, and Other.';

-- Table: RESERVATION_STATUS_SELECT (Lookup that defines the lifecycle states a reservation can have.)
CREATE TABLE IF NOT EXISTS fs.reservation_status_select (
    reservation_status_code             VARCHAR(40) PRIMARY KEY,
    name                                VARCHAR(120) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_status_select IS 'Lookup that defines the lifecycle states a reservation can have.';

-- Table: RESERVATION_TYPE_SELECT (Lookup that defines the category or purpose of each reservation.)
CREATE TABLE IF NOT EXISTS fs.reservation_type_select (
    reservation_type_code               VARCHAR(40) PRIMARY KEY,
    name                                VARCHAR(120) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_type_select IS 'Lookup that defines the category or purpose of each reservation.';

-- Table: RESERVATION_WATCH (A dated window during which something might make vehicles unavailable, typically)
CREATE TABLE IF NOT EXISTS fs.reservation_watch (
    reservation_watch_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id                           UUID,
    vehicle_id                          UUID,
    watch_reason_code                   VARCHAR(30),
    starts_on                           DATE,
    ends_on                             DATE,
    watch_note                          TEXT,
    escalated_to_withhold_id            UUID,
    cleared_at                          TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_watch IS 'A dated window during which something might make vehicles unavailable, typically a weather forecast.';

-- Table: RESERVATION_WITHHOLD (Takes a vehicle off booking entirely, for a dated window or open-ended.)
CREATE TABLE IF NOT EXISTS fs.reservation_withhold (
    reservation_withhold_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id                           UUID,
    vehicle_id                          UUID,
    withhold_reason_code                VARCHAR(30),
    starts_on                           DATE,
    ends_on                             DATE,
    withhold_note                       TEXT,
    placed_by_user_id                   UUID,
    placed_at                           TIMESTAMPTZ,
    released_by_user_id                 UUID,
    released_at                         TIMESTAMPTZ,
    release_note                        TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_withhold IS 'Takes a vehicle off booking entirely, for a dated window or open-ended.';

-- Table: RESERVATION_WITHHOLD_REASON_SELECT (Reasons a vehicle may be withheld from booking. Seeded: Awaiting Launch, Weather)
CREATE TABLE IF NOT EXISTS fs.reservation_withhold_reason_select (
    withhold_reason_code                VARCHAR(30) PRIMARY KEY,
    label                               VARCHAR(80),
    description                         TEXT,
    is_system_placed                    BOOLEAN,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.reservation_withhold_reason_select IS 'Reasons a vehicle may be withheld from booking. Seeded: Awaiting Launch, Weather, Sale Pending, Safety, Marketing, VIP, Other.';

-- Table: VEHICLE_ACCESS_ALLOWANCE (Where a vehicle is restricted to a named list, the members who may book it. Ever)
CREATE TABLE IF NOT EXISTS fs.vehicle_access_allowance (
    vehicle_access_allowance_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    member_id                           UUID,
    added_reason                        TEXT,
    added_at                            TIMESTAMPTZ,
    added_by_user_id                    UUID,
    removed_at                          TIMESTAMPTZ,
    removed_by_user_id                  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_access_allowance IS 'Where a vehicle is restricted to a named list, the members who may book it. Everyone else does not see the vehicle at all, exactly as with an exclusion.';

-- Table: VEHICLE_ACCESS_EXCLUSION (Members who may not book a particular vehicle; the vehicle is simply absent for )
CREATE TABLE IF NOT EXISTS fs.vehicle_access_exclusion (
    vehicle_access_exclusion_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    member_id                           UUID,
    corporate_account_id                UUID,
    exclusion_source                    fs.vehicle_access_exclusion_exclusion_source_enum,
    confidential_reason                 TEXT,
    applied_at                          TIMESTAMPTZ,
    applied_by_user_id                  UUID,
    removed_at                          TIMESTAMPTZ,
    removed_by_user_id                  UUID,
    removal_reason                      TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_access_exclusion IS 'Members who may not book a particular vehicle; the vehicle is simply absent for them.';

-- Table: VEHICLE_MEMBER_QUALIFICATION (A qualification a member holds. Granted by staff rather than applied for, since )
CREATE TABLE IF NOT EXISTS fs.vehicle_member_qualification (
    vehicle_member_qualification_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    vehicle_qualification_id            UUID,
    granted_at                          TIMESTAMPTZ,
    granted_by_user_id                  UUID,
    grant_note                          TEXT,
    expires_on                          DATE,
    revoked_at                          TIMESTAMPTZ,
    revoked_by_user_id                  UUID,
    revocation_reason                   TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_member_qualification IS 'A qualification a member holds. Granted by staff rather than applied for, since the requirement is not advertised.';

-- Table: VEHICLE_QUALIFICATION (A qualification a member must hold before booking a particular vehicle - a manua)
CREATE TABLE IF NOT EXISTS fs.vehicle_qualification (
    vehicle_qualification_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    qualification_name                  VARCHAR(120),
    qualification_description           TEXT,
    expiry_basis                        fs.vehicle_qualification_expiry_basis_enum,
    expiry_months                       SMALLINT,
    show_to_unqualified_members         BOOLEAN,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_qualification IS 'A qualification a member must hold before booking a particular vehicle - a manual transmission checkout, a high-performance assessment.';

-- Table: VEHICLE_RESERVATION (A booking of a club vehicle: dates, member, vehicle, status, and any courtesy gr)
CREATE TABLE IF NOT EXISTS fs.vehicle_reservation (
    vehicle_reservation_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_type_code               VARCHAR(40),
    reservation_status_code             VARCHAR(40),
    vehicle_id                          UUID,
    member_id                           UUID,
    member_package_id                   UUID,
    reserving_branch_id                 UUID,
    source_type_code                    VARCHAR(40),
    created_by_user_role                fs.vehicle_reservation_created_by_user_role_enum,
    start_time_scheduled                TIMESTAMPTZ,
    end_time_scheduled                  TIMESTAMPTZ,
    start_type                          fs.vehicle_reservation_start_type_enum,
    start_location_code                 VARCHAR(40),
    return_type                         fs.vehicle_reservation_return_type_enum,
    end_location_code                   VARCHAR(40),
    buffer_days_after_end               SMALLINT,
    is_tentative                        BOOLEAN,
    is_backup                           BOOLEAN,
    is_fpw_eligible                     BOOLEAN,
    linked_reservation_id               UUID,
    base_points_estimate                INTEGER,
    weekday_count_estimate              INTEGER,
    weekend_count_estimate              INTEGER,
    counts_toward_limits                BOOLEAN,
    service_category_code               VARCHAR(40),
    service_type_code                   VARCHAR(40),
    service_vendor_id                   UUID,
    notes                               TEXT,
    last_checkin_event_id               UUID,
    last_checkout_event_id              UUID,
    early_pickup_from                   TIMESTAMPTZ,
    early_pickup_granted_at             TIMESTAMPTZ,
    early_pickup_granted_by_user_id     UUID,
    late_return_until                   TIMESTAMPTZ,
    late_return_granted_at              TIMESTAMPTZ,
    late_return_granted_by_user_id      UUID,
    member_address_id                   UUID,
    delivery_quote_amount               NUMERIC(12,2),
    delivery_quote_miles                NUMERIC(6,1),
    branch_delivery_rate_id             UUID,
    delivery_quote_at                   TIMESTAMPTZ,
    delivery_quote_accepted_at          TIMESTAMPTZ,
    delivery_quote_accepted_by_user_id  UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_reservation IS 'A booking of a club vehicle: dates, member, vehicle, status, and any courtesy grants.';

-- -----------------------------------------------------------------------------
-- DOMAIN: VEHICLE USE
-- -----------------------------------------------------------------------------

-- Table: SERVICE_CATEGORY (High-level categories of vehicle service.)
CREATE TABLE IF NOT EXISTS fs.service_category (
    service_category_code               VARCHAR(40) PRIMARY KEY,
    service_category_name               VARCHAR(60) UNIQUE,
    description                         TEXT,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.service_category IS 'High-level categories of vehicle service.';

-- Table: SERVICE_REASON_SELECT (Lookup defining reasons for service trips.)
CREATE TABLE IF NOT EXISTS fs.service_reason_select (
    service_reason_code                 VARCHAR(40) PRIMARY KEY,
    name                                VARCHAR(120) UNIQUE,
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.service_reason_select IS 'Lookup defining reasons for service trips.';

-- Table: TOLL_AUTHORITY_SELECT (List of toll authorities that issue toll transactions; authorities vary by branc)
CREATE TABLE IF NOT EXISTS fs.toll_authority_select (
    authority_code                      VARCHAR(20) PRIMARY KEY,
    authority_name                      VARCHAR(120) UNIQUE,
    sort_order                          SMALLINT,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.toll_authority_select IS 'List of toll authorities that issue toll transactions; authorities vary by branch.';

-- Table: VEHICLE_ATTACHMENT_RETENTION_POLICY (Retention and archival rules for attachments and photos, by source type.)
CREATE TABLE IF NOT EXISTS fs.vehicle_attachment_retention_policy (
    attachment_retention_policy_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_type_code                    VARCHAR(40),
    source_category                     VARCHAR(40),
    retention_period_months             INTEGER,
    retention_action                    fs.vehicle_attachment_retention_policy_retention_action_enum,
    auto_archive_flag                   BOOLEAN,
    notes                               TEXT,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_attachment_retention_policy IS 'Retention and archival rules for attachments and photos, by source type.';

-- Table: VEHICLE_CONDITION_CODE (The six conditions a vehicle can be in while it is in the club’s care. Condition)
CREATE TABLE IF NOT EXISTS fs.vehicle_condition_code (
    condition_code                      VARCHAR(30) PRIMARY KEY,
    status_code                         VARCHAR(40) UNIQUE,
    name                                VARCHAR(120),
    description                         TEXT,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_condition_code IS 'The six conditions a vehicle can be in while it is in the club’s care. Condition does not apply while a vehicle is out.';

-- Table: VEHICLE_CONDITION_HISTORY (Every condition change, with its reason and cause. The condition on VEHICLE is a)
CREATE TABLE IF NOT EXISTS fs.vehicle_condition_history (
    vehicle_condition_history_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    vehicle_trip_id                     UUID,
    condition_code                      VARCHAR(30),
    condition_reason_code               VARCHAR(40),
    reservation_id                      UUID,
    inspection_id                       UUID,
    notes                               TEXT,
    changed_by_user_id                  UUID,
    changed_at                          TIMESTAMPTZ
);
COMMENT ON TABLE fs.vehicle_condition_history IS 'Every condition change, with its reason and cause. The condition on VEHICLE is a cache of the latest row here; the two are written in one transaction and the history is the truth.';

-- Table: VEHICLE_CONDITION_REASON (Why a vehicle is in its current condition. Carries the detail that DOWN delibera)
CREATE TABLE IF NOT EXISTS fs.vehicle_condition_reason (
    condition_reason_code               VARCHAR(40) PRIMARY KEY,
    status_reason_name                  VARCHAR(120),
    description                         TEXT,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_condition_reason IS 'Why a vehicle is in its current condition. Carries the detail that DOWN deliberately does not encode in its name, so damage found and service scheduled are a reason change rather than two conditions.';

-- Table: VEHICLE_CONDITION_TRANSITION_RULE (Which condition changes are permitted, expressed as data so a process change nee)
CREATE TABLE IF NOT EXISTS fs.vehicle_condition_transition_rule (
    status_transition_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_condition_code                 VARCHAR(30),
    to_condition_code                   VARCHAR(30),
    requires_approval                   BOOLEAN,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_condition_transition_rule IS 'Which condition changes are permitted, expressed as data so a process change needs no developer.';

-- Table: VEHICLE_EVENT_ATTACHMENT (Holds photos or documents attached to specific vehicle events with retention and)
CREATE TABLE IF NOT EXISTS fs.vehicle_event_attachment (
    vehicle_event_attachment_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_event_id                    UUID,
    attachment_type                     fs.vehicle_event_attachment_attachment_type_enum,
    attachment_url                      TEXT,
    description                         TEXT,
    attachment_order                    SMALLINT,
    attachment_retention_policy_id      UUID,
    retention_expires_on                DATE,
    retention_action                    fs.vehicle_event_attachment_retention_action_enum,
    archived_flag                       BOOLEAN,
    archived_at                         TIMESTAMPTZ,
    file_size_bytes                     BIGINT,
    mime_type                           VARCHAR(80),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_event_attachment IS 'Holds photos or documents attached to specific vehicle events with retention and metadata fields for managing long-term photo storage.';

-- Table: VEHICLE_EVENT_LOG (Logs operational events for each trip (check-out, check-in, refuel, damage repor)
CREATE TABLE IF NOT EXISTS fs.vehicle_event_log (
    vehicle_event_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_trip_id                     UUID,
    reservation_id                      UUID,
    event_type                          fs.vehicle_event_log_event_type_enum,
    event_role                          fs.vehicle_event_log_event_role_enum,
    vehicle_id                          UUID,
    branch_id                           UUID,
    member_id                           UUID,
    service_vendor_id                   UUID,
    fuel_percent                        INTEGER,
    notes                               TEXT,
    event_time                          TIMESTAMPTZ,
    captured_at                         TIMESTAMPTZ,
    captured_by_user_id                 UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_event_log IS 'Logs operational events for each trip (check-out, check-in, refuel, damage report, etc.)';

-- Table: VEHICLE_FUEL_LEVEL_SELECT (Maps the fuel levels staff pick from a dropdown - Full, 7/8, 3/4 and the rest - )
CREATE TABLE IF NOT EXISTS fs.vehicle_fuel_level_select (
    fuel_level_code                     VARCHAR(10) PRIMARY KEY,
    label                               VARCHAR(20) UNIQUE,
    fuel_percent                        SMALLINT,
    sort_order                          SMALLINT,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_fuel_level_select IS 'Maps the fuel levels staff pick from a dropdown - Full, 7/8, 3/4 and the rest - to the numeric percent the platform stores.';

-- Table: VEHICLE_LOCATION (Tracks home/current branch assignment over time.)
CREATE TABLE IF NOT EXISTS fs.vehicle_location (
    vehicle_location_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    home_branch_id                      UUID,
    current_branch_id                   UUID,
    effective_from                      DATE,
    effective_to                        DATE,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_location IS 'Tracks home/current branch assignment over time.';

-- Table: VEHICLE_ODOMETER_LOG (Log of all odometer readings captured by any workflow, with source linkage and c)
CREATE TABLE IF NOT EXISTS fs.vehicle_odometer_log (
    vehicle_odometer_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_event_id                    UUID,
    vehicle_id                          UUID,
    odometer_value                      INTEGER,
    captured_at                         TIMESTAMPTZ,
    captured_by_user_id                 UUID,
    is_estimated                        BOOLEAN,
    quality_flag                        fs.vehicle_odometer_log_quality_flag_enum,
    effective_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_odometer_log IS 'Log of all odometer readings captured by any workflow, with source linkage and capture details.';

-- Table: VEHICLE_SERVICE_TYPE (Specific service types within a category.)
CREATE TABLE IF NOT EXISTS fs.vehicle_service_type (
    service_type_code                   VARCHAR(40) PRIMARY KEY,
    service_category_code               VARCHAR(40),
    service_type_name                   VARCHAR(60) UNIQUE,
    description                         TEXT,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_service_type IS 'Specific service types within a category.';

-- Table: VEHICLE_SOURCE_TYPE (Stores allowable source contexts for odometer, inspection, and service readings.)
CREATE TABLE IF NOT EXISTS fs.vehicle_source_type (
    source_type_code                    VARCHAR(40) PRIMARY KEY,
    source_type_name                    VARCHAR(100),
    description                         TEXT,
    applies_to_table                    VARCHAR(60),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_source_type IS 'Stores allowable source contexts for odometer, inspection, and service readings.';

-- Table: VEHICLE_TOLL_TRANSACTION (Stores individual toll transactions imported from toll authorities; matched to v)
CREATE TABLE IF NOT EXISTS fs.vehicle_toll_transaction (
    vehicle_toll_transaction_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    toll_tag                            VARCHAR(40),
    transaction_at                      TIMESTAMPTZ,
    toll_authority_code                 VARCHAR(20),
    location                            VARCHAR(160),
    amount                              NUMERIC(10,2),
    import_source                       VARCHAR(80),
    import_batch_id                     VARCHAR(60),
    match_status                        fs.vehicle_toll_transaction_match_status_enum,
    vehicle_trip_id                     UUID,
    member_charge_id                    UUID,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_toll_transaction IS 'Stores individual toll transactions imported from toll authorities; matched to vehicle trips by timestamp and billed to members via member charges.';

-- Table: VEHICLE_TRIP (Stores data related to actual vehicle movement based on checkout and checkin of )
CREATE TABLE IF NOT EXISTS fs.vehicle_trip (
    vehicle_trip_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_reservation_id              UUID,
    trip_type_code                      VARCHAR(20),
    vehicle_id                          UUID,
    start_time_actual                   TIMESTAMPTZ,
    end_time_actual                     TIMESTAMPTZ,
    odometer_start_id                   UUID,
    odometer_end_id                     UUID,
    miles_driven                        INTEGER,
    fuel_start_percent                  INTEGER,
    fuel_end_percent                    INTEGER,
    extra_miles                         INTEGER,
    extra_miles_reason                  fs.vehicle_trip_extra_miles_reason_enum,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID,
    pay_vop_use                         fs.vehicle_trip_pay_vop_use_enum
);
COMMENT ON TABLE fs.vehicle_trip IS 'Stores data related to actual vehicle movement based on checkout and checkin of vehicles.';

-- Table: VEHICLE_TRIP_MEMBER (Stores member-specific operational, package, and points details related to a mem)
CREATE TABLE IF NOT EXISTS fs.vehicle_trip_member (
    vehicle_trip_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id                           UUID,
    member_package_id                   UUID,
    member_package_participant_id       UUID,
    branch_id                           UUID,
    source_type_code                    VARCHAR(40),
    source_id                           UUID,
    start_time_actual                   TIMESTAMPTZ,
    end_time_actual                     TIMESTAMPTZ,
    weekday_count_actual                INTEGER,
    weekend_count_actual                INTEGER,
    start_type                          fs.vehicle_trip_member_start_type_enum,
    return_type                         fs.vehicle_trip_member_return_type_enum,
    incident_flag                       BOOLEAN,
    miles_member                        INTEGER,
    miles_member_adjustment             INTEGER,
    miles_member_adjustment_reason      TEXT,
    vehicle_tier_snapshot               VARCHAR(20),
    weekday_point_value_snapshot        INTEGER,
    weekend_point_value_snapshot        INTEGER,
    extra_mile_point_value_snapshot     NUMERIC(6,3),
    included_miles_snapshot             INTEGER,
    overage_miles_snapshot              INTEGER,
    base_points                         INTEGER,
    extra_mileage_points                INTEGER,
    credits_applied_points              INTEGER,
    total_points                        INTEGER,
    counts_toward_limits                BOOLEAN,
    calculation_version                 VARCHAR(20),
    calculation_detail                  TEXT,
    vop_payout_log_id                   UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_trip_member IS 'Stores member-specific operational, package, and points details related to a member vehicle trip.';

-- Table: VEHICLE_TRIP_SERVICE (Stores service-specific details and vendor information related to a service vehi)
CREATE TABLE IF NOT EXISTS fs.vehicle_trip_service (
    vehicle_trip_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id                           UUID,
    service_category_code               VARCHAR(40),
    service_type_code                   VARCHAR(40),
    service_reason_code                 VARCHAR(40),
    service_cost                        NUMERIC(12,2),
    billed_member_id                    UUID,
    billed_vehicle_partner_id           UUID,
    billed_amount                       NUMERIC(12,2),
    warranty_claim_reference            VARCHAR(60),
    service_notes                       TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_trip_service IS 'Stores service-specific details and vendor information related to a service vehicle trip.';

-- Table: VEHICLE_TRIP_TYPE_SELECT (The kinds of trip a vehicle can make, and what each kind means for the business.)
CREATE TABLE IF NOT EXISTS fs.vehicle_trip_type_select (
    trip_type_code                      VARCHAR(20) PRIMARY KEY,
    label                               VARCHAR(50),
    description                         TEXT,
    is_revenue                          BOOLEAN,
    posts_points                        BOOLEAN,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_trip_type_select IS 'The kinds of trip a vehicle can make, and what each kind means for the business.';

-- -----------------------------------------------------------------------------
-- DOMAIN: VEHICLES
-- -----------------------------------------------------------------------------

-- Table: VEHICLE (Core vehicle record: identity, attributes, and the cached state of each car in t)
CREATE TABLE IF NOT EXISTS fs.vehicle (
    vehicle_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vin                                 VARCHAR(17) UNIQUE,
    vehicle_make_code                   VARCHAR(40),
    model                               VARCHAR(80),
    trim                                VARCHAR(40),
    vehicle_name                        VARCHAR(160),
    year                                VARCHAR(4),
    exterior_color                      VARCHAR(40),
    exterior_color_short                VARCHAR(40),
    interior_color                      VARCHAR(40),
    paint_code_1                        VARCHAR(40),
    paint_code_2                        VARCHAR(40),
    condition_code                      VARCHAR(30),
    condition_since                     TIMESTAMPTZ,
    home_branch_id                      UUID,
    launch_date                         DATE,
    expected_arrival_date               DATE,
    arrival_date                        DATE,
    notes                               TEXT,
    fleet_stage                         fs.vehicle_fleet_stage_enum,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle IS 'Core vehicle record: identity, attributes, and the cached state of each car in the fleet.';

-- Table: VEHICLE_ACCESSORIES (Accessories and kit included with the vehicle, plus a simple features list.)
CREATE TABLE IF NOT EXISTS fs.vehicle_accessories (
    vehicle_accessories_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    manuals                             BOOLEAN,
    car_cover                           BOOLEAN,
    charger                             BOOLEAN,
    number_keys                         fs.vehicle_accessories_number_keys_enum,
    accessories                         VARCHAR(240),
    features                            VARCHAR(240),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_accessories IS 'Accessories and kit included with the vehicle, plus a simple features list.';

-- Table: VEHICLE_COLOR_SELECT (Defines standardized color options for both interior and exterior color fields.)
CREATE TABLE IF NOT EXISTS fs.vehicle_color_select (
    vehicle_color_code                  VARCHAR(40) PRIMARY KEY,
    vehicle_color_name                  VARCHAR(120) UNIQUE,
    color_category                      VARCHAR(40),
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_color_select IS 'Defines standardized color options for both interior and exterior color fields.';

-- Table: VEHICLE_DESCRIPTION (Catalog-friendly details: body type, transmission, seating, cargo, range, primar)
CREATE TABLE IF NOT EXISTS fs.vehicle_description (
    vehicle_description_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    body_style                          fs.vehicle_description_body_style_enum,
    transmission                        fs.vehicle_description_transmission_enum,
    engine                              fs.vehicle_description_engine_enum,
    seats                               fs.vehicle_description_seats_enum,
    doors                               fs.vehicle_description_doors_enum,
    trunk_size                          fs.vehicle_description_trunk_size_enum,
    fuel_tank_size                      INTEGER,
    range                               INTEGER,
    image_url                           VARCHAR(255),
    description                         TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_description IS 'Catalog-friendly details: body type, transmission, seating, cargo, range, primary image, and description.';

-- Table: VEHICLE_FINANCING_LIFECYCLE (Financing and ownership details, including lender, lease flag, purchase and sale)
CREATE TABLE IF NOT EXISTS fs.vehicle_financing_lifecycle (
    vehicle_financing_lifecycle_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    finance_type                        fs.vehicle_financing_lifecycle_finance_type_enum,
    finance_term_months                 INTEGER,
    lender_lessor                       VARCHAR(160),
    guarantor                           VARCHAR(160),
    purchase_date                       DATE,
    purchase_price                      INTEGER,
    end_target_date                     DATE,
    end_date_is_committed               BOOLEAN,
    end_commitment_note                 VARCHAR(200),
    end_target_mileage                  INTEGER,
    end_target_value                    INTEGER,
    sale_date                           DATE,
    sale_price                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_financing_lifecycle IS 'Financing and ownership details, including lender, lease flag, purchase and sale information, and the valuation milestones for the vehicle’s lifecycle.';

-- Table: VEHICLE_MAKE_SELECT (Provides a consistent set of vehicle makes for data entry and reporting.)
CREATE TABLE IF NOT EXISTS fs.vehicle_make_select (
    vehicle_make_code                   VARCHAR(40) PRIMARY KEY,
    vehicle_make_name                   VARCHAR(10) UNIQUE,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_make_select IS 'Provides a consistent set of vehicle makes for data entry and reporting.';

-- Table: VEHICLE_MILEAGE_ALLOCATION (Records each monthly addition to a vehicle’s mileage limit and the limit that re)
CREATE TABLE IF NOT EXISTS fs.vehicle_mileage_allocation (
    vehicle_mileage_allocation_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_mileage_allowance_id        UUID,
    vehicle_id                          UUID,
    allocated_on                        DATE,
    miles_allocated                     INTEGER,
    odometer_limit                      INTEGER,
    odometer_at_allocation              INTEGER,
    miles_over_at_allocation            INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_mileage_allocation IS 'Records each monthly addition to a vehicle’s mileage limit and the limit that resulted.';

-- Table: VEHICLE_MILEAGE_ALLOWANCE (Stores the monthly mileage allowance for a vehicle whose use is limited, such as)
CREATE TABLE IF NOT EXISTS fs.vehicle_mileage_allowance (
    vehicle_mileage_allowance_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    monthly_miles                       INTEGER,
    effective_start                     DATE,
    effective_end                       DATE,
    starting_odometer                   INTEGER,
    withhold_threshold_miles            INTEGER,
    is_active                           BOOLEAN,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_mileage_allowance IS 'Stores the monthly mileage allowance for a vehicle whose use is limited, such as a leased car.';

-- Table: VEHICLE_PERFORMANCE (Performance specs for the vehicle like horsepower, top speed, acceleration, and )
CREATE TABLE IF NOT EXISTS fs.vehicle_performance (
    vehicle_performance_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    horsepower                          INTEGER,
    top_speed                           INTEGER,
    zero_to_sixty_time                  NUMERIC(4,1),
    rpm_redline                         INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_performance IS 'Performance specs for the vehicle like horsepower, top speed, acceleration, and redline.';

-- Table: VEHICLE_REGISTRATION_WARRANTY (Registration, inspection, license/toll details and warranty for a vehicle. Exact)
CREATE TABLE IF NOT EXISTS fs.vehicle_registration_warranty (
    vehicle_registration_warranty_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    registration_state                  VARCHAR(2),
    temp_license_plate                  VARCHAR(15),
    license_plate                       VARCHAR(15),
    toll_tag                            VARCHAR(30),
    registration_expires_on             DATE,
    inspection_expires_on               DATE,
    warranty_end                        DATE,
    warranty_company                    VARCHAR(120),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_registration_warranty IS 'Registration, inspection, license/toll details and warranty for a vehicle. Exactly one row per vehicle.';

-- Table: VEHICLE_RELEASE_ROW (The priority rows governing who may book a vehicle after its launch date, in ord)
CREATE TABLE IF NOT EXISTS fs.vehicle_release_row (
    vehicle_release_row_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    sort_order                          INTEGER,
    duration_days                       INTEGER,
    minimum_podium_status_code          VARCHAR(40),
    hide_from_lower_tiers               BOOLEAN,
    applied_from_template_id            UUID,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_release_row IS 'The priority rows governing who may book a vehicle after its launch date, in order.';

-- Table: VEHICLE_RELEASE_TEMPLATE (A reusable set of priority rows applied when a vehicle launches, because most ve)
CREATE TABLE IF NOT EXISTS fs.vehicle_release_template (
    vehicle_release_template_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_name                       VARCHAR(120),
    description                         TEXT,
    is_default                          BOOLEAN,
    is_active                           BOOLEAN,
    sort_order                          INTEGER,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_release_template IS 'A reusable set of priority rows applied when a vehicle launches, because most vehicles follow the same pattern.';

-- Table: VEHICLE_RELEASE_TEMPLATE_ROW (The rows inside a release template. Identical in shape to the rows they are copi)
CREATE TABLE IF NOT EXISTS fs.vehicle_release_template_row (
    vehicle_release_template_row_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_release_template_id         UUID,
    sort_order                          INTEGER,
    duration_days                       INTEGER,
    minimum_podium_status_code          VARCHAR(40),
    hide_from_lower_tiers               BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_release_template_row IS 'The rows inside a release template. Identical in shape to the rows they are copied onto.';

-- Table: VEHICLE_SPEC (Service-related specs and GPS/telematics device information for the vehicle.)
CREATE TABLE IF NOT EXISTS fs.vehicle_spec (
    vehicle_spec_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    engine_oil_brand                    VARCHAR(40),
    engine_oil_spec                     VARCHAR(20),
    gps_type                            fs.vehicle_spec_gps_type_enum,
    gps_device_id                       VARCHAR(40),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_spec IS 'Service-related specs and GPS/telematics device information for the vehicle.';

-- Table: VEHICLE_TIRE_BRAND_SELECT (Stores approved tire brand names for use in front and rear tire brand fields.)
CREATE TABLE IF NOT EXISTS fs.vehicle_tire_brand_select (
    tire_brand_code                     VARCHAR(40) PRIMARY KEY,
    tire_brand_name                     VARCHAR(120) UNIQUE,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_tire_brand_select IS 'Stores approved tire brand names for use in front and rear tire brand fields.';

-- Table: VEHICLE_TIRES (Front/rear tire sizes, pressures, brands, models, and spare size for the vehicle)
CREATE TABLE IF NOT EXISTS fs.vehicle_tires (
    vehicle_tires_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id                          UUID,
    front_tire_size                     VARCHAR(80),
    front_tire_psi                      SMALLINT,
    front_tire_brand                    VARCHAR(40),
    front_tire_model                    VARCHAR(80),
    rear_tire_size                      VARCHAR(20),
    rear_tire_psi                       SMALLINT,
    rear_tire_brand                     VARCHAR(40),
    rear_tire_model                     VARCHAR(80),
    spare_tire_size                     VARCHAR(80),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_tires IS 'Front/rear tire sizes, pressures, brands, models, and spare size for the vehicle.';

-- Table: VEHICLE_YEAR_SELECT (Provides a consistent set of vehicle model years for data entry and reporting.)
CREATE TABLE IF NOT EXISTS fs.vehicle_year_select (
    vehicle_year_code                   VARCHAR(4) PRIMARY KEY,
    vehicle_year_label                  VARCHAR(10) UNIQUE,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vehicle_year_select IS 'Provides a consistent set of vehicle model years for data entry and reporting.';

-- -----------------------------------------------------------------------------
-- DOMAIN: VENDOR MANAGEMENT
-- -----------------------------------------------------------------------------

-- Table: VENDOR (Stores details for all vendors and service providers associated with the company)
CREATE TABLE IF NOT EXISTS fs.vendor (
    vendor_id                           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_type_code                    VARCHAR(40),
    vendor_name                         VARCHAR(160) UNIQUE,
    home_branch_id                      UUID,
    vendor_email                        VARCHAR(120),
    vendor_phone                        VARCHAR(20),
    address_line1                       VARCHAR(200),
    address_line2                       VARCHAR(100),
    city                                VARCHAR(100),
    state                               VARCHAR(2),
    postal_code                         VARCHAR(10),
    website_url                         VARCHAR(200),
    vendor_tax_id                       VARCHAR(20),
    i9_verified                         BOOLEAN,
    insurance_certificate_exp           DATE,
    w9_on_file                          BOOLEAN,
    is_active                           BOOLEAN,
    notes                               TEXT,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vendor IS 'Stores details for all vendors and service providers associated with the company, including contact information, tax details, and compliance data.';

-- Table: VENDOR_CONTACT (Stores contact information for one or more individuals per vendor, and the login)
CREATE TABLE IF NOT EXISTS fs.vendor_contact (
    vendor_contact_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id                           UUID,
    user_id                             UUID UNIQUE,
    contact_name                        VARCHAR(120),
    preferred_name                      VARCHAR(80),
    contact_role                        VARCHAR(80),
    contact_phone                       VARCHAR(20),
    contact_phone_type                  fs.vendor_contact_contact_phone_type_enum,
    contact_email                       VARCHAR(120),
    is_primary                          BOOLEAN,
    contact_active                      BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vendor_contact IS 'Stores contact information for one or more individuals per vendor, and the login account for any contact who has been given access.';

-- Table: VENDOR_TYPE_SELECT (Defines allowable vendor types used for classification (e.g., detailing, mainten)
CREATE TABLE IF NOT EXISTS fs.vendor_type_select (
    vendor_type_code                    VARCHAR(40) PRIMARY KEY,
    vendor_type_name                    VARCHAR(100),
    description                         TEXT,
    sort_order                          INTEGER,
    is_active                           BOOLEAN,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by_user_id                  UUID,
    updated_by_user_id                  UUID
);
COMMENT ON TABLE fs.vendor_type_select IS 'Defines allowable vendor types used for classification (e.g., detailing, maintenance, catering, cleaning).';

-- =============================================================================
-- 3. FOREIGN KEY CONSTRAINTS (1,146 constraints)
-- =============================================================================
DO $$ BEGIN ALTER TABLE fs.automation_action ADD CONSTRAINT fk_automation_action_rule_id FOREIGN KEY (rule_id) REFERENCES fs.automation_rule (automation_rule_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_action ADD CONSTRAINT fk_automation_action_task_template_id FOREIGN KEY (task_template_id) REFERENCES fs.task_template (task_template_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_action ADD CONSTRAINT fk_automation_action_notification_template_id FOREIGN KEY (notification_template_id) REFERENCES fs.notification_template (notification_template_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_action ADD CONSTRAINT fk_automation_action_webhook_id FOREIGN KEY (webhook_id) REFERENCES fs.webhook (webhook_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_action ADD CONSTRAINT fk_automation_action_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_action ADD CONSTRAINT fk_automation_action_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_condition ADD CONSTRAINT fk_automation_condition_rule_id FOREIGN KEY (rule_id) REFERENCES fs.automation_rule (automation_rule_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_condition ADD CONSTRAINT fk_automation_condition_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_condition ADD CONSTRAINT fk_automation_condition_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_execution_log ADD CONSTRAINT fk_automation_execution_log_rule_id FOREIGN KEY (rule_id) REFERENCES fs.automation_rule (automation_rule_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_execution_log ADD CONSTRAINT fk_automation_execution_log_action_id FOREIGN KEY (action_id) REFERENCES fs.automation_action (automation_action_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_execution_log ADD CONSTRAINT fk_automation_execution_log_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_rule ADD CONSTRAINT fk_automation_rule_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.automation_rule ADD CONSTRAINT fk_automation_rule_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.scheduled_job ADD CONSTRAINT fk_scheduled_job_rule_id FOREIGN KEY (rule_id) REFERENCES fs.automation_rule (automation_rule_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.scheduled_job ADD CONSTRAINT fk_scheduled_job_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.scheduled_job ADD CONSTRAINT fk_scheduled_job_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.scheduled_job ADD CONSTRAINT fk_scheduled_job_report_schedule_id FOREIGN KEY (report_schedule_id) REFERENCES fs.report_schedule (report_schedule_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch ADD CONSTRAINT fk_branch_time_zone FOREIGN KEY (time_zone) REFERENCES fs.timezone_select (timezone_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch ADD CONSTRAINT fk_branch_state_mail FOREIGN KEY (state_mail) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch ADD CONSTRAINT fk_branch_state_physical FOREIGN KEY (state_physical) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch ADD CONSTRAINT fk_branch_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch ADD CONSTRAINT fk_branch_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch_delivery_rate ADD CONSTRAINT fk_branch_delivery_rate_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch_delivery_rate ADD CONSTRAINT fk_branch_delivery_rate_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch_delivery_rate ADD CONSTRAINT fk_branch_delivery_rate_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch_phone ADD CONSTRAINT fk_branch_phone_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch_phone ADD CONSTRAINT fk_branch_phone_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch_phone ADD CONSTRAINT fk_branch_phone_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch_toll_source ADD CONSTRAINT fk_branch_toll_source_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch_toll_source ADD CONSTRAINT fk_branch_toll_source_toll_authority_code FOREIGN KEY (toll_authority_code) REFERENCES fs.toll_authority_select (authority_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch_toll_source ADD CONSTRAINT fk_branch_toll_source_integration_provider_id FOREIGN KEY (integration_provider_id) REFERENCES fs.integration_provider (integration_provider_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch_toll_source ADD CONSTRAINT fk_branch_toll_source_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.branch_toll_source ADD CONSTRAINT fk_branch_toll_source_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.geofence ADD CONSTRAINT fk_geofence_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.geofence ADD CONSTRAINT fk_geofence_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.geofence ADD CONSTRAINT fk_geofence_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_branch_access ADD CONSTRAINT fk_member_branch_access_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_branch_access ADD CONSTRAINT fk_member_branch_access_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_branch_access ADD CONSTRAINT fk_member_branch_access_granted_by_user_id FOREIGN KEY (granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_branch_access ADD CONSTRAINT fk_member_branch_access_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_branch_access ADD CONSTRAINT fk_member_branch_access_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_branch_access ADD CONSTRAINT fk_member_branch_access_revoked_by_user_id FOREIGN KEY (revoked_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_branch_access ADD CONSTRAINT fk_staff_branch_access_staff_id FOREIGN KEY (staff_id) REFERENCES fs.staff (staff_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_branch_access ADD CONSTRAINT fk_staff_branch_access_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_branch_access ADD CONSTRAINT fk_staff_branch_access_granted_by_user_id FOREIGN KEY (granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_branch_access ADD CONSTRAINT fk_staff_branch_access_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_branch_access ADD CONSTRAINT fk_staff_branch_access_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_branch_access ADD CONSTRAINT fk_staff_branch_access_revoked_by_user_id FOREIGN KEY (revoked_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_branch_access ADD CONSTRAINT fk_vendor_branch_access_vendor_id FOREIGN KEY (vendor_id) REFERENCES fs.vendor (vendor_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_branch_access ADD CONSTRAINT fk_vendor_branch_access_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_branch_access ADD CONSTRAINT fk_vendor_branch_access_granted_by_user_id FOREIGN KEY (granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_branch_access ADD CONSTRAINT fk_vendor_branch_access_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_branch_access ADD CONSTRAINT fk_vendor_branch_access_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_branch_access ADD CONSTRAINT fk_vendor_branch_access_revoked_by_user_id FOREIGN KEY (revoked_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.audit_log ADD CONSTRAINT fk_audit_log_document_id FOREIGN KEY (document_id) REFERENCES fs.document (document_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.audit_log ADD CONSTRAINT fk_audit_log_actor_user_id FOREIGN KEY (actor_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document ADD CONSTRAINT fk_document_document_type_code FOREIGN KEY (document_type_code) REFERENCES fs.document_type (document_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document ADD CONSTRAINT fk_document_uploaded_by_user_id FOREIGN KEY (uploaded_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document ADD CONSTRAINT fk_document_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document ADD CONSTRAINT fk_document_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_category ADD CONSTRAINT fk_document_category_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_category ADD CONSTRAINT fk_document_category_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_link ADD CONSTRAINT fk_document_link_document_id FOREIGN KEY (document_id) REFERENCES fs.document (document_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_link ADD CONSTRAINT fk_document_link_document_category_code FOREIGN KEY (document_category_code) REFERENCES fs.document_category (document_category_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_link ADD CONSTRAINT fk_document_link_target_table FOREIGN KEY (target_table) REFERENCES fs.target_table_select (target_table_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_link ADD CONSTRAINT fk_document_link_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_link ADD CONSTRAINT fk_document_link_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_retention ADD CONSTRAINT fk_document_retention_document_id FOREIGN KEY (document_id) REFERENCES fs.document (document_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_retention ADD CONSTRAINT fk_document_retention_policy_id FOREIGN KEY (policy_id) REFERENCES fs.retention_policy (retention_policy_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_retention ADD CONSTRAINT fk_document_retention_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_retention ADD CONSTRAINT fk_document_retention_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_tag ADD CONSTRAINT fk_document_tag_document_id FOREIGN KEY (document_id) REFERENCES fs.document (document_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_tag ADD CONSTRAINT fk_document_tag_tag_id FOREIGN KEY (tag_id) REFERENCES fs.tag (tag_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_tag ADD CONSTRAINT fk_document_tag_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_tag ADD CONSTRAINT fk_document_tag_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_type ADD CONSTRAINT fk_document_type_document_category_code FOREIGN KEY (document_category_code) REFERENCES fs.document_category (document_category_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_type ADD CONSTRAINT fk_document_type_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_type ADD CONSTRAINT fk_document_type_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_version ADD CONSTRAINT fk_document_version_document_id FOREIGN KEY (document_id) REFERENCES fs.document (document_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_version ADD CONSTRAINT fk_document_version_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.document_version ADD CONSTRAINT fk_document_version_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.retention_policy ADD CONSTRAINT fk_retention_policy_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.retention_policy ADD CONSTRAINT fk_retention_policy_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.tag ADD CONSTRAINT fk_tag_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.tag ADD CONSTRAINT fk_tag_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event ADD CONSTRAINT fk_event_event_type_code FOREIGN KEY (event_type_code) REFERENCES fs.event_type_select (event_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event ADD CONSTRAINT fk_event_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event ADD CONSTRAINT fk_event_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_guest ADD CONSTRAINT fk_event_guest_event_registration_id FOREIGN KEY (event_registration_id) REFERENCES fs.event_registration (event_registration_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_guest ADD CONSTRAINT fk_event_guest_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_guest ADD CONSTRAINT fk_event_guest_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_partner ADD CONSTRAINT fk_event_partner_event_id FOREIGN KEY (event_id) REFERENCES fs.event (event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_partner ADD CONSTRAINT fk_event_partner_vendor_id FOREIGN KEY (vendor_id) REFERENCES fs.vendor (vendor_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_partner ADD CONSTRAINT fk_event_partner_granted_by_user_id FOREIGN KEY (granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_partner ADD CONSTRAINT fk_event_partner_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_partner ADD CONSTRAINT fk_event_partner_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_registration ADD CONSTRAINT fk_event_registration_event_id FOREIGN KEY (event_id) REFERENCES fs.event (event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_registration ADD CONSTRAINT fk_event_registration_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_registration ADD CONSTRAINT fk_event_registration_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_registration ADD CONSTRAINT fk_event_registration_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_type_select ADD CONSTRAINT fk_event_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.event_type_select ADD CONSTRAINT fk_event_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form ADD CONSTRAINT fk_form_target_table FOREIGN KEY (target_table) REFERENCES fs.target_table_select (target_table_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form ADD CONSTRAINT fk_form_no_defect_condition_code FOREIGN KEY (no_defect_condition_code) REFERENCES fs.vehicle_condition_code (condition_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form ADD CONSTRAINT fk_form_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form ADD CONSTRAINT fk_form_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_card ADD CONSTRAINT fk_form_card_form_id FOREIGN KEY (form_id) REFERENCES fs.form (form_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_card ADD CONSTRAINT fk_form_card_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_card ADD CONSTRAINT fk_form_card_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_card_option ADD CONSTRAINT fk_form_card_option_form_card_id FOREIGN KEY (form_card_id) REFERENCES fs.form_card (form_card_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_card_option ADD CONSTRAINT fk_form_card_option_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_card_option ADD CONSTRAINT fk_form_card_option_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_card_point ADD CONSTRAINT fk_form_card_point_form_card_id FOREIGN KEY (form_card_id) REFERENCES fs.form_card (form_card_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_card_point ADD CONSTRAINT fk_form_card_point_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_card_point ADD CONSTRAINT fk_form_card_point_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_defect ADD CONSTRAINT fk_form_defect_form_response_point_id FOREIGN KEY (form_response_point_id) REFERENCES fs.form_response_point (form_response_point_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_defect ADD CONSTRAINT fk_form_defect_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_defect ADD CONSTRAINT fk_form_defect_resolved_by FOREIGN KEY (resolved_by) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_mapping ADD CONSTRAINT fk_form_mapping_form_id FOREIGN KEY (form_id) REFERENCES fs.form (form_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_mapping ADD CONSTRAINT fk_form_mapping_target_table FOREIGN KEY (target_table) REFERENCES fs.target_table_select (target_table_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_mapping ADD CONSTRAINT fk_form_mapping_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_mapping ADD CONSTRAINT fk_form_mapping_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_response ADD CONSTRAINT fk_form_response_form_id FOREIGN KEY (form_id) REFERENCES fs.form (form_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_response ADD CONSTRAINT fk_form_response_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_response ADD CONSTRAINT fk_form_response_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_response ADD CONSTRAINT fk_form_response_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_response ADD CONSTRAINT fk_form_response_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_response_card ADD CONSTRAINT fk_form_response_card_form_response_id FOREIGN KEY (form_response_id) REFERENCES fs.form_response (form_response_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_response_card ADD CONSTRAINT fk_form_response_card_form_card_id FOREIGN KEY (form_card_id) REFERENCES fs.form_card (form_card_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_response_point ADD CONSTRAINT fk_form_response_point_form_response_card_id FOREIGN KEY (form_response_card_id) REFERENCES fs.form_response_card (form_response_card_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.form_response_point ADD CONSTRAINT fk_form_response_point_form_card_point_id FOREIGN KEY (form_card_point_id) REFERENCES fs.form_card_point (form_card_point_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_configuration ADD CONSTRAINT fk_integration_configuration_provider_id FOREIGN KEY (provider_id) REFERENCES fs.integration_provider (integration_provider_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_configuration ADD CONSTRAINT fk_integration_configuration_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_configuration ADD CONSTRAINT fk_integration_configuration_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_credential ADD CONSTRAINT fk_integration_credential_provider_id FOREIGN KEY (provider_id) REFERENCES fs.integration_provider (integration_provider_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_credential ADD CONSTRAINT fk_integration_credential_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_credential ADD CONSTRAINT fk_integration_credential_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_credential ADD CONSTRAINT fk_integration_credential_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_event_log ADD CONSTRAINT fk_integration_event_log_provider_id FOREIGN KEY (provider_id) REFERENCES fs.integration_provider (integration_provider_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_event_log ADD CONSTRAINT fk_integration_event_log_webhook_id FOREIGN KEY (webhook_id) REFERENCES fs.webhook (webhook_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_event_log ADD CONSTRAINT fk_integration_event_log_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_mapping_rule ADD CONSTRAINT fk_integration_mapping_rule_provider_id FOREIGN KEY (provider_id) REFERENCES fs.integration_provider (integration_provider_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_mapping_rule ADD CONSTRAINT fk_integration_mapping_rule_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_mapping_rule ADD CONSTRAINT fk_integration_mapping_rule_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_provider ADD CONSTRAINT fk_integration_provider_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.integration_provider ADD CONSTRAINT fk_integration_provider_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.webhook ADD CONSTRAINT fk_webhook_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.webhook ADD CONSTRAINT fk_webhook_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.webhook_delivery_log ADD CONSTRAINT fk_webhook_delivery_log_webhook_id FOREIGN KEY (webhook_id) REFERENCES fs.webhook (webhook_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.webhook_event_subscription ADD CONSTRAINT fk_webhook_event_subscription_webhook_id FOREIGN KEY (webhook_id) REFERENCES fs.webhook (webhook_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.webhook_event_subscription ADD CONSTRAINT fk_webhook_event_subscription_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.webhook_event_subscription ADD CONSTRAINT fk_webhook_event_subscription_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.webhook_inbound ADD CONSTRAINT fk_webhook_inbound_provider_id FOREIGN KEY (provider_id) REFERENCES fs.integration_provider (integration_provider_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car ADD CONSTRAINT fk_member_car_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car ADD CONSTRAINT fk_member_car_year FOREIGN KEY (year) REFERENCES fs.vehicle_year_select (vehicle_year_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car ADD CONSTRAINT fk_member_car_make FOREIGN KEY (make) REFERENCES fs.vehicle_make_select (vehicle_make_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car ADD CONSTRAINT fk_member_car_color FOREIGN KEY (color) REFERENCES fs.vehicle_color_select (vehicle_color_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car ADD CONSTRAINT fk_member_car_photo_document_id FOREIGN KEY (photo_document_id) REFERENCES fs.document (document_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car ADD CONSTRAINT fk_member_car_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car ADD CONSTRAINT fk_member_car_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_service ADD CONSTRAINT fk_member_car_service_member_car_stay_id FOREIGN KEY (member_car_stay_id) REFERENCES fs.member_car_stay (member_car_stay_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_service ADD CONSTRAINT fk_member_car_service_member_car_id FOREIGN KEY (member_car_id) REFERENCES fs.member_car (member_car_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_service ADD CONSTRAINT fk_member_car_service_member_charge_id FOREIGN KEY (member_charge_id) REFERENCES fs.member_charge (member_charge_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_service ADD CONSTRAINT fk_member_car_service_member_car_service_type_code FOREIGN KEY (member_car_service_type_code) REFERENCES fs.member_car_service_type (member_car_service_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_service ADD CONSTRAINT fk_member_car_service_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_service ADD CONSTRAINT fk_member_car_service_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_service_type ADD CONSTRAINT fk_member_car_service_type_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_service_type ADD CONSTRAINT fk_member_car_service_type_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_stay ADD CONSTRAINT fk_member_car_stay_member_car_id FOREIGN KEY (member_car_id) REFERENCES fs.member_car (member_car_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_stay ADD CONSTRAINT fk_member_car_stay_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_stay ADD CONSTRAINT fk_member_car_stay_vehicle_reservation_id FOREIGN KEY (vehicle_reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_stay ADD CONSTRAINT fk_member_car_stay_task_id FOREIGN KEY (task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_stay ADD CONSTRAINT fk_member_car_stay_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_car_stay ADD CONSTRAINT fk_member_car_stay_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.benefit_adjustment_kind_select ADD CONSTRAINT fk_benefit_adjustment_kind_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.benefit_adjustment_kind_select ADD CONSTRAINT fk_benefit_adjustment_kind_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.benefit_target_select ADD CONSTRAINT fk_benefit_target_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.benefit_target_select ADD CONSTRAINT fk_benefit_target_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account ADD CONSTRAINT fk_corporate_account_home_branch_id FOREIGN KEY (home_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account ADD CONSTRAINT fk_corporate_account_billing_state FOREIGN KEY (billing_state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account ADD CONSTRAINT fk_corporate_account_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account ADD CONSTRAINT fk_corporate_account_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account_contact ADD CONSTRAINT fk_corporate_account_contact_corporate_account_id FOREIGN KEY (corporate_account_id) REFERENCES fs.corporate_account (corporate_account_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account_contact ADD CONSTRAINT fk_corporate_account_contact_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account_contact ADD CONSTRAINT fk_corporate_account_contact_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.feedback_rating_scale ADD CONSTRAINT fk_feedback_rating_scale_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.feedback_rating_scale ADD CONSTRAINT fk_feedback_rating_scale_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.industry_select ADD CONSTRAINT fk_industry_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.industry_select ADD CONSTRAINT fk_industry_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.insurance_carrier_select ADD CONSTRAINT fk_insurance_carrier_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.insurance_carrier_select ADD CONSTRAINT fk_insurance_carrier_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.insurance_coverage_select ADD CONSTRAINT fk_insurance_coverage_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.insurance_coverage_select ADD CONSTRAINT fk_insurance_coverage_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.insurance_type_select ADD CONSTRAINT fk_insurance_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.insurance_type_select ADD CONSTRAINT fk_insurance_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.lap_rule ADD CONSTRAINT fk_lap_rule_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.lap_rule ADD CONSTRAINT fk_lap_rule_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member ADD CONSTRAINT fk_member_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member ADD CONSTRAINT fk_member_home_branch_id FOREIGN KEY (home_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member ADD CONSTRAINT fk_member_license_state FOREIGN KEY (license_state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member ADD CONSTRAINT fk_member_podium_status FOREIGN KEY (podium_status) REFERENCES fs.podium_status_select (podium_status_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member ADD CONSTRAINT fk_member_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member ADD CONSTRAINT fk_member_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_address ADD CONSTRAINT fk_member_address_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_address ADD CONSTRAINT fk_member_address_member_state FOREIGN KEY (member_state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_address ADD CONSTRAINT fk_member_address_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_address ADD CONSTRAINT fk_member_address_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_branch_history ADD CONSTRAINT fk_member_branch_history_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_branch_history ADD CONSTRAINT fk_member_branch_history_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_branch_history ADD CONSTRAINT fk_member_branch_history_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_branch_history ADD CONSTRAINT fk_member_branch_history_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_charge ADD CONSTRAINT fk_member_charge_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_charge ADD CONSTRAINT fk_member_charge_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_charge ADD CONSTRAINT fk_member_charge_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_charge ADD CONSTRAINT fk_member_charge_service_trip_id FOREIGN KEY (service_trip_id) REFERENCES fs.vehicle_trip_service (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_charge ADD CONSTRAINT fk_member_charge_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_charge ADD CONSTRAINT fk_member_charge_charge_type_code FOREIGN KEY (charge_type_code) REFERENCES fs.member_charge_type (charge_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_charge ADD CONSTRAINT fk_member_charge_approved_by_user_id FOREIGN KEY (approved_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_charge ADD CONSTRAINT fk_member_charge_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_charge ADD CONSTRAINT fk_member_charge_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_charge_type ADD CONSTRAINT fk_member_charge_type_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_charge_type ADD CONSTRAINT fk_member_charge_type_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_date ADD CONSTRAINT fk_member_date_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_date ADD CONSTRAINT fk_member_date_date_type_code FOREIGN KEY (date_type_code) REFERENCES fs.member_date_type (date_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_date ADD CONSTRAINT fk_member_date_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_date ADD CONSTRAINT fk_member_date_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_date_type ADD CONSTRAINT fk_member_date_type_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_date_type ADD CONSTRAINT fk_member_date_type_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_email ADD CONSTRAINT fk_member_email_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_email ADD CONSTRAINT fk_member_email_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_email ADD CONSTRAINT fk_member_email_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_feedback ADD CONSTRAINT fk_member_feedback_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_feedback ADD CONSTRAINT fk_member_feedback_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_feedback ADD CONSTRAINT fk_member_feedback_event_id FOREIGN KEY (event_id) REFERENCES fs.event (event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_feedback ADD CONSTRAINT fk_member_feedback_rating_scale_code FOREIGN KEY (rating_scale_code) REFERENCES fs.feedback_rating_scale (scale_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_feedback ADD CONSTRAINT fk_member_feedback_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_feedback ADD CONSTRAINT fk_member_feedback_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_garage_item ADD CONSTRAINT fk_member_garage_item_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_garage_item ADD CONSTRAINT fk_member_garage_item_member_car_id FOREIGN KEY (member_car_id) REFERENCES fs.member_car (member_car_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_garage_item ADD CONSTRAINT fk_member_garage_item_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_garage_item ADD CONSTRAINT fk_member_garage_item_cover_document_id FOREIGN KEY (cover_document_id) REFERENCES fs.document (document_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_garage_item ADD CONSTRAINT fk_member_garage_item_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_garage_item ADD CONSTRAINT fk_member_garage_item_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_insurance_coverage ADD CONSTRAINT fk_member_insurance_coverage_policy_id FOREIGN KEY (policy_id) REFERENCES fs.member_insurance_policy (member_insurance_policy_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_insurance_coverage ADD CONSTRAINT fk_member_insurance_coverage_insurance_type_code FOREIGN KEY (insurance_type_code) REFERENCES fs.insurance_type_select (insurance_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_insurance_coverage ADD CONSTRAINT fk_member_insurance_coverage_insurance_coverage_code FOREIGN KEY (insurance_coverage_code) REFERENCES fs.insurance_coverage_select (insurance_coverage_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_insurance_coverage ADD CONSTRAINT fk_member_insurance_coverage_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_insurance_coverage ADD CONSTRAINT fk_member_insurance_coverage_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_insurance_policy ADD CONSTRAINT fk_member_insurance_policy_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_insurance_policy ADD CONSTRAINT fk_member_insurance_policy_carrier_code FOREIGN KEY (carrier_code) REFERENCES fs.insurance_carrier_select (carrier_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_insurance_policy ADD CONSTRAINT fk_member_insurance_policy_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_insurance_policy ADD CONSTRAINT fk_member_insurance_policy_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_lap ADD CONSTRAINT fk_member_lap_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_lap ADD CONSTRAINT fk_member_lap_lap_rule_id FOREIGN KEY (lap_rule_id) REFERENCES fs.lap_rule (lap_rule_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_lap ADD CONSTRAINT fk_member_lap_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_lap ADD CONSTRAINT fk_member_lap_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_note ADD CONSTRAINT fk_member_note_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_note ADD CONSTRAINT fk_member_note_requested_contact_user_id FOREIGN KEY (requested_contact_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_note ADD CONSTRAINT fk_member_note_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_note ADD CONSTRAINT fk_member_note_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_note_category ADD CONSTRAINT fk_member_note_category_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_note_category ADD CONSTRAINT fk_member_note_category_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_note_category_link ADD CONSTRAINT fk_member_note_category_link_member_note_id FOREIGN KEY (member_note_id) REFERENCES fs.member_note (member_note_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_note_category_link ADD CONSTRAINT fk_member_note_category_link_member_note_category_code FOREIGN KEY (member_note_category_code) REFERENCES fs.member_note_category (member_note_category_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_note_category_link ADD CONSTRAINT fk_member_note_category_link_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package ADD CONSTRAINT fk_member_package_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package ADD CONSTRAINT fk_member_package_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package ADD CONSTRAINT fk_member_package_corporate_account_id FOREIGN KEY (corporate_account_id) REFERENCES fs.corporate_account (corporate_account_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package ADD CONSTRAINT fk_member_package_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package ADD CONSTRAINT fk_member_package_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_customization ADD CONSTRAINT fk_member_package_customization_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_customization ADD CONSTRAINT fk_member_package_customization_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_customization ADD CONSTRAINT fk_member_package_customization_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_hold ADD CONSTRAINT fk_member_package_hold_member_package_id FOREIGN KEY (member_package_id) REFERENCES fs.member_package (member_package_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_hold ADD CONSTRAINT fk_member_package_hold_authorized_by_user_id FOREIGN KEY (authorized_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_hold ADD CONSTRAINT fk_member_package_hold_reminder_task_id FOREIGN KEY (reminder_task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_hold ADD CONSTRAINT fk_member_package_hold_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_hold ADD CONSTRAINT fk_member_package_hold_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_participant ADD CONSTRAINT fk_member_package_participant_member_package_id FOREIGN KEY (member_package_id) REFERENCES fs.member_package (member_package_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_participant ADD CONSTRAINT fk_member_package_participant_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_participant ADD CONSTRAINT fk_member_package_participant_participant_type FOREIGN KEY (participant_type) REFERENCES fs.participant_type_select (participant_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_participant ADD CONSTRAINT fk_member_package_participant_granted_by_user_id FOREIGN KEY (granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_participant ADD CONSTRAINT fk_member_package_participant_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_participant ADD CONSTRAINT fk_member_package_participant_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_rate ADD CONSTRAINT fk_member_package_rate_member_package_id FOREIGN KEY (member_package_id) REFERENCES fs.member_package (member_package_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_rate ADD CONSTRAINT fk_member_package_rate_rate_card_id FOREIGN KEY (rate_card_id) REFERENCES fs.rate_card (rate_card_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_rate ADD CONSTRAINT fk_member_package_rate_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_rate ADD CONSTRAINT fk_member_package_rate_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_payment_schedule ADD CONSTRAINT fk_member_payment_schedule_member_package_id FOREIGN KEY (member_package_id) REFERENCES fs.member_package (member_package_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_payment_schedule ADD CONSTRAINT fk_member_payment_schedule_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_payment_schedule ADD CONSTRAINT fk_member_payment_schedule_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_phone ADD CONSTRAINT fk_member_phone_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_phone ADD CONSTRAINT fk_member_phone_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_phone ADD CONSTRAINT fk_member_phone_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_profile ADD CONSTRAINT fk_member_profile_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_profile ADD CONSTRAINT fk_member_profile_photo_document_id FOREIGN KEY (photo_document_id) REFERENCES fs.document (document_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_profile ADD CONSTRAINT fk_member_profile_industry_code FOREIGN KEY (industry_code) REFERENCES fs.industry_select (industry_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_profile ADD CONSTRAINT fk_member_profile_referred_by_member_id FOREIGN KEY (referred_by_member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_profile ADD CONSTRAINT fk_member_profile_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_profile ADD CONSTRAINT fk_member_profile_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_relationship ADD CONSTRAINT fk_member_relationship_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_relationship ADD CONSTRAINT fk_member_relationship_related_member_id FOREIGN KEY (related_member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_relationship ADD CONSTRAINT fk_member_relationship_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_relationship ADD CONSTRAINT fk_member_relationship_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_trip_story ADD CONSTRAINT fk_member_trip_story_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_trip_story ADD CONSTRAINT fk_member_trip_story_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_trip_story ADD CONSTRAINT fk_member_trip_story_cover_document_id FOREIGN KEY (cover_document_id) REFERENCES fs.document (document_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_trip_story ADD CONSTRAINT fk_member_trip_story_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_trip_story ADD CONSTRAINT fk_member_trip_story_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_trip_story_answer ADD CONSTRAINT fk_member_trip_story_answer_member_trip_story_id FOREIGN KEY (member_trip_story_id) REFERENCES fs.member_trip_story (member_trip_story_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_trip_story_answer ADD CONSTRAINT fk_member_trip_story_answer_member_trip_story_prompt_id FOREIGN KEY (member_trip_story_prompt_id) REFERENCES fs.member_trip_story_prompt (member_trip_story_prompt_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_trip_story_answer ADD CONSTRAINT fk_member_trip_story_answer_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_trip_story_answer ADD CONSTRAINT fk_member_trip_story_answer_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_trip_story_prompt ADD CONSTRAINT fk_member_trip_story_prompt_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_trip_story_prompt ADD CONSTRAINT fk_member_trip_story_prompt_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.participant_type_select ADD CONSTRAINT fk_participant_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.participant_type_select ADD CONSTRAINT fk_participant_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.podium_status_benefit ADD CONSTRAINT fk_podium_status_benefit_podium_status_code FOREIGN KEY (podium_status_code) REFERENCES fs.podium_status_select (podium_status_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.podium_status_benefit ADD CONSTRAINT fk_podium_status_benefit_benefit_target FOREIGN KEY (benefit_target) REFERENCES fs.benefit_target_select (benefit_target_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.podium_status_benefit ADD CONSTRAINT fk_podium_status_benefit_adjustment_kind FOREIGN KEY (adjustment_kind) REFERENCES fs.benefit_adjustment_kind_select (benefit_adjustment_kind_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.podium_status_benefit ADD CONSTRAINT fk_podium_status_benefit_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.podium_status_benefit ADD CONSTRAINT fk_podium_status_benefit_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.podium_status_select ADD CONSTRAINT fk_podium_status_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.podium_status_select ADD CONSTRAINT fk_podium_status_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.booking_type_select ADD CONSTRAINT fk_booking_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.booking_type_select ADD CONSTRAINT fk_booking_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level ADD CONSTRAINT fk_membership_level_membership_series_id FOREIGN KEY (membership_series_id) REFERENCES fs.membership_series (membership_series_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level ADD CONSTRAINT fk_membership_level_membership_level_type_code FOREIGN KEY (membership_level_type_code) REFERENCES fs.membership_level_type_select (membership_level_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level ADD CONSTRAINT fk_membership_level_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level ADD CONSTRAINT fk_membership_level_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_bookings ADD CONSTRAINT fk_membership_level_bookings_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_bookings ADD CONSTRAINT fk_membership_level_bookings_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_bookings ADD CONSTRAINT fk_membership_level_bookings_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_branch_availability ADD CONSTRAINT fk_membership_level_branch_availability_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_branch_availability ADD CONSTRAINT fk_membership_level_branch_availability_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_branch_availability ADD CONSTRAINT fk_membership_level_branch_availability_granted_by_user_id FOREIGN KEY (granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_branch_availability ADD CONSTRAINT fk_membership_level_branch_availability_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_branch_availability ADD CONSTRAINT fk_membership_level_branch_availability_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_branch_availability ADD CONSTRAINT fk_membership_level_branch_availability_revoked_by_user_id FOREIGN KEY (revoked_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_free_pass ADD CONSTRAINT fk_membership_level_free_pass_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_free_pass ADD CONSTRAINT fk_membership_level_free_pass_tier_max_id FOREIGN KEY (tier_max_id) REFERENCES fs.vehicle_tier (vehicle_tier_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_free_pass ADD CONSTRAINT fk_membership_level_free_pass_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_free_pass ADD CONSTRAINT fk_membership_level_free_pass_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_mileage ADD CONSTRAINT fk_membership_level_mileage_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_mileage ADD CONSTRAINT fk_membership_level_mileage_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_mileage ADD CONSTRAINT fk_membership_level_mileage_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_perks ADD CONSTRAINT fk_membership_level_perks_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_perks ADD CONSTRAINT fk_membership_level_perks_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_perks ADD CONSTRAINT fk_membership_level_perks_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_points_caps ADD CONSTRAINT fk_membership_level_points_caps_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_points_caps ADD CONSTRAINT fk_membership_level_points_caps_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_points_caps ADD CONSTRAINT fk_membership_level_points_caps_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_pricing ADD CONSTRAINT fk_membership_level_pricing_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_pricing ADD CONSTRAINT fk_membership_level_pricing_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_pricing ADD CONSTRAINT fk_membership_level_pricing_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_pricing ADD CONSTRAINT fk_membership_level_pricing_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_type_select ADD CONSTRAINT fk_membership_level_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_type_select ADD CONSTRAINT fk_membership_level_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_series ADD CONSTRAINT fk_membership_series_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_series ADD CONSTRAINT fk_membership_series_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_series_rate_card ADD CONSTRAINT fk_membership_series_rate_card_membership_series_id FOREIGN KEY (membership_series_id) REFERENCES fs.membership_series (membership_series_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_series_rate_card ADD CONSTRAINT fk_membership_series_rate_card_rate_card_id FOREIGN KEY (rate_card_id) REFERENCES fs.rate_card (rate_card_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_series_rate_card ADD CONSTRAINT fk_membership_series_rate_card_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_series_rate_card ADD CONSTRAINT fk_membership_series_rate_card_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mileage_type_select ADD CONSTRAINT fk_mileage_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mileage_type_select ADD CONSTRAINT fk_mileage_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_bookings ADD CONSTRAINT fk_mpc_bookings_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_bookings ADD CONSTRAINT fk_mpc_bookings_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_bookings ADD CONSTRAINT fk_mpc_bookings_booking_type FOREIGN KEY (booking_type) REFERENCES fs.booking_type_select (booking_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_bookings ADD CONSTRAINT fk_mpc_bookings_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_branch_access ADD CONSTRAINT fk_mpc_branch_access_member_package_customization_id FOREIGN KEY (member_package_customization_id) REFERENCES fs.member_package_customization (member_package_customization_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_branch_access ADD CONSTRAINT fk_mpc_branch_access_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_branch_access ADD CONSTRAINT fk_mpc_branch_access_granted_by_user_id FOREIGN KEY (granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_branch_access ADD CONSTRAINT fk_mpc_branch_access_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_free_pass ADD CONSTRAINT fk_mpc_free_pass_mpc_id FOREIGN KEY (mpc_id) REFERENCES fs.member_package_customization (member_package_customization_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_free_pass ADD CONSTRAINT fk_mpc_free_pass_tier_max_id_override FOREIGN KEY (tier_max_id_override) REFERENCES fs.vehicle_tier (vehicle_tier_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_free_pass ADD CONSTRAINT fk_mpc_free_pass_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_mileage ADD CONSTRAINT fk_mpc_mileage_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_mileage ADD CONSTRAINT fk_mpc_mileage_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_mileage ADD CONSTRAINT fk_mpc_mileage_mileage_type FOREIGN KEY (mileage_type) REFERENCES fs.mileage_type_select (mileage_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_mileage ADD CONSTRAINT fk_mpc_mileage_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_perks ADD CONSTRAINT fk_mpc_perks_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_perks ADD CONSTRAINT fk_mpc_perks_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_perks ADD CONSTRAINT fk_mpc_perks_perk_type FOREIGN KEY (perk_type) REFERENCES fs.perk_type_select (perk_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_perks ADD CONSTRAINT fk_mpc_perks_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_points_and_caps ADD CONSTRAINT fk_mpc_points_and_caps_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_points_and_caps ADD CONSTRAINT fk_mpc_points_and_caps_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_points_and_caps ADD CONSTRAINT fk_mpc_points_and_caps_points_cap_type FOREIGN KEY (points_cap_type) REFERENCES fs.points_cap_type_select (points_cap_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_points_and_caps ADD CONSTRAINT fk_mpc_points_and_caps_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_pricing ADD CONSTRAINT fk_mpc_pricing_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_pricing ADD CONSTRAINT fk_mpc_pricing_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_pricing ADD CONSTRAINT fk_mpc_pricing_pricing_type FOREIGN KEY (pricing_type) REFERENCES fs.pricing_type_select (pricing_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_pricing ADD CONSTRAINT fk_mpc_pricing_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_tier_assignment ADD CONSTRAINT fk_mpc_tier_assignment_member_package_customization_id FOREIGN KEY (member_package_customization_id) REFERENCES fs.member_package_customization (member_package_customization_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_tier_assignment ADD CONSTRAINT fk_mpc_tier_assignment_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_tier_assignment ADD CONSTRAINT fk_mpc_tier_assignment_vehicle_tier_id_override FOREIGN KEY (vehicle_tier_id_override) REFERENCES fs.vehicle_tier (vehicle_tier_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_tier_assignment ADD CONSTRAINT fk_mpc_tier_assignment_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_tier_point_rate ADD CONSTRAINT fk_mpc_tier_point_rate_member_package_customization_id FOREIGN KEY (member_package_customization_id) REFERENCES fs.member_package_customization (member_package_customization_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_tier_point_rate ADD CONSTRAINT fk_mpc_tier_point_rate_vehicle_tier_id FOREIGN KEY (vehicle_tier_id) REFERENCES fs.vehicle_tier (vehicle_tier_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_tier_point_rate ADD CONSTRAINT fk_mpc_tier_point_rate_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_vehicle_tier_access ADD CONSTRAINT fk_mpc_vehicle_tier_access_member_package_customization_id FOREIGN KEY (member_package_customization_id) REFERENCES fs.member_package_customization (member_package_customization_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_vehicle_tier_access ADD CONSTRAINT fk_mpc_vehicle_tier_access_vehicle_tier_id FOREIGN KEY (vehicle_tier_id) REFERENCES fs.vehicle_tier (vehicle_tier_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mpc_vehicle_tier_access ADD CONSTRAINT fk_mpc_vehicle_tier_access_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.perk_type_select ADD CONSTRAINT fk_perk_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.perk_type_select ADD CONSTRAINT fk_perk_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.points_cap_type_select ADD CONSTRAINT fk_points_cap_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.points_cap_type_select ADD CONSTRAINT fk_points_cap_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.pricing_type_select ADD CONSTRAINT fk_pricing_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.pricing_type_select ADD CONSTRAINT fk_pricing_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card ADD CONSTRAINT fk_rate_card_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card ADD CONSTRAINT fk_rate_card_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_placement ADD CONSTRAINT fk_rate_card_placement_rate_card_id FOREIGN KEY (rate_card_id) REFERENCES fs.rate_card (rate_card_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_placement ADD CONSTRAINT fk_rate_card_placement_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_placement ADD CONSTRAINT fk_rate_card_placement_vehicle_tier_id FOREIGN KEY (vehicle_tier_id) REFERENCES fs.vehicle_tier (vehicle_tier_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_placement ADD CONSTRAINT fk_rate_card_placement_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_placement ADD CONSTRAINT fk_rate_card_placement_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_rate ADD CONSTRAINT fk_rate_card_rate_rate_card_id FOREIGN KEY (rate_card_id) REFERENCES fs.rate_card (rate_card_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_rate ADD CONSTRAINT fk_rate_card_rate_vehicle_tier_id FOREIGN KEY (vehicle_tier_id) REFERENCES fs.vehicle_tier (vehicle_tier_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_rate ADD CONSTRAINT fk_rate_card_rate_rate_card_season_id FOREIGN KEY (rate_card_season_id) REFERENCES fs.rate_card_season (rate_card_season_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_rate ADD CONSTRAINT fk_rate_card_rate_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_rate ADD CONSTRAINT fk_rate_card_rate_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_season ADD CONSTRAINT fk_rate_card_season_rate_card_id FOREIGN KEY (rate_card_id) REFERENCES fs.rate_card (rate_card_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_season ADD CONSTRAINT fk_rate_card_season_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.rate_card_season ADD CONSTRAINT fk_rate_card_season_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier ADD CONSTRAINT fk_vehicle_tier_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier ADD CONSTRAINT fk_vehicle_tier_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier_access ADD CONSTRAINT fk_vehicle_tier_access_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier_access ADD CONSTRAINT fk_vehicle_tier_access_vehicle_tier_id FOREIGN KEY (vehicle_tier_id) REFERENCES fs.vehicle_tier (vehicle_tier_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier_access ADD CONSTRAINT fk_vehicle_tier_access_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier_access ADD CONSTRAINT fk_vehicle_tier_access_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification ADD CONSTRAINT fk_notification_template_id FOREIGN KEY (template_id) REFERENCES fs.notification_template (notification_template_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification ADD CONSTRAINT fk_notification_recipient_user_id FOREIGN KEY (recipient_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification ADD CONSTRAINT fk_notification_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification ADD CONSTRAINT fk_notification_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_delivery_log ADD CONSTRAINT fk_notification_delivery_log_notification_id FOREIGN KEY (notification_id) REFERENCES fs.notification (notification_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_delivery_log ADD CONSTRAINT fk_notification_delivery_log_provider FOREIGN KEY (provider) REFERENCES fs.integration_provider (integration_provider_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_delivery_log ADD CONSTRAINT fk_notification_delivery_log_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_delivery_log ADD CONSTRAINT fk_notification_delivery_log_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_preference ADD CONSTRAINT fk_notification_preference_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_preference ADD CONSTRAINT fk_notification_preference_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_preference ADD CONSTRAINT fk_notification_preference_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_template ADD CONSTRAINT fk_notification_template_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_template ADD CONSTRAINT fk_notification_template_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_template_variable ADD CONSTRAINT fk_notification_template_variable_template_id FOREIGN KEY (template_id) REFERENCES fs.notification_template (notification_template_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_template_variable ADD CONSTRAINT fk_notification_template_variable_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.notification_template_variable ADD CONSTRAINT fk_notification_template_variable_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.credit_reason_type ADD CONSTRAINT fk_credit_reason_type_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.credit_reason_type ADD CONSTRAINT fk_credit_reason_type_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_credit ADD CONSTRAINT fk_member_perk_credit_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_credit ADD CONSTRAINT fk_member_perk_credit_perk_type FOREIGN KEY (perk_type) REFERENCES fs.perk_type_select (perk_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_credit ADD CONSTRAINT fk_member_perk_credit_credit_reason_type_code FOREIGN KEY (credit_reason_type_code) REFERENCES fs.credit_reason_type (credit_reason_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_credit ADD CONSTRAINT fk_member_perk_credit_approved_by_user_id FOREIGN KEY (approved_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_credit ADD CONSTRAINT fk_member_perk_credit_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_credit ADD CONSTRAINT fk_member_perk_credit_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_ledger ADD CONSTRAINT fk_member_perk_ledger_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_ledger ADD CONSTRAINT fk_member_perk_ledger_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_ledger ADD CONSTRAINT fk_member_perk_ledger_perk_type FOREIGN KEY (perk_type) REFERENCES fs.perk_type_select (perk_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_ledger ADD CONSTRAINT fk_member_perk_ledger_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_ledger ADD CONSTRAINT fk_member_perk_ledger_member_package_participant_id FOREIGN KEY (member_package_participant_id) REFERENCES fs.member_package_participant (member_package_participant_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_ledger ADD CONSTRAINT fk_member_perk_ledger_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_perk_ledger ADD CONSTRAINT fk_member_perk_ledger_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_point_credit ADD CONSTRAINT fk_member_point_credit_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_point_credit ADD CONSTRAINT fk_member_point_credit_credit_reason_type_code FOREIGN KEY (credit_reason_type_code) REFERENCES fs.credit_reason_type (credit_reason_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_point_credit ADD CONSTRAINT fk_member_point_credit_approved_by_user_id FOREIGN KEY (approved_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_point_credit ADD CONSTRAINT fk_member_point_credit_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_point_credit ADD CONSTRAINT fk_member_point_credit_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_carryover ADD CONSTRAINT fk_member_points_carryover_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_carryover ADD CONSTRAINT fk_member_points_carryover_source_package_id FOREIGN KEY (source_package_id) REFERENCES fs.member_package (member_package_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_carryover ADD CONSTRAINT fk_member_points_carryover_allocation_package_id FOREIGN KEY (allocation_package_id) REFERENCES fs.member_package (member_package_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_carryover ADD CONSTRAINT fk_member_points_carryover_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_carryover ADD CONSTRAINT fk_member_points_carryover_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_ledger ADD CONSTRAINT fk_member_points_ledger_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_ledger ADD CONSTRAINT fk_member_points_ledger_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_ledger ADD CONSTRAINT fk_member_points_ledger_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_ledger ADD CONSTRAINT fk_member_points_ledger_reservation_perk_application_id FOREIGN KEY (reservation_perk_application_id) REFERENCES fs.reservation_perk_application (reservation_perk_application_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_ledger ADD CONSTRAINT fk_member_points_ledger_member_package_participant_id FOREIGN KEY (member_package_participant_id) REFERENCES fs.member_package_participant (member_package_participant_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_ledger ADD CONSTRAINT fk_member_points_ledger_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_points_ledger ADD CONSTRAINT fk_member_points_ledger_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_destination_select ADD CONSTRAINT fk_export_destination_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_destination_select ADD CONSTRAINT fk_export_destination_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_format_select ADD CONSTRAINT fk_export_format_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_format_select ADD CONSTRAINT fk_export_format_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_job ADD CONSTRAINT fk_export_job_requested_by_user_id FOREIGN KEY (requested_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_job ADD CONSTRAINT fk_export_job_export_template_id FOREIGN KEY (export_template_id) REFERENCES fs.export_template (export_template_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_job ADD CONSTRAINT fk_export_job_export_format_code FOREIGN KEY (export_format_code) REFERENCES fs.export_format_select (export_format_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_job ADD CONSTRAINT fk_export_job_export_destination_code FOREIGN KEY (export_destination_code) REFERENCES fs.export_destination_select (export_destination_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_job ADD CONSTRAINT fk_export_job_approved_by_user_id FOREIGN KEY (approved_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_schedule ADD CONSTRAINT fk_export_schedule_export_template_id FOREIGN KEY (export_template_id) REFERENCES fs.export_template (export_template_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_schedule ADD CONSTRAINT fk_export_schedule_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_schedule ADD CONSTRAINT fk_export_schedule_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_schedule_recipient ADD CONSTRAINT fk_export_schedule_recipient_export_schedule_id FOREIGN KEY (export_schedule_id) REFERENCES fs.export_schedule (export_schedule_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_schedule_recipient ADD CONSTRAINT fk_export_schedule_recipient_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_schedule_recipient ADD CONSTRAINT fk_export_schedule_recipient_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_schedule_recipient ADD CONSTRAINT fk_export_schedule_recipient_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_template ADD CONSTRAINT fk_export_template_export_format_code FOREIGN KEY (export_format_code) REFERENCES fs.export_format_select (export_format_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_template ADD CONSTRAINT fk_export_template_export_destination_code FOREIGN KEY (export_destination_code) REFERENCES fs.export_destination_select (export_destination_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_template ADD CONSTRAINT fk_export_template_required_permission_code FOREIGN KEY (required_permission_code) REFERENCES fs.permission (permission_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_template ADD CONSTRAINT fk_export_template_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.export_template ADD CONSTRAINT fk_export_template_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.report_definition ADD CONSTRAINT fk_report_definition_required_permission_code FOREIGN KEY (required_permission_code) REFERENCES fs.permission (permission_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.report_definition ADD CONSTRAINT fk_report_definition_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.report_definition ADD CONSTRAINT fk_report_definition_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.report_job ADD CONSTRAINT fk_report_job_requested_by_user_id FOREIGN KEY (requested_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.report_schedule ADD CONSTRAINT fk_report_schedule_report_definition_id FOREIGN KEY (report_definition_id) REFERENCES fs.report_definition (report_definition_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.report_schedule ADD CONSTRAINT fk_report_schedule_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.report_schedule ADD CONSTRAINT fk_report_schedule_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account_shadow ADD CONSTRAINT fk_corporate_account_shadow_home_branch_id FOREIGN KEY (home_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account_shadow ADD CONSTRAINT fk_corporate_account_shadow_billing_state FOREIGN KEY (billing_state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account_shadow ADD CONSTRAINT fk_corporate_account_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account_shadow ADD CONSTRAINT fk_corporate_account_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account_shadow ADD CONSTRAINT fk_corporate_account_shadow_corporate_account_id FOREIGN KEY (corporate_account_id) REFERENCES fs.corporate_account (corporate_account_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.corporate_account_shadow ADD CONSTRAINT fk_corporate_account_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_customization_shadow ADD CONSTRAINT fk_member_package_customization_shadow_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_customization_shadow ADD CONSTRAINT fk_member_package_customization_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_customization_shadow ADD CONSTRAINT fk_member_package_customization_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_customization_shadow ADD CONSTRAINT fk_member_package_customization_shadow_member_package_customiza FOREIGN KEY (member_package_customization_id) REFERENCES fs.member_package_customization (member_package_customization_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_customization_shadow ADD CONSTRAINT fk_member_package_customization_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_shadow ADD CONSTRAINT fk_member_package_shadow_member_package_id FOREIGN KEY (member_package_id) REFERENCES fs.member_package (member_package_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_shadow ADD CONSTRAINT fk_member_package_shadow_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_shadow ADD CONSTRAINT fk_member_package_shadow_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_shadow ADD CONSTRAINT fk_member_package_shadow_corporate_account_id FOREIGN KEY (corporate_account_id) REFERENCES fs.corporate_account (corporate_account_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_shadow ADD CONSTRAINT fk_member_package_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_shadow ADD CONSTRAINT fk_member_package_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_package_shadow ADD CONSTRAINT fk_member_package_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_payment_schedule_shadow ADD CONSTRAINT fk_member_payment_schedule_shadow_member_package_id FOREIGN KEY (member_package_id) REFERENCES fs.member_package (member_package_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_payment_schedule_shadow ADD CONSTRAINT fk_member_payment_schedule_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_payment_schedule_shadow ADD CONSTRAINT fk_member_payment_schedule_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_payment_schedule_shadow ADD CONSTRAINT fk_member_payment_schedule_shadow_member_payment_schedule_id FOREIGN KEY (member_payment_schedule_id) REFERENCES fs.member_payment_schedule (member_payment_schedule_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_payment_schedule_shadow ADD CONSTRAINT fk_member_payment_schedule_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_shadow ADD CONSTRAINT fk_member_shadow_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_shadow ADD CONSTRAINT fk_member_shadow_home_branch_id FOREIGN KEY (home_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_shadow ADD CONSTRAINT fk_member_shadow_license_state FOREIGN KEY (license_state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_shadow ADD CONSTRAINT fk_member_shadow_podium_status FOREIGN KEY (podium_status) REFERENCES fs.podium_status_select (podium_status_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_shadow ADD CONSTRAINT fk_member_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_shadow ADD CONSTRAINT fk_member_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_shadow ADD CONSTRAINT fk_member_shadow_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.member_shadow ADD CONSTRAINT fk_member_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_bookings_shadow ADD CONSTRAINT fk_membership_level_bookings_shadow_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_bookings_shadow ADD CONSTRAINT fk_membership_level_bookings_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_bookings_shadow ADD CONSTRAINT fk_membership_level_bookings_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_bookings_shadow ADD CONSTRAINT fk_membership_level_bookings_shadow_membership_level_bookings_i FOREIGN KEY (membership_level_bookings_id) REFERENCES fs.membership_level_bookings (membership_level_bookings_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_bookings_shadow ADD CONSTRAINT fk_membership_level_bookings_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_free_pass_shadow ADD CONSTRAINT fk_membership_level_free_pass_shadow_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_free_pass_shadow ADD CONSTRAINT fk_membership_level_free_pass_shadow_tier_max_id FOREIGN KEY (tier_max_id) REFERENCES fs.vehicle_tier (vehicle_tier_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_free_pass_shadow ADD CONSTRAINT fk_membership_level_free_pass_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_free_pass_shadow ADD CONSTRAINT fk_membership_level_free_pass_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_free_pass_shadow ADD CONSTRAINT fk_membership_level_free_pass_shadow_membership_level_free_pass FOREIGN KEY (membership_level_free_pass_id) REFERENCES fs.membership_level_free_pass (membership_level_free_pass_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_free_pass_shadow ADD CONSTRAINT fk_membership_level_free_pass_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_mileage_shadow ADD CONSTRAINT fk_membership_level_mileage_shadow_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_mileage_shadow ADD CONSTRAINT fk_membership_level_mileage_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_mileage_shadow ADD CONSTRAINT fk_membership_level_mileage_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_mileage_shadow ADD CONSTRAINT fk_membership_level_mileage_shadow_membership_level_mileage_id FOREIGN KEY (membership_level_mileage_id) REFERENCES fs.membership_level_mileage (membership_level_mileage_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_mileage_shadow ADD CONSTRAINT fk_membership_level_mileage_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_perks_shadow ADD CONSTRAINT fk_membership_level_perks_shadow_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_perks_shadow ADD CONSTRAINT fk_membership_level_perks_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_perks_shadow ADD CONSTRAINT fk_membership_level_perks_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_perks_shadow ADD CONSTRAINT fk_membership_level_perks_shadow_membership_level_perks_id FOREIGN KEY (membership_level_perks_id) REFERENCES fs.membership_level_perks (membership_level_perks_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_perks_shadow ADD CONSTRAINT fk_membership_level_perks_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_points_caps_shadow ADD CONSTRAINT fk_membership_level_points_caps_shadow_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_points_caps_shadow ADD CONSTRAINT fk_membership_level_points_caps_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_points_caps_shadow ADD CONSTRAINT fk_membership_level_points_caps_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_points_caps_shadow ADD CONSTRAINT fk_membership_level_points_caps_shadow_membership_level_points_ FOREIGN KEY (membership_level_points_caps_id) REFERENCES fs.membership_level_points_caps (membership_level_points_caps_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_points_caps_shadow ADD CONSTRAINT fk_membership_level_points_caps_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_shadow ADD CONSTRAINT fk_membership_level_shadow_membership_series_id FOREIGN KEY (membership_series_id) REFERENCES fs.membership_series (membership_series_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_shadow ADD CONSTRAINT fk_membership_level_shadow_membership_level_type_code FOREIGN KEY (membership_level_type_code) REFERENCES fs.membership_level_type_select (membership_level_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_shadow ADD CONSTRAINT fk_membership_level_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_shadow ADD CONSTRAINT fk_membership_level_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_shadow ADD CONSTRAINT fk_membership_level_shadow_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.membership_level_shadow ADD CONSTRAINT fk_membership_level_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role_shadow ADD CONSTRAINT fk_role_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role_shadow ADD CONSTRAINT fk_role_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role_shadow ADD CONSTRAINT fk_role_shadow_role_id FOREIGN KEY (role_id) REFERENCES fs.role (role_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role_shadow ADD CONSTRAINT fk_role_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_shadow ADD CONSTRAINT fk_staff_shadow_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_shadow ADD CONSTRAINT fk_staff_shadow_home_branch_id FOREIGN KEY (home_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_shadow ADD CONSTRAINT fk_staff_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_shadow ADD CONSTRAINT fk_staff_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_shadow ADD CONSTRAINT fk_staff_shadow_license_state FOREIGN KEY (license_state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_shadow ADD CONSTRAINT fk_staff_shadow_staff_id FOREIGN KEY (staff_id) REFERENCES fs.staff (staff_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_shadow ADD CONSTRAINT fk_staff_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_shadow ADD CONSTRAINT fk_user_shadow_mfa_method_code FOREIGN KEY (mfa_method_code) REFERENCES fs.mfa_method_select (mfa_method_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_shadow ADD CONSTRAINT fk_user_shadow_default_view_code FOREIGN KEY (default_view_code) REFERENCES fs.user_view_select (user_view_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_shadow ADD CONSTRAINT fk_user_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_shadow ADD CONSTRAINT fk_user_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_shadow ADD CONSTRAINT fk_user_shadow_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_shadow ADD CONSTRAINT fk_user_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_financing_lifecycle_shadow ADD CONSTRAINT fk_vehicle_financing_lifecycle_shadow_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_financing_lifecycle_shadow ADD CONSTRAINT fk_vehicle_financing_lifecycle_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_financing_lifecycle_shadow ADD CONSTRAINT fk_vehicle_financing_lifecycle_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_financing_lifecycle_shadow ADD CONSTRAINT fk_vehicle_financing_lifecycle_shadow_vehicle_financing_lifecyc FOREIGN KEY (vehicle_financing_lifecycle_id) REFERENCES fs.vehicle_financing_lifecycle (vehicle_financing_lifecycle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_financing_lifecycle_shadow ADD CONSTRAINT fk_vehicle_financing_lifecycle_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_partner_shadow ADD CONSTRAINT fk_vehicle_partner_shadow_state FOREIGN KEY (state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_partner_shadow ADD CONSTRAINT fk_vehicle_partner_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_partner_shadow ADD CONSTRAINT fk_vehicle_partner_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_partner_shadow ADD CONSTRAINT fk_vehicle_partner_shadow_vehicle_partner_id FOREIGN KEY (vehicle_partner_id) REFERENCES fs.vehicle_partner (vehicle_partner_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_partner_shadow ADD CONSTRAINT fk_vehicle_partner_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_registration_warranty_shadow ADD CONSTRAINT fk_vehicle_registration_warranty_shadow_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_registration_warranty_shadow ADD CONSTRAINT fk_vehicle_registration_warranty_shadow_registration_state FOREIGN KEY (registration_state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_registration_warranty_shadow ADD CONSTRAINT fk_vehicle_registration_warranty_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_registration_warranty_shadow ADD CONSTRAINT fk_vehicle_registration_warranty_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_registration_warranty_shadow ADD CONSTRAINT fk_vehicle_registration_warranty_shadow_vehicle_registration_wa FOREIGN KEY (vehicle_registration_warranty_id) REFERENCES fs.vehicle_registration_warranty (vehicle_registration_warranty_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_registration_warranty_shadow ADD CONSTRAINT fk_vehicle_registration_warranty_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_shadow ADD CONSTRAINT fk_vehicle_shadow_vehicle_make_code FOREIGN KEY (vehicle_make_code) REFERENCES fs.vehicle_make_select (vehicle_make_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_shadow ADD CONSTRAINT fk_vehicle_shadow_year FOREIGN KEY (year) REFERENCES fs.vehicle_year_select (vehicle_year_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_shadow ADD CONSTRAINT fk_vehicle_shadow_exterior_color_short FOREIGN KEY (exterior_color_short) REFERENCES fs.vehicle_color_select (vehicle_color_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_shadow ADD CONSTRAINT fk_vehicle_shadow_interior_color FOREIGN KEY (interior_color) REFERENCES fs.vehicle_color_select (vehicle_color_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_shadow ADD CONSTRAINT fk_vehicle_shadow_condition_code FOREIGN KEY (condition_code) REFERENCES fs.vehicle_condition_code (condition_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_shadow ADD CONSTRAINT fk_vehicle_shadow_home_branch_id FOREIGN KEY (home_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_shadow ADD CONSTRAINT fk_vehicle_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_shadow ADD CONSTRAINT fk_vehicle_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_shadow ADD CONSTRAINT fk_vehicle_shadow_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_shadow ADD CONSTRAINT fk_vehicle_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier_access_shadow ADD CONSTRAINT fk_vehicle_tier_access_shadow_membership_level_id FOREIGN KEY (membership_level_id) REFERENCES fs.membership_level (membership_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier_access_shadow ADD CONSTRAINT fk_vehicle_tier_access_shadow_vehicle_tier_id FOREIGN KEY (vehicle_tier_id) REFERENCES fs.vehicle_tier (vehicle_tier_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier_access_shadow ADD CONSTRAINT fk_vehicle_tier_access_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier_access_shadow ADD CONSTRAINT fk_vehicle_tier_access_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier_access_shadow ADD CONSTRAINT fk_vehicle_tier_access_shadow_vehicle_tier_access_id FOREIGN KEY (vehicle_tier_access_id) REFERENCES fs.vehicle_tier_access (vehicle_tier_access_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tier_access_shadow ADD CONSTRAINT fk_vehicle_tier_access_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_shadow ADD CONSTRAINT fk_vendor_shadow_home_branch_id FOREIGN KEY (home_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_shadow ADD CONSTRAINT fk_vendor_shadow_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_shadow ADD CONSTRAINT fk_vendor_shadow_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_shadow ADD CONSTRAINT fk_vendor_shadow_vendor_type_code FOREIGN KEY (vendor_type_code) REFERENCES fs.vendor_type_select (vendor_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_shadow ADD CONSTRAINT fk_vendor_shadow_state FOREIGN KEY (state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_shadow ADD CONSTRAINT fk_vendor_shadow_vendor_id FOREIGN KEY (vendor_id) REFERENCES fs.vendor (vendor_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_shadow ADD CONSTRAINT fk_vendor_shadow_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff ADD CONSTRAINT fk_staff_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff ADD CONSTRAINT fk_staff_home_branch_id FOREIGN KEY (home_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff ADD CONSTRAINT fk_staff_license_state FOREIGN KEY (license_state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff ADD CONSTRAINT fk_staff_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff ADD CONSTRAINT fk_staff_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_email ADD CONSTRAINT fk_staff_email_staff_id FOREIGN KEY (staff_id) REFERENCES fs.staff (staff_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_email ADD CONSTRAINT fk_staff_email_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_email ADD CONSTRAINT fk_staff_email_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_phone ADD CONSTRAINT fk_staff_phone_staff_id FOREIGN KEY (staff_id) REFERENCES fs.staff (staff_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_phone ADD CONSTRAINT fk_staff_phone_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.staff_phone ADD CONSTRAINT fk_staff_phone_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.day_of_month_select ADD CONSTRAINT fk_day_of_month_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.day_of_month_select ADD CONSTRAINT fk_day_of_month_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.day_of_week_select ADD CONSTRAINT fk_day_of_week_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.day_of_week_select ADD CONSTRAINT fk_day_of_week_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.holiday_definition ADD CONSTRAINT fk_holiday_definition_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.holiday_definition ADD CONSTRAINT fk_holiday_definition_restricted_date_type_code FOREIGN KEY (restricted_date_type_code) REFERENCES fs.restricted_date_type_select (restricted_date_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.holiday_definition ADD CONSTRAINT fk_holiday_definition_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.holiday_definition ADD CONSTRAINT fk_holiday_definition_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.month_select ADD CONSTRAINT fk_month_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.month_select ADD CONSTRAINT fk_month_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.platform_setting ADD CONSTRAINT fk_platform_setting_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.platform_setting ADD CONSTRAINT fk_platform_setting_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.restricted_date_type_select ADD CONSTRAINT fk_restricted_date_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.restricted_date_type_select ADD CONSTRAINT fk_restricted_date_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.state_select ADD CONSTRAINT fk_state_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.state_select ADD CONSTRAINT fk_state_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.target_table_select ADD CONSTRAINT fk_target_table_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.target_table_select ADD CONSTRAINT fk_target_table_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.timezone_select ADD CONSTRAINT fk_timezone_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.timezone_select ADD CONSTRAINT fk_timezone_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task ADD CONSTRAINT fk_task_task_status_code FOREIGN KEY (task_status_code) REFERENCES fs.task_status (task_status_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task ADD CONSTRAINT fk_task_task_priority_code FOREIGN KEY (task_priority_code) REFERENCES fs.task_priority (task_priority_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task ADD CONSTRAINT fk_task_task_type_code FOREIGN KEY (task_type_code) REFERENCES fs.task_type_select (task_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task ADD CONSTRAINT fk_task_assigned_to_user_id FOREIGN KEY (assigned_to_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task ADD CONSTRAINT fk_task_cancelled_by_user_id FOREIGN KEY (cancelled_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task ADD CONSTRAINT fk_task_assigned_by_user_id FOREIGN KEY (assigned_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task ADD CONSTRAINT fk_task_verified_by_user_id FOREIGN KEY (verified_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task ADD CONSTRAINT fk_task_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task ADD CONSTRAINT fk_task_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_assignment ADD CONSTRAINT fk_task_assignment_task_id FOREIGN KEY (task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_assignment ADD CONSTRAINT fk_task_assignment_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_assignment ADD CONSTRAINT fk_task_assignment_role_id FOREIGN KEY (role_id) REFERENCES fs.role (role_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_assignment ADD CONSTRAINT fk_task_assignment_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_assignment ADD CONSTRAINT fk_task_assignment_assigned_by_user_id FOREIGN KEY (assigned_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_assignment ADD CONSTRAINT fk_task_assignment_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_assignment ADD CONSTRAINT fk_task_assignment_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_audit_log ADD CONSTRAINT fk_task_audit_log_task_id FOREIGN KEY (task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_audit_log ADD CONSTRAINT fk_task_audit_log_actor_user_id FOREIGN KEY (actor_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_checklist_item ADD CONSTRAINT fk_task_checklist_item_task_id FOREIGN KEY (task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_checklist_item ADD CONSTRAINT fk_task_checklist_item_assigned_to_user_id FOREIGN KEY (assigned_to_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_checklist_item ADD CONSTRAINT fk_task_checklist_item_depends_on_item_id FOREIGN KEY (depends_on_item_id) REFERENCES fs.task_checklist_item (task_checklist_item_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_checklist_item ADD CONSTRAINT fk_task_checklist_item_completed_by_user_id FOREIGN KEY (completed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_checklist_item ADD CONSTRAINT fk_task_checklist_item_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_checklist_item ADD CONSTRAINT fk_task_checklist_item_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_comment ADD CONSTRAINT fk_task_comment_task_id FOREIGN KEY (task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_comment ADD CONSTRAINT fk_task_comment_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_dependency ADD CONSTRAINT fk_task_dependency_task_id FOREIGN KEY (task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_dependency ADD CONSTRAINT fk_task_dependency_depends_on_task_id FOREIGN KEY (depends_on_task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_dependency ADD CONSTRAINT fk_task_dependency_assigned_by_user_id FOREIGN KEY (assigned_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_dependency ADD CONSTRAINT fk_task_dependency_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_dependency ADD CONSTRAINT fk_task_dependency_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_log ADD CONSTRAINT fk_task_escalation_log_task_id FOREIGN KEY (task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_log ADD CONSTRAINT fk_task_escalation_log_task_escalation_path_level_id FOREIGN KEY (task_escalation_path_level_id) REFERENCES fs.task_escalation_path_level (task_escalation_path_level_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_log ADD CONSTRAINT fk_task_escalation_log_role_id FOREIGN KEY (role_id) REFERENCES fs.role (role_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_log ADD CONSTRAINT fk_task_escalation_log_escalated_to_user_id FOREIGN KEY (escalated_to_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_log ADD CONSTRAINT fk_task_escalation_log_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_log ADD CONSTRAINT fk_task_escalation_log_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_path ADD CONSTRAINT fk_task_escalation_path_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_path ADD CONSTRAINT fk_task_escalation_path_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_path_level ADD CONSTRAINT fk_task_escalation_path_level_task_escalation_path_id FOREIGN KEY (task_escalation_path_id) REFERENCES fs.task_escalation_path (task_escalation_path_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_path_level ADD CONSTRAINT fk_task_escalation_path_level_role_id FOREIGN KEY (role_id) REFERENCES fs.role (role_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_path_level ADD CONSTRAINT fk_task_escalation_path_level_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_escalation_path_level ADD CONSTRAINT fk_task_escalation_path_level_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_link ADD CONSTRAINT fk_task_link_task_id FOREIGN KEY (task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_link ADD CONSTRAINT fk_task_link_target_table FOREIGN KEY (target_table) REFERENCES fs.target_table_select (target_table_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_link ADD CONSTRAINT fk_task_link_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_link ADD CONSTRAINT fk_task_link_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_priority ADD CONSTRAINT fk_task_priority_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_priority ADD CONSTRAINT fk_task_priority_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_status ADD CONSTRAINT fk_task_status_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_status ADD CONSTRAINT fk_task_status_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_tag ADD CONSTRAINT fk_task_tag_task_id FOREIGN KEY (task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_tag ADD CONSTRAINT fk_task_tag_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_tag ADD CONSTRAINT fk_task_tag_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template ADD CONSTRAINT fk_task_template_default_task_type_code FOREIGN KEY (default_task_type_code) REFERENCES fs.task_type_select (task_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template ADD CONSTRAINT fk_task_template_default_priority_code FOREIGN KEY (default_priority_code) REFERENCES fs.task_priority (task_priority_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template ADD CONSTRAINT fk_task_template_default_assignee_user_id FOREIGN KEY (default_assignee_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template ADD CONSTRAINT fk_task_template_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template ADD CONSTRAINT fk_task_template_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template_step ADD CONSTRAINT fk_task_template_step_task_template_id FOREIGN KEY (task_template_id) REFERENCES fs.task_template (task_template_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template_step ADD CONSTRAINT fk_task_template_step_default_task_type_code FOREIGN KEY (default_task_type_code) REFERENCES fs.task_type_select (task_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template_step ADD CONSTRAINT fk_task_template_step_default_priority_code FOREIGN KEY (default_priority_code) REFERENCES fs.task_priority (task_priority_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template_step ADD CONSTRAINT fk_task_template_step_default_assignee_user_id FOREIGN KEY (default_assignee_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template_step ADD CONSTRAINT fk_task_template_step_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template_step ADD CONSTRAINT fk_task_template_step_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template_step_dependency ADD CONSTRAINT fk_task_template_step_dependency_task_template_step_id FOREIGN KEY (task_template_step_id) REFERENCES fs.task_template_step (task_template_step_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template_step_dependency ADD CONSTRAINT fk_task_template_step_dependency_depends_on_step_id FOREIGN KEY (depends_on_step_id) REFERENCES fs.task_template_step (task_template_step_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template_step_dependency ADD CONSTRAINT fk_task_template_step_dependency_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_template_step_dependency ADD CONSTRAINT fk_task_template_step_dependency_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_type_select ADD CONSTRAINT fk_task_type_select_task_escalation_path_id FOREIGN KEY (task_escalation_path_id) REFERENCES fs.task_escalation_path (task_escalation_path_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_type_select ADD CONSTRAINT fk_task_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.task_type_select ADD CONSTRAINT fk_task_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.access_event_type_select ADD CONSTRAINT fk_access_event_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.access_event_type_select ADD CONSTRAINT fk_access_event_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.access_log ADD CONSTRAINT fk_access_log_access_event_type_code FOREIGN KEY (access_event_type_code) REFERENCES fs.access_event_type_select (access_event_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.access_log ADD CONSTRAINT fk_access_log_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.access_log ADD CONSTRAINT fk_access_log_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.access_log ADD CONSTRAINT fk_access_log_permission_code FOREIGN KEY (permission_code) REFERENCES fs.permission (permission_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.access_log ADD CONSTRAINT fk_access_log_export_entity_type FOREIGN KEY (export_entity_type) REFERENCES fs.target_table_select (target_table_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.access_log ADD CONSTRAINT fk_access_log_export_format_code FOREIGN KEY (export_format_code) REFERENCES fs.export_format_select (export_format_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.access_log ADD CONSTRAINT fk_access_log_export_destination_code FOREIGN KEY (export_destination_code) REFERENCES fs.export_destination_select (export_destination_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mfa_method_select ADD CONSTRAINT fk_mfa_method_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.mfa_method_select ADD CONSTRAINT fk_mfa_method_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.permission ADD CONSTRAINT fk_permission_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.permission ADD CONSTRAINT fk_permission_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role ADD CONSTRAINT fk_role_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role ADD CONSTRAINT fk_role_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role_permission ADD CONSTRAINT fk_role_permission_role_id FOREIGN KEY (role_id) REFERENCES fs.role (role_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role_permission ADD CONSTRAINT fk_role_permission_permission_id FOREIGN KEY (permission_id) REFERENCES fs.permission (permission_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role_permission ADD CONSTRAINT fk_role_permission_granted_by_user_id FOREIGN KEY (granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role_permission ADD CONSTRAINT fk_role_permission_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role_permission ADD CONSTRAINT fk_role_permission_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.role_permission ADD CONSTRAINT fk_role_permission_revoked_by_user_id FOREIGN KEY (revoked_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs."user" ADD CONSTRAINT fk_user_mfa_method_code FOREIGN KEY (mfa_method_code) REFERENCES fs.mfa_method_select (mfa_method_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs."user" ADD CONSTRAINT fk_user_default_view_code FOREIGN KEY (default_view_code) REFERENCES fs.user_view_select (user_view_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs."user" ADD CONSTRAINT fk_user_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs."user" ADD CONSTRAINT fk_user_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_device ADD CONSTRAINT fk_user_device_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_device ADD CONSTRAINT fk_user_device_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_device ADD CONSTRAINT fk_user_device_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_mfa_recovery_code ADD CONSTRAINT fk_user_mfa_recovery_code_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_mfa_recovery_code ADD CONSTRAINT fk_user_mfa_recovery_code_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_mfa_recovery_code ADD CONSTRAINT fk_user_mfa_recovery_code_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_role ADD CONSTRAINT fk_user_role_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_role ADD CONSTRAINT fk_user_role_role_id FOREIGN KEY (role_id) REFERENCES fs.role (role_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_role ADD CONSTRAINT fk_user_role_granted_by_user_id FOREIGN KEY (granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_role ADD CONSTRAINT fk_user_role_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_role ADD CONSTRAINT fk_user_role_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_role ADD CONSTRAINT fk_user_role_revoked_by_user_id FOREIGN KEY (revoked_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_trusted_device ADD CONSTRAINT fk_user_trusted_device_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_trusted_device ADD CONSTRAINT fk_user_trusted_device_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_trusted_device ADD CONSTRAINT fk_user_trusted_device_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_view_select ADD CONSTRAINT fk_user_view_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.user_view_select ADD CONSTRAINT fk_user_view_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection ADD CONSTRAINT fk_vehicle_inspection_vehicle_event_id FOREIGN KEY (vehicle_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection ADD CONSTRAINT fk_vehicle_inspection_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection ADD CONSTRAINT fk_vehicle_inspection_inspection_type FOREIGN KEY (inspection_type) REFERENCES fs.vehicle_inspection_type (inspection_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection ADD CONSTRAINT fk_vehicle_inspection_vehicle_odometer_id FOREIGN KEY (vehicle_odometer_id) REFERENCES fs.vehicle_odometer_log (vehicle_odometer_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection ADD CONSTRAINT fk_vehicle_inspection_source_type_code FOREIGN KEY (source_type_code) REFERENCES fs.vehicle_source_type (source_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection ADD CONSTRAINT fk_vehicle_inspection_inspector_user_id FOREIGN KEY (inspector_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection ADD CONSTRAINT fk_vehicle_inspection_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection ADD CONSTRAINT fk_vehicle_inspection_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkin ADD CONSTRAINT fk_vehicle_inspection_checkin_vehicle_event_id FOREIGN KEY (vehicle_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkin ADD CONSTRAINT fk_vehicle_inspection_checkin_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkin ADD CONSTRAINT fk_vehicle_inspection_checkin_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkin ADD CONSTRAINT fk_vehicle_inspection_checkin_vehicle_odometer_id FOREIGN KEY (vehicle_odometer_id) REFERENCES fs.vehicle_odometer_log (vehicle_odometer_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkin ADD CONSTRAINT fk_vehicle_inspection_checkin_inspector_user_id FOREIGN KEY (inspector_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkin ADD CONSTRAINT fk_vehicle_inspection_checkin_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkin ADD CONSTRAINT fk_vehicle_inspection_checkin_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkout ADD CONSTRAINT fk_vehicle_inspection_checkout_vehicle_event_id FOREIGN KEY (vehicle_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkout ADD CONSTRAINT fk_vehicle_inspection_checkout_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkout ADD CONSTRAINT fk_vehicle_inspection_checkout_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkout ADD CONSTRAINT fk_vehicle_inspection_checkout_vehicle_odometer_id FOREIGN KEY (vehicle_odometer_id) REFERENCES fs.vehicle_odometer_log (vehicle_odometer_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkout ADD CONSTRAINT fk_vehicle_inspection_checkout_inspector_user_id FOREIGN KEY (inspector_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkout ADD CONSTRAINT fk_vehicle_inspection_checkout_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkout ADD CONSTRAINT fk_vehicle_inspection_checkout_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkup ADD CONSTRAINT fk_vehicle_inspection_checkup_inspection_id FOREIGN KEY (inspection_id) REFERENCES fs.vehicle_inspection (inspection_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkup ADD CONSTRAINT fk_vehicle_inspection_checkup_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkup ADD CONSTRAINT fk_vehicle_inspection_checkup_vehicle_odometer_id FOREIGN KEY (vehicle_odometer_id) REFERENCES fs.vehicle_odometer_log (vehicle_odometer_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkup ADD CONSTRAINT fk_vehicle_inspection_checkup_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_checkup ADD CONSTRAINT fk_vehicle_inspection_checkup_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_damage ADD CONSTRAINT fk_vehicle_inspection_damage_vehicle_event_id FOREIGN KEY (vehicle_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_damage ADD CONSTRAINT fk_vehicle_inspection_damage_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_damage ADD CONSTRAINT fk_vehicle_inspection_damage_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_damage ADD CONSTRAINT fk_vehicle_inspection_damage_inspection_issue_id FOREIGN KEY (inspection_issue_id) REFERENCES fs.vehicle_inspection_issue (inspection_issue_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_damage ADD CONSTRAINT fk_vehicle_inspection_damage_inspector_user_id FOREIGN KEY (inspector_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_damage ADD CONSTRAINT fk_vehicle_inspection_damage_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_damage ADD CONSTRAINT fk_vehicle_inspection_damage_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_fuel ADD CONSTRAINT fk_vehicle_inspection_fuel_vehicle_event_id FOREIGN KEY (vehicle_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_fuel ADD CONSTRAINT fk_vehicle_inspection_fuel_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_fuel ADD CONSTRAINT fk_vehicle_inspection_fuel_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_fuel ADD CONSTRAINT fk_vehicle_inspection_fuel_odometer_log_id FOREIGN KEY (odometer_log_id) REFERENCES fs.vehicle_odometer_log (vehicle_odometer_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_fuel ADD CONSTRAINT fk_vehicle_inspection_fuel_billed_member_id FOREIGN KEY (billed_member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_fuel ADD CONSTRAINT fk_vehicle_inspection_fuel_inspector_user_id FOREIGN KEY (inspector_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_fuel ADD CONSTRAINT fk_vehicle_inspection_fuel_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_fuel ADD CONSTRAINT fk_vehicle_inspection_fuel_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_initial ADD CONSTRAINT fk_vehicle_inspection_initial_vehicle_event_id FOREIGN KEY (vehicle_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_initial ADD CONSTRAINT fk_vehicle_inspection_initial_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_initial ADD CONSTRAINT fk_vehicle_inspection_initial_inspection_type_code FOREIGN KEY (inspection_type_code) REFERENCES fs.vehicle_inspection_type (inspection_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_initial ADD CONSTRAINT fk_vehicle_inspection_initial_vehicle_odometer_id FOREIGN KEY (vehicle_odometer_id) REFERENCES fs.vehicle_odometer_log (vehicle_odometer_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_initial ADD CONSTRAINT fk_vehicle_inspection_initial_inspector_user_id FOREIGN KEY (inspector_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_initial ADD CONSTRAINT fk_vehicle_inspection_initial_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_initial ADD CONSTRAINT fk_vehicle_inspection_initial_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_issue ADD CONSTRAINT fk_vehicle_inspection_issue_inspection_id FOREIGN KEY (inspection_id) REFERENCES fs.vehicle_inspection (inspection_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_issue ADD CONSTRAINT fk_vehicle_inspection_issue_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_issue ADD CONSTRAINT fk_vehicle_inspection_issue_attachment_id FOREIGN KEY (attachment_id) REFERENCES fs.vehicle_event_attachment (vehicle_event_attachment_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_issue ADD CONSTRAINT fk_vehicle_inspection_issue_task_id FOREIGN KEY (task_id) REFERENCES fs.task (task_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_issue ADD CONSTRAINT fk_vehicle_inspection_issue_resolved_by_user_id FOREIGN KEY (resolved_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_issue ADD CONSTRAINT fk_vehicle_inspection_issue_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_issue ADD CONSTRAINT fk_vehicle_inspection_issue_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_item_left ADD CONSTRAINT fk_vehicle_inspection_item_left_vehicle_event_id FOREIGN KEY (vehicle_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_item_left ADD CONSTRAINT fk_vehicle_inspection_item_left_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_item_left ADD CONSTRAINT fk_vehicle_inspection_item_left_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_item_left ADD CONSTRAINT fk_vehicle_inspection_item_left_inspection_issue_id FOREIGN KEY (inspection_issue_id) REFERENCES fs.vehicle_inspection_issue (inspection_issue_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_item_left ADD CONSTRAINT fk_vehicle_inspection_item_left_inspector_user_id FOREIGN KEY (inspector_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_item_left ADD CONSTRAINT fk_vehicle_inspection_item_left_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_item_left ADD CONSTRAINT fk_vehicle_inspection_item_left_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_transfer ADD CONSTRAINT fk_vehicle_inspection_transfer_vehicle_event_id FOREIGN KEY (vehicle_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_transfer ADD CONSTRAINT fk_vehicle_inspection_transfer_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_transfer ADD CONSTRAINT fk_vehicle_inspection_transfer_inspection_type_code FOREIGN KEY (inspection_type_code) REFERENCES fs.vehicle_inspection_type (inspection_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_transfer ADD CONSTRAINT fk_vehicle_inspection_transfer_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_transfer ADD CONSTRAINT fk_vehicle_inspection_transfer_origin_branch_id FOREIGN KEY (origin_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_transfer ADD CONSTRAINT fk_vehicle_inspection_transfer_destination_branch_id FOREIGN KEY (destination_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_transfer ADD CONSTRAINT fk_vehicle_inspection_transfer_vehicle_odometer_id FOREIGN KEY (vehicle_odometer_id) REFERENCES fs.vehicle_odometer_log (vehicle_odometer_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_transfer ADD CONSTRAINT fk_vehicle_inspection_transfer_fuel_level_code FOREIGN KEY (fuel_level_code) REFERENCES fs.vehicle_fuel_level_select (fuel_level_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_transfer ADD CONSTRAINT fk_vehicle_inspection_transfer_inspector_user_id FOREIGN KEY (inspector_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_transfer ADD CONSTRAINT fk_vehicle_inspection_transfer_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_transfer ADD CONSTRAINT fk_vehicle_inspection_transfer_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_type ADD CONSTRAINT fk_vehicle_inspection_type_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_type ADD CONSTRAINT fk_vehicle_inspection_type_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_wheels_tires ADD CONSTRAINT fk_vehicle_inspection_wheels_tires_vehicle_event_id FOREIGN KEY (vehicle_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_wheels_tires ADD CONSTRAINT fk_vehicle_inspection_wheels_tires_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_wheels_tires ADD CONSTRAINT fk_vehicle_inspection_wheels_tires_odometer_log_id FOREIGN KEY (odometer_log_id) REFERENCES fs.vehicle_odometer_log (vehicle_odometer_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_wheels_tires ADD CONSTRAINT fk_vehicle_inspection_wheels_tires_inspector_user_id FOREIGN KEY (inspector_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_wheels_tires ADD CONSTRAINT fk_vehicle_inspection_wheels_tires_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_inspection_wheels_tires ADD CONSTRAINT fk_vehicle_inspection_wheels_tires_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_partner ADD CONSTRAINT fk_vehicle_partner_state FOREIGN KEY (state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_partner ADD CONSTRAINT fk_vehicle_partner_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_partner ADD CONSTRAINT fk_vehicle_partner_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_partner_contact ADD CONSTRAINT fk_vehicle_partner_contact_vehicle_partner_id FOREIGN KEY (vehicle_partner_id) REFERENCES fs.vehicle_partner (vehicle_partner_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_partner_contact ADD CONSTRAINT fk_vehicle_partner_contact_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_partner_contact ADD CONSTRAINT fk_vehicle_partner_contact_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_guarantee_group ADD CONSTRAINT fk_vop_guarantee_group_vehicle_partner_id FOREIGN KEY (vehicle_partner_id) REFERENCES fs.vehicle_partner (vehicle_partner_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_guarantee_group ADD CONSTRAINT fk_vop_guarantee_group_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_guarantee_group ADD CONSTRAINT fk_vop_guarantee_group_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_guarantee_group_plan ADD CONSTRAINT fk_vop_guarantee_group_plan_vop_guarantee_group_id FOREIGN KEY (vop_guarantee_group_id) REFERENCES fs.vop_guarantee_group (vop_guarantee_group_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_guarantee_group_plan ADD CONSTRAINT fk_vop_guarantee_group_plan_vop_plan_id FOREIGN KEY (vop_plan_id) REFERENCES fs.vop_plan (vop_plan_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_guarantee_group_plan ADD CONSTRAINT fk_vop_guarantee_group_plan_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_guarantee_group_plan ADD CONSTRAINT fk_vop_guarantee_group_plan_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_log ADD CONSTRAINT fk_vop_payout_log_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_log ADD CONSTRAINT fk_vop_payout_log_vop_plan_id FOREIGN KEY (vop_plan_id) REFERENCES fs.vop_plan (vop_plan_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_log ADD CONSTRAINT fk_vop_payout_log_vehicle_partner_id FOREIGN KEY (vehicle_partner_id) REFERENCES fs.vehicle_partner (vehicle_partner_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_log ADD CONSTRAINT fk_vop_payout_log_vehicle_reservation_id FOREIGN KEY (vehicle_reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_log ADD CONSTRAINT fk_vop_payout_log_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_log ADD CONSTRAINT fk_vop_payout_log_payout_period_id FOREIGN KEY (payout_period_id) REFERENCES fs.vop_payout_period (payout_period_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_log ADD CONSTRAINT fk_vop_payout_log_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_log ADD CONSTRAINT fk_vop_payout_log_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_period ADD CONSTRAINT fk_vop_payout_period_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_period ADD CONSTRAINT fk_vop_payout_period_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_summary ADD CONSTRAINT fk_vop_payout_summary_payout_period_id FOREIGN KEY (payout_period_id) REFERENCES fs.vop_payout_period (payout_period_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_summary ADD CONSTRAINT fk_vop_payout_summary_vop_plan_id FOREIGN KEY (vop_plan_id) REFERENCES fs.vop_plan (vop_plan_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_summary ADD CONSTRAINT fk_vop_payout_summary_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_summary ADD CONSTRAINT fk_vop_payout_summary_vehicle_partner_id FOREIGN KEY (vehicle_partner_id) REFERENCES fs.vehicle_partner (vehicle_partner_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_summary ADD CONSTRAINT fk_vop_payout_summary_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_payout_summary ADD CONSTRAINT fk_vop_payout_summary_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_plan ADD CONSTRAINT fk_vop_plan_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_plan ADD CONSTRAINT fk_vop_plan_vehicle_partner_id FOREIGN KEY (vehicle_partner_id) REFERENCES fs.vehicle_partner (vehicle_partner_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_plan ADD CONSTRAINT fk_vop_plan_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vop_plan ADD CONSTRAINT fk_vop_plan_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_hold ADD CONSTRAINT fk_reservation_hold_vehicle_reservation_id FOREIGN KEY (vehicle_reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_hold ADD CONSTRAINT fk_reservation_hold_hold_reason_code FOREIGN KEY (hold_reason_code) REFERENCES fs.reservation_hold_reason_select (hold_reason_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_hold ADD CONSTRAINT fk_reservation_hold_placed_by_user_id FOREIGN KEY (placed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_hold ADD CONSTRAINT fk_reservation_hold_released_by_user_id FOREIGN KEY (released_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_hold ADD CONSTRAINT fk_reservation_hold_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_hold ADD CONSTRAINT fk_reservation_hold_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_hold_reason_select ADD CONSTRAINT fk_reservation_hold_reason_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_hold_reason_select ADD CONSTRAINT fk_reservation_hold_reason_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_location_select ADD CONSTRAINT fk_reservation_location_select_state FOREIGN KEY (state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_location_select ADD CONSTRAINT fk_reservation_location_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_location_select ADD CONSTRAINT fk_reservation_location_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_perk_application ADD CONSTRAINT fk_reservation_perk_application_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_perk_application ADD CONSTRAINT fk_reservation_perk_application_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_perk_application ADD CONSTRAINT fk_reservation_perk_application_perk_type FOREIGN KEY (perk_type) REFERENCES fs.perk_type_select (perk_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_perk_application ADD CONSTRAINT fk_reservation_perk_application_vehicle_tier_id_applied FOREIGN KEY (vehicle_tier_id_applied) REFERENCES fs.vehicle_tier (vehicle_tier_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_perk_application ADD CONSTRAINT fk_reservation_perk_application_member_package_id FOREIGN KEY (member_package_id) REFERENCES fs.member_package (member_package_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_perk_application ADD CONSTRAINT fk_reservation_perk_application_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_perk_application ADD CONSTRAINT fk_reservation_perk_application_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_protected_period ADD CONSTRAINT fk_reservation_protected_period_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_protected_period ADD CONSTRAINT fk_reservation_protected_period_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_protected_period ADD CONSTRAINT fk_reservation_protected_period_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_protection ADD CONSTRAINT fk_reservation_protection_reservation_protected_period_id FOREIGN KEY (reservation_protected_period_id) REFERENCES fs.reservation_protected_period (reservation_protected_period_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_protection ADD CONSTRAINT fk_reservation_protection_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_protection ADD CONSTRAINT fk_reservation_protection_booked_reservation_id FOREIGN KEY (booked_reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_protection ADD CONSTRAINT fk_reservation_protection_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_protection ADD CONSTRAINT fk_reservation_protection_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_restricted_dates ADD CONSTRAINT fk_reservation_restricted_dates_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_restricted_dates ADD CONSTRAINT fk_reservation_restricted_dates_restricted_date_type_code FOREIGN KEY (restricted_date_type_code) REFERENCES fs.restricted_date_type_select (restricted_date_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_restricted_dates ADD CONSTRAINT fk_reservation_restricted_dates_holiday_definition_id FOREIGN KEY (holiday_definition_id) REFERENCES fs.holiday_definition (holiday_definition_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_restricted_dates ADD CONSTRAINT fk_reservation_restricted_dates_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_restricted_dates ADD CONSTRAINT fk_reservation_restricted_dates_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_rule ADD CONSTRAINT fk_reservation_rule_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_rule ADD CONSTRAINT fk_reservation_rule_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_source_type_select ADD CONSTRAINT fk_reservation_source_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_source_type_select ADD CONSTRAINT fk_reservation_source_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_status_history ADD CONSTRAINT fk_reservation_status_history_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_status_history ADD CONSTRAINT fk_reservation_status_history_status_reason_code FOREIGN KEY (status_reason_code) REFERENCES fs.reservation_status_reason_select (status_reason_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_status_history ADD CONSTRAINT fk_reservation_status_history_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_status_history ADD CONSTRAINT fk_reservation_status_history_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_status_reason_select ADD CONSTRAINT fk_reservation_status_reason_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_status_reason_select ADD CONSTRAINT fk_reservation_status_reason_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_status_select ADD CONSTRAINT fk_reservation_status_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_status_select ADD CONSTRAINT fk_reservation_status_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_type_select ADD CONSTRAINT fk_reservation_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_type_select ADD CONSTRAINT fk_reservation_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_watch ADD CONSTRAINT fk_reservation_watch_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_watch ADD CONSTRAINT fk_reservation_watch_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_watch ADD CONSTRAINT fk_reservation_watch_watch_reason_code FOREIGN KEY (watch_reason_code) REFERENCES fs.reservation_withhold_reason_select (withhold_reason_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_watch ADD CONSTRAINT fk_reservation_watch_escalated_to_withhold_id FOREIGN KEY (escalated_to_withhold_id) REFERENCES fs.reservation_withhold (reservation_withhold_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_watch ADD CONSTRAINT fk_reservation_watch_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_watch ADD CONSTRAINT fk_reservation_watch_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_withhold ADD CONSTRAINT fk_reservation_withhold_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_withhold ADD CONSTRAINT fk_reservation_withhold_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_withhold ADD CONSTRAINT fk_reservation_withhold_withhold_reason_code FOREIGN KEY (withhold_reason_code) REFERENCES fs.reservation_withhold_reason_select (withhold_reason_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_withhold ADD CONSTRAINT fk_reservation_withhold_placed_by_user_id FOREIGN KEY (placed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_withhold ADD CONSTRAINT fk_reservation_withhold_released_by_user_id FOREIGN KEY (released_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_withhold ADD CONSTRAINT fk_reservation_withhold_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_withhold ADD CONSTRAINT fk_reservation_withhold_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_withhold_reason_select ADD CONSTRAINT fk_reservation_withhold_reason_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.reservation_withhold_reason_select ADD CONSTRAINT fk_reservation_withhold_reason_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_allowance ADD CONSTRAINT fk_vehicle_access_allowance_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_allowance ADD CONSTRAINT fk_vehicle_access_allowance_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_allowance ADD CONSTRAINT fk_vehicle_access_allowance_added_by_user_id FOREIGN KEY (added_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_allowance ADD CONSTRAINT fk_vehicle_access_allowance_removed_by_user_id FOREIGN KEY (removed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_allowance ADD CONSTRAINT fk_vehicle_access_allowance_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_allowance ADD CONSTRAINT fk_vehicle_access_allowance_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_exclusion ADD CONSTRAINT fk_vehicle_access_exclusion_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_exclusion ADD CONSTRAINT fk_vehicle_access_exclusion_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_exclusion ADD CONSTRAINT fk_vehicle_access_exclusion_corporate_account_id FOREIGN KEY (corporate_account_id) REFERENCES fs.corporate_account (corporate_account_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_exclusion ADD CONSTRAINT fk_vehicle_access_exclusion_applied_by_user_id FOREIGN KEY (applied_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_exclusion ADD CONSTRAINT fk_vehicle_access_exclusion_removed_by_user_id FOREIGN KEY (removed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_exclusion ADD CONSTRAINT fk_vehicle_access_exclusion_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_access_exclusion ADD CONSTRAINT fk_vehicle_access_exclusion_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_member_qualification ADD CONSTRAINT fk_vehicle_member_qualification_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_member_qualification ADD CONSTRAINT fk_vehicle_member_qualification_vehicle_qualification_id FOREIGN KEY (vehicle_qualification_id) REFERENCES fs.vehicle_qualification (vehicle_qualification_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_member_qualification ADD CONSTRAINT fk_vehicle_member_qualification_granted_by_user_id FOREIGN KEY (granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_member_qualification ADD CONSTRAINT fk_vehicle_member_qualification_revoked_by_user_id FOREIGN KEY (revoked_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_member_qualification ADD CONSTRAINT fk_vehicle_member_qualification_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_member_qualification ADD CONSTRAINT fk_vehicle_member_qualification_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_qualification ADD CONSTRAINT fk_vehicle_qualification_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_qualification ADD CONSTRAINT fk_vehicle_qualification_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_qualification ADD CONSTRAINT fk_vehicle_qualification_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_reservation_type_code FOREIGN KEY (reservation_type_code) REFERENCES fs.reservation_type_select (reservation_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_reservation_status_code FOREIGN KEY (reservation_status_code) REFERENCES fs.reservation_status_select (reservation_status_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_member_package_id FOREIGN KEY (member_package_id) REFERENCES fs.member_package (member_package_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_reserving_branch_id FOREIGN KEY (reserving_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_source_type_code FOREIGN KEY (source_type_code) REFERENCES fs.reservation_source_type_select (source_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_start_location_code FOREIGN KEY (start_location_code) REFERENCES fs.reservation_location_select (reservation_location_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_end_location_code FOREIGN KEY (end_location_code) REFERENCES fs.reservation_location_select (reservation_location_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_linked_reservation_id FOREIGN KEY (linked_reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_service_category_code FOREIGN KEY (service_category_code) REFERENCES fs.service_category (service_category_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_service_type_code FOREIGN KEY (service_type_code) REFERENCES fs.vehicle_service_type (service_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_service_vendor_id FOREIGN KEY (service_vendor_id) REFERENCES fs.vendor (vendor_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_last_checkin_event_id FOREIGN KEY (last_checkin_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_last_checkout_event_id FOREIGN KEY (last_checkout_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_early_pickup_granted_by_user_id FOREIGN KEY (early_pickup_granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_late_return_granted_by_user_id FOREIGN KEY (late_return_granted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_member_address_id FOREIGN KEY (member_address_id) REFERENCES fs.member_address (member_address_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_branch_delivery_rate_id FOREIGN KEY (branch_delivery_rate_id) REFERENCES fs.branch_delivery_rate (branch_delivery_rate_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_delivery_quote_accepted_by_user_id FOREIGN KEY (delivery_quote_accepted_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_reservation ADD CONSTRAINT fk_vehicle_reservation_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.service_category ADD CONSTRAINT fk_service_category_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.service_category ADD CONSTRAINT fk_service_category_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.service_reason_select ADD CONSTRAINT fk_service_reason_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.service_reason_select ADD CONSTRAINT fk_service_reason_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.toll_authority_select ADD CONSTRAINT fk_toll_authority_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.toll_authority_select ADD CONSTRAINT fk_toll_authority_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_attachment_retention_policy ADD CONSTRAINT fk_vehicle_attachment_retention_policy_source_type_code FOREIGN KEY (source_type_code) REFERENCES fs.vehicle_source_type (source_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_attachment_retention_policy ADD CONSTRAINT fk_vehicle_attachment_retention_policy_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_attachment_retention_policy ADD CONSTRAINT fk_vehicle_attachment_retention_policy_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_code ADD CONSTRAINT fk_vehicle_condition_code_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_code ADD CONSTRAINT fk_vehicle_condition_code_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_history ADD CONSTRAINT fk_vehicle_condition_history_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_history ADD CONSTRAINT fk_vehicle_condition_history_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_history ADD CONSTRAINT fk_vehicle_condition_history_condition_code FOREIGN KEY (condition_code) REFERENCES fs.vehicle_condition_code (condition_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_history ADD CONSTRAINT fk_vehicle_condition_history_condition_reason_code FOREIGN KEY (condition_reason_code) REFERENCES fs.vehicle_condition_reason (condition_reason_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_history ADD CONSTRAINT fk_vehicle_condition_history_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_history ADD CONSTRAINT fk_vehicle_condition_history_inspection_id FOREIGN KEY (inspection_id) REFERENCES fs.vehicle_inspection (inspection_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_history ADD CONSTRAINT fk_vehicle_condition_history_changed_by_user_id FOREIGN KEY (changed_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_reason ADD CONSTRAINT fk_vehicle_condition_reason_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_reason ADD CONSTRAINT fk_vehicle_condition_reason_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_transition_rule ADD CONSTRAINT fk_vehicle_condition_transition_rule_from_condition_code FOREIGN KEY (from_condition_code) REFERENCES fs.vehicle_condition_code (condition_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_transition_rule ADD CONSTRAINT fk_vehicle_condition_transition_rule_to_condition_code FOREIGN KEY (to_condition_code) REFERENCES fs.vehicle_condition_code (condition_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_transition_rule ADD CONSTRAINT fk_vehicle_condition_transition_rule_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_condition_transition_rule ADD CONSTRAINT fk_vehicle_condition_transition_rule_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_attachment ADD CONSTRAINT fk_vehicle_event_attachment_vehicle_event_id FOREIGN KEY (vehicle_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_attachment ADD CONSTRAINT fk_vehicle_event_attachment_attachment_retention_policy_id FOREIGN KEY (attachment_retention_policy_id) REFERENCES fs.vehicle_attachment_retention_policy (attachment_retention_policy_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_attachment ADD CONSTRAINT fk_vehicle_event_attachment_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_attachment ADD CONSTRAINT fk_vehicle_event_attachment_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_log ADD CONSTRAINT fk_vehicle_event_log_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_log ADD CONSTRAINT fk_vehicle_event_log_reservation_id FOREIGN KEY (reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_log ADD CONSTRAINT fk_vehicle_event_log_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_log ADD CONSTRAINT fk_vehicle_event_log_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_log ADD CONSTRAINT fk_vehicle_event_log_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_log ADD CONSTRAINT fk_vehicle_event_log_service_vendor_id FOREIGN KEY (service_vendor_id) REFERENCES fs.vendor (vendor_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_log ADD CONSTRAINT fk_vehicle_event_log_captured_by_user_id FOREIGN KEY (captured_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_log ADD CONSTRAINT fk_vehicle_event_log_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_event_log ADD CONSTRAINT fk_vehicle_event_log_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_fuel_level_select ADD CONSTRAINT fk_vehicle_fuel_level_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_fuel_level_select ADD CONSTRAINT fk_vehicle_fuel_level_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_location ADD CONSTRAINT fk_vehicle_location_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_location ADD CONSTRAINT fk_vehicle_location_home_branch_id FOREIGN KEY (home_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_location ADD CONSTRAINT fk_vehicle_location_current_branch_id FOREIGN KEY (current_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_location ADD CONSTRAINT fk_vehicle_location_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_location ADD CONSTRAINT fk_vehicle_location_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_odometer_log ADD CONSTRAINT fk_vehicle_odometer_log_vehicle_event_id FOREIGN KEY (vehicle_event_id) REFERENCES fs.vehicle_event_log (vehicle_event_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_odometer_log ADD CONSTRAINT fk_vehicle_odometer_log_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_odometer_log ADD CONSTRAINT fk_vehicle_odometer_log_captured_by_user_id FOREIGN KEY (captured_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_odometer_log ADD CONSTRAINT fk_vehicle_odometer_log_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_odometer_log ADD CONSTRAINT fk_vehicle_odometer_log_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_service_type ADD CONSTRAINT fk_vehicle_service_type_service_category_code FOREIGN KEY (service_category_code) REFERENCES fs.service_category (service_category_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_service_type ADD CONSTRAINT fk_vehicle_service_type_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_service_type ADD CONSTRAINT fk_vehicle_service_type_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_source_type ADD CONSTRAINT fk_vehicle_source_type_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_source_type ADD CONSTRAINT fk_vehicle_source_type_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_toll_transaction ADD CONSTRAINT fk_vehicle_toll_transaction_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_toll_transaction ADD CONSTRAINT fk_vehicle_toll_transaction_toll_authority_code FOREIGN KEY (toll_authority_code) REFERENCES fs.toll_authority_select (authority_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_toll_transaction ADD CONSTRAINT fk_vehicle_toll_transaction_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_toll_transaction ADD CONSTRAINT fk_vehicle_toll_transaction_member_charge_id FOREIGN KEY (member_charge_id) REFERENCES fs.member_charge (member_charge_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_toll_transaction ADD CONSTRAINT fk_vehicle_toll_transaction_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_toll_transaction ADD CONSTRAINT fk_vehicle_toll_transaction_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip ADD CONSTRAINT fk_vehicle_trip_vehicle_reservation_id FOREIGN KEY (vehicle_reservation_id) REFERENCES fs.vehicle_reservation (vehicle_reservation_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip ADD CONSTRAINT fk_vehicle_trip_trip_type_code FOREIGN KEY (trip_type_code) REFERENCES fs.vehicle_trip_type_select (trip_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip ADD CONSTRAINT fk_vehicle_trip_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip ADD CONSTRAINT fk_vehicle_trip_odometer_start_id FOREIGN KEY (odometer_start_id) REFERENCES fs.vehicle_odometer_log (vehicle_odometer_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip ADD CONSTRAINT fk_vehicle_trip_odometer_end_id FOREIGN KEY (odometer_end_id) REFERENCES fs.vehicle_odometer_log (vehicle_odometer_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip ADD CONSTRAINT fk_vehicle_trip_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip ADD CONSTRAINT fk_vehicle_trip_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_member ADD CONSTRAINT fk_vehicle_trip_member_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_member ADD CONSTRAINT fk_vehicle_trip_member_member_id FOREIGN KEY (member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_member ADD CONSTRAINT fk_vehicle_trip_member_member_package_id FOREIGN KEY (member_package_id) REFERENCES fs.member_package (member_package_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_member ADD CONSTRAINT fk_vehicle_trip_member_member_package_participant_id FOREIGN KEY (member_package_participant_id) REFERENCES fs.member_package_participant (member_package_participant_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_member ADD CONSTRAINT fk_vehicle_trip_member_branch_id FOREIGN KEY (branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_member ADD CONSTRAINT fk_vehicle_trip_member_source_type_code FOREIGN KEY (source_type_code) REFERENCES fs.reservation_source_type_select (source_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_member ADD CONSTRAINT fk_vehicle_trip_member_vop_payout_log_id FOREIGN KEY (vop_payout_log_id) REFERENCES fs.vop_payout_log (vop_payout_log_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_member ADD CONSTRAINT fk_vehicle_trip_member_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_member ADD CONSTRAINT fk_vehicle_trip_member_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_service ADD CONSTRAINT fk_vehicle_trip_service_vehicle_trip_id FOREIGN KEY (vehicle_trip_id) REFERENCES fs.vehicle_trip (vehicle_trip_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_service ADD CONSTRAINT fk_vehicle_trip_service_vendor_id FOREIGN KEY (vendor_id) REFERENCES fs.vendor (vendor_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_service ADD CONSTRAINT fk_vehicle_trip_service_service_category_code FOREIGN KEY (service_category_code) REFERENCES fs.service_category (service_category_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_service ADD CONSTRAINT fk_vehicle_trip_service_service_type_code FOREIGN KEY (service_type_code) REFERENCES fs.vehicle_service_type (service_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_service ADD CONSTRAINT fk_vehicle_trip_service_service_reason_code FOREIGN KEY (service_reason_code) REFERENCES fs.service_reason_select (service_reason_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_service ADD CONSTRAINT fk_vehicle_trip_service_billed_member_id FOREIGN KEY (billed_member_id) REFERENCES fs.member (member_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_service ADD CONSTRAINT fk_vehicle_trip_service_billed_vehicle_partner_id FOREIGN KEY (billed_vehicle_partner_id) REFERENCES fs.vehicle_partner (vehicle_partner_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_service ADD CONSTRAINT fk_vehicle_trip_service_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_service ADD CONSTRAINT fk_vehicle_trip_service_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_type_select ADD CONSTRAINT fk_vehicle_trip_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_trip_type_select ADD CONSTRAINT fk_vehicle_trip_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle ADD CONSTRAINT fk_vehicle_vehicle_make_code FOREIGN KEY (vehicle_make_code) REFERENCES fs.vehicle_make_select (vehicle_make_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle ADD CONSTRAINT fk_vehicle_year FOREIGN KEY (year) REFERENCES fs.vehicle_year_select (vehicle_year_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle ADD CONSTRAINT fk_vehicle_exterior_color_short FOREIGN KEY (exterior_color_short) REFERENCES fs.vehicle_color_select (vehicle_color_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle ADD CONSTRAINT fk_vehicle_interior_color FOREIGN KEY (interior_color) REFERENCES fs.vehicle_color_select (vehicle_color_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle ADD CONSTRAINT fk_vehicle_condition_code FOREIGN KEY (condition_code) REFERENCES fs.vehicle_condition_code (condition_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle ADD CONSTRAINT fk_vehicle_home_branch_id FOREIGN KEY (home_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle ADD CONSTRAINT fk_vehicle_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle ADD CONSTRAINT fk_vehicle_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_accessories ADD CONSTRAINT fk_vehicle_accessories_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_accessories ADD CONSTRAINT fk_vehicle_accessories_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_accessories ADD CONSTRAINT fk_vehicle_accessories_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_color_select ADD CONSTRAINT fk_vehicle_color_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_color_select ADD CONSTRAINT fk_vehicle_color_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_description ADD CONSTRAINT fk_vehicle_description_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_description ADD CONSTRAINT fk_vehicle_description_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_description ADD CONSTRAINT fk_vehicle_description_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_financing_lifecycle ADD CONSTRAINT fk_vehicle_financing_lifecycle_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_financing_lifecycle ADD CONSTRAINT fk_vehicle_financing_lifecycle_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_financing_lifecycle ADD CONSTRAINT fk_vehicle_financing_lifecycle_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_make_select ADD CONSTRAINT fk_vehicle_make_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_make_select ADD CONSTRAINT fk_vehicle_make_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_mileage_allocation ADD CONSTRAINT fk_vehicle_mileage_allocation_vehicle_mileage_allowance_id FOREIGN KEY (vehicle_mileage_allowance_id) REFERENCES fs.vehicle_mileage_allowance (vehicle_mileage_allowance_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_mileage_allocation ADD CONSTRAINT fk_vehicle_mileage_allocation_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_mileage_allocation ADD CONSTRAINT fk_vehicle_mileage_allocation_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_mileage_allocation ADD CONSTRAINT fk_vehicle_mileage_allocation_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_mileage_allowance ADD CONSTRAINT fk_vehicle_mileage_allowance_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_mileage_allowance ADD CONSTRAINT fk_vehicle_mileage_allowance_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_mileage_allowance ADD CONSTRAINT fk_vehicle_mileage_allowance_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_performance ADD CONSTRAINT fk_vehicle_performance_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_performance ADD CONSTRAINT fk_vehicle_performance_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_performance ADD CONSTRAINT fk_vehicle_performance_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_registration_warranty ADD CONSTRAINT fk_vehicle_registration_warranty_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_registration_warranty ADD CONSTRAINT fk_vehicle_registration_warranty_registration_state FOREIGN KEY (registration_state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_registration_warranty ADD CONSTRAINT fk_vehicle_registration_warranty_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_registration_warranty ADD CONSTRAINT fk_vehicle_registration_warranty_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_release_row ADD CONSTRAINT fk_vehicle_release_row_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_release_row ADD CONSTRAINT fk_vehicle_release_row_minimum_podium_status_code FOREIGN KEY (minimum_podium_status_code) REFERENCES fs.podium_status_select (podium_status_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_release_row ADD CONSTRAINT fk_vehicle_release_row_applied_from_template_id FOREIGN KEY (applied_from_template_id) REFERENCES fs.vehicle_release_template (vehicle_release_template_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_release_row ADD CONSTRAINT fk_vehicle_release_row_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_release_row ADD CONSTRAINT fk_vehicle_release_row_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_release_template ADD CONSTRAINT fk_vehicle_release_template_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_release_template ADD CONSTRAINT fk_vehicle_release_template_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_release_template_row ADD CONSTRAINT fk_vehicle_release_template_row_vehicle_release_template_id FOREIGN KEY (vehicle_release_template_id) REFERENCES fs.vehicle_release_template (vehicle_release_template_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_release_template_row ADD CONSTRAINT fk_vehicle_release_template_row_minimum_podium_status_code FOREIGN KEY (minimum_podium_status_code) REFERENCES fs.podium_status_select (podium_status_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_release_template_row ADD CONSTRAINT fk_vehicle_release_template_row_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_release_template_row ADD CONSTRAINT fk_vehicle_release_template_row_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_spec ADD CONSTRAINT fk_vehicle_spec_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_spec ADD CONSTRAINT fk_vehicle_spec_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_spec ADD CONSTRAINT fk_vehicle_spec_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tire_brand_select ADD CONSTRAINT fk_vehicle_tire_brand_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tire_brand_select ADD CONSTRAINT fk_vehicle_tire_brand_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tires ADD CONSTRAINT fk_vehicle_tires_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES fs.vehicle (vehicle_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tires ADD CONSTRAINT fk_vehicle_tires_front_tire_brand FOREIGN KEY (front_tire_brand) REFERENCES fs.vehicle_tire_brand_select (tire_brand_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tires ADD CONSTRAINT fk_vehicle_tires_rear_tire_brand FOREIGN KEY (rear_tire_brand) REFERENCES fs.vehicle_tire_brand_select (tire_brand_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tires ADD CONSTRAINT fk_vehicle_tires_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_tires ADD CONSTRAINT fk_vehicle_tires_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_year_select ADD CONSTRAINT fk_vehicle_year_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vehicle_year_select ADD CONSTRAINT fk_vehicle_year_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor ADD CONSTRAINT fk_vendor_vendor_type_code FOREIGN KEY (vendor_type_code) REFERENCES fs.vendor_type_select (vendor_type_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor ADD CONSTRAINT fk_vendor_home_branch_id FOREIGN KEY (home_branch_id) REFERENCES fs.branch (branch_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor ADD CONSTRAINT fk_vendor_state FOREIGN KEY (state) REFERENCES fs.state_select (state_code) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor ADD CONSTRAINT fk_vendor_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor ADD CONSTRAINT fk_vendor_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_contact ADD CONSTRAINT fk_vendor_contact_vendor_id FOREIGN KEY (vendor_id) REFERENCES fs.vendor (vendor_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_contact ADD CONSTRAINT fk_vendor_contact_user_id FOREIGN KEY (user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_contact ADD CONSTRAINT fk_vendor_contact_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_contact ADD CONSTRAINT fk_vendor_contact_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_type_select ADD CONSTRAINT fk_vendor_type_select_created_by_user_id FOREIGN KEY (created_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fs.vendor_type_select ADD CONSTRAINT fk_vendor_type_select_updated_by_user_id FOREIGN KEY (updated_by_user_id) REFERENCES fs."user" (user_id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Total foreign keys added: 1146

-- =============================================================================
-- 4. INDEXES ON FOREIGN KEY AND FREQUENT QUERY COLUMNS
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_automation_action_rule_id ON fs.automation_action (rule_id);
CREATE INDEX IF NOT EXISTS idx_automation_action_task_template_id ON fs.automation_action (task_template_id);
CREATE INDEX IF NOT EXISTS idx_automation_action_notification_template_id ON fs.automation_action (notification_template_id);
CREATE INDEX IF NOT EXISTS idx_automation_action_webhook_id ON fs.automation_action (webhook_id);
CREATE INDEX IF NOT EXISTS idx_automation_action_created_by_user_id ON fs.automation_action (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_automation_action_updated_by_user_id ON fs.automation_action (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_automation_condition_rule_id ON fs.automation_condition (rule_id);
CREATE INDEX IF NOT EXISTS idx_automation_condition_created_by_user_id ON fs.automation_condition (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_automation_condition_updated_by_user_id ON fs.automation_condition (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_automation_execution_log_rule_id ON fs.automation_execution_log (rule_id);
CREATE INDEX IF NOT EXISTS idx_automation_execution_log_action_id ON fs.automation_execution_log (action_id);
CREATE INDEX IF NOT EXISTS idx_automation_execution_log_created_by_user_id ON fs.automation_execution_log (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_automation_rule_created_by_user_id ON fs.automation_rule (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_automation_rule_updated_by_user_id ON fs.automation_rule (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_job_rule_id ON fs.scheduled_job (rule_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_job_created_by_user_id ON fs.scheduled_job (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_job_updated_by_user_id ON fs.scheduled_job (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_job_report_schedule_id ON fs.scheduled_job (report_schedule_id);
CREATE INDEX IF NOT EXISTS idx_branch_time_zone ON fs.branch (time_zone);
CREATE INDEX IF NOT EXISTS idx_branch_state_mail ON fs.branch (state_mail);
CREATE INDEX IF NOT EXISTS idx_branch_state_physical ON fs.branch (state_physical);
CREATE INDEX IF NOT EXISTS idx_branch_created_by_user_id ON fs.branch (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_branch_updated_by_user_id ON fs.branch (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_branch_delivery_rate_branch_id ON fs.branch_delivery_rate (branch_id);
CREATE INDEX IF NOT EXISTS idx_branch_delivery_rate_created_by_user_id ON fs.branch_delivery_rate (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_branch_delivery_rate_updated_by_user_id ON fs.branch_delivery_rate (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_branch_phone_branch_id ON fs.branch_phone (branch_id);
CREATE INDEX IF NOT EXISTS idx_branch_phone_created_by_user_id ON fs.branch_phone (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_branch_phone_updated_by_user_id ON fs.branch_phone (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_branch_toll_source_branch_id ON fs.branch_toll_source (branch_id);
CREATE INDEX IF NOT EXISTS idx_branch_toll_source_toll_authority_code ON fs.branch_toll_source (toll_authority_code);
CREATE INDEX IF NOT EXISTS idx_branch_toll_source_integration_provider_id ON fs.branch_toll_source (integration_provider_id);
CREATE INDEX IF NOT EXISTS idx_branch_toll_source_created_by_user_id ON fs.branch_toll_source (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_branch_toll_source_updated_by_user_id ON fs.branch_toll_source (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_geofence_branch_id ON fs.geofence (branch_id);
CREATE INDEX IF NOT EXISTS idx_geofence_created_by_user_id ON fs.geofence (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_geofence_updated_by_user_id ON fs.geofence (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_branch_access_membership_level_id ON fs.member_branch_access (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_member_branch_access_branch_id ON fs.member_branch_access (branch_id);
CREATE INDEX IF NOT EXISTS idx_member_branch_access_granted_by_user_id ON fs.member_branch_access (granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_branch_access_created_by_user_id ON fs.member_branch_access (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_branch_access_updated_by_user_id ON fs.member_branch_access (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_branch_access_revoked_by_user_id ON fs.member_branch_access (revoked_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_branch_access_staff_id ON fs.staff_branch_access (staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_branch_access_branch_id ON fs.staff_branch_access (branch_id);
CREATE INDEX IF NOT EXISTS idx_staff_branch_access_granted_by_user_id ON fs.staff_branch_access (granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_branch_access_created_by_user_id ON fs.staff_branch_access (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_branch_access_updated_by_user_id ON fs.staff_branch_access (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_branch_access_revoked_by_user_id ON fs.staff_branch_access (revoked_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_branch_access_vendor_id ON fs.vendor_branch_access (vendor_id);
CREATE INDEX IF NOT EXISTS idx_vendor_branch_access_branch_id ON fs.vendor_branch_access (branch_id);
CREATE INDEX IF NOT EXISTS idx_vendor_branch_access_granted_by_user_id ON fs.vendor_branch_access (granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_branch_access_created_by_user_id ON fs.vendor_branch_access (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_branch_access_updated_by_user_id ON fs.vendor_branch_access (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_branch_access_revoked_by_user_id ON fs.vendor_branch_access (revoked_by_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_document_id ON fs.audit_log (document_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor_user_id ON fs.audit_log (actor_user_id);
CREATE INDEX IF NOT EXISTS idx_document_document_type_code ON fs.document (document_type_code);
CREATE INDEX IF NOT EXISTS idx_document_uploaded_by_user_id ON fs.document (uploaded_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_created_by_user_id ON fs.document (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_updated_by_user_id ON fs.document (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_category_created_by_user_id ON fs.document_category (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_category_updated_by_user_id ON fs.document_category (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_link_document_id ON fs.document_link (document_id);
CREATE INDEX IF NOT EXISTS idx_document_link_document_category_code ON fs.document_link (document_category_code);
CREATE INDEX IF NOT EXISTS idx_document_link_target_table ON fs.document_link (target_table);
CREATE INDEX IF NOT EXISTS idx_document_link_created_by_user_id ON fs.document_link (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_link_updated_by_user_id ON fs.document_link (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_retention_policy_id ON fs.document_retention (policy_id);
CREATE INDEX IF NOT EXISTS idx_document_retention_created_by_user_id ON fs.document_retention (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_retention_updated_by_user_id ON fs.document_retention (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_tag_created_by_user_id ON fs.document_tag (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_tag_updated_by_user_id ON fs.document_tag (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_type_document_category_code ON fs.document_type (document_category_code);
CREATE INDEX IF NOT EXISTS idx_document_type_created_by_user_id ON fs.document_type (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_type_updated_by_user_id ON fs.document_type (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_version_document_id ON fs.document_version (document_id);
CREATE INDEX IF NOT EXISTS idx_document_version_created_by_user_id ON fs.document_version (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_document_version_updated_by_user_id ON fs.document_version (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_retention_policy_created_by_user_id ON fs.retention_policy (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_retention_policy_updated_by_user_id ON fs.retention_policy (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_tag_created_by_user_id ON fs.tag (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_tag_updated_by_user_id ON fs.tag (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_event_event_type_code ON fs.event (event_type_code);
CREATE INDEX IF NOT EXISTS idx_event_created_by_user_id ON fs.event (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_event_updated_by_user_id ON fs.event (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_event_guest_event_registration_id ON fs.event_guest (event_registration_id);
CREATE INDEX IF NOT EXISTS idx_event_guest_created_by_user_id ON fs.event_guest (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_event_guest_updated_by_user_id ON fs.event_guest (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_event_partner_event_id ON fs.event_partner (event_id);
CREATE INDEX IF NOT EXISTS idx_event_partner_vendor_id ON fs.event_partner (vendor_id);
CREATE INDEX IF NOT EXISTS idx_event_partner_granted_by_user_id ON fs.event_partner (granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_event_partner_created_by_user_id ON fs.event_partner (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_event_partner_updated_by_user_id ON fs.event_partner (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_event_registration_event_id ON fs.event_registration (event_id);
CREATE INDEX IF NOT EXISTS idx_event_registration_member_id ON fs.event_registration (member_id);
CREATE INDEX IF NOT EXISTS idx_event_registration_created_by_user_id ON fs.event_registration (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_event_registration_updated_by_user_id ON fs.event_registration (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_event_type_select_created_by_user_id ON fs.event_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_event_type_select_updated_by_user_id ON fs.event_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_form_target_table ON fs.form (target_table);
CREATE INDEX IF NOT EXISTS idx_form_no_defect_condition_code ON fs.form (no_defect_condition_code);
CREATE INDEX IF NOT EXISTS idx_form_created_by_user_id ON fs.form (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_form_updated_by_user_id ON fs.form (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_form_card_form_id ON fs.form_card (form_id);
CREATE INDEX IF NOT EXISTS idx_form_card_created_by_user_id ON fs.form_card (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_form_card_updated_by_user_id ON fs.form_card (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_form_card_option_form_card_id ON fs.form_card_option (form_card_id);
CREATE INDEX IF NOT EXISTS idx_form_card_option_created_by_user_id ON fs.form_card_option (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_form_card_option_updated_by_user_id ON fs.form_card_option (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_form_card_point_form_card_id ON fs.form_card_point (form_card_id);
CREATE INDEX IF NOT EXISTS idx_form_card_point_created_by_user_id ON fs.form_card_point (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_form_card_point_updated_by_user_id ON fs.form_card_point (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_form_defect_form_response_point_id ON fs.form_defect (form_response_point_id);
CREATE INDEX IF NOT EXISTS idx_form_defect_vehicle_id ON fs.form_defect (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_form_defect_resolved_by ON fs.form_defect (resolved_by);
CREATE INDEX IF NOT EXISTS idx_form_mapping_form_id ON fs.form_mapping (form_id);
CREATE INDEX IF NOT EXISTS idx_form_mapping_target_table ON fs.form_mapping (target_table);
CREATE INDEX IF NOT EXISTS idx_form_mapping_created_by_user_id ON fs.form_mapping (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_form_mapping_updated_by_user_id ON fs.form_mapping (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_form_response_form_id ON fs.form_response (form_id);
CREATE INDEX IF NOT EXISTS idx_form_response_user_id ON fs.form_response (user_id);
CREATE INDEX IF NOT EXISTS idx_form_response_branch_id ON fs.form_response (branch_id);
CREATE INDEX IF NOT EXISTS idx_form_response_vehicle_id ON fs.form_response (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_form_response_member_id ON fs.form_response (member_id);
CREATE INDEX IF NOT EXISTS idx_form_response_card_form_response_id ON fs.form_response_card (form_response_id);
CREATE INDEX IF NOT EXISTS idx_form_response_card_form_card_id ON fs.form_response_card (form_card_id);
CREATE INDEX IF NOT EXISTS idx_form_response_point_form_response_card_id ON fs.form_response_point (form_response_card_id);
CREATE INDEX IF NOT EXISTS idx_form_response_point_form_card_point_id ON fs.form_response_point (form_card_point_id);
CREATE INDEX IF NOT EXISTS idx_integration_configuration_provider_id ON fs.integration_configuration (provider_id);
CREATE INDEX IF NOT EXISTS idx_integration_configuration_created_by_user_id ON fs.integration_configuration (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_integration_configuration_updated_by_user_id ON fs.integration_configuration (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_integration_credential_provider_id ON fs.integration_credential (provider_id);
CREATE INDEX IF NOT EXISTS idx_integration_credential_user_id ON fs.integration_credential (user_id);
CREATE INDEX IF NOT EXISTS idx_integration_credential_created_by_user_id ON fs.integration_credential (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_integration_credential_updated_by_user_id ON fs.integration_credential (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_integration_event_log_provider_id ON fs.integration_event_log (provider_id);
CREATE INDEX IF NOT EXISTS idx_integration_event_log_webhook_id ON fs.integration_event_log (webhook_id);
CREATE INDEX IF NOT EXISTS idx_integration_event_log_created_by_user_id ON fs.integration_event_log (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_integration_mapping_rule_provider_id ON fs.integration_mapping_rule (provider_id);
CREATE INDEX IF NOT EXISTS idx_integration_mapping_rule_created_by_user_id ON fs.integration_mapping_rule (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_integration_mapping_rule_updated_by_user_id ON fs.integration_mapping_rule (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_integration_provider_created_by_user_id ON fs.integration_provider (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_integration_provider_updated_by_user_id ON fs.integration_provider (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_webhook_created_by_user_id ON fs.webhook (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_webhook_updated_by_user_id ON fs.webhook (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_webhook_delivery_log_webhook_id ON fs.webhook_delivery_log (webhook_id);
CREATE INDEX IF NOT EXISTS idx_webhook_event_subscription_webhook_id ON fs.webhook_event_subscription (webhook_id);
CREATE INDEX IF NOT EXISTS idx_webhook_event_subscription_created_by_user_id ON fs.webhook_event_subscription (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_webhook_event_subscription_updated_by_user_id ON fs.webhook_event_subscription (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_webhook_inbound_provider_id ON fs.webhook_inbound (provider_id);
CREATE INDEX IF NOT EXISTS idx_member_car_member_id ON fs.member_car (member_id);
CREATE INDEX IF NOT EXISTS idx_member_car_year ON fs.member_car (year);
CREATE INDEX IF NOT EXISTS idx_member_car_make ON fs.member_car (make);
CREATE INDEX IF NOT EXISTS idx_member_car_color ON fs.member_car (color);
CREATE INDEX IF NOT EXISTS idx_member_car_photo_document_id ON fs.member_car (photo_document_id);
CREATE INDEX IF NOT EXISTS idx_member_car_created_by_user_id ON fs.member_car (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_car_updated_by_user_id ON fs.member_car (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_car_service_member_car_stay_id ON fs.member_car_service (member_car_stay_id);
CREATE INDEX IF NOT EXISTS idx_member_car_service_member_car_id ON fs.member_car_service (member_car_id);
CREATE INDEX IF NOT EXISTS idx_member_car_service_member_charge_id ON fs.member_car_service (member_charge_id);
CREATE INDEX IF NOT EXISTS idx_member_car_service_member_car_service_type_code ON fs.member_car_service (member_car_service_type_code);
CREATE INDEX IF NOT EXISTS idx_member_car_service_created_by_user_id ON fs.member_car_service (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_car_service_updated_by_user_id ON fs.member_car_service (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_car_service_type_created_by_user_id ON fs.member_car_service_type (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_car_service_type_updated_by_user_id ON fs.member_car_service_type (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_car_stay_member_car_id ON fs.member_car_stay (member_car_id);
CREATE INDEX IF NOT EXISTS idx_member_car_stay_member_id ON fs.member_car_stay (member_id);
CREATE INDEX IF NOT EXISTS idx_member_car_stay_vehicle_reservation_id ON fs.member_car_stay (vehicle_reservation_id);
CREATE INDEX IF NOT EXISTS idx_member_car_stay_task_id ON fs.member_car_stay (task_id);
CREATE INDEX IF NOT EXISTS idx_member_car_stay_created_by_user_id ON fs.member_car_stay (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_car_stay_updated_by_user_id ON fs.member_car_stay (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_benefit_adjustment_kind_select_created_by_user_id ON fs.benefit_adjustment_kind_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_benefit_adjustment_kind_select_updated_by_user_id ON fs.benefit_adjustment_kind_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_benefit_target_select_created_by_user_id ON fs.benefit_target_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_benefit_target_select_updated_by_user_id ON fs.benefit_target_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_corporate_account_home_branch_id ON fs.corporate_account (home_branch_id);
CREATE INDEX IF NOT EXISTS idx_corporate_account_billing_state ON fs.corporate_account (billing_state);
CREATE INDEX IF NOT EXISTS idx_corporate_account_created_by_user_id ON fs.corporate_account (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_corporate_account_updated_by_user_id ON fs.corporate_account (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_corporate_account_contact_corporate_account_id ON fs.corporate_account_contact (corporate_account_id);
CREATE INDEX IF NOT EXISTS idx_corporate_account_contact_created_by_user_id ON fs.corporate_account_contact (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_corporate_account_contact_updated_by_user_id ON fs.corporate_account_contact (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_feedback_rating_scale_created_by_user_id ON fs.feedback_rating_scale (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_feedback_rating_scale_updated_by_user_id ON fs.feedback_rating_scale (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_industry_select_created_by_user_id ON fs.industry_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_industry_select_updated_by_user_id ON fs.industry_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_insurance_carrier_select_created_by_user_id ON fs.insurance_carrier_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_insurance_carrier_select_updated_by_user_id ON fs.insurance_carrier_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_insurance_coverage_select_created_by_user_id ON fs.insurance_coverage_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_insurance_coverage_select_updated_by_user_id ON fs.insurance_coverage_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_insurance_type_select_created_by_user_id ON fs.insurance_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_insurance_type_select_updated_by_user_id ON fs.insurance_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_lap_rule_created_by_user_id ON fs.lap_rule (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_lap_rule_updated_by_user_id ON fs.lap_rule (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_user_id ON fs.member (user_id);
CREATE INDEX IF NOT EXISTS idx_member_home_branch_id ON fs.member (home_branch_id);
CREATE INDEX IF NOT EXISTS idx_member_license_state ON fs.member (license_state);
CREATE INDEX IF NOT EXISTS idx_member_podium_status ON fs.member (podium_status);
CREATE INDEX IF NOT EXISTS idx_member_created_by_user_id ON fs.member (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_updated_by_user_id ON fs.member (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_address_member_id ON fs.member_address (member_id);
CREATE INDEX IF NOT EXISTS idx_member_address_member_state ON fs.member_address (member_state);
CREATE INDEX IF NOT EXISTS idx_member_address_created_by_user_id ON fs.member_address (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_address_updated_by_user_id ON fs.member_address (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_branch_history_member_id ON fs.member_branch_history (member_id);
CREATE INDEX IF NOT EXISTS idx_member_branch_history_branch_id ON fs.member_branch_history (branch_id);
CREATE INDEX IF NOT EXISTS idx_member_branch_history_created_by_user_id ON fs.member_branch_history (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_branch_history_updated_by_user_id ON fs.member_branch_history (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_charge_member_id ON fs.member_charge (member_id);
CREATE INDEX IF NOT EXISTS idx_member_charge_vehicle_trip_id ON fs.member_charge (vehicle_trip_id);
CREATE INDEX IF NOT EXISTS idx_member_charge_reservation_id ON fs.member_charge (reservation_id);
CREATE INDEX IF NOT EXISTS idx_member_charge_service_trip_id ON fs.member_charge (service_trip_id);
CREATE INDEX IF NOT EXISTS idx_member_charge_vehicle_id ON fs.member_charge (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_member_charge_charge_type_code ON fs.member_charge (charge_type_code);
CREATE INDEX IF NOT EXISTS idx_member_charge_approved_by_user_id ON fs.member_charge (approved_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_charge_created_by_user_id ON fs.member_charge (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_charge_updated_by_user_id ON fs.member_charge (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_charge_type_created_by_user_id ON fs.member_charge_type (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_charge_type_updated_by_user_id ON fs.member_charge_type (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_date_member_id ON fs.member_date (member_id);
CREATE INDEX IF NOT EXISTS idx_member_date_date_type_code ON fs.member_date (date_type_code);
CREATE INDEX IF NOT EXISTS idx_member_date_created_by_user_id ON fs.member_date (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_date_updated_by_user_id ON fs.member_date (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_date_type_created_by_user_id ON fs.member_date_type (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_date_type_updated_by_user_id ON fs.member_date_type (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_email_member_id ON fs.member_email (member_id);
CREATE INDEX IF NOT EXISTS idx_member_email_created_by_user_id ON fs.member_email (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_email_updated_by_user_id ON fs.member_email (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_feedback_member_id ON fs.member_feedback (member_id);
CREATE INDEX IF NOT EXISTS idx_member_feedback_vehicle_trip_id ON fs.member_feedback (vehicle_trip_id);
CREATE INDEX IF NOT EXISTS idx_member_feedback_event_id ON fs.member_feedback (event_id);
CREATE INDEX IF NOT EXISTS idx_member_feedback_rating_scale_code ON fs.member_feedback (rating_scale_code);
CREATE INDEX IF NOT EXISTS idx_member_feedback_created_by_user_id ON fs.member_feedback (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_feedback_updated_by_user_id ON fs.member_feedback (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_garage_item_member_id ON fs.member_garage_item (member_id);
CREATE INDEX IF NOT EXISTS idx_member_garage_item_member_car_id ON fs.member_garage_item (member_car_id);
CREATE INDEX IF NOT EXISTS idx_member_garage_item_vehicle_id ON fs.member_garage_item (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_member_garage_item_cover_document_id ON fs.member_garage_item (cover_document_id);
CREATE INDEX IF NOT EXISTS idx_member_garage_item_created_by_user_id ON fs.member_garage_item (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_garage_item_updated_by_user_id ON fs.member_garage_item (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_insurance_coverage_policy_id ON fs.member_insurance_coverage (policy_id);
CREATE INDEX IF NOT EXISTS idx_member_insurance_coverage_insurance_type_code ON fs.member_insurance_coverage (insurance_type_code);
CREATE INDEX IF NOT EXISTS idx_member_insurance_coverage_insurance_coverage_code ON fs.member_insurance_coverage (insurance_coverage_code);
CREATE INDEX IF NOT EXISTS idx_member_insurance_coverage_created_by_user_id ON fs.member_insurance_coverage (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_insurance_coverage_updated_by_user_id ON fs.member_insurance_coverage (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_insurance_policy_member_id ON fs.member_insurance_policy (member_id);
CREATE INDEX IF NOT EXISTS idx_member_insurance_policy_carrier_code ON fs.member_insurance_policy (carrier_code);
CREATE INDEX IF NOT EXISTS idx_member_insurance_policy_created_by_user_id ON fs.member_insurance_policy (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_insurance_policy_updated_by_user_id ON fs.member_insurance_policy (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_lap_member_id ON fs.member_lap (member_id);
CREATE INDEX IF NOT EXISTS idx_member_lap_lap_rule_id ON fs.member_lap (lap_rule_id);
CREATE INDEX IF NOT EXISTS idx_member_lap_created_by_user_id ON fs.member_lap (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_lap_updated_by_user_id ON fs.member_lap (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_note_member_id ON fs.member_note (member_id);
CREATE INDEX IF NOT EXISTS idx_member_note_requested_contact_user_id ON fs.member_note (requested_contact_user_id);
CREATE INDEX IF NOT EXISTS idx_member_note_created_by_user_id ON fs.member_note (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_note_updated_by_user_id ON fs.member_note (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_note_category_created_by_user_id ON fs.member_note_category (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_note_category_updated_by_user_id ON fs.member_note_category (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_note_category_link_member_note_id ON fs.member_note_category_link (member_note_id);
CREATE INDEX IF NOT EXISTS idx_member_note_category_link_member_note_category_code ON fs.member_note_category_link (member_note_category_code);
CREATE INDEX IF NOT EXISTS idx_member_note_category_link_created_by_user_id ON fs.member_note_category_link (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_member_id ON fs.member_package (member_id);
CREATE INDEX IF NOT EXISTS idx_member_package_membership_level_id ON fs.member_package (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_member_package_corporate_account_id ON fs.member_package (corporate_account_id);
CREATE INDEX IF NOT EXISTS idx_member_package_created_by_user_id ON fs.member_package (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_updated_by_user_id ON fs.member_package (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_customization_member_id ON fs.member_package_customization (member_id);
CREATE INDEX IF NOT EXISTS idx_member_package_customization_created_by_user_id ON fs.member_package_customization (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_customization_updated_by_user_id ON fs.member_package_customization (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_hold_member_package_id ON fs.member_package_hold (member_package_id);
CREATE INDEX IF NOT EXISTS idx_member_package_hold_authorized_by_user_id ON fs.member_package_hold (authorized_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_hold_reminder_task_id ON fs.member_package_hold (reminder_task_id);
CREATE INDEX IF NOT EXISTS idx_member_package_hold_created_by_user_id ON fs.member_package_hold (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_hold_updated_by_user_id ON fs.member_package_hold (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_participant_member_package_id ON fs.member_package_participant (member_package_id);
CREATE INDEX IF NOT EXISTS idx_member_package_participant_member_id ON fs.member_package_participant (member_id);
CREATE INDEX IF NOT EXISTS idx_member_package_participant_participant_type ON fs.member_package_participant (participant_type);
CREATE INDEX IF NOT EXISTS idx_member_package_participant_granted_by_user_id ON fs.member_package_participant (granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_participant_created_by_user_id ON fs.member_package_participant (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_participant_updated_by_user_id ON fs.member_package_participant (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_rate_member_package_id ON fs.member_package_rate (member_package_id);
CREATE INDEX IF NOT EXISTS idx_member_package_rate_rate_card_id ON fs.member_package_rate (rate_card_id);
CREATE INDEX IF NOT EXISTS idx_member_package_rate_created_by_user_id ON fs.member_package_rate (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_rate_updated_by_user_id ON fs.member_package_rate (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_payment_schedule_member_package_id ON fs.member_payment_schedule (member_package_id);
CREATE INDEX IF NOT EXISTS idx_member_payment_schedule_created_by_user_id ON fs.member_payment_schedule (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_payment_schedule_updated_by_user_id ON fs.member_payment_schedule (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_phone_member_id ON fs.member_phone (member_id);
CREATE INDEX IF NOT EXISTS idx_member_phone_created_by_user_id ON fs.member_phone (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_phone_updated_by_user_id ON fs.member_phone (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_profile_member_id ON fs.member_profile (member_id);
CREATE INDEX IF NOT EXISTS idx_member_profile_photo_document_id ON fs.member_profile (photo_document_id);
CREATE INDEX IF NOT EXISTS idx_member_profile_industry_code ON fs.member_profile (industry_code);
CREATE INDEX IF NOT EXISTS idx_member_profile_referred_by_member_id ON fs.member_profile (referred_by_member_id);
CREATE INDEX IF NOT EXISTS idx_member_profile_created_by_user_id ON fs.member_profile (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_profile_updated_by_user_id ON fs.member_profile (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_relationship_member_id ON fs.member_relationship (member_id);
CREATE INDEX IF NOT EXISTS idx_member_relationship_related_member_id ON fs.member_relationship (related_member_id);
CREATE INDEX IF NOT EXISTS idx_member_relationship_created_by_user_id ON fs.member_relationship (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_relationship_updated_by_user_id ON fs.member_relationship (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_trip_story_vehicle_trip_id ON fs.member_trip_story (vehicle_trip_id);
CREATE INDEX IF NOT EXISTS idx_member_trip_story_member_id ON fs.member_trip_story (member_id);
CREATE INDEX IF NOT EXISTS idx_member_trip_story_cover_document_id ON fs.member_trip_story (cover_document_id);
CREATE INDEX IF NOT EXISTS idx_member_trip_story_created_by_user_id ON fs.member_trip_story (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_trip_story_updated_by_user_id ON fs.member_trip_story (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_trip_story_answer_member_trip_story_id ON fs.member_trip_story_answer (member_trip_story_id);
CREATE INDEX IF NOT EXISTS idx_member_trip_story_answer_member_trip_story_prompt_id ON fs.member_trip_story_answer (member_trip_story_prompt_id);
CREATE INDEX IF NOT EXISTS idx_member_trip_story_answer_created_by_user_id ON fs.member_trip_story_answer (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_trip_story_answer_updated_by_user_id ON fs.member_trip_story_answer (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_trip_story_prompt_created_by_user_id ON fs.member_trip_story_prompt (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_trip_story_prompt_updated_by_user_id ON fs.member_trip_story_prompt (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_participant_type_select_created_by_user_id ON fs.participant_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_participant_type_select_updated_by_user_id ON fs.participant_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_podium_status_benefit_podium_status_code ON fs.podium_status_benefit (podium_status_code);
CREATE INDEX IF NOT EXISTS idx_podium_status_benefit_benefit_target ON fs.podium_status_benefit (benefit_target);
CREATE INDEX IF NOT EXISTS idx_podium_status_benefit_adjustment_kind ON fs.podium_status_benefit (adjustment_kind);
CREATE INDEX IF NOT EXISTS idx_podium_status_benefit_created_by_user_id ON fs.podium_status_benefit (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_podium_status_benefit_updated_by_user_id ON fs.podium_status_benefit (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_podium_status_select_created_by_user_id ON fs.podium_status_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_podium_status_select_updated_by_user_id ON fs.podium_status_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_booking_type_select_created_by_user_id ON fs.booking_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_booking_type_select_updated_by_user_id ON fs.booking_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_membership_series_id ON fs.membership_level (membership_series_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_membership_level_type_code ON fs.membership_level (membership_level_type_code);
CREATE INDEX IF NOT EXISTS idx_membership_level_created_by_user_id ON fs.membership_level (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_updated_by_user_id ON fs.membership_level (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_bookings_membership_level_id ON fs.membership_level_bookings (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_bookings_created_by_user_id ON fs.membership_level_bookings (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_bookings_updated_by_user_id ON fs.membership_level_bookings (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_branch_availability_membership_level_id ON fs.membership_level_branch_availability (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_branch_availability_branch_id ON fs.membership_level_branch_availability (branch_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_branch_availability_granted_by_user_id ON fs.membership_level_branch_availability (granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_branch_availability_created_by_user_id ON fs.membership_level_branch_availability (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_branch_availability_updated_by_user_id ON fs.membership_level_branch_availability (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_branch_availability_revoked_by_user_id ON fs.membership_level_branch_availability (revoked_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_free_pass_membership_level_id ON fs.membership_level_free_pass (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_free_pass_tier_max_id ON fs.membership_level_free_pass (tier_max_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_free_pass_created_by_user_id ON fs.membership_level_free_pass (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_free_pass_updated_by_user_id ON fs.membership_level_free_pass (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_mileage_membership_level_id ON fs.membership_level_mileage (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_mileage_created_by_user_id ON fs.membership_level_mileage (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_mileage_updated_by_user_id ON fs.membership_level_mileage (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_perks_membership_level_id ON fs.membership_level_perks (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_perks_created_by_user_id ON fs.membership_level_perks (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_perks_updated_by_user_id ON fs.membership_level_perks (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_points_caps_membership_level_id ON fs.membership_level_points_caps (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_points_caps_created_by_user_id ON fs.membership_level_points_caps (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_points_caps_updated_by_user_id ON fs.membership_level_points_caps (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_pricing_membership_level_id ON fs.membership_level_pricing (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_pricing_branch_id ON fs.membership_level_pricing (branch_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_pricing_created_by_user_id ON fs.membership_level_pricing (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_pricing_updated_by_user_id ON fs.membership_level_pricing (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_type_select_created_by_user_id ON fs.membership_level_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_type_select_updated_by_user_id ON fs.membership_level_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_series_created_by_user_id ON fs.membership_series (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_series_updated_by_user_id ON fs.membership_series (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_series_rate_card_membership_series_id ON fs.membership_series_rate_card (membership_series_id);
CREATE INDEX IF NOT EXISTS idx_membership_series_rate_card_rate_card_id ON fs.membership_series_rate_card (rate_card_id);
CREATE INDEX IF NOT EXISTS idx_membership_series_rate_card_created_by_user_id ON fs.membership_series_rate_card (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_series_rate_card_updated_by_user_id ON fs.membership_series_rate_card (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mileage_type_select_created_by_user_id ON fs.mileage_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mileage_type_select_updated_by_user_id ON fs.mileage_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mpc_bookings_member_id ON fs.mpc_bookings (member_id);
CREATE INDEX IF NOT EXISTS idx_mpc_bookings_membership_level_id ON fs.mpc_bookings (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_mpc_bookings_booking_type ON fs.mpc_bookings (booking_type);
CREATE INDEX IF NOT EXISTS idx_mpc_bookings_created_by_user_id ON fs.mpc_bookings (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mpc_branch_access_member_package_customization_id ON fs.mpc_branch_access (member_package_customization_id);
CREATE INDEX IF NOT EXISTS idx_mpc_branch_access_branch_id ON fs.mpc_branch_access (branch_id);
CREATE INDEX IF NOT EXISTS idx_mpc_branch_access_granted_by_user_id ON fs.mpc_branch_access (granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mpc_branch_access_created_by_user_id ON fs.mpc_branch_access (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mpc_free_pass_mpc_id ON fs.mpc_free_pass (mpc_id);
CREATE INDEX IF NOT EXISTS idx_mpc_free_pass_tier_max_id_override ON fs.mpc_free_pass (tier_max_id_override);
CREATE INDEX IF NOT EXISTS idx_mpc_free_pass_created_by_user_id ON fs.mpc_free_pass (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mpc_mileage_member_id ON fs.mpc_mileage (member_id);
CREATE INDEX IF NOT EXISTS idx_mpc_mileage_membership_level_id ON fs.mpc_mileage (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_mpc_mileage_mileage_type ON fs.mpc_mileage (mileage_type);
CREATE INDEX IF NOT EXISTS idx_mpc_mileage_created_by_user_id ON fs.mpc_mileage (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mpc_perks_member_id ON fs.mpc_perks (member_id);
CREATE INDEX IF NOT EXISTS idx_mpc_perks_membership_level_id ON fs.mpc_perks (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_mpc_perks_perk_type ON fs.mpc_perks (perk_type);
CREATE INDEX IF NOT EXISTS idx_mpc_perks_created_by_user_id ON fs.mpc_perks (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mpc_points_and_caps_member_id ON fs.mpc_points_and_caps (member_id);
CREATE INDEX IF NOT EXISTS idx_mpc_points_and_caps_membership_level_id ON fs.mpc_points_and_caps (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_mpc_points_and_caps_points_cap_type ON fs.mpc_points_and_caps (points_cap_type);
CREATE INDEX IF NOT EXISTS idx_mpc_points_and_caps_created_by_user_id ON fs.mpc_points_and_caps (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mpc_pricing_member_id ON fs.mpc_pricing (member_id);
CREATE INDEX IF NOT EXISTS idx_mpc_pricing_membership_level_id ON fs.mpc_pricing (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_mpc_pricing_pricing_type ON fs.mpc_pricing (pricing_type);
CREATE INDEX IF NOT EXISTS idx_mpc_pricing_created_by_user_id ON fs.mpc_pricing (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mpc_tier_assignment_member_package_customization_id ON fs.mpc_tier_assignment (member_package_customization_id);
CREATE INDEX IF NOT EXISTS idx_mpc_tier_assignment_vehicle_id ON fs.mpc_tier_assignment (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_mpc_tier_assignment_vehicle_tier_id_override ON fs.mpc_tier_assignment (vehicle_tier_id_override);
CREATE INDEX IF NOT EXISTS idx_mpc_tier_assignment_created_by_user_id ON fs.mpc_tier_assignment (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mpc_tier_point_rate_member_package_customization_id ON fs.mpc_tier_point_rate (member_package_customization_id);
CREATE INDEX IF NOT EXISTS idx_mpc_tier_point_rate_vehicle_tier_id ON fs.mpc_tier_point_rate (vehicle_tier_id);
CREATE INDEX IF NOT EXISTS idx_mpc_tier_point_rate_created_by_user_id ON fs.mpc_tier_point_rate (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mpc_vehicle_tier_access_member_package_customization_id ON fs.mpc_vehicle_tier_access (member_package_customization_id);
CREATE INDEX IF NOT EXISTS idx_mpc_vehicle_tier_access_vehicle_tier_id ON fs.mpc_vehicle_tier_access (vehicle_tier_id);
CREATE INDEX IF NOT EXISTS idx_mpc_vehicle_tier_access_created_by_user_id ON fs.mpc_vehicle_tier_access (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_perk_type_select_created_by_user_id ON fs.perk_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_perk_type_select_updated_by_user_id ON fs.perk_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_points_cap_type_select_created_by_user_id ON fs.points_cap_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_points_cap_type_select_updated_by_user_id ON fs.points_cap_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_pricing_type_select_created_by_user_id ON fs.pricing_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_pricing_type_select_updated_by_user_id ON fs.pricing_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_created_by_user_id ON fs.rate_card (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_updated_by_user_id ON fs.rate_card (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_placement_rate_card_id ON fs.rate_card_placement (rate_card_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_placement_vehicle_id ON fs.rate_card_placement (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_placement_vehicle_tier_id ON fs.rate_card_placement (vehicle_tier_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_placement_created_by_user_id ON fs.rate_card_placement (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_placement_updated_by_user_id ON fs.rate_card_placement (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_rate_rate_card_id ON fs.rate_card_rate (rate_card_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_rate_vehicle_tier_id ON fs.rate_card_rate (vehicle_tier_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_rate_rate_card_season_id ON fs.rate_card_rate (rate_card_season_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_rate_created_by_user_id ON fs.rate_card_rate (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_rate_updated_by_user_id ON fs.rate_card_rate (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_season_rate_card_id ON fs.rate_card_season (rate_card_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_season_created_by_user_id ON fs.rate_card_season (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_rate_card_season_updated_by_user_id ON fs.rate_card_season (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_created_by_user_id ON fs.vehicle_tier (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_updated_by_user_id ON fs.vehicle_tier (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_access_membership_level_id ON fs.vehicle_tier_access (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_access_vehicle_tier_id ON fs.vehicle_tier_access (vehicle_tier_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_access_created_by_user_id ON fs.vehicle_tier_access (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_access_updated_by_user_id ON fs.vehicle_tier_access (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_template_id ON fs.notification (template_id);
CREATE INDEX IF NOT EXISTS idx_notification_recipient_user_id ON fs.notification (recipient_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_created_by_user_id ON fs.notification (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_updated_by_user_id ON fs.notification (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_delivery_log_notification_id ON fs.notification_delivery_log (notification_id);
CREATE INDEX IF NOT EXISTS idx_notification_delivery_log_provider ON fs.notification_delivery_log (provider);
CREATE INDEX IF NOT EXISTS idx_notification_delivery_log_created_by_user_id ON fs.notification_delivery_log (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_delivery_log_updated_by_user_id ON fs.notification_delivery_log (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_preference_member_id ON fs.notification_preference (member_id);
CREATE INDEX IF NOT EXISTS idx_notification_preference_updated_by_user_id ON fs.notification_preference (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_preference_created_by_user_id ON fs.notification_preference (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_template_created_by_user_id ON fs.notification_template (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_template_updated_by_user_id ON fs.notification_template (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_template_variable_template_id ON fs.notification_template_variable (template_id);
CREATE INDEX IF NOT EXISTS idx_notification_template_variable_created_by_user_id ON fs.notification_template_variable (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_template_variable_updated_by_user_id ON fs.notification_template_variable (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_credit_reason_type_created_by_user_id ON fs.credit_reason_type (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_credit_reason_type_updated_by_user_id ON fs.credit_reason_type (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_perk_credit_member_id ON fs.member_perk_credit (member_id);
CREATE INDEX IF NOT EXISTS idx_member_perk_credit_perk_type ON fs.member_perk_credit (perk_type);
CREATE INDEX IF NOT EXISTS idx_member_perk_credit_credit_reason_type_code ON fs.member_perk_credit (credit_reason_type_code);
CREATE INDEX IF NOT EXISTS idx_member_perk_credit_approved_by_user_id ON fs.member_perk_credit (approved_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_perk_credit_created_by_user_id ON fs.member_perk_credit (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_perk_credit_updated_by_user_id ON fs.member_perk_credit (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_perk_ledger_member_id ON fs.member_perk_ledger (member_id);
CREATE INDEX IF NOT EXISTS idx_member_perk_ledger_vehicle_trip_id ON fs.member_perk_ledger (vehicle_trip_id);
CREATE INDEX IF NOT EXISTS idx_member_perk_ledger_perk_type ON fs.member_perk_ledger (perk_type);
CREATE INDEX IF NOT EXISTS idx_member_perk_ledger_reservation_id ON fs.member_perk_ledger (reservation_id);
CREATE INDEX IF NOT EXISTS idx_member_perk_ledger_member_package_participant_id ON fs.member_perk_ledger (member_package_participant_id);
CREATE INDEX IF NOT EXISTS idx_member_perk_ledger_created_by_user_id ON fs.member_perk_ledger (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_perk_ledger_updated_by_user_id ON fs.member_perk_ledger (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_point_credit_member_id ON fs.member_point_credit (member_id);
CREATE INDEX IF NOT EXISTS idx_member_point_credit_credit_reason_type_code ON fs.member_point_credit (credit_reason_type_code);
CREATE INDEX IF NOT EXISTS idx_member_point_credit_approved_by_user_id ON fs.member_point_credit (approved_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_point_credit_created_by_user_id ON fs.member_point_credit (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_point_credit_updated_by_user_id ON fs.member_point_credit (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_points_carryover_member_id ON fs.member_points_carryover (member_id);
CREATE INDEX IF NOT EXISTS idx_member_points_carryover_source_package_id ON fs.member_points_carryover (source_package_id);
CREATE INDEX IF NOT EXISTS idx_member_points_carryover_allocation_package_id ON fs.member_points_carryover (allocation_package_id);
CREATE INDEX IF NOT EXISTS idx_member_points_carryover_created_by_user_id ON fs.member_points_carryover (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_points_carryover_updated_by_user_id ON fs.member_points_carryover (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_points_ledger_member_id ON fs.member_points_ledger (member_id);
CREATE INDEX IF NOT EXISTS idx_member_points_ledger_vehicle_trip_id ON fs.member_points_ledger (vehicle_trip_id);
CREATE INDEX IF NOT EXISTS idx_member_points_ledger_reservation_id ON fs.member_points_ledger (reservation_id);
CREATE INDEX IF NOT EXISTS idx_member_points_ledger_reservation_perk_application_id ON fs.member_points_ledger (reservation_perk_application_id);
CREATE INDEX IF NOT EXISTS idx_member_points_ledger_member_package_participant_id ON fs.member_points_ledger (member_package_participant_id);
CREATE INDEX IF NOT EXISTS idx_member_points_ledger_created_by_user_id ON fs.member_points_ledger (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_points_ledger_updated_by_user_id ON fs.member_points_ledger (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_destination_select_created_by_user_id ON fs.export_destination_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_destination_select_updated_by_user_id ON fs.export_destination_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_format_select_created_by_user_id ON fs.export_format_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_format_select_updated_by_user_id ON fs.export_format_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_job_requested_by_user_id ON fs.export_job (requested_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_job_export_template_id ON fs.export_job (export_template_id);
CREATE INDEX IF NOT EXISTS idx_export_job_export_format_code ON fs.export_job (export_format_code);
CREATE INDEX IF NOT EXISTS idx_export_job_export_destination_code ON fs.export_job (export_destination_code);
CREATE INDEX IF NOT EXISTS idx_export_job_approved_by_user_id ON fs.export_job (approved_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_schedule_export_template_id ON fs.export_schedule (export_template_id);
CREATE INDEX IF NOT EXISTS idx_export_schedule_created_by_user_id ON fs.export_schedule (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_schedule_updated_by_user_id ON fs.export_schedule (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_schedule_recipient_export_schedule_id ON fs.export_schedule_recipient (export_schedule_id);
CREATE INDEX IF NOT EXISTS idx_export_schedule_recipient_user_id ON fs.export_schedule_recipient (user_id);
CREATE INDEX IF NOT EXISTS idx_export_schedule_recipient_created_by_user_id ON fs.export_schedule_recipient (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_schedule_recipient_updated_by_user_id ON fs.export_schedule_recipient (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_template_export_format_code ON fs.export_template (export_format_code);
CREATE INDEX IF NOT EXISTS idx_export_template_export_destination_code ON fs.export_template (export_destination_code);
CREATE INDEX IF NOT EXISTS idx_export_template_required_permission_code ON fs.export_template (required_permission_code);
CREATE INDEX IF NOT EXISTS idx_export_template_created_by_user_id ON fs.export_template (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_export_template_updated_by_user_id ON fs.export_template (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_report_definition_required_permission_code ON fs.report_definition (required_permission_code);
CREATE INDEX IF NOT EXISTS idx_report_definition_created_by_user_id ON fs.report_definition (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_report_definition_updated_by_user_id ON fs.report_definition (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_report_job_requested_by_user_id ON fs.report_job (requested_by_user_id);
CREATE INDEX IF NOT EXISTS idx_report_schedule_report_definition_id ON fs.report_schedule (report_definition_id);
CREATE INDEX IF NOT EXISTS idx_report_schedule_created_by_user_id ON fs.report_schedule (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_report_schedule_updated_by_user_id ON fs.report_schedule (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_corporate_account_shadow_home_branch_id ON fs.corporate_account_shadow (home_branch_id);
CREATE INDEX IF NOT EXISTS idx_corporate_account_shadow_billing_state ON fs.corporate_account_shadow (billing_state);
CREATE INDEX IF NOT EXISTS idx_corporate_account_shadow_created_by_user_id ON fs.corporate_account_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_corporate_account_shadow_updated_by_user_id ON fs.corporate_account_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_corporate_account_shadow_corporate_account_id ON fs.corporate_account_shadow (corporate_account_id);
CREATE INDEX IF NOT EXISTS idx_corporate_account_shadow_changed_by_user_id ON fs.corporate_account_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_customization_shadow_member_id ON fs.member_package_customization_shadow (member_id);
CREATE INDEX IF NOT EXISTS idx_member_package_customization_shadow_created_by_user_id ON fs.member_package_customization_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_customization_shadow_updated_by_user_id ON fs.member_package_customization_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_customization_shadow_member_package_customiz ON fs.member_package_customization_shadow (member_package_customization_id);
CREATE INDEX IF NOT EXISTS idx_member_package_customization_shadow_changed_by_user_id ON fs.member_package_customization_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_shadow_member_package_id ON fs.member_package_shadow (member_package_id);
CREATE INDEX IF NOT EXISTS idx_member_package_shadow_member_id ON fs.member_package_shadow (member_id);
CREATE INDEX IF NOT EXISTS idx_member_package_shadow_membership_level_id ON fs.member_package_shadow (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_member_package_shadow_corporate_account_id ON fs.member_package_shadow (corporate_account_id);
CREATE INDEX IF NOT EXISTS idx_member_package_shadow_created_by_user_id ON fs.member_package_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_shadow_updated_by_user_id ON fs.member_package_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_package_shadow_changed_by_user_id ON fs.member_package_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_payment_schedule_shadow_member_package_id ON fs.member_payment_schedule_shadow (member_package_id);
CREATE INDEX IF NOT EXISTS idx_member_payment_schedule_shadow_created_by_user_id ON fs.member_payment_schedule_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_payment_schedule_shadow_updated_by_user_id ON fs.member_payment_schedule_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_payment_schedule_shadow_member_payment_schedule_id ON fs.member_payment_schedule_shadow (member_payment_schedule_id);
CREATE INDEX IF NOT EXISTS idx_member_payment_schedule_shadow_changed_by_user_id ON fs.member_payment_schedule_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_shadow_user_id ON fs.member_shadow (user_id);
CREATE INDEX IF NOT EXISTS idx_member_shadow_home_branch_id ON fs.member_shadow (home_branch_id);
CREATE INDEX IF NOT EXISTS idx_member_shadow_license_state ON fs.member_shadow (license_state);
CREATE INDEX IF NOT EXISTS idx_member_shadow_podium_status ON fs.member_shadow (podium_status);
CREATE INDEX IF NOT EXISTS idx_member_shadow_created_by_user_id ON fs.member_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_shadow_updated_by_user_id ON fs.member_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_member_shadow_member_id ON fs.member_shadow (member_id);
CREATE INDEX IF NOT EXISTS idx_member_shadow_changed_by_user_id ON fs.member_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_bookings_shadow_membership_level_id ON fs.membership_level_bookings_shadow (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_bookings_shadow_created_by_user_id ON fs.membership_level_bookings_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_bookings_shadow_updated_by_user_id ON fs.membership_level_bookings_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_bookings_shadow_membership_level_bookings_ ON fs.membership_level_bookings_shadow (membership_level_bookings_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_bookings_shadow_changed_by_user_id ON fs.membership_level_bookings_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_free_pass_shadow_membership_level_id ON fs.membership_level_free_pass_shadow (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_free_pass_shadow_tier_max_id ON fs.membership_level_free_pass_shadow (tier_max_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_free_pass_shadow_created_by_user_id ON fs.membership_level_free_pass_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_free_pass_shadow_updated_by_user_id ON fs.membership_level_free_pass_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_free_pass_shadow_membership_level_free_pas ON fs.membership_level_free_pass_shadow (membership_level_free_pass_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_free_pass_shadow_changed_by_user_id ON fs.membership_level_free_pass_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_mileage_shadow_membership_level_id ON fs.membership_level_mileage_shadow (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_mileage_shadow_created_by_user_id ON fs.membership_level_mileage_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_mileage_shadow_updated_by_user_id ON fs.membership_level_mileage_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_mileage_shadow_membership_level_mileage_id ON fs.membership_level_mileage_shadow (membership_level_mileage_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_mileage_shadow_changed_by_user_id ON fs.membership_level_mileage_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_perks_shadow_membership_level_id ON fs.membership_level_perks_shadow (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_perks_shadow_created_by_user_id ON fs.membership_level_perks_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_perks_shadow_updated_by_user_id ON fs.membership_level_perks_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_perks_shadow_membership_level_perks_id ON fs.membership_level_perks_shadow (membership_level_perks_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_perks_shadow_changed_by_user_id ON fs.membership_level_perks_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_points_caps_shadow_membership_level_id ON fs.membership_level_points_caps_shadow (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_points_caps_shadow_created_by_user_id ON fs.membership_level_points_caps_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_points_caps_shadow_updated_by_user_id ON fs.membership_level_points_caps_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_points_caps_shadow_membership_level_points ON fs.membership_level_points_caps_shadow (membership_level_points_caps_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_points_caps_shadow_changed_by_user_id ON fs.membership_level_points_caps_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_shadow_membership_series_id ON fs.membership_level_shadow (membership_series_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_shadow_membership_level_type_code ON fs.membership_level_shadow (membership_level_type_code);
CREATE INDEX IF NOT EXISTS idx_membership_level_shadow_created_by_user_id ON fs.membership_level_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_shadow_updated_by_user_id ON fs.membership_level_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_shadow_membership_level_id ON fs.membership_level_shadow (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_membership_level_shadow_changed_by_user_id ON fs.membership_level_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_role_shadow_created_by_user_id ON fs.role_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_role_shadow_updated_by_user_id ON fs.role_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_role_shadow_role_id ON fs.role_shadow (role_id);
CREATE INDEX IF NOT EXISTS idx_role_shadow_changed_by_user_id ON fs.role_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_shadow_user_id ON fs.staff_shadow (user_id);
CREATE INDEX IF NOT EXISTS idx_staff_shadow_home_branch_id ON fs.staff_shadow (home_branch_id);
CREATE INDEX IF NOT EXISTS idx_staff_shadow_created_by_user_id ON fs.staff_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_shadow_updated_by_user_id ON fs.staff_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_shadow_license_state ON fs.staff_shadow (license_state);
CREATE INDEX IF NOT EXISTS idx_staff_shadow_staff_id ON fs.staff_shadow (staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_shadow_changed_by_user_id ON fs.staff_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_shadow_mfa_method_code ON fs.user_shadow (mfa_method_code);
CREATE INDEX IF NOT EXISTS idx_user_shadow_default_view_code ON fs.user_shadow (default_view_code);
CREATE INDEX IF NOT EXISTS idx_user_shadow_created_by_user_id ON fs.user_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_shadow_updated_by_user_id ON fs.user_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_shadow_user_id ON fs.user_shadow (user_id);
CREATE INDEX IF NOT EXISTS idx_user_shadow_changed_by_user_id ON fs.user_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_financing_lifecycle_shadow_vehicle_id ON fs.vehicle_financing_lifecycle_shadow (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_financing_lifecycle_shadow_created_by_user_id ON fs.vehicle_financing_lifecycle_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_financing_lifecycle_shadow_updated_by_user_id ON fs.vehicle_financing_lifecycle_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_financing_lifecycle_shadow_vehicle_financing_lifecy ON fs.vehicle_financing_lifecycle_shadow (vehicle_financing_lifecycle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_financing_lifecycle_shadow_changed_by_user_id ON fs.vehicle_financing_lifecycle_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_partner_shadow_state ON fs.vehicle_partner_shadow (state);
CREATE INDEX IF NOT EXISTS idx_vehicle_partner_shadow_created_by_user_id ON fs.vehicle_partner_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_partner_shadow_updated_by_user_id ON fs.vehicle_partner_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_partner_shadow_vehicle_partner_id ON fs.vehicle_partner_shadow (vehicle_partner_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_partner_shadow_changed_by_user_id ON fs.vehicle_partner_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_registration_warranty_shadow_vehicle_id ON fs.vehicle_registration_warranty_shadow (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_registration_warranty_shadow_registration_state ON fs.vehicle_registration_warranty_shadow (registration_state);
CREATE INDEX IF NOT EXISTS idx_vehicle_registration_warranty_shadow_created_by_user_id ON fs.vehicle_registration_warranty_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_registration_warranty_shadow_updated_by_user_id ON fs.vehicle_registration_warranty_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_registration_warranty_shadow_vehicle_registration_w ON fs.vehicle_registration_warranty_shadow (vehicle_registration_warranty_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_registration_warranty_shadow_changed_by_user_id ON fs.vehicle_registration_warranty_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_shadow_vehicle_make_code ON fs.vehicle_shadow (vehicle_make_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_shadow_year ON fs.vehicle_shadow (year);
CREATE INDEX IF NOT EXISTS idx_vehicle_shadow_exterior_color_short ON fs.vehicle_shadow (exterior_color_short);
CREATE INDEX IF NOT EXISTS idx_vehicle_shadow_interior_color ON fs.vehicle_shadow (interior_color);
CREATE INDEX IF NOT EXISTS idx_vehicle_shadow_condition_code ON fs.vehicle_shadow (condition_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_shadow_home_branch_id ON fs.vehicle_shadow (home_branch_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_shadow_created_by_user_id ON fs.vehicle_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_shadow_updated_by_user_id ON fs.vehicle_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_shadow_vehicle_id ON fs.vehicle_shadow (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_shadow_changed_by_user_id ON fs.vehicle_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_access_shadow_membership_level_id ON fs.vehicle_tier_access_shadow (membership_level_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_access_shadow_vehicle_tier_id ON fs.vehicle_tier_access_shadow (vehicle_tier_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_access_shadow_created_by_user_id ON fs.vehicle_tier_access_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_access_shadow_updated_by_user_id ON fs.vehicle_tier_access_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_access_shadow_vehicle_tier_access_id ON fs.vehicle_tier_access_shadow (vehicle_tier_access_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tier_access_shadow_changed_by_user_id ON fs.vehicle_tier_access_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_shadow_home_branch_id ON fs.vendor_shadow (home_branch_id);
CREATE INDEX IF NOT EXISTS idx_vendor_shadow_created_by_user_id ON fs.vendor_shadow (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_shadow_updated_by_user_id ON fs.vendor_shadow (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_shadow_vendor_type_code ON fs.vendor_shadow (vendor_type_code);
CREATE INDEX IF NOT EXISTS idx_vendor_shadow_state ON fs.vendor_shadow (state);
CREATE INDEX IF NOT EXISTS idx_vendor_shadow_vendor_id ON fs.vendor_shadow (vendor_id);
CREATE INDEX IF NOT EXISTS idx_vendor_shadow_changed_by_user_id ON fs.vendor_shadow (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_user_id ON fs.staff (user_id);
CREATE INDEX IF NOT EXISTS idx_staff_home_branch_id ON fs.staff (home_branch_id);
CREATE INDEX IF NOT EXISTS idx_staff_license_state ON fs.staff (license_state);
CREATE INDEX IF NOT EXISTS idx_staff_created_by_user_id ON fs.staff (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_updated_by_user_id ON fs.staff (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_email_staff_id ON fs.staff_email (staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_email_created_by_user_id ON fs.staff_email (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_email_updated_by_user_id ON fs.staff_email (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_phone_staff_id ON fs.staff_phone (staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_phone_created_by_user_id ON fs.staff_phone (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_phone_updated_by_user_id ON fs.staff_phone (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_day_of_month_select_created_by_user_id ON fs.day_of_month_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_day_of_month_select_updated_by_user_id ON fs.day_of_month_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_day_of_week_select_created_by_user_id ON fs.day_of_week_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_day_of_week_select_updated_by_user_id ON fs.day_of_week_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_holiday_definition_branch_id ON fs.holiday_definition (branch_id);
CREATE INDEX IF NOT EXISTS idx_holiday_definition_restricted_date_type_code ON fs.holiday_definition (restricted_date_type_code);
CREATE INDEX IF NOT EXISTS idx_holiday_definition_created_by_user_id ON fs.holiday_definition (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_holiday_definition_updated_by_user_id ON fs.holiday_definition (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_month_select_created_by_user_id ON fs.month_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_month_select_updated_by_user_id ON fs.month_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_platform_setting_created_by_user_id ON fs.platform_setting (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_platform_setting_updated_by_user_id ON fs.platform_setting (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_restricted_date_type_select_created_by_user_id ON fs.restricted_date_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_restricted_date_type_select_updated_by_user_id ON fs.restricted_date_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_state_select_created_by_user_id ON fs.state_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_state_select_updated_by_user_id ON fs.state_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_target_table_select_created_by_user_id ON fs.target_table_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_target_table_select_updated_by_user_id ON fs.target_table_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_timezone_select_created_by_user_id ON fs.timezone_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_timezone_select_updated_by_user_id ON fs.timezone_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_task_status_code ON fs.task (task_status_code);
CREATE INDEX IF NOT EXISTS idx_task_task_priority_code ON fs.task (task_priority_code);
CREATE INDEX IF NOT EXISTS idx_task_task_type_code ON fs.task (task_type_code);
CREATE INDEX IF NOT EXISTS idx_task_assigned_to_user_id ON fs.task (assigned_to_user_id);
CREATE INDEX IF NOT EXISTS idx_task_cancelled_by_user_id ON fs.task (cancelled_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_assigned_by_user_id ON fs.task (assigned_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_verified_by_user_id ON fs.task (verified_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_created_by_user_id ON fs.task (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_updated_by_user_id ON fs.task (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_assignment_task_id ON fs.task_assignment (task_id);
CREATE INDEX IF NOT EXISTS idx_task_assignment_user_id ON fs.task_assignment (user_id);
CREATE INDEX IF NOT EXISTS idx_task_assignment_role_id ON fs.task_assignment (role_id);
CREATE INDEX IF NOT EXISTS idx_task_assignment_branch_id ON fs.task_assignment (branch_id);
CREATE INDEX IF NOT EXISTS idx_task_assignment_assigned_by_user_id ON fs.task_assignment (assigned_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_assignment_created_by_user_id ON fs.task_assignment (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_assignment_updated_by_user_id ON fs.task_assignment (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_audit_log_task_id ON fs.task_audit_log (task_id);
CREATE INDEX IF NOT EXISTS idx_task_audit_log_actor_user_id ON fs.task_audit_log (actor_user_id);
CREATE INDEX IF NOT EXISTS idx_task_checklist_item_task_id ON fs.task_checklist_item (task_id);
CREATE INDEX IF NOT EXISTS idx_task_checklist_item_assigned_to_user_id ON fs.task_checklist_item (assigned_to_user_id);
CREATE INDEX IF NOT EXISTS idx_task_checklist_item_depends_on_item_id ON fs.task_checklist_item (depends_on_item_id);
CREATE INDEX IF NOT EXISTS idx_task_checklist_item_completed_by_user_id ON fs.task_checklist_item (completed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_checklist_item_created_by_user_id ON fs.task_checklist_item (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_checklist_item_updated_by_user_id ON fs.task_checklist_item (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_comment_task_id ON fs.task_comment (task_id);
CREATE INDEX IF NOT EXISTS idx_task_comment_user_id ON fs.task_comment (user_id);
CREATE INDEX IF NOT EXISTS idx_task_dependency_task_id ON fs.task_dependency (task_id);
CREATE INDEX IF NOT EXISTS idx_task_dependency_depends_on_task_id ON fs.task_dependency (depends_on_task_id);
CREATE INDEX IF NOT EXISTS idx_task_dependency_assigned_by_user_id ON fs.task_dependency (assigned_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_dependency_created_by_user_id ON fs.task_dependency (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_dependency_updated_by_user_id ON fs.task_dependency (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_log_task_id ON fs.task_escalation_log (task_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_log_task_escalation_path_level_id ON fs.task_escalation_log (task_escalation_path_level_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_log_role_id ON fs.task_escalation_log (role_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_log_escalated_to_user_id ON fs.task_escalation_log (escalated_to_user_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_log_created_by_user_id ON fs.task_escalation_log (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_log_updated_by_user_id ON fs.task_escalation_log (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_path_created_by_user_id ON fs.task_escalation_path (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_path_updated_by_user_id ON fs.task_escalation_path (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_path_level_task_escalation_path_id ON fs.task_escalation_path_level (task_escalation_path_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_path_level_role_id ON fs.task_escalation_path_level (role_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_path_level_created_by_user_id ON fs.task_escalation_path_level (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_escalation_path_level_updated_by_user_id ON fs.task_escalation_path_level (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_link_task_id ON fs.task_link (task_id);
CREATE INDEX IF NOT EXISTS idx_task_link_target_table ON fs.task_link (target_table);
CREATE INDEX IF NOT EXISTS idx_task_link_created_by_user_id ON fs.task_link (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_link_updated_by_user_id ON fs.task_link (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_priority_created_by_user_id ON fs.task_priority (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_priority_updated_by_user_id ON fs.task_priority (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_status_created_by_user_id ON fs.task_status (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_status_updated_by_user_id ON fs.task_status (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_tag_task_id ON fs.task_tag (task_id);
CREATE INDEX IF NOT EXISTS idx_task_tag_created_by_user_id ON fs.task_tag (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_tag_updated_by_user_id ON fs.task_tag (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_template_default_task_type_code ON fs.task_template (default_task_type_code);
CREATE INDEX IF NOT EXISTS idx_task_template_default_priority_code ON fs.task_template (default_priority_code);
CREATE INDEX IF NOT EXISTS idx_task_template_default_assignee_user_id ON fs.task_template (default_assignee_user_id);
CREATE INDEX IF NOT EXISTS idx_task_template_created_by_user_id ON fs.task_template (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_template_updated_by_user_id ON fs.task_template (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_template_step_task_template_id ON fs.task_template_step (task_template_id);
CREATE INDEX IF NOT EXISTS idx_task_template_step_default_task_type_code ON fs.task_template_step (default_task_type_code);
CREATE INDEX IF NOT EXISTS idx_task_template_step_default_priority_code ON fs.task_template_step (default_priority_code);
CREATE INDEX IF NOT EXISTS idx_task_template_step_default_assignee_user_id ON fs.task_template_step (default_assignee_user_id);
CREATE INDEX IF NOT EXISTS idx_task_template_step_created_by_user_id ON fs.task_template_step (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_template_step_updated_by_user_id ON fs.task_template_step (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_template_step_dependency_task_template_step_id ON fs.task_template_step_dependency (task_template_step_id);
CREATE INDEX IF NOT EXISTS idx_task_template_step_dependency_depends_on_step_id ON fs.task_template_step_dependency (depends_on_step_id);
CREATE INDEX IF NOT EXISTS idx_task_template_step_dependency_created_by_user_id ON fs.task_template_step_dependency (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_template_step_dependency_updated_by_user_id ON fs.task_template_step_dependency (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_type_select_task_escalation_path_id ON fs.task_type_select (task_escalation_path_id);
CREATE INDEX IF NOT EXISTS idx_task_type_select_created_by_user_id ON fs.task_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_task_type_select_updated_by_user_id ON fs.task_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_access_event_type_select_created_by_user_id ON fs.access_event_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_access_event_type_select_updated_by_user_id ON fs.access_event_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_access_log_access_event_type_code ON fs.access_log (access_event_type_code);
CREATE INDEX IF NOT EXISTS idx_access_log_user_id ON fs.access_log (user_id);
CREATE INDEX IF NOT EXISTS idx_access_log_branch_id ON fs.access_log (branch_id);
CREATE INDEX IF NOT EXISTS idx_access_log_permission_code ON fs.access_log (permission_code);
CREATE INDEX IF NOT EXISTS idx_access_log_export_entity_type ON fs.access_log (export_entity_type);
CREATE INDEX IF NOT EXISTS idx_access_log_export_format_code ON fs.access_log (export_format_code);
CREATE INDEX IF NOT EXISTS idx_access_log_export_destination_code ON fs.access_log (export_destination_code);
CREATE INDEX IF NOT EXISTS idx_mfa_method_select_created_by_user_id ON fs.mfa_method_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mfa_method_select_updated_by_user_id ON fs.mfa_method_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_permission_created_by_user_id ON fs.permission (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_permission_updated_by_user_id ON fs.permission (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_role_created_by_user_id ON fs.role (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_role_updated_by_user_id ON fs.role (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_role_permission_granted_by_user_id ON fs.role_permission (granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_role_permission_created_by_user_id ON fs.role_permission (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_role_permission_updated_by_user_id ON fs.role_permission (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_role_permission_revoked_by_user_id ON fs.role_permission (revoked_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_mfa_method_code ON fs."user" (mfa_method_code);
CREATE INDEX IF NOT EXISTS idx_user_default_view_code ON fs."user" (default_view_code);
CREATE INDEX IF NOT EXISTS idx_user_created_by_user_id ON fs."user" (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_updated_by_user_id ON fs."user" (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_device_user_id ON fs.user_device (user_id);
CREATE INDEX IF NOT EXISTS idx_user_device_created_by_user_id ON fs.user_device (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_device_updated_by_user_id ON fs.user_device (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_mfa_recovery_code_user_id ON fs.user_mfa_recovery_code (user_id);
CREATE INDEX IF NOT EXISTS idx_user_mfa_recovery_code_created_by_user_id ON fs.user_mfa_recovery_code (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_mfa_recovery_code_updated_by_user_id ON fs.user_mfa_recovery_code (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_role_granted_by_user_id ON fs.user_role (granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_role_created_by_user_id ON fs.user_role (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_role_updated_by_user_id ON fs.user_role (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_role_revoked_by_user_id ON fs.user_role (revoked_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_trusted_device_user_id ON fs.user_trusted_device (user_id);
CREATE INDEX IF NOT EXISTS idx_user_trusted_device_created_by_user_id ON fs.user_trusted_device (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_trusted_device_updated_by_user_id ON fs.user_trusted_device (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_view_select_created_by_user_id ON fs.user_view_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_user_view_select_updated_by_user_id ON fs.user_view_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_vehicle_event_id ON fs.vehicle_inspection (vehicle_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_vehicle_id ON fs.vehicle_inspection (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_inspection_type ON fs.vehicle_inspection (inspection_type);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_vehicle_odometer_id ON fs.vehicle_inspection (vehicle_odometer_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_source_type_code ON fs.vehicle_inspection (source_type_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_inspector_user_id ON fs.vehicle_inspection (inspector_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_created_by_user_id ON fs.vehicle_inspection (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_updated_by_user_id ON fs.vehicle_inspection (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkin_vehicle_event_id ON fs.vehicle_inspection_checkin (vehicle_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkin_vehicle_id ON fs.vehicle_inspection_checkin (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkin_reservation_id ON fs.vehicle_inspection_checkin (reservation_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkin_vehicle_odometer_id ON fs.vehicle_inspection_checkin (vehicle_odometer_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkin_inspector_user_id ON fs.vehicle_inspection_checkin (inspector_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkin_created_by_user_id ON fs.vehicle_inspection_checkin (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkin_updated_by_user_id ON fs.vehicle_inspection_checkin (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkout_vehicle_event_id ON fs.vehicle_inspection_checkout (vehicle_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkout_vehicle_id ON fs.vehicle_inspection_checkout (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkout_reservation_id ON fs.vehicle_inspection_checkout (reservation_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkout_vehicle_odometer_id ON fs.vehicle_inspection_checkout (vehicle_odometer_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkout_inspector_user_id ON fs.vehicle_inspection_checkout (inspector_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkout_created_by_user_id ON fs.vehicle_inspection_checkout (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkout_updated_by_user_id ON fs.vehicle_inspection_checkout (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkup_inspection_id ON fs.vehicle_inspection_checkup (inspection_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkup_vehicle_id ON fs.vehicle_inspection_checkup (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkup_vehicle_odometer_id ON fs.vehicle_inspection_checkup (vehicle_odometer_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkup_created_by_user_id ON fs.vehicle_inspection_checkup (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_checkup_updated_by_user_id ON fs.vehicle_inspection_checkup (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_damage_vehicle_event_id ON fs.vehicle_inspection_damage (vehicle_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_damage_vehicle_id ON fs.vehicle_inspection_damage (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_damage_reservation_id ON fs.vehicle_inspection_damage (reservation_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_damage_inspection_issue_id ON fs.vehicle_inspection_damage (inspection_issue_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_damage_inspector_user_id ON fs.vehicle_inspection_damage (inspector_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_damage_created_by_user_id ON fs.vehicle_inspection_damage (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_damage_updated_by_user_id ON fs.vehicle_inspection_damage (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_fuel_vehicle_event_id ON fs.vehicle_inspection_fuel (vehicle_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_fuel_vehicle_id ON fs.vehicle_inspection_fuel (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_fuel_reservation_id ON fs.vehicle_inspection_fuel (reservation_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_fuel_odometer_log_id ON fs.vehicle_inspection_fuel (odometer_log_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_fuel_billed_member_id ON fs.vehicle_inspection_fuel (billed_member_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_fuel_inspector_user_id ON fs.vehicle_inspection_fuel (inspector_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_fuel_created_by_user_id ON fs.vehicle_inspection_fuel (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_fuel_updated_by_user_id ON fs.vehicle_inspection_fuel (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_initial_vehicle_event_id ON fs.vehicle_inspection_initial (vehicle_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_initial_vehicle_id ON fs.vehicle_inspection_initial (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_initial_inspection_type_code ON fs.vehicle_inspection_initial (inspection_type_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_initial_vehicle_odometer_id ON fs.vehicle_inspection_initial (vehicle_odometer_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_initial_inspector_user_id ON fs.vehicle_inspection_initial (inspector_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_initial_created_by_user_id ON fs.vehicle_inspection_initial (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_initial_updated_by_user_id ON fs.vehicle_inspection_initial (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_issue_inspection_id ON fs.vehicle_inspection_issue (inspection_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_issue_vehicle_id ON fs.vehicle_inspection_issue (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_issue_attachment_id ON fs.vehicle_inspection_issue (attachment_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_issue_task_id ON fs.vehicle_inspection_issue (task_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_issue_resolved_by_user_id ON fs.vehicle_inspection_issue (resolved_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_issue_created_by_user_id ON fs.vehicle_inspection_issue (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_issue_updated_by_user_id ON fs.vehicle_inspection_issue (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_item_left_vehicle_event_id ON fs.vehicle_inspection_item_left (vehicle_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_item_left_vehicle_id ON fs.vehicle_inspection_item_left (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_item_left_reservation_id ON fs.vehicle_inspection_item_left (reservation_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_item_left_inspection_issue_id ON fs.vehicle_inspection_item_left (inspection_issue_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_item_left_inspector_user_id ON fs.vehicle_inspection_item_left (inspector_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_item_left_created_by_user_id ON fs.vehicle_inspection_item_left (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_item_left_updated_by_user_id ON fs.vehicle_inspection_item_left (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_transfer_vehicle_event_id ON fs.vehicle_inspection_transfer (vehicle_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_transfer_vehicle_id ON fs.vehicle_inspection_transfer (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_transfer_inspection_type_code ON fs.vehicle_inspection_transfer (inspection_type_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_transfer_vehicle_trip_id ON fs.vehicle_inspection_transfer (vehicle_trip_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_transfer_origin_branch_id ON fs.vehicle_inspection_transfer (origin_branch_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_transfer_destination_branch_id ON fs.vehicle_inspection_transfer (destination_branch_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_transfer_vehicle_odometer_id ON fs.vehicle_inspection_transfer (vehicle_odometer_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_transfer_fuel_level_code ON fs.vehicle_inspection_transfer (fuel_level_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_transfer_inspector_user_id ON fs.vehicle_inspection_transfer (inspector_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_transfer_created_by_user_id ON fs.vehicle_inspection_transfer (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_transfer_updated_by_user_id ON fs.vehicle_inspection_transfer (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_type_created_by_user_id ON fs.vehicle_inspection_type (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_type_updated_by_user_id ON fs.vehicle_inspection_type (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_wheels_tires_vehicle_event_id ON fs.vehicle_inspection_wheels_tires (vehicle_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_wheels_tires_vehicle_id ON fs.vehicle_inspection_wheels_tires (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_wheels_tires_odometer_log_id ON fs.vehicle_inspection_wheels_tires (odometer_log_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_wheels_tires_inspector_user_id ON fs.vehicle_inspection_wheels_tires (inspector_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_wheels_tires_created_by_user_id ON fs.vehicle_inspection_wheels_tires (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inspection_wheels_tires_updated_by_user_id ON fs.vehicle_inspection_wheels_tires (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_partner_state ON fs.vehicle_partner (state);
CREATE INDEX IF NOT EXISTS idx_vehicle_partner_created_by_user_id ON fs.vehicle_partner (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_partner_updated_by_user_id ON fs.vehicle_partner (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_partner_contact_vehicle_partner_id ON fs.vehicle_partner_contact (vehicle_partner_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_partner_contact_created_by_user_id ON fs.vehicle_partner_contact (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_partner_contact_updated_by_user_id ON fs.vehicle_partner_contact (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_guarantee_group_vehicle_partner_id ON fs.vop_guarantee_group (vehicle_partner_id);
CREATE INDEX IF NOT EXISTS idx_vop_guarantee_group_created_by_user_id ON fs.vop_guarantee_group (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_guarantee_group_updated_by_user_id ON fs.vop_guarantee_group (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_guarantee_group_plan_vop_guarantee_group_id ON fs.vop_guarantee_group_plan (vop_guarantee_group_id);
CREATE INDEX IF NOT EXISTS idx_vop_guarantee_group_plan_vop_plan_id ON fs.vop_guarantee_group_plan (vop_plan_id);
CREATE INDEX IF NOT EXISTS idx_vop_guarantee_group_plan_created_by_user_id ON fs.vop_guarantee_group_plan (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_guarantee_group_plan_updated_by_user_id ON fs.vop_guarantee_group_plan (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_log_vehicle_id ON fs.vop_payout_log (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_log_vop_plan_id ON fs.vop_payout_log (vop_plan_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_log_vehicle_partner_id ON fs.vop_payout_log (vehicle_partner_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_log_vehicle_reservation_id ON fs.vop_payout_log (vehicle_reservation_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_log_vehicle_trip_id ON fs.vop_payout_log (vehicle_trip_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_log_payout_period_id ON fs.vop_payout_log (payout_period_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_log_created_by_user_id ON fs.vop_payout_log (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_log_updated_by_user_id ON fs.vop_payout_log (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_period_created_by_user_id ON fs.vop_payout_period (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_period_updated_by_user_id ON fs.vop_payout_period (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_summary_payout_period_id ON fs.vop_payout_summary (payout_period_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_summary_vop_plan_id ON fs.vop_payout_summary (vop_plan_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_summary_vehicle_id ON fs.vop_payout_summary (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_summary_vehicle_partner_id ON fs.vop_payout_summary (vehicle_partner_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_summary_created_by_user_id ON fs.vop_payout_summary (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_payout_summary_updated_by_user_id ON fs.vop_payout_summary (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_plan_vehicle_id ON fs.vop_plan (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vop_plan_vehicle_partner_id ON fs.vop_plan (vehicle_partner_id);
CREATE INDEX IF NOT EXISTS idx_vop_plan_created_by_user_id ON fs.vop_plan (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vop_plan_updated_by_user_id ON fs.vop_plan (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_hold_vehicle_reservation_id ON fs.reservation_hold (vehicle_reservation_id);
CREATE INDEX IF NOT EXISTS idx_reservation_hold_hold_reason_code ON fs.reservation_hold (hold_reason_code);
CREATE INDEX IF NOT EXISTS idx_reservation_hold_placed_by_user_id ON fs.reservation_hold (placed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_hold_released_by_user_id ON fs.reservation_hold (released_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_hold_created_by_user_id ON fs.reservation_hold (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_hold_updated_by_user_id ON fs.reservation_hold (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_hold_reason_select_created_by_user_id ON fs.reservation_hold_reason_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_hold_reason_select_updated_by_user_id ON fs.reservation_hold_reason_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_location_select_state ON fs.reservation_location_select (state);
CREATE INDEX IF NOT EXISTS idx_reservation_location_select_created_by_user_id ON fs.reservation_location_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_location_select_updated_by_user_id ON fs.reservation_location_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_perk_application_reservation_id ON fs.reservation_perk_application (reservation_id);
CREATE INDEX IF NOT EXISTS idx_reservation_perk_application_member_id ON fs.reservation_perk_application (member_id);
CREATE INDEX IF NOT EXISTS idx_reservation_perk_application_perk_type ON fs.reservation_perk_application (perk_type);
CREATE INDEX IF NOT EXISTS idx_reservation_perk_application_vehicle_tier_id_applied ON fs.reservation_perk_application (vehicle_tier_id_applied);
CREATE INDEX IF NOT EXISTS idx_reservation_perk_application_member_package_id ON fs.reservation_perk_application (member_package_id);
CREATE INDEX IF NOT EXISTS idx_reservation_perk_application_created_by_user_id ON fs.reservation_perk_application (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_perk_application_updated_by_user_id ON fs.reservation_perk_application (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_protected_period_branch_id ON fs.reservation_protected_period (branch_id);
CREATE INDEX IF NOT EXISTS idx_reservation_protected_period_created_by_user_id ON fs.reservation_protected_period (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_protected_period_updated_by_user_id ON fs.reservation_protected_period (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_protection_reservation_protected_period_id ON fs.reservation_protection (reservation_protected_period_id);
CREATE INDEX IF NOT EXISTS idx_reservation_protection_vehicle_id ON fs.reservation_protection (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_reservation_protection_booked_reservation_id ON fs.reservation_protection (booked_reservation_id);
CREATE INDEX IF NOT EXISTS idx_reservation_protection_created_by_user_id ON fs.reservation_protection (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_protection_updated_by_user_id ON fs.reservation_protection (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_restricted_dates_branch_id ON fs.reservation_restricted_dates (branch_id);
CREATE INDEX IF NOT EXISTS idx_reservation_restricted_dates_restricted_date_type_code ON fs.reservation_restricted_dates (restricted_date_type_code);
CREATE INDEX IF NOT EXISTS idx_reservation_restricted_dates_holiday_definition_id ON fs.reservation_restricted_dates (holiday_definition_id);
CREATE INDEX IF NOT EXISTS idx_reservation_restricted_dates_created_by_user_id ON fs.reservation_restricted_dates (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_restricted_dates_updated_by_user_id ON fs.reservation_restricted_dates (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_rule_created_by_user_id ON fs.reservation_rule (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_rule_updated_by_user_id ON fs.reservation_rule (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_source_type_select_created_by_user_id ON fs.reservation_source_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_source_type_select_updated_by_user_id ON fs.reservation_source_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_status_history_reservation_id ON fs.reservation_status_history (reservation_id);
CREATE INDEX IF NOT EXISTS idx_reservation_status_history_status_reason_code ON fs.reservation_status_history (status_reason_code);
CREATE INDEX IF NOT EXISTS idx_reservation_status_history_created_by_user_id ON fs.reservation_status_history (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_status_history_updated_by_user_id ON fs.reservation_status_history (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_status_reason_select_created_by_user_id ON fs.reservation_status_reason_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_status_reason_select_updated_by_user_id ON fs.reservation_status_reason_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_status_select_created_by_user_id ON fs.reservation_status_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_status_select_updated_by_user_id ON fs.reservation_status_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_type_select_created_by_user_id ON fs.reservation_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_type_select_updated_by_user_id ON fs.reservation_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_watch_branch_id ON fs.reservation_watch (branch_id);
CREATE INDEX IF NOT EXISTS idx_reservation_watch_vehicle_id ON fs.reservation_watch (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_reservation_watch_watch_reason_code ON fs.reservation_watch (watch_reason_code);
CREATE INDEX IF NOT EXISTS idx_reservation_watch_escalated_to_withhold_id ON fs.reservation_watch (escalated_to_withhold_id);
CREATE INDEX IF NOT EXISTS idx_reservation_watch_created_by_user_id ON fs.reservation_watch (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_watch_updated_by_user_id ON fs.reservation_watch (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_withhold_branch_id ON fs.reservation_withhold (branch_id);
CREATE INDEX IF NOT EXISTS idx_reservation_withhold_vehicle_id ON fs.reservation_withhold (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_reservation_withhold_withhold_reason_code ON fs.reservation_withhold (withhold_reason_code);
CREATE INDEX IF NOT EXISTS idx_reservation_withhold_placed_by_user_id ON fs.reservation_withhold (placed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_withhold_released_by_user_id ON fs.reservation_withhold (released_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_withhold_created_by_user_id ON fs.reservation_withhold (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_withhold_updated_by_user_id ON fs.reservation_withhold (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_withhold_reason_select_created_by_user_id ON fs.reservation_withhold_reason_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_withhold_reason_select_updated_by_user_id ON fs.reservation_withhold_reason_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_allowance_vehicle_id ON fs.vehicle_access_allowance (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_allowance_member_id ON fs.vehicle_access_allowance (member_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_allowance_added_by_user_id ON fs.vehicle_access_allowance (added_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_allowance_removed_by_user_id ON fs.vehicle_access_allowance (removed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_allowance_created_by_user_id ON fs.vehicle_access_allowance (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_allowance_updated_by_user_id ON fs.vehicle_access_allowance (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_exclusion_vehicle_id ON fs.vehicle_access_exclusion (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_exclusion_member_id ON fs.vehicle_access_exclusion (member_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_exclusion_corporate_account_id ON fs.vehicle_access_exclusion (corporate_account_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_exclusion_applied_by_user_id ON fs.vehicle_access_exclusion (applied_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_exclusion_removed_by_user_id ON fs.vehicle_access_exclusion (removed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_exclusion_created_by_user_id ON fs.vehicle_access_exclusion (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_exclusion_updated_by_user_id ON fs.vehicle_access_exclusion (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_member_qualification_member_id ON fs.vehicle_member_qualification (member_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_member_qualification_vehicle_qualification_id ON fs.vehicle_member_qualification (vehicle_qualification_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_member_qualification_granted_by_user_id ON fs.vehicle_member_qualification (granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_member_qualification_revoked_by_user_id ON fs.vehicle_member_qualification (revoked_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_member_qualification_created_by_user_id ON fs.vehicle_member_qualification (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_member_qualification_updated_by_user_id ON fs.vehicle_member_qualification (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_qualification_vehicle_id ON fs.vehicle_qualification (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_qualification_created_by_user_id ON fs.vehicle_qualification (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_qualification_updated_by_user_id ON fs.vehicle_qualification (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_reservation_type_code ON fs.vehicle_reservation (reservation_type_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_reservation_status_code ON fs.vehicle_reservation (reservation_status_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_vehicle_id ON fs.vehicle_reservation (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_member_id ON fs.vehicle_reservation (member_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_member_package_id ON fs.vehicle_reservation (member_package_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_reserving_branch_id ON fs.vehicle_reservation (reserving_branch_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_source_type_code ON fs.vehicle_reservation (source_type_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_start_location_code ON fs.vehicle_reservation (start_location_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_end_location_code ON fs.vehicle_reservation (end_location_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_linked_reservation_id ON fs.vehicle_reservation (linked_reservation_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_service_category_code ON fs.vehicle_reservation (service_category_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_service_type_code ON fs.vehicle_reservation (service_type_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_service_vendor_id ON fs.vehicle_reservation (service_vendor_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_last_checkin_event_id ON fs.vehicle_reservation (last_checkin_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_last_checkout_event_id ON fs.vehicle_reservation (last_checkout_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_early_pickup_granted_by_user_id ON fs.vehicle_reservation (early_pickup_granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_late_return_granted_by_user_id ON fs.vehicle_reservation (late_return_granted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_member_address_id ON fs.vehicle_reservation (member_address_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_branch_delivery_rate_id ON fs.vehicle_reservation (branch_delivery_rate_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_delivery_quote_accepted_by_user_id ON fs.vehicle_reservation (delivery_quote_accepted_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_created_by_user_id ON fs.vehicle_reservation (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_reservation_updated_by_user_id ON fs.vehicle_reservation (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_service_category_created_by_user_id ON fs.service_category (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_service_category_updated_by_user_id ON fs.service_category (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_service_reason_select_created_by_user_id ON fs.service_reason_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_service_reason_select_updated_by_user_id ON fs.service_reason_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_toll_authority_select_created_by_user_id ON fs.toll_authority_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_toll_authority_select_updated_by_user_id ON fs.toll_authority_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_attachment_retention_policy_source_type_code ON fs.vehicle_attachment_retention_policy (source_type_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_attachment_retention_policy_created_by_user_id ON fs.vehicle_attachment_retention_policy (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_attachment_retention_policy_updated_by_user_id ON fs.vehicle_attachment_retention_policy (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_code_created_by_user_id ON fs.vehicle_condition_code (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_code_updated_by_user_id ON fs.vehicle_condition_code (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_history_vehicle_id ON fs.vehicle_condition_history (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_history_vehicle_trip_id ON fs.vehicle_condition_history (vehicle_trip_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_history_condition_code ON fs.vehicle_condition_history (condition_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_history_condition_reason_code ON fs.vehicle_condition_history (condition_reason_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_history_reservation_id ON fs.vehicle_condition_history (reservation_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_history_inspection_id ON fs.vehicle_condition_history (inspection_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_history_changed_by_user_id ON fs.vehicle_condition_history (changed_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_reason_created_by_user_id ON fs.vehicle_condition_reason (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_reason_updated_by_user_id ON fs.vehicle_condition_reason (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_transition_rule_from_condition_code ON fs.vehicle_condition_transition_rule (from_condition_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_transition_rule_to_condition_code ON fs.vehicle_condition_transition_rule (to_condition_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_transition_rule_created_by_user_id ON fs.vehicle_condition_transition_rule (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_transition_rule_updated_by_user_id ON fs.vehicle_condition_transition_rule (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_attachment_vehicle_event_id ON fs.vehicle_event_attachment (vehicle_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_attachment_attachment_retention_policy_id ON fs.vehicle_event_attachment (attachment_retention_policy_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_attachment_created_by_user_id ON fs.vehicle_event_attachment (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_attachment_updated_by_user_id ON fs.vehicle_event_attachment (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_log_vehicle_trip_id ON fs.vehicle_event_log (vehicle_trip_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_log_reservation_id ON fs.vehicle_event_log (reservation_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_log_vehicle_id ON fs.vehicle_event_log (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_log_branch_id ON fs.vehicle_event_log (branch_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_log_member_id ON fs.vehicle_event_log (member_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_log_service_vendor_id ON fs.vehicle_event_log (service_vendor_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_log_captured_by_user_id ON fs.vehicle_event_log (captured_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_log_created_by_user_id ON fs.vehicle_event_log (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_event_log_updated_by_user_id ON fs.vehicle_event_log (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_fuel_level_select_created_by_user_id ON fs.vehicle_fuel_level_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_fuel_level_select_updated_by_user_id ON fs.vehicle_fuel_level_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_location_vehicle_id ON fs.vehicle_location (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_location_home_branch_id ON fs.vehicle_location (home_branch_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_location_current_branch_id ON fs.vehicle_location (current_branch_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_location_created_by_user_id ON fs.vehicle_location (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_location_updated_by_user_id ON fs.vehicle_location (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_odometer_log_vehicle_event_id ON fs.vehicle_odometer_log (vehicle_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_odometer_log_vehicle_id ON fs.vehicle_odometer_log (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_odometer_log_captured_by_user_id ON fs.vehicle_odometer_log (captured_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_odometer_log_created_by_user_id ON fs.vehicle_odometer_log (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_odometer_log_updated_by_user_id ON fs.vehicle_odometer_log (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_service_type_service_category_code ON fs.vehicle_service_type (service_category_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_service_type_created_by_user_id ON fs.vehicle_service_type (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_service_type_updated_by_user_id ON fs.vehicle_service_type (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_source_type_created_by_user_id ON fs.vehicle_source_type (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_source_type_updated_by_user_id ON fs.vehicle_source_type (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_toll_transaction_vehicle_id ON fs.vehicle_toll_transaction (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_toll_transaction_toll_authority_code ON fs.vehicle_toll_transaction (toll_authority_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_toll_transaction_vehicle_trip_id ON fs.vehicle_toll_transaction (vehicle_trip_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_toll_transaction_member_charge_id ON fs.vehicle_toll_transaction (member_charge_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_toll_transaction_created_by_user_id ON fs.vehicle_toll_transaction (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_toll_transaction_updated_by_user_id ON fs.vehicle_toll_transaction (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_vehicle_reservation_id ON fs.vehicle_trip (vehicle_reservation_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_trip_type_code ON fs.vehicle_trip (trip_type_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_vehicle_id ON fs.vehicle_trip (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_odometer_start_id ON fs.vehicle_trip (odometer_start_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_odometer_end_id ON fs.vehicle_trip (odometer_end_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_created_by_user_id ON fs.vehicle_trip (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_updated_by_user_id ON fs.vehicle_trip (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_member_member_id ON fs.vehicle_trip_member (member_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_member_member_package_id ON fs.vehicle_trip_member (member_package_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_member_member_package_participant_id ON fs.vehicle_trip_member (member_package_participant_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_member_branch_id ON fs.vehicle_trip_member (branch_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_member_source_type_code ON fs.vehicle_trip_member (source_type_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_member_vop_payout_log_id ON fs.vehicle_trip_member (vop_payout_log_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_member_created_by_user_id ON fs.vehicle_trip_member (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_member_updated_by_user_id ON fs.vehicle_trip_member (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_service_vendor_id ON fs.vehicle_trip_service (vendor_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_service_service_category_code ON fs.vehicle_trip_service (service_category_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_service_service_type_code ON fs.vehicle_trip_service (service_type_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_service_service_reason_code ON fs.vehicle_trip_service (service_reason_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_service_billed_member_id ON fs.vehicle_trip_service (billed_member_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_service_billed_vehicle_partner_id ON fs.vehicle_trip_service (billed_vehicle_partner_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_service_created_by_user_id ON fs.vehicle_trip_service (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_service_updated_by_user_id ON fs.vehicle_trip_service (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_type_select_created_by_user_id ON fs.vehicle_trip_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trip_type_select_updated_by_user_id ON fs.vehicle_trip_type_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_vehicle_make_code ON fs.vehicle (vehicle_make_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_year ON fs.vehicle (year);
CREATE INDEX IF NOT EXISTS idx_vehicle_exterior_color_short ON fs.vehicle (exterior_color_short);
CREATE INDEX IF NOT EXISTS idx_vehicle_interior_color ON fs.vehicle (interior_color);
CREATE INDEX IF NOT EXISTS idx_vehicle_condition_code ON fs.vehicle (condition_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_home_branch_id ON fs.vehicle (home_branch_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_created_by_user_id ON fs.vehicle (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_updated_by_user_id ON fs.vehicle (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_accessories_vehicle_id ON fs.vehicle_accessories (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_accessories_created_by_user_id ON fs.vehicle_accessories (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_accessories_updated_by_user_id ON fs.vehicle_accessories (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_color_select_created_by_user_id ON fs.vehicle_color_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_color_select_updated_by_user_id ON fs.vehicle_color_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_description_vehicle_id ON fs.vehicle_description (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_description_created_by_user_id ON fs.vehicle_description (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_description_updated_by_user_id ON fs.vehicle_description (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_financing_lifecycle_vehicle_id ON fs.vehicle_financing_lifecycle (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_financing_lifecycle_created_by_user_id ON fs.vehicle_financing_lifecycle (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_financing_lifecycle_updated_by_user_id ON fs.vehicle_financing_lifecycle (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_make_select_created_by_user_id ON fs.vehicle_make_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_make_select_updated_by_user_id ON fs.vehicle_make_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_mileage_allocation_vehicle_mileage_allowance_id ON fs.vehicle_mileage_allocation (vehicle_mileage_allowance_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_mileage_allocation_vehicle_id ON fs.vehicle_mileage_allocation (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_mileage_allocation_created_by_user_id ON fs.vehicle_mileage_allocation (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_mileage_allocation_updated_by_user_id ON fs.vehicle_mileage_allocation (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_mileage_allowance_vehicle_id ON fs.vehicle_mileage_allowance (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_mileage_allowance_created_by_user_id ON fs.vehicle_mileage_allowance (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_mileage_allowance_updated_by_user_id ON fs.vehicle_mileage_allowance (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_performance_vehicle_id ON fs.vehicle_performance (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_performance_created_by_user_id ON fs.vehicle_performance (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_performance_updated_by_user_id ON fs.vehicle_performance (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_registration_warranty_vehicle_id ON fs.vehicle_registration_warranty (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_registration_warranty_registration_state ON fs.vehicle_registration_warranty (registration_state);
CREATE INDEX IF NOT EXISTS idx_vehicle_registration_warranty_created_by_user_id ON fs.vehicle_registration_warranty (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_registration_warranty_updated_by_user_id ON fs.vehicle_registration_warranty (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_release_row_vehicle_id ON fs.vehicle_release_row (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_release_row_minimum_podium_status_code ON fs.vehicle_release_row (minimum_podium_status_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_release_row_applied_from_template_id ON fs.vehicle_release_row (applied_from_template_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_release_row_created_by_user_id ON fs.vehicle_release_row (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_release_row_updated_by_user_id ON fs.vehicle_release_row (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_release_template_created_by_user_id ON fs.vehicle_release_template (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_release_template_updated_by_user_id ON fs.vehicle_release_template (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_release_template_row_vehicle_release_template_id ON fs.vehicle_release_template_row (vehicle_release_template_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_release_template_row_minimum_podium_status_code ON fs.vehicle_release_template_row (minimum_podium_status_code);
CREATE INDEX IF NOT EXISTS idx_vehicle_release_template_row_created_by_user_id ON fs.vehicle_release_template_row (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_release_template_row_updated_by_user_id ON fs.vehicle_release_template_row (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_spec_vehicle_id ON fs.vehicle_spec (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_spec_created_by_user_id ON fs.vehicle_spec (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_spec_updated_by_user_id ON fs.vehicle_spec (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tire_brand_select_created_by_user_id ON fs.vehicle_tire_brand_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tire_brand_select_updated_by_user_id ON fs.vehicle_tire_brand_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tires_vehicle_id ON fs.vehicle_tires (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tires_front_tire_brand ON fs.vehicle_tires (front_tire_brand);
CREATE INDEX IF NOT EXISTS idx_vehicle_tires_rear_tire_brand ON fs.vehicle_tires (rear_tire_brand);
CREATE INDEX IF NOT EXISTS idx_vehicle_tires_created_by_user_id ON fs.vehicle_tires (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_tires_updated_by_user_id ON fs.vehicle_tires (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_year_select_created_by_user_id ON fs.vehicle_year_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_year_select_updated_by_user_id ON fs.vehicle_year_select (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_vendor_type_code ON fs.vendor (vendor_type_code);
CREATE INDEX IF NOT EXISTS idx_vendor_home_branch_id ON fs.vendor (home_branch_id);
CREATE INDEX IF NOT EXISTS idx_vendor_state ON fs.vendor (state);
CREATE INDEX IF NOT EXISTS idx_vendor_created_by_user_id ON fs.vendor (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_updated_by_user_id ON fs.vendor (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_contact_vendor_id ON fs.vendor_contact (vendor_id);
CREATE INDEX IF NOT EXISTS idx_vendor_contact_user_id ON fs.vendor_contact (user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_contact_created_by_user_id ON fs.vendor_contact (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_contact_updated_by_user_id ON fs.vendor_contact (updated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_type_select_created_by_user_id ON fs.vendor_type_select (created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_vendor_type_select_updated_by_user_id ON fs.vendor_type_select (updated_by_user_id);

-- Total indexes created: 1137

-- =============================================================================
-- 5. COMPATIBILITY VIEWS AND ALIASES
-- =============================================================================
CREATE OR REPLACE VIEW fs.users AS SELECT * FROM fs."user";
CREATE OR REPLACE VIEW fs.app_user AS SELECT * FROM fs."user";
GRANT USAGE ON SCHEMA fs TO fs_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA fs TO fs_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA fs TO fs_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA fs TO fs_app;

COMMIT;
