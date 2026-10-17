-- =====================================================================
-- procedures.sql : stored procedures (run after triggers.sql)
-- =====================================================================

-- ---------------------------------------------------------------------
-- allocate_berth(call_id [, stay])
--
-- Books the earliest free berth that suits the vessel:
--   * berth cargo_type = vessel_type
--   * berth max_loa >= vessel loa, max_draft >= vessel draft
--   * the window [start, start + stay) overlaps no existing booking
--
-- The ship can berth no earlier than its actual arrival (ata), else the
-- ML predicted_eta, else the agent eta.  Candidate start times are that
-- "ready" time plus the end of every booking on the berth after it: the
-- earliest free slot always begins at one of those moments.
-- Ties go to the smallest suitable berth, keeping big berths free for
-- big ships.
--
-- Usage:  CALL allocate_berth(5);                 -- default 24 h stay
--         CALL allocate_berth(5, '12 hours');
-- Returns the chosen berth and window as INOUT parameters.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE allocate_berth(
    p_call_id     INTEGER,
    p_stay        INTERVAL    DEFAULT INTERVAL '24 hours',
    INOUT o_berth VARCHAR     DEFAULT NULL,
    INOUT o_start TIMESTAMPTZ DEFAULT NULL,
    INOUT o_end   TIMESTAMPTZ DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    pc    port_call%ROWTYPE;
    v     vessel%ROWTYPE;
    ready TIMESTAMPTZ;
BEGIN
    IF p_stay <= INTERVAL '0' THEN
        RAISE EXCEPTION 'Stay must be positive, got %', p_stay;
    END IF;

    -- lock the call so two sessions cannot allocate it at the same time
    SELECT * INTO pc FROM port_call WHERE call_id = p_call_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Port call % does not exist', p_call_id;
    END IF;
    IF pc.berth_number IS NOT NULL THEN
        RAISE EXCEPTION 'Port call % already has berth %', p_call_id, pc.berth_number;
    END IF;
    IF pc.call_status = 'Departed' THEN
        RAISE EXCEPTION 'Port call % has already departed', p_call_id;
    END IF;

    SELECT * INTO v FROM vessel WHERE imo_number = pc.imo_number;
    ready := COALESCE(pc.ata, pc.predicted_eta, pc.eta);

    -- lock every candidate berth (in a fixed order, to avoid deadlocks)
    -- so concurrent allocations for the same berths run one at a time
    PERFORM 1 FROM berth b
    WHERE b.cargo_type = v.vessel_type
      AND b.max_loa   >= v.loa
      AND b.max_draft >= v.draft
    ORDER BY b.berth_number
    FOR UPDATE;

    SELECT b.berth_number, slot.start_at
      INTO o_berth, o_start
    FROM berth b
    CROSS JOIN LATERAL (
        SELECT min(c.start_at) AS start_at
        FROM (
            SELECT ready AS start_at
            UNION
            SELECT x.berth_end FROM port_call x
            WHERE x.berth_number = b.berth_number AND x.berth_end > ready
        ) c
        WHERE NOT EXISTS (
            SELECT 1 FROM port_call x
            WHERE x.berth_number = b.berth_number
              AND x.berth_start < c.start_at + p_stay
              AND c.start_at    < COALESCE(x.berth_end, 'infinity')
        )
    ) slot
    WHERE b.cargo_type = v.vessel_type
      AND b.max_loa   >= v.loa
      AND b.max_draft >= v.draft
      AND slot.start_at IS NOT NULL
    ORDER BY slot.start_at, b.max_loa, b.berth_number
    LIMIT 1;

    IF o_berth IS NULL THEN
        RAISE EXCEPTION 'No suitable berth for % (%, LOA % m, draft % m)',
                        v.vessel_name, v.vessel_type, v.loa, v.draft;
    END IF;

    o_end := o_start + p_stay;

    -- the overlap and fit triggers still run on this UPDATE as a safety net
    UPDATE port_call
    SET berth_number = o_berth, berth_start = o_start, berth_end = o_end
    WHERE call_id = p_call_id;
END;
$$;
