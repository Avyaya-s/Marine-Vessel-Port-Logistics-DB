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

-- ---------------------------------------------------------------------
-- T2. Reject a vessel that is physically too big for the berth.
--
-- Only hard physical limits are enforced here (LOA and draft).  Cargo
-- type is a planning preference, so allocate_berth() matches it but the
-- trigger does not; a port can still put a ship at a non-matching berth
-- manually if it fits.
--
-- Fires on imo_number too: swapping the vessel on an existing booking
-- must be re-checked just like changing the berth.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_check_berth_fit() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v vessel%ROWTYPE;
    b berth%ROWTYPE;
BEGIN
    IF NEW.berth_number IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v FROM vessel WHERE imo_number   = NEW.imo_number;
    SELECT * INTO b FROM berth  WHERE berth_number = NEW.berth_number;

    -- FK checks run after BEFORE triggers; if either row is missing,
    -- let the foreign key report the error instead.
    IF v.imo_number IS NULL OR b.berth_number IS NULL THEN
        RETURN NEW;
    END IF;

    IF v.loa > b.max_loa THEN
        RAISE EXCEPTION 'Vessel % (LOA % m) is too long for berth % (max LOA % m)',
                        v.vessel_name, v.loa, b.berth_number, b.max_loa
              USING ERRCODE = 'check_violation';
    END IF;

        IF v.draft > b.max_draft THEN
        RAISE EXCEPTION 'Vessel % (draft % m) is too deep for berth % (max draft % m)',
                        v.vessel_name, v.draft, b.berth_number, b.max_draft
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS check_berth_fit ON port_call;
CREATE TRIGGER check_berth_fit
    BEFORE INSERT OR UPDATE OF berth_number, imo_number
    ON port_call
    FOR EACH ROW
    EXECUTE FUNCTION trg_check_berth_fit();

-- ---------------------------------------------------------------------
-- T3. Keep call_status in sync with the actual-time columns.
--
-- The status is derived from the latest fact recorded:
--     atd set -> Departed,  atb set -> Berthed,  ata set -> Waiting,
--     none    -> Expected.
-- A trigger cannot fire "when the clock reaches berth_start", so the
-- status follows facts (ata / atb / atd), which are written when the
-- event actually happens (geofence, operator, AIS).
--
-- call_status is stored (not computed in a view) so dashboards can
-- filter on it cheaply; this trigger is what keeps that copy correct.
-- Setting call_status by hand to a value that contradicts the facts is
-- rejected: record the timestamp instead.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_set_call_status() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    derived VARCHAR(10);
BEGIN
    derived := CASE
                   WHEN NEW.atd IS NOT NULL THEN 'Departed'
                   WHEN NEW.atb IS NOT NULL THEN 'Berthed'
                   WHEN NEW.ata IS NOT NULL THEN 'Waiting'
                   ELSE 'Expected'
               END;

    IF TG_OP = 'UPDATE'
       AND NEW.call_status IS DISTINCT FROM OLD.call_status
       AND NEW.call_status <> derived THEN
        RAISE EXCEPTION 'call_status cannot be set to % for call %: the recorded times say %',
                        NEW.call_status, NEW.call_id, derived
              USING ERRCODE = 'check_violation',
                    HINT    = 'Set ata, atb or atd instead; the status follows automatically.';
    END IF;

    NEW.call_status := derived;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_call_status ON port_call;
CREATE TRIGGER set_call_status
    BEFORE INSERT OR UPDATE OF ata, atb, atd, call_status
    ON port_call
    FOR EACH ROW
    EXECUTE FUNCTION trg_set_call_status();

-- ---------------------------------------------------------------------
-- T4. Companies must play the role they are used in.
--
-- A foreign key only proves the company exists.  These rules need the
-- company's type as well:
--   port_call.agent_id      -> company_type = 'agent'
--   shipment.shipper_id     -> company_type = 'shipper'
--   shipment.consignee_id   -> company_type = 'consignee'
-- One function serves both tables; TG_TABLE_NAME says which fired it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_check_company_role() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    actual VARCHAR(10);
BEGIN
    IF TG_TABLE_NAME = 'port_call' THEN
        SELECT company_type INTO actual FROM company WHERE company_id = NEW.agent_id;
        IF actual <> 'agent' THEN
            RAISE EXCEPTION 'Company % is of type %, not agent', NEW.agent_id, actual
                  USING ERRCODE = 'check_violation';
        END IF;
    ELSE  -- shipment
        SELECT company_type INTO actual FROM company WHERE company_id = NEW.shipper_id;
        IF actual <> 'shipper' THEN
            RAISE EXCEPTION 'Company % is of type %, not shipper', NEW.shipper_id, actual
                  USING ERRCODE = 'check_violation';
        END IF;
        SELECT company_type INTO actual FROM company WHERE company_id = NEW.consignee_id;
        IF actual <> 'consignee' THEN
            RAISE EXCEPTION 'Company % is of type %, not consignee', NEW.consignee_id, actual
                  USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    -- if the company does not exist, actual is NULL, "NULL <> 'agent'" is
    -- not true, and the foreign key reports the error instead
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS check_company_role ON port_call;
CREATE TRIGGER check_company_role
    BEFORE INSERT OR UPDATE OF agent_id
    ON port_call
    FOR EACH ROW
    EXECUTE FUNCTION trg_check_company_role();

DROP TRIGGER IF EXISTS check_company_role ON shipment;
CREATE TRIGGER check_company_role
    BEFORE INSERT OR UPDATE OF shipper_id, consignee_id
    ON shipment
    FOR EACH ROW
    EXECUTE FUNCTION trg_check_company_role();

-- ---------------------------------------------------------------------
-- T5. The same rule from the other side: a company's type cannot change
-- while it is used in a role that needs the old type.  Without this, an
-- agent could be re-typed as a shipper and silently break T4.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_lock_company_type() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    uses INTEGER;
BEGIN
    IF NEW.company_type = OLD.company_type THEN
        RETURN NEW;
    END IF;

    SELECT CASE OLD.company_type
               WHEN 'agent'     THEN (SELECT count(*) FROM port_call WHERE agent_id     = OLD.company_id)
               WHEN 'shipper'   THEN (SELECT count(*) FROM shipment  WHERE shipper_id   = OLD.company_id)
               WHEN 'consignee' THEN (SELECT count(*) FROM shipment  WHERE consignee_id = OLD.company_id)
           END
      INTO uses;

    IF uses > 0 THEN
        RAISE EXCEPTION 'Company % cannot change from % to %: it is used as % in % record(s)',
                        OLD.company_id, OLD.company_type, NEW.company_type,
                        OLD.company_type, uses
              USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS lock_company_type ON company;
CREATE TRIGGER lock_company_type
    BEFORE UPDATE OF company_type
    ON company
    FOR EACH ROW
    EXECUTE FUNCTION trg_lock_company_type();
