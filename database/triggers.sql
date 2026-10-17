-- =====================================================================
-- triggers.sql : business-rule triggers (run after schema.sql)
-- =====================================================================

-- ---------------------------------------------------------------------
-- T1. Reject overlapping bookings on the same berth.
--
-- Two windows overlap when  A.start < B.end  AND  B.start < A.end.
-- Windows are half-open [start, end), so a ship leaving at 10:00 and the
-- next one arriving at 10:00 is allowed.  A booking with no berth_end yet
-- (ship alongside, departure unknown) is treated as open-ended.
--
-- Concurrency: two transactions could each check, see no clash, and both
-- insert.  Locking the berth row (FOR UPDATE) first makes bookings for the
-- same berth run one after another, so the check cannot be bypassed.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_check_berth_overlap() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    clash port_call%ROWTYPE;
BEGIN
    -- nothing to check until a berth and a start time are both set
    IF NEW.berth_number IS NULL OR NEW.berth_start IS NULL THEN
        RETURN NEW;
    END IF;

    PERFORM 1 FROM berth WHERE berth_number = NEW.berth_number FOR UPDATE;

    SELECT * INTO clash
    FROM port_call pc
    WHERE pc.berth_number = NEW.berth_number
      AND pc.call_id     <> NEW.call_id                 -- ignore the row being updated
      AND pc.berth_start IS NOT NULL
      AND pc.berth_start < COALESCE(NEW.berth_end, 'infinity')
      AND NEW.berth_start < COALESCE(pc.berth_end, 'infinity')
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Berth % is already booked by call % from % to %',
                        NEW.berth_number, clash.call_id, clash.berth_start,
                        COALESCE(clash.berth_end::text, 'open-ended')
              USING ERRCODE = 'exclusion_violation',
                    HINT    = 'Choose another berth or a non-overlapping time window.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS check_berth_overlap ON port_call;
CREATE TRIGGER check_berth_overlap
    BEFORE INSERT OR UPDATE OF berth_number, berth_start, berth_end
    ON port_call
    FOR EACH ROW
    EXECUTE FUNCTION trg_check_berth_overlap();
