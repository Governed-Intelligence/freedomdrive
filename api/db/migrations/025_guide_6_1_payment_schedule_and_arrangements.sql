-- Migration 025: Guide 6.1 Payment Arrangement and Dues Schedule Support
-- Supports Rules 6.1-R09, 6.1-R10, 6.1-R14, 6.1-C18, 6.1-C19, 6.1-C20, 6.1-C22, 6.1-C23, 6.1-C24, 6.1-C31

-- Add payment arrangement and planned start fields to operational fs.members
ALTER TABLE fs.members ADD COLUMN IF NOT EXISTS payment_arrangement_confirmed BOOLEAN DEFAULT FALSE;
ALTER TABLE fs.members ADD COLUMN IF NOT EXISTS payment_method_type VARCHAR(40);
ALTER TABLE fs.members ADD COLUMN IF NOT EXISTS billing_email VARCHAR(320);
ALTER TABLE fs.members ADD COLUMN IF NOT EXISTS planned_start_date DATE;

-- Add payment arrangement fields to canonical fs.member if present
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'fs' AND table_name = 'member') THEN
    ALTER TABLE fs.member ADD COLUMN IF NOT EXISTS payment_arrangement_confirmed BOOLEAN DEFAULT FALSE;
    ALTER TABLE fs.member ADD COLUMN IF NOT EXISTS payment_method_type VARCHAR(40);
    ALTER TABLE fs.member ADD COLUMN IF NOT EXISTS billing_email VARCHAR(320);
    ALTER TABLE fs.member ADD COLUMN IF NOT EXISTS planned_start_date DATE;
  END IF;
END $$;

-- Enhance fs.member_payment_schedule to support direct member lookup and installment storage
ALTER TABLE fs.member_payment_schedule ADD COLUMN IF NOT EXISTS member_id UUID;
ALTER TABLE fs.member_payment_schedule ADD COLUMN IF NOT EXISTS payment_method_type VARCHAR(40);
ALTER TABLE fs.member_payment_schedule ADD COLUMN IF NOT EXISTS billing_email VARCHAR(320);
ALTER TABLE fs.member_payment_schedule ADD COLUMN IF NOT EXISTS installments_json JSONB;

-- Index member_id on member_payment_schedule
CREATE INDEX IF NOT EXISTS idx_member_payment_schedule_member_id ON fs.member_payment_schedule (member_id);
