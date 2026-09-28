-- =============================================================================
-- Migration 030: Allow 0 points for courtesy bookings in process_reservation_points
-- Required for Guide 9.2-R10, 9.2-C16 (Courtesy bookings consume 0 points)
-- =============================================================================

CREATE OR REPLACE FUNCTION fs.process_reservation_points()
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

        IF v_min_days IS NOT NULL AND NEW.days_booked < v_min_days THEN
            RAISE EXCEPTION 'Vehicle tier % requires % day minimum; booking is only % days',
                v_tier_id, v_min_days, NEW.days_booked;
        END IF;

        -- Courtesy bookings or 0-point bookings do NOT consume points
        IF COALESCE(NEW.total_points_cost, 0) > 0 AND NOT COALESCE(NEW.is_courtesy, FALSE) THEN
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
    END IF;

    -- Refund on cancellation of an already-confirmed res
    IF TG_OP = 'UPDATE'
       AND OLD.status IN ('confirmed','requested')
       AND NEW.status = 'cancelled' THEN

        -- Only refund if we previously debited (status was 'confirmed' and points > 0)
        IF OLD.status = 'confirmed' AND COALESCE(OLD.total_points_cost, 0) > 0 AND NOT COALESCE(OLD.is_courtesy, FALSE) THEN
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
