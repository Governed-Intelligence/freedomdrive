-- =============================================================================
-- Migration 028: Align legacy status history trigger on fs.reservations
-- Ensures log_reservation_status does not fail against canonical 285-table schema
-- =============================================================================

CREATE OR REPLACE FUNCTION fs.log_reservation_status()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'fs' AND table_name = 'reservation_status_history' AND column_name = 'previous_status'
    ) THEN
        IF TG_OP = 'INSERT' THEN
            INSERT INTO fs.reservation_status_history(reservation_id, previous_status, new_status)
            VALUES (NEW.id, NULL, NEW.status);
        ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
            INSERT INTO fs.reservation_status_history(reservation_id, previous_status, new_status)
            VALUES (NEW.id, OLD.status, NEW.status);
        END IF;
    ELSIF EXISTS (
        SELECT 1 FROM information_schema.tables
         WHERE table_schema = 'fs' AND table_name = 'reservation_status_history_legacy'
    ) THEN
        IF TG_OP = 'INSERT' THEN
            INSERT INTO fs.reservation_status_history_legacy(reservation_id, previous_status, new_status)
            VALUES (NEW.id, NULL, NEW.status);
        ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
            INSERT INTO fs.reservation_status_history_legacy(reservation_id, previous_status, new_status)
            VALUES (NEW.id, OLD.status, NEW.status);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
