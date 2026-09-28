-- =============================================================================
-- FREEDOM SUPERCARS — PostgreSQL Database Schema
-- =============================================================================
-- Version:     1.0.0
-- Engine:      PostgreSQL 14+
-- Location:    Houston, TX (2119 Brittmoore Rd) — designed for multi-location
-- Author:      SMEPro Technologies (IOS+ architecture pattern)
--
-- CORE DOMAIN RULES:
--   * 4 membership plans: 15, 30, 60, 100 driving days per year
--   * 5 vehicle tiers (T1–T5); T5 requires 3-day minimum booking
--   * Each tier consumes a different number of "tier points" per driving day
--   * Each plan carries a fixed annual point allocation
--   * Points are immutably ledgered (audit trail, no destructive updates)
--   * Higher-tier reservations enforce minimum-stay constraints
--   * Members may have authorized additional drivers (spouse/partner/etc.)
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Extensions
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "citext";        -- case-insensitive text (emails)
CREATE EXTENSION IF NOT EXISTS "btree_gist";    -- for EXCLUDE constraints on ranges

-- -----------------------------------------------------------------------------
-- 1. Schema + Enum Types
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS fs;
SET search_path TO fs, public;

CREATE TYPE fs.member_status        AS ENUM ('prospect','active','paused','suspended','cancelled','expired');
CREATE TYPE fs.subscription_status  AS ENUM ('pending','active','paused','cancelled','expired','renewed');
CREATE TYPE fs.reservation_status   AS ENUM ('requested','confirmed','picked_up','returned','cancelled','no_show');
CREATE TYPE fs.vehicle_status       AS ENUM ('available','reserved','in_use','maintenance','detailing','in_transit','retired');
CREATE TYPE fs.vehicle_condition    AS ENUM ('excellent','good','fair','needs_attention','out_of_service');
CREATE TYPE fs.drivetrain_type      AS ENUM ('rwd','awd','4wd','fwd');
CREATE TYPE fs.fuel_type            AS ENUM ('gasoline','hybrid','phev','electric','diesel');
CREATE TYPE fs.transmission_type    AS ENUM ('manual','automatic','dct','pdk','amt','single_speed');
CREATE TYPE fs.body_style           AS ENUM ('coupe','convertible','roadster','spyder','targa','sedan','suv','shooting_brake','crossover');
CREATE TYPE fs.txn_type             AS ENUM ('grant','debit','refund','adjustment','rollover','expiration','forfeit','bonus');
CREATE TYPE fs.payment_status       AS ENUM ('pending','paid','failed','refunded','partial','disputed');
CREATE TYPE fs.incident_severity    AS ENUM ('minor','moderate','major','total_loss');

-- =============================================================================
-- 2. LOCATIONS (multi-location-ready; Houston is the current location)
-- =============================================================================
CREATE TABLE fs.locations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code            VARCHAR(10) UNIQUE NOT NULL,     -- 'HOU', 'DFW', 'ATX', etc.
    name            VARCHAR(200) NOT NULL,
    address_line1   VARCHAR(200) NOT NULL,
    address_line2   VARCHAR(200),
    city            VARCHAR(100) NOT NULL,
    state           VARCHAR(2)   NOT NULL,
    postal_code     VARCHAR(20)  NOT NULL,
    country         VARCHAR(2)   NOT NULL DEFAULT 'US',
    phone           VARCHAR(25),
    email           CITEXT,
    timezone        VARCHAR(50)  NOT NULL DEFAULT 'America/Chicago',
    latitude        NUMERIC(10,7),
    longitude       NUMERIC(10,7),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    opened_on       DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 3. PLANS + TIERS (the business-rule heart of the system)
-- =============================================================================

-- The four plans offered by Freedom Supercars
CREATE TABLE fs.plans (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code                VARCHAR(20) UNIQUE NOT NULL,  -- 'PLAN_15','PLAN_30','PLAN_60','PLAN_100'
    name                VARCHAR(100) NOT NULL,        -- '15-Day Membership', etc.
    driving_days        INTEGER      NOT NULL,        -- 15, 30, 60, 100
    annual_tier_points  INTEGER      NOT NULL,        -- total point pool per year
    annual_price_usd    NUMERIC(10,2),                -- may be NULL (market-tailored)
    initiation_fee_usd  NUMERIC(10,2) NOT NULL DEFAULT 0,
    monthly_price_usd   NUMERIC(10,2),
    guest_drivers_allowed INTEGER NOT NULL DEFAULT 1, -- additional authorized drivers
    rollover_allowed    BOOLEAN      NOT NULL DEFAULT FALSE,
    rollover_cap_points INTEGER,                      -- max points that can roll into next year
    description         TEXT,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order          INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT plans_driving_days_valid     CHECK (driving_days IN (15,30,60,100)),
    CONSTRAINT plans_points_positive        CHECK (annual_tier_points > 0),
    CONSTRAINT plans_rollover_cap_logic     CHECK (
        (rollover_allowed = FALSE AND rollover_cap_points IS NULL)
        OR (rollover_allowed = TRUE AND rollover_cap_points >= 0)
    )
);

-- Vehicle tiers and their point-per-day cost + booking rules
CREATE TABLE fs.tiers (
    id                  SMALLINT PRIMARY KEY,         -- 1,2,3,4,5
    name                VARCHAR(50) NOT NULL,
    points_per_day      NUMERIC(5,2) NOT NULL,        -- cost of 1 driving day at this tier
    min_booking_days    INTEGER      NOT NULL DEFAULT 1,
    max_booking_days    INTEGER      NOT NULL DEFAULT 14,
    daily_mileage_cap   INTEGER      NOT NULL DEFAULT 150,
    overage_fee_per_mile NUMERIC(5,2) NOT NULL DEFAULT 3.00,
    description         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT tiers_id_range               CHECK (id BETWEEN 1 AND 5),
    CONSTRAINT tiers_points_positive        CHECK (points_per_day > 0),
    CONSTRAINT tiers_min_le_max_booking     CHECK (min_booking_days <= max_booking_days),
    CONSTRAINT tiers_min_booking_positive   CHECK (min_booking_days >= 1)
);

-- Per-plan tier access rules (optional caps per tier, min notice, etc.)
-- This lets you say e.g. "The 15-day plan can use up to 5 T5 days per year"
CREATE TABLE fs.plan_tier_allocations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    plan_id             UUID NOT NULL REFERENCES fs.plans(id) ON DELETE CASCADE,
    tier_id             SMALLINT NOT NULL REFERENCES fs.tiers(id),
    max_days_per_year   INTEGER,                    -- NULL = unlimited (subject to point pool)
    max_days_per_booking INTEGER,                   -- NULL = use tier default
    advance_booking_days INTEGER NOT NULL DEFAULT 60,
    blackout_weekend_eligible BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plan_id, tier_id)
);

-- =============================================================================
-- 4. VEHICLE CATALOG
-- =============================================================================
CREATE TABLE fs.manufacturers (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(100) UNIQUE NOT NULL,
    country         VARCHAR(50),
    logo_url        TEXT,
    is_prestige     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE fs.vehicle_models (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    manufacturer_id UUID NOT NULL REFERENCES fs.manufacturers(id),
    model_name      VARCHAR(150) NOT NULL,
    trim            VARCHAR(100),
    body_style      fs.body_style,
    fuel_type       fs.fuel_type NOT NULL DEFAULT 'gasoline',
    drivetrain      fs.drivetrain_type,
    transmission    fs.transmission_type,
    horsepower      INTEGER,
    torque_lb_ft    INTEGER,
    top_speed_mph   INTEGER,
    zero_to_60_sec  NUMERIC(4,2),
    seats           SMALLINT NOT NULL DEFAULT 2,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (manufacturer_id, model_name, trim)
);

-- Individual vehicles (VINs) in the fleet
CREATE TABLE fs.vehicles (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vin                 VARCHAR(17) UNIQUE,
    stock_number        VARCHAR(20) UNIQUE,
    location_id         UUID NOT NULL REFERENCES fs.locations(id),
    model_id            UUID NOT NULL REFERENCES fs.vehicle_models(id),
    tier_id             SMALLINT NOT NULL REFERENCES fs.tiers(id),
    model_year          INTEGER NOT NULL,
    exterior_color      VARCHAR(80),
    interior_color      VARCHAR(80),
    license_plate       VARCHAR(15),
    license_state       VARCHAR(2),
    current_mileage     INTEGER NOT NULL DEFAULT 0,
    acquired_on         DATE,
    acquisition_cost    NUMERIC(12,2),
    in_service_on       DATE,
    retired_on          DATE,
    status              fs.vehicle_status    NOT NULL DEFAULT 'available',
    condition           fs.vehicle_condition NOT NULL DEFAULT 'excellent',
    photo_url           TEXT,
    notes               TEXT,
    is_marquee          BOOLEAN NOT NULL DEFAULT FALSE,  -- flagship display car
    is_member_visible   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT vehicles_year_reasonable     CHECK (model_year BETWEEN 1980 AND 2100),
    CONSTRAINT vehicles_mileage_nonneg      CHECK (current_mileage >= 0),
    CONSTRAINT vehicles_retire_after_acquire CHECK (retired_on IS NULL OR acquired_on IS NULL OR retired_on >= acquired_on)
);

CREATE INDEX idx_vehicles_status        ON fs.vehicles(status) WHERE retired_on IS NULL;
CREATE INDEX idx_vehicles_tier          ON fs.vehicles(tier_id) WHERE retired_on IS NULL;
CREATE INDEX idx_vehicles_location      ON fs.vehicles(location_id);

-- Vehicle status transitions (audit trail for availability)
CREATE TABLE fs.vehicle_status_log (
    id              BIGSERIAL PRIMARY KEY,
    vehicle_id      UUID NOT NULL REFERENCES fs.vehicles(id) ON DELETE CASCADE,
    previous_status fs.vehicle_status,
    new_status      fs.vehicle_status NOT NULL,
    reason          TEXT,
    changed_by      UUID,
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_vehicle_status_log_vehicle ON fs.vehicle_status_log(vehicle_id, changed_at DESC);

-- Historical previous-fleet roster (for marketing / archive display)
CREATE TABLE fs.previous_vehicles (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    manufacturer    VARCHAR(100) NOT NULL,
    model           VARCHAR(150) NOT NULL,
    trim            VARCHAR(100),
    color           VARCHAR(50),
    location_id     UUID REFERENCES fs.locations(id),
    retired_on      DATE,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 5. MEMBERS + SUBSCRIPTIONS
-- =============================================================================
CREATE TABLE fs.members (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_number   VARCHAR(20) UNIQUE NOT NULL,
    first_name      VARCHAR(100) NOT NULL,
    last_name       VARCHAR(100) NOT NULL,
    email           CITEXT UNIQUE NOT NULL,
    phone           VARCHAR(25),
    date_of_birth   DATE,
    drivers_license_number  VARCHAR(50),
    drivers_license_state   VARCHAR(2),
    drivers_license_expires DATE,
    address_line1   VARCHAR(200),
    address_line2   VARCHAR(200),
    city            VARCHAR(100),
    state           VARCHAR(2),
    postal_code     VARCHAR(20),
    country         VARCHAR(2) DEFAULT 'US',
    primary_location_id UUID REFERENCES fs.locations(id),
    status          fs.member_status NOT NULL DEFAULT 'prospect',
    joined_on       DATE,
    referral_source VARCHAR(100),
    notes           TEXT,
    stripe_customer_id VARCHAR(50),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_members_status     ON fs.members(status);
CREATE INDEX idx_members_email      ON fs.members(email);

-- Authorized additional drivers (spouse, business partner, etc.)
CREATE TABLE fs.authorized_drivers (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id       UUID NOT NULL REFERENCES fs.members(id) ON DELETE CASCADE,
    first_name      VARCHAR(100) NOT NULL,
    last_name       VARCHAR(100) NOT NULL,
    relationship    VARCHAR(50),
    email           CITEXT,
    phone           VARCHAR(25),
    drivers_license_number  VARCHAR(50) NOT NULL,
    drivers_license_state   VARCHAR(2) NOT NULL,
    drivers_license_expires DATE NOT NULL,
    date_of_birth   DATE NOT NULL,
    approved_on     DATE,
    approved_by     UUID,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A member's active/historical subscriptions (one plan at a time typically)
CREATE TABLE fs.member_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id           UUID NOT NULL REFERENCES fs.members(id) ON DELETE CASCADE,
    plan_id             UUID NOT NULL REFERENCES fs.plans(id),
    status              fs.subscription_status NOT NULL DEFAULT 'pending',
    start_date          DATE NOT NULL,
    end_date            DATE NOT NULL,
    points_granted      INTEGER NOT NULL,           -- points at issue time (snapshot)
    points_rolled_in    INTEGER NOT NULL DEFAULT 0, -- from prior term
    auto_renew          BOOLEAN NOT NULL DEFAULT TRUE,
    cancellation_date   DATE,
    cancellation_reason TEXT,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT subs_date_order          CHECK (end_date > start_date),
    CONSTRAINT subs_points_nonneg       CHECK (points_granted >= 0 AND points_rolled_in >= 0)
);

CREATE INDEX idx_subs_member        ON fs.member_subscriptions(member_id);
CREATE INDEX idx_subs_status        ON fs.member_subscriptions(status);
CREATE INDEX idx_subs_active_range  ON fs.member_subscriptions(start_date, end_date);

-- Enforce: only one ACTIVE subscription per member at a time
CREATE UNIQUE INDEX idx_subs_one_active
    ON fs.member_subscriptions(member_id)
    WHERE status = 'active';

-- =============================================================================
-- 6. TIER POINT LEDGER (immutable)
-- =============================================================================
CREATE TABLE fs.point_transactions (
    id                  BIGSERIAL PRIMARY KEY,
    subscription_id     UUID NOT NULL REFERENCES fs.member_subscriptions(id),
    txn_type            fs.txn_type NOT NULL,
    points              INTEGER NOT NULL,           -- positive=credit, negative=debit
    balance_after       INTEGER NOT NULL,
    reservation_id      UUID,                       -- FK added after reservations table
    reason              TEXT,
    created_by          UUID,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT txn_no_zero              CHECK (points <> 0),
    CONSTRAINT txn_balance_nonneg       CHECK (balance_after >= 0),
    CONSTRAINT txn_debit_negative       CHECK (txn_type <> 'debit' OR points < 0),
    CONSTRAINT txn_grant_positive       CHECK (txn_type NOT IN ('grant','rollover','bonus','refund') OR points > 0)
);

CREATE INDEX idx_points_sub      ON fs.point_transactions(subscription_id, created_at DESC);
CREATE INDEX idx_points_res      ON fs.point_transactions(reservation_id);

-- =============================================================================
-- 7. RESERVATIONS
-- =============================================================================
CREATE TABLE fs.reservations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    confirmation_code   VARCHAR(15) UNIQUE NOT NULL,
    member_id           UUID NOT NULL REFERENCES fs.members(id),
    subscription_id     UUID NOT NULL REFERENCES fs.member_subscriptions(id),
    vehicle_id          UUID NOT NULL REFERENCES fs.vehicles(id),
    authorized_driver_id UUID REFERENCES fs.authorized_drivers(id),
    status              fs.reservation_status NOT NULL DEFAULT 'requested',
    pickup_at           TIMESTAMPTZ NOT NULL,
    return_at           TIMESTAMPTZ NOT NULL,
    -- Convenience tstzrange generated from the above (for conflict prevention)
    booking_period      TSTZRANGE GENERATED ALWAYS AS (tstzrange(pickup_at, return_at, '[)')) STORED,
    days_booked         INTEGER NOT NULL,           -- whole days billed
    tier_points_per_day NUMERIC(5,2) NOT NULL,      -- snapshot from tier at booking time
    total_points_cost   INTEGER NOT NULL,           -- days_booked * points_per_day
    destination         VARCHAR(200),
    purpose             VARCHAR(200),
    concierge_notes     TEXT,
    member_notes        TEXT,
    cancelled_at        TIMESTAMPTZ,
    cancelled_by        UUID,
    cancellation_reason TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT res_date_order           CHECK (return_at > pickup_at),
    CONSTRAINT res_days_positive        CHECK (days_booked >= 1),
    CONSTRAINT res_points_positive      CHECK (total_points_cost >= 1)
);

-- Prevent two confirmed/picked-up reservations from overlapping on the same car
ALTER TABLE fs.reservations
    ADD CONSTRAINT reservations_no_overlap
    EXCLUDE USING GIST (
        vehicle_id  WITH =,
        booking_period WITH &&
    )
    WHERE (status IN ('confirmed','picked_up'));

-- Now add the deferred FK from point_transactions → reservations
ALTER TABLE fs.point_transactions
    ADD CONSTRAINT fk_points_reservation
    FOREIGN KEY (reservation_id) REFERENCES fs.reservations(id);

CREATE INDEX idx_res_member             ON fs.reservations(member_id);
CREATE INDEX idx_res_vehicle            ON fs.reservations(vehicle_id);
CREATE INDEX idx_res_pickup             ON fs.reservations(pickup_at);
CREATE INDEX idx_res_status_pickup      ON fs.reservations(status, pickup_at);

-- Reservation status history
CREATE TABLE fs.reservation_status_history (
    id              BIGSERIAL PRIMARY KEY,
    reservation_id  UUID NOT NULL REFERENCES fs.reservations(id) ON DELETE CASCADE,
    previous_status fs.reservation_status,
    new_status      fs.reservation_status NOT NULL,
    reason          TEXT,
    changed_by      UUID,
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Pickup / return records (actual mileage, fuel, condition)
CREATE TABLE fs.reservation_pickups_returns (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_id      UUID NOT NULL REFERENCES fs.reservations(id) ON DELETE CASCADE,
    event_type          VARCHAR(10) NOT NULL CHECK (event_type IN ('pickup','return')),
    event_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    mileage             INTEGER NOT NULL,
    fuel_level_pct      SMALLINT CHECK (fuel_level_pct BETWEEN 0 AND 100),
    condition           fs.vehicle_condition,
    pre_existing_damage TEXT,
    new_damage          TEXT,
    handled_by_staff    UUID,
    member_signature_url TEXT,
    photos_url          TEXT[],                     -- array of photo URLs
    notes               TEXT
);

CREATE INDEX idx_pickup_return_res  ON fs.reservation_pickups_returns(reservation_id);

-- =============================================================================
-- 8. INCIDENTS, MAINTENANCE, FUEL/DETAILING
-- =============================================================================
CREATE TABLE fs.damage_incidents (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_id          UUID NOT NULL REFERENCES fs.vehicles(id),
    reservation_id      UUID REFERENCES fs.reservations(id),
    member_id           UUID REFERENCES fs.members(id),
    severity            fs.incident_severity NOT NULL,
    description         TEXT NOT NULL,
    occurred_at         TIMESTAMPTZ NOT NULL,
    reported_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    estimated_cost      NUMERIC(10,2),
    actual_cost         NUMERIC(10,2),
    insurance_claim_number VARCHAR(50),
    resolved_on         DATE,
    police_report_number VARCHAR(50),
    photos_url          TEXT[],
    notes               TEXT
);

CREATE TABLE fs.vehicle_maintenance (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_id      UUID NOT NULL REFERENCES fs.vehicles(id),
    service_type    VARCHAR(100) NOT NULL,
    service_date    DATE NOT NULL,
    mileage         INTEGER NOT NULL,
    vendor          VARCHAR(200),
    cost            NUMERIC(10,2),
    next_service_mileage INTEGER,
    next_service_date DATE,
    description     TEXT,
    invoice_url     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_maint_vehicle  ON fs.vehicle_maintenance(vehicle_id, service_date DESC);

-- =============================================================================
-- 9. PAYMENTS
-- =============================================================================
CREATE TABLE fs.payments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id           UUID NOT NULL REFERENCES fs.members(id),
    subscription_id     UUID REFERENCES fs.member_subscriptions(id),
    reservation_id      UUID REFERENCES fs.reservations(id),
    amount              NUMERIC(10,2) NOT NULL,
    currency            CHAR(3) NOT NULL DEFAULT 'USD',
    description         VARCHAR(200),
    category            VARCHAR(50),               -- 'subscription','initiation','overage','damage','event','other'
    status              fs.payment_status NOT NULL DEFAULT 'pending',
    stripe_payment_intent VARCHAR(100),
    paid_at             TIMESTAMPTZ,
    refunded_at         TIMESTAMPTZ,
    refund_amount       NUMERIC(10,2),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_pay_member ON fs.payments(member_id, created_at DESC);

-- =============================================================================
-- 10. EVENTS (driving tours, member dinners, clubhouse)
-- =============================================================================
CREATE TABLE fs.events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(200) NOT NULL,
    event_type      VARCHAR(50) NOT NULL,          -- 'driving_tour','dinner','networking','track_day','reveal'
    location_id     UUID REFERENCES fs.locations(id),
    venue           VARCHAR(200),
    starts_at       TIMESTAMPTZ NOT NULL,
    ends_at         TIMESTAMPTZ NOT NULL,
    capacity        INTEGER,
    member_price    NUMERIC(10,2) NOT NULL DEFAULT 0,
    guest_price     NUMERIC(10,2) NOT NULL DEFAULT 0,
    description     TEXT,
    is_published    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT events_date_order CHECK (ends_at > starts_at)
);

CREATE TABLE fs.event_registrations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id        UUID NOT NULL REFERENCES fs.events(id) ON DELETE CASCADE,
    member_id       UUID NOT NULL REFERENCES fs.members(id),
    guests_count    SMALLINT NOT NULL DEFAULT 0,
    status          VARCHAR(20) NOT NULL DEFAULT 'registered', -- 'registered','waitlist','attended','no_show','cancelled'
    registered_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (event_id, member_id)
);

-- =============================================================================
-- 11. BUSINESS LOGIC: functions + triggers
-- =============================================================================

-- 11.1 Current available point balance for a subscription
CREATE OR REPLACE FUNCTION fs.subscription_balance(p_subscription_id UUID)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(points),0)::INTEGER
      FROM fs.point_transactions
     WHERE subscription_id = p_subscription_id;
$$;

-- 11.2 Cost calculation for a tentative booking
CREATE OR REPLACE FUNCTION fs.calc_reservation_cost(
    p_tier_id      SMALLINT,
    p_days_booked  INTEGER
) RETURNS INTEGER
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_ppd NUMERIC;
    v_min INTEGER;
BEGIN
    SELECT points_per_day, min_booking_days INTO v_ppd, v_min FROM fs.tiers WHERE id = p_tier_id;
    IF v_ppd IS NULL THEN
        RAISE EXCEPTION 'Unknown tier: %', p_tier_id;
    END IF;
    IF p_days_booked < v_min THEN
        RAISE EXCEPTION 'Tier % requires a minimum booking of % days (got %)',
            p_tier_id, v_min, p_days_booked;
    END IF;
    RETURN CEIL(v_ppd * p_days_booked)::INTEGER;
END;
$$;

-- 11.3 When a reservation is confirmed, debit points + write ledger entry
CREATE OR REPLACE FUNCTION fs.debit_points_on_confirm()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_tier_id        SMALLINT;
    v_min_days       INTEGER;
    v_balance_before INTEGER;
    v_balance_after  INTEGER;
BEGIN
    -- On INSERT or status change into confirmed
    IF (TG_OP = 'INSERT' AND NEW.status = 'confirmed')
       OR (TG_OP = 'UPDATE' AND OLD.status <> 'confirmed' AND NEW.status = 'confirmed') THEN

        SELECT tier_id INTO v_tier_id FROM fs.vehicles WHERE id = NEW.vehicle_id;
        SELECT min_booking_days INTO v_min_days FROM fs.tiers WHERE id = v_tier_id;

        IF NEW.days_booked < v_min_days THEN
            RAISE EXCEPTION 'Vehicle tier % requires % day minimum; booking is only % days',
                v_tier_id, v_min_days, NEW.days_booked;
        END IF;

        v_balance_before := fs.subscription_balance(NEW.subscription_id);
        IF v_balance_before < NEW.total_points_cost THEN
            RAISE EXCEPTION 'Insufficient tier points: need %, have %',
                NEW.total_points_cost, v_balance_before;
        END IF;

        v_balance_after := v_balance_before - NEW.total_points_cost;

        INSERT INTO fs.point_transactions(
            subscription_id, txn_type, points, balance_after, reservation_id, reason
        ) VALUES (
            NEW.subscription_id, 'debit', -NEW.total_points_cost, v_balance_after,
            NEW.id, 'Reservation confirmed: ' || NEW.confirmation_code
        );
    END IF;

    -- Refund on cancellation of an already-confirmed res
    IF TG_OP = 'UPDATE'
       AND OLD.status IN ('confirmed','requested')
       AND NEW.status = 'cancelled' THEN

        -- Only refund if we previously debited (status was 'confirmed')
        IF OLD.status = 'confirmed' THEN
            v_balance_before := fs.subscription_balance(NEW.subscription_id);
            v_balance_after  := v_balance_before + OLD.total_points_cost;

            INSERT INTO fs.point_transactions(
                subscription_id, txn_type, points, balance_after, reservation_id, reason
            ) VALUES (
                NEW.subscription_id, 'refund', OLD.total_points_cost, v_balance_after,
                NEW.id, 'Reservation cancelled: ' || NEW.confirmation_code
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_reservations_point_ledger
AFTER INSERT OR UPDATE ON fs.reservations
FOR EACH ROW EXECUTE FUNCTION fs.debit_points_on_confirm();

-- 11.4 Log status transitions
CREATE OR REPLACE FUNCTION fs.log_reservation_status()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO fs.reservation_status_history(reservation_id, previous_status, new_status)
        VALUES (NEW.id, NULL, NEW.status);
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO fs.reservation_status_history(reservation_id, previous_status, new_status)
        VALUES (NEW.id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_reservations_status_history
AFTER INSERT OR UPDATE OF status ON fs.reservations
FOR EACH ROW EXECUTE FUNCTION fs.log_reservation_status();

-- 11.5 Vehicle status log
CREATE OR REPLACE FUNCTION fs.log_vehicle_status()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO fs.vehicle_status_log(vehicle_id, previous_status, new_status)
        VALUES (NEW.id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_vehicles_status_log
AFTER UPDATE OF status ON fs.vehicles
FOR EACH ROW EXECUTE FUNCTION fs.log_vehicle_status();

-- 11.6 updated_at maintainer
CREATE OR REPLACE FUNCTION fs.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DO $$
DECLARE t TEXT;
BEGIN
    FOR t IN SELECT unnest(ARRAY[
        'locations','plans','vehicles','members',
        'member_subscriptions','reservations'
    ]) LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%1$s_touch BEFORE UPDATE ON fs.%1$I
             FOR EACH ROW EXECUTE FUNCTION fs.touch_updated_at();', t);
    END LOOP;
END $$;

-- 11.7 On subscription activation, grant the point pool
CREATE OR REPLACE FUNCTION fs.grant_points_on_activation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_plan_points INTEGER;
BEGIN
    IF (TG_OP = 'INSERT' AND NEW.status = 'active')
       OR (TG_OP = 'UPDATE' AND OLD.status <> 'active' AND NEW.status = 'active') THEN

        -- Initial grant from plan
        SELECT annual_tier_points INTO v_plan_points FROM fs.plans WHERE id = NEW.plan_id;

        INSERT INTO fs.point_transactions(subscription_id, txn_type, points, balance_after, reason)
        VALUES (NEW.id, 'grant', v_plan_points, v_plan_points, 'Annual plan grant');

        -- Rollover from previous term
        IF NEW.points_rolled_in > 0 THEN
            INSERT INTO fs.point_transactions(subscription_id, txn_type, points, balance_after, reason)
            VALUES (NEW.id, 'rollover', NEW.points_rolled_in,
                    v_plan_points + NEW.points_rolled_in,
                    'Rollover from prior term');
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_subs_grant_points
AFTER INSERT OR UPDATE ON fs.member_subscriptions
FOR EACH ROW EXECUTE FUNCTION fs.grant_points_on_activation();

-- =============================================================================
-- 12. VIEWS
-- =============================================================================

-- Active fleet roster with model + tier info
CREATE OR REPLACE VIEW fs.v_active_fleet AS
SELECT
    v.id                    AS vehicle_id,
    v.stock_number,
    v.model_year,
    mf.name                 AS manufacturer,
    vm.model_name           AS model,
    vm.trim,
    v.exterior_color,
    v.tier_id,
    t.points_per_day,
    t.min_booking_days,
    vm.horsepower,
    vm.top_speed_mph,
    vm.zero_to_60_sec,
    v.status,
    v.condition,
    v.current_mileage,
    l.code                  AS location_code
  FROM fs.vehicles v
  JOIN fs.vehicle_models vm ON vm.id = v.model_id
  JOIN fs.manufacturers mf  ON mf.id = vm.manufacturer_id
  JOIN fs.tiers t           ON t.id = v.tier_id
  JOIN fs.locations l       ON l.id = v.location_id
 WHERE v.retired_on IS NULL;

-- Member dashboard — current subscription + balance
CREATE OR REPLACE VIEW fs.v_member_subscription_status AS
SELECT
    m.id                AS member_id,
    m.member_number,
    m.first_name || ' ' || m.last_name AS full_name,
    m.email,
    m.status            AS member_status,
    s.id                AS subscription_id,
    p.name              AS plan_name,
    p.driving_days,
    s.start_date,
    s.end_date,
    s.points_granted + s.points_rolled_in AS points_issued,
    fs.subscription_balance(s.id)         AS points_remaining,
    ROUND(100.0 * fs.subscription_balance(s.id)::NUMERIC
         / NULLIF(s.points_granted + s.points_rolled_in, 0), 1) AS pct_remaining
  FROM fs.members m
  JOIN fs.member_subscriptions s ON s.member_id = m.id AND s.status = 'active'
  JOIN fs.plans p                ON p.id = s.plan_id;

-- Upcoming reservations
CREATE OR REPLACE VIEW fs.v_upcoming_reservations AS
SELECT
    r.id,
    r.confirmation_code,
    m.member_number,
    m.first_name || ' ' || m.last_name AS member_name,
    mf.name || ' ' || vm.model_name    AS vehicle,
    v.exterior_color,
    r.tier_points_per_day,
    r.pickup_at,
    r.return_at,
    r.days_booked,
    r.total_points_cost,
    r.status
  FROM fs.reservations r
  JOIN fs.members m          ON m.id = r.member_id
  JOIN fs.vehicles v         ON v.id = r.vehicle_id
  JOIN fs.vehicle_models vm  ON vm.id = v.model_id
  JOIN fs.manufacturers mf   ON mf.id = vm.manufacturer_id
 WHERE r.status IN ('requested','confirmed','picked_up')
   AND r.return_at >= now()
 ORDER BY r.pickup_at;

-- =============================================================================
-- 13. SEED DATA
-- =============================================================================

-- 13.1 Houston location
INSERT INTO fs.locations (code, name, address_line1, city, state, postal_code, phone, email, timezone, latitude, longitude, opened_on)
VALUES ('HOU', 'Freedom Supercars Houston', '2119 Brittmoore Rd', 'Houston', 'TX', '77043',
        '832-726-1940', 'info@freedomsupercars.com', 'America/Chicago',
        29.8192615, -95.5739822, '2009-01-01');

-- 13.2 Tiers (point cost per day — industry-standard defaults; adjust as needed)
INSERT INTO fs.tiers (id, name, points_per_day, min_booking_days, max_booking_days, description) VALUES
  (1, 'Tier 1 — Entry Luxury',  1.0, 1, 14, 'Entry-level luxury (currently not in Houston fleet).'),
  (2, 'Tier 2 — Luxury/Electric', 1.5, 1, 14, 'Luxury GT and electric grand tourers (Audi E-Tron GT).'),
  (3, 'Tier 3 — Performance',     2.0, 1, 10, 'Core performance fleet — Ferrari Roma, Porsche GT3 RS, Aston F1, Lambo Urus.'),
  (4, 'Tier 4 — Hypercar-adjacent', 3.0, 2, 7, 'Top-tier sports cars — McLaren Artura, Porsche GT3, Huracan Sterrato, DBX 707.'),
  (5, 'Tier 5 — Flagship',         5.0, 3, 5, 'Flagships requiring 3-day minimum — Ferrari 296 GTB, Rolls Royce Cullinan.');

-- 13.3 Plans (4 plans; point allocations scaled so a member could use mostly T3 vehicles)
-- Logic: 15-day plan ≈ 30 T3 points; 30 ≈ 60; 60 ≈ 120; 100 ≈ 200.
-- These are configurable defaults Jim can tune.
INSERT INTO fs.plans (code, name, driving_days, annual_tier_points, guest_drivers_allowed, rollover_allowed, rollover_cap_points, sort_order, description) VALUES
  ('PLAN_15',  '15-Day Starter Membership',   15,  30, 1, FALSE, NULL, 1, 'Entry membership: 15 driving days/year. Point pool of 30.'),
  ('PLAN_30',  '30-Day Enthusiast Membership',30,  60, 2, TRUE,  10,  2, 'Most popular. 30 driving days/year. 60 points. Limited rollover.'),
  ('PLAN_60',  '60-Day Connoisseur Membership',60, 120, 2, TRUE,  20,  3, 'For the avid driver: 60 days, 120 points, larger rollover cap.'),
  ('PLAN_100', '100-Day Signature Membership', 100, 200, 3, TRUE,  40,  4, 'Signature tier: 100 driving days/year, 200 points, 3 authorized drivers.');

-- 13.4 Plan → Tier allocations (optional per-tier caps)
-- By default, all plans can use all tiers up to the point-pool limit.
-- The 15-day plan is capped to 5 T5 days (T5 is premium).
DO $$
DECLARE
    p_id UUID;
    tier_rec RECORD;
BEGIN
    FOR p_id IN SELECT id FROM fs.plans LOOP
        FOR tier_rec IN SELECT id FROM fs.tiers WHERE id BETWEEN 2 AND 5 LOOP
            INSERT INTO fs.plan_tier_allocations(plan_id, tier_id, max_days_per_year, advance_booking_days)
            VALUES (p_id, tier_rec.id,
                    CASE WHEN tier_rec.id = 5 AND p_id = (SELECT id FROM fs.plans WHERE code='PLAN_15') THEN 5 ELSE NULL END,
                    CASE WHEN tier_rec.id = 5 THEN 90 ELSE 60 END);
        END LOOP;
    END LOOP;
END $$;

-- 13.5 Manufacturers
INSERT INTO fs.manufacturers (name, country) VALUES
  ('Audi','Germany'),('Mercedes-Benz','Germany'),('Ferrari','Italy'),
  ('Porsche','Germany'),('Aston Martin','United Kingdom'),('Lamborghini','Italy'),
  ('Bentley','United Kingdom'),('McLaren','United Kingdom'),('Rolls-Royce','United Kingdom'),
  ('Maserati','Italy'),('BMW','Germany'),('Chevrolet','United States'),
  ('Dodge','United States'),('Ford','United States'),('Jaguar','United Kingdom'),
  ('Land Rover','United Kingdom'),('Lotus','United Kingdom'),('Nissan','Japan'),
  ('Acura','Japan'),('Alfa Romeo','Italy'),('Fisker','United States'),
  ('Spyker','Netherlands'),('Tesla','United States');

-- 13.6 Current fleet — vehicle models
WITH mfg AS (SELECT name, id FROM fs.manufacturers)
INSERT INTO fs.vehicle_models (manufacturer_id, model_name, trim, body_style, fuel_type, drivetrain, horsepower, top_speed_mph, zero_to_60_sec, seats) VALUES
  ((SELECT id FROM mfg WHERE name='Audi'),         'E-Tron GT',            NULL,                  'sedan',      'electric', 'awd', 522, 155, 3.8, 4),
  ((SELECT id FROM mfg WHERE name='Mercedes-Benz'),'SL63 AMG',             NULL,                  'convertible','gasoline', 'awd', 577, 196, 3.5, 4),
  ((SELECT id FROM mfg WHERE name='Ferrari'),      'Portofino',            NULL,                  'convertible','gasoline', 'rwd', 592, 200, 3.4, 4),
  ((SELECT id FROM mfg WHERE name='Audi'),         'R8',                   'V10 Performance',     'coupe',      'gasoline', 'awd', 602, 201, 3.1, 2),
  ((SELECT id FROM mfg WHERE name='Porsche'),      '911 GTS',              'Cabriolet T-Hybrid',  'convertible','hybrid',   'awd', NULL,NULL,NULL,4),
  ((SELECT id FROM mfg WHERE name='Porsche'),      '911 Targa 4S',         NULL,                  'targa',      'gasoline', 'awd', 444, 190, 3.7, 4),
  ((SELECT id FROM mfg WHERE name='Mercedes-Benz'),'G63 AMG',              NULL,                  'suv',        'gasoline','4wd', 577, 185, 4.5, 5),
  ((SELECT id FROM mfg WHERE name='Ferrari'),      'Roma',                 NULL,                  'coupe',      'gasoline', 'rwd', 612, 201, 3.3, 4),
  ((SELECT id FROM mfg WHERE name='Porsche'),      '991 GT3 RS',           NULL,                  'coupe',      'gasoline', 'rwd', 520, 190, 3.0, 2),
  ((SELECT id FROM mfg WHERE name='Aston Martin'), 'Vantage',              'F1 Edition',          'coupe',      'gasoline', 'rwd', 528, 195, 3.5, 2),
  ((SELECT id FROM mfg WHERE name='Lamborghini'),  'Urus',                 NULL,                  'suv',        'gasoline','4wd', 600, 196, 3.4, 5),
  ((SELECT id FROM mfg WHERE name='Bentley'),      'Continental GT',       NULL,                  'coupe',      'gasoline', 'awd', 568, 198, 4.0, 4),
  ((SELECT id FROM mfg WHERE name='Porsche'),      '911 GT3',              NULL,                  'coupe',      'gasoline', 'rwd', 502, 193, 3.0, 2),
  ((SELECT id FROM mfg WHERE name='McLaren'),      'Artura',               'Performance Spyder',  'spyder',     'phev',     'rwd', 671, 205, 2.8, 2),
  ((SELECT id FROM mfg WHERE name='Aston Martin'), 'DBX',                  '707',                 'suv',        'gasoline','4wd', 707, 193, 3.1, 5),
  ((SELECT id FROM mfg WHERE name='Lamborghini'),  'Huracan Sterrato',     NULL,                  'coupe',      'gasoline', 'awd', 602, 205, 3.0, 2),
  ((SELECT id FROM mfg WHERE name='Rolls-Royce'),  'Cullinan',             NULL,                  'suv',        'gasoline','4wd', 563, 155, 5.0, 5),
  ((SELECT id FROM mfg WHERE name='Ferrari'),      '296 GTB',              NULL,                  'coupe',      'phev',     'rwd', 819, 205, 2.7, 2);

-- 13.7 Individual current-fleet vehicles (Houston)
WITH hou AS (SELECT id FROM fs.locations WHERE code='HOU'),
     vm  AS (SELECT vm.id AS model_id, mf.name AS mname, vm.model_name, vm.trim
               FROM fs.vehicle_models vm JOIN fs.manufacturers mf ON mf.id = vm.manufacturer_id)
INSERT INTO fs.vehicles (stock_number, location_id, model_id, tier_id, model_year, exterior_color, status, in_service_on, is_marquee) VALUES
  ('FS-HOU-001', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Audi'          AND model_name='E-Tron GT'),           2, 2024, 'Silver',          'available', '2024-01-15', FALSE),
  ('FS-HOU-002', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Mercedes-Benz' AND model_name='SL63 AMG'),            3, 2024, 'Grey',            'available', '2024-02-01', FALSE),
  ('FS-HOU-003', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Ferrari'       AND model_name='Portofino'),           3, 2022, 'Rosso Corsa',     'available', '2022-06-01', FALSE),
  ('FS-HOU-004', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Audi'          AND trim='V10 Performance'),           3, 2023, 'Nardo Grey',      'available', '2023-04-15', TRUE),
  ('FS-HOU-005', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Porsche'       AND model_name='911 GTS'),             3, 2025, 'Racing Green',    'available', '2025-01-10', FALSE),
  ('FS-HOU-006', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Porsche'       AND model_name='911 Targa 4S'),        3, 2024, 'Black',           'available', '2024-05-20', FALSE),
  ('FS-HOU-007', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Mercedes-Benz' AND model_name='G63 AMG'),             3, 2024, 'Matte Black',     'available', '2024-03-10', FALSE),
  ('FS-HOU-008', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Ferrari'       AND model_name='Roma'),                3, 2023, 'Grigio Silverstone','available','2023-07-01', FALSE),
  ('FS-HOU-009', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Porsche'       AND model_name='991 GT3 RS'),          3, 2019, 'Black',           'available', '2022-10-01', FALSE),
  ('FS-HOU-010', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Aston Martin'  AND trim='F1 Edition'),                3, 2023, 'British Racing Green','available','2023-09-01', TRUE),
  ('FS-HOU-011', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Lamborghini'   AND model_name='Urus'),                3, 2023, 'Blu Eleos',       'available', '2023-03-15', FALSE),
  ('FS-HOU-012', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Bentley'       AND model_name='Continental GT'),      3, 2022, 'Candy Red',       'available', '2022-08-20', FALSE),
  ('FS-HOU-013', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Porsche'       AND model_name='911 GT3'),             4, 2023, 'Racing Yellow',   'available', '2023-11-01', TRUE),
  ('FS-HOU-014', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='McLaren'       AND trim='Performance Spyder'),        4, 2024, 'McLaren Orange',  'available', '2024-06-15', TRUE),
  ('FS-HOU-015', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Aston Martin'  AND trim='707'),                       4, 2024, 'Magnetic Silver', 'available', '2024-04-10', FALSE),
  ('FS-HOU-016', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Lamborghini'   AND model_name='Huracan Sterrato'),    4, 2024, 'Verde Gea',       'available', '2024-08-01', TRUE),
  ('FS-HOU-017', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Rolls-Royce'   AND model_name='Cullinan'),            5, 2023, 'Arctic White',    'available', '2023-12-01', TRUE),
  ('FS-HOU-018', (SELECT id FROM hou), (SELECT model_id FROM vm WHERE mname='Ferrari'       AND model_name='296 GTB'),             5, 2024, 'Giallo Modena',   'available', '2024-10-15', TRUE);

-- 13.8 Previous fleet roster (from club's historical archive)
INSERT INTO fs.previous_vehicles (manufacturer, model, trim, color, location_id) VALUES
  ('Acura','NSX',NULL,'Blue',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Alfa Romeo','4C','Launch Edition','White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Aston Martin','DB9','Volante','Bronze',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Aston Martin','DBX','707','Gray',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Aston Martin','Vantage',NULL,'Silver',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Aston Martin','Vantage GT',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Aston Martin','V12 Vantage S','Convertible','Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Audi','R8','V8','Silver',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Audi','R8','V8','Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Audi','R8','Spider','Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Audi','R8','V10 GT','Ice Blue',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('BMW','M2','Performance Edition','White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('BMW','i8',NULL,'Silver',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('BMW','i8',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Bentley','Continental GT',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Bentley','Continental GTS',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Chevrolet','Corvette','C8 Convertible','Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Chevrolet','Corvette','C8 Z06 Convertible','Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Chevrolet','Corvette','C7 ZR1','Blue',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Chevrolet','Corvette','C7 Z06','Gray',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Chevrolet','Corvette','C7 Z06 LMR','White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Dodge','Viper',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Dodge','Viper',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Dodge','Viper','SRT','Orange',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','360 Modena Spider',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','360 Modena Spider',NULL,'Yellow',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','F430',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','F430 Spider',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','California',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','California T',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','California T',NULL,'Light Blue',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','458 Italia',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','458 Italia Spider',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','458 Italia Spider',NULL,'Dark Blue',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','488 GTB',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','488 Spider',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','F8',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','F12',NULL,'Grey',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ferrari','Portofino',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Fisker','Karma',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ford','GT',NULL,'Gray',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Ford','GT',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Jaguar','F-Type R',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Gallardo',NULL,'Orange',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Gallardo',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Gallardo',NULL,'Yellow',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Gallardo',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Gallardo Spyder',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Gallardo Superleggera',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Gallardo Super Trofeo Stradale',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Gallardo Performante Spyder',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Gallardo Performante Spyder',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Gallardo Squadra Corsa',NULL,'Yellow',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Huracan',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Huracan',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Huracan Evo',NULL,'Blue',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Huracan Spyder',NULL,'Yellow',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Huracan Spyder',NULL,'Green',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Aventador',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Aventador',NULL,'Matte Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Aventador Roadster',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Aventador S',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lamborghini','Urus',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Land Rover','Range Rover','HSE','White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Land Rover','Range Rover','LR4','Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Lotus','Evora',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Maserati','GranTurismo','Coupe','Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Maserati','GranTurismo','Cabriolet','Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Maserati','GranTurismo','Sportline','Gray',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Maserati','Ghibli',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Maserati','Ghibli','4QS','Bronze',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('McLaren','Artura','MSO','Orange',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('McLaren','MP4-12C',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('McLaren','MP4-12C','MSO','Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('McLaren','570S Spider',NULL,'Orange',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('McLaren','600LT',NULL,'Orange',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('McLaren','675LT',NULL,'Gray',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('McLaren','720S',NULL,'Orange',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Mercedes-Benz','SL55 AMG',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Mercedes-Benz','SL63 AMG',NULL,'Grey',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Mercedes-Benz','SLS AMG GT',NULL,'Silver',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Mercedes-Benz','SLS AMG',NULL,'Silver',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Mercedes-Benz','AMG GTS',NULL,'Gray',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Nissan','GTR',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Nissan','GTR','Black Edition','Blue',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','Cayman S',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','Cayman GT4',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','Macan GTS',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','Panamera Turbo',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','911 Carrera Cabriolet',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','911 GT3',NULL,'Blue',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','911 GT3 RS',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','911 GT3 RS',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','911 Targa 4S',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','911 Turbo',NULL,'Silver',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','911 Turbo S',NULL,'Navy',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','911 Turbo S',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','911 Turbo S Cabriolet',NULL,'Shark Blue',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','911 Turbo Cabriolet',NULL,'Bronze',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Porsche','Taycan Turbo S',NULL,'Red',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Rolls-Royce','Phantom',NULL,'White',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Rolls-Royce','Ghost',NULL,'Silver',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Rolls-Royce','Ghost',NULL,'Gray',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Rolls-Royce','Ghost II',NULL,'Gray',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Rolls-Royce','Ghost II',NULL,'Navy',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Spyker','C8 Spyder',NULL,'Silver',(SELECT id FROM fs.locations WHERE code='HOU')),
  ('Tesla','P85D+',NULL,'Black',(SELECT id FROM fs.locations WHERE code='HOU'));

COMMIT;

-- =============================================================================
-- 14. VERIFICATION QUERIES (run these after deployment to validate)
-- =============================================================================
-- Plans summary
-- SELECT code, name, driving_days, annual_tier_points FROM fs.plans ORDER BY sort_order;

-- Tier point economics
-- SELECT id, name, points_per_day, min_booking_days FROM fs.tiers ORDER BY id;

-- Current fleet by tier
-- SELECT tier_id, COUNT(*) AS fleet_count FROM fs.vehicles WHERE retired_on IS NULL GROUP BY tier_id ORDER BY tier_id;

-- Full fleet listing
-- SELECT * FROM fs.v_active_fleet ORDER BY tier_id, manufacturer, model;

-- How many "days of driving" could a member get per plan at each tier?
-- SELECT p.code, p.annual_tier_points, t.id AS tier, t.points_per_day,
--        FLOOR(p.annual_tier_points / t.points_per_day) AS max_days_at_tier
--   FROM fs.plans p CROSS JOIN fs.tiers t
--  WHERE t.id BETWEEN 2 AND 5
--  ORDER BY p.sort_order, t.id;

-- =============================================================================
-- END OF SCHEMA
-- =============================================================================
