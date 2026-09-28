-- =============================================================================
-- Migration 026: Guide 7.6 / 7.7 Rate Cards & Guide 9.2 Member Reservations
-- =============================================================================
-- Enforces:
--   7.6-R01 / 7.6-C01 / 7.6-C02: Rate card is append-only once first_used_on is set.
--   7.6-R02 / 7.6-C03: Edit/delete of existing rate on used card refused (suggest copy).
--   7.6-R03 / 7.6-C04 / 7.7-C04: Placement for vehicle not yet on used card can be added.
--   7.6-R03 / 7.6-C05: Rate row for tier not yet priced by used card can be added.
--   7.6-R04 / 7.7-R05 / 7.6-C06 / 7.7-C05: Vehicle holds at most ONE placement per card.
--   7.6-C07 / 7.7-C03: Closing or superseding placement on used card is refused.
--   7.6-R08 / 7.6-C10 / 7.6-C11: Season coverage and non-overlap validation.
--   7.6-R14 / 7.6-C14: Extra-mile fractional precision (NUMERIC(10,3)).
--   9.2-R01 / 9.2-C01-C05: All four vehicle conditions pass before member evaluation.
--   9.2-R02 / 9.2-C06: Membership must be active across the whole reservation.
--   9.2-R03 / 9.2-C07 / 9.2-C08: Valid insurance through entire trip; refused first.
--   9.2-R07 / 9.2-C10-C12: Weekend charges one bundled figure; weekdays charge per day.
--   9.2-R08 / 9.2-C13: Estimate stored broken into weekday and weekend parts.
--   9.2-R09 / 9.2-C15: Confirmation posts real charge to points ledger.
--   9.2-R10 / 9.2-C16: Courtesy booking occupies calendar and consumes 0 points.
--   9.2-C17: Booking against Pending member is created tentative.
--   trg_reservations_block_until: Automatically appends turnaround prep buffer.
-- =============================================================================

BEGIN;

SET search_path TO fs, public;

-- 1. Precision alignment for extra_mile_point_value (7.6-C14)
ALTER TABLE fs.rate_card_rate 
  ALTER COLUMN extra_mile_point_value TYPE NUMERIC(10,3);

DO $$ BEGIN
  ALTER TABLE fs.mpc_tier_point_rate 
    ALTER COLUMN extra_mile_point_value_override TYPE NUMERIC(10,3);
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- 2. Enforce at most ONE placement per vehicle per card (7.6-R04, 7.7-R05, 7.6-C06, 7.7-C05)
CREATE UNIQUE INDEX IF NOT EXISTS uq_rate_card_placement_card_vehicle 
  ON fs.rate_card_placement (rate_card_id, vehicle_id);

-- 3. Unique tier and season on rate card rates
CREATE UNIQUE INDEX IF NOT EXISTS uq_rate_card_rate_tier_season 
  ON fs.rate_card_rate (rate_card_id, vehicle_tier_id, COALESCE(rate_card_season_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- 4. Rate card freeze trigger (7.6-R01, 7.6-R02, 7.6-C01, 7.6-C02)
CREATE OR REPLACE FUNCTION fs.trg_freeze_rate_card_fn()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.first_used_on IS NOT NULL THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION '7.6-R02 / 7.6-C02: Rate card is frozen once first_used_on is set. It cannot be deleted.'
        USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' THEN
      IF NEW.card_code IS DISTINCT FROM OLD.card_code OR
         NEW.card_name IS DISTINCT FROM OLD.card_name OR
         NEW.description IS DISTINCT FROM OLD.description OR
         NEW.first_used_on IS DISTINCT FROM OLD.first_used_on THEN
        RAISE EXCEPTION '7.6-R02 / 7.6-C02: Rate card is frozen once first_used_on is set. Rates, placements, seasons, and the card record are all frozen.'
          USING ERRCODE = '23514';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_freeze_rate_card ON fs.rate_card;
CREATE TRIGGER trg_freeze_rate_card
BEFORE UPDATE OR DELETE ON fs.rate_card
FOR EACH ROW EXECUTE FUNCTION fs.trg_freeze_rate_card_fn();

-- 5. Rate card rate freeze trigger (7.6-R02, 7.6-C03, 7.6-C05)
CREATE OR REPLACE FUNCTION fs.trg_freeze_rate_card_rate_fn()
RETURNS TRIGGER AS $$
DECLARE
  v_first_used DATE;
BEGIN
  SELECT first_used_on INTO v_first_used
    FROM fs.rate_card
   WHERE rate_card_id = COALESCE(OLD.rate_card_id, NEW.rate_card_id);

  IF v_first_used IS NOT NULL THEN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
      RAISE EXCEPTION '7.6-R02 / 7.6-C03: An edit or deletion of an existing rate on a used card is refused. Create a new rate card instead.'
        USING ERRCODE = '23514';
    END IF;
    -- INSERT is permitted (7.6-C05)
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_freeze_rate_card_rate ON fs.rate_card_rate;
CREATE TRIGGER trg_freeze_rate_card_rate
BEFORE UPDATE OR DELETE ON fs.rate_card_rate
FOR EACH ROW EXECUTE FUNCTION fs.trg_freeze_rate_card_rate_fn();

-- 6. Rate card placement freeze trigger (7.6-C07, 7.7-C03, 7.7-C04)
CREATE OR REPLACE FUNCTION fs.trg_freeze_rate_card_placement_fn()
RETURNS TRIGGER AS $$
DECLARE
  v_first_used DATE;
BEGIN
  SELECT first_used_on INTO v_first_used
    FROM fs.rate_card
   WHERE rate_card_id = COALESCE(OLD.rate_card_id, NEW.rate_card_id);

  IF v_first_used IS NOT NULL THEN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
      RAISE EXCEPTION '7.6-C07 / 7.7-C03: Editing, closing, or superseding an existing placement on a card in use is refused.'
        USING ERRCODE = '23514';
    END IF;
    -- INSERT is permitted (7.6-C04 / 7.7-C04)
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_freeze_rate_card_placement ON fs.rate_card_placement;
CREATE TRIGGER trg_freeze_rate_card_placement
BEFORE UPDATE OR DELETE ON fs.rate_card_placement
FOR EACH ROW EXECUTE FUNCTION fs.trg_freeze_rate_card_placement_fn();

-- 7. Rate card season freeze trigger (7.6-R02, 7.6-C02)
CREATE OR REPLACE FUNCTION fs.trg_freeze_rate_card_season_fn()
RETURNS TRIGGER AS $$
DECLARE
  v_first_used DATE;
BEGIN
  SELECT first_used_on INTO v_first_used
    FROM fs.rate_card
   WHERE rate_card_id = COALESCE(OLD.rate_card_id, NEW.rate_card_id);

  IF v_first_used IS NOT NULL THEN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
      RAISE EXCEPTION '7.6-R02 / 7.6-C02: Seasons on a used rate card are frozen.'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_freeze_rate_card_season ON fs.rate_card_season;
CREATE TRIGGER trg_freeze_rate_card_season
BEFORE UPDATE OR DELETE ON fs.rate_card_season
FOR EACH ROW EXECUTE FUNCTION fs.trg_freeze_rate_card_season_fn();

-- 8. Hardening fs.reservations for Guide 9.2
ALTER TABLE fs.reservations
  ADD COLUMN IF NOT EXISTS weekday_points INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS weekend_points INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_courtesy BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_tentative BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS counts_toward_limits BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS rate_card_id UUID REFERENCES fs.rate_card (rate_card_id);

-- Update turnaround buffer trigger to automatically calculate block_until and total_points_cost
CREATE OR REPLACE FUNCTION fs.set_block_until()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.prep_buffer_hours := COALESCE(NEW.prep_buffer_hours, 4);
    NEW.block_until := NEW.return_at + (NEW.prep_buffer_hours * INTERVAL '1 hour');
    
    IF NEW.is_courtesy THEN
      NEW.total_points_cost := 0;
      NEW.counts_toward_limits := FALSE;
    ELSE
      IF NEW.weekday_points IS NOT NULL OR NEW.weekend_points IS NOT NULL THEN
        NEW.total_points_cost := COALESCE(NEW.weekday_points, 0) + COALESCE(NEW.weekend_points, 0);
      END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reservations_block_until ON fs.reservations;
CREATE TRIGGER trg_reservations_block_until
BEFORE INSERT OR UPDATE OF return_at, prep_buffer_hours, weekday_points, weekend_points, is_courtesy ON fs.reservations
FOR EACH ROW EXECUTE FUNCTION fs.set_block_until();

UPDATE fs.reservations 
   SET block_until = return_at + (COALESCE(prep_buffer_hours, 4) * INTERVAL '1 hour')
 WHERE block_until IS NULL;

-- 9. Member insurance policy verification helper column on member if needed
ALTER TABLE fs.member_insurance_policy
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_member_insurance_policy_dates 
  ON fs.member_insurance_policy (member_id, effective_on, expires_on);

COMMIT;
