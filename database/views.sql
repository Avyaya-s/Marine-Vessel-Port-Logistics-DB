-- =====================================================================
-- views.sql : read-only views for the dashboard, reports and the NL
-- query assistant (run after schema.sql).
--
-- A view stores a query, not data: every SELECT re-runs it against the
-- current tables, so derived values (waiting time, delays) are never
-- stale and never stored twice.
-- schema.sql drops the tables with CASCADE, which drops these views too,
-- so re-run this file after a rebuild.
-- =====================================================================

-- ---------------------------------------------------------------------
-- v_waiting_time : one row per port call whose ship has arrived.
--
--   waiting_time    = atb - ata          time spent at anchorage (NULL while still waiting)
--   berthing_delay  = atb - berth_start  how late berthing was vs the plan
--   agent_eta_error = ata - eta          how wrong the agent's ETA was
--   model_eta_error = ata - predicted_eta  how wrong the ML ETA was
--
-- The two *_eta_error columns are what the ETA model is judged on
-- (MAE of model vs MAE of agent).  *_hours columns are numeric so the
-- frontend can chart them directly.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_waiting_time AS
SELECT pc.call_id,
       v.vessel_name,
       v.vessel_type,
       pc.berth_number,
       pc.call_status,
       pc.eta,
       pc.predicted_eta,
       pc.ata,
       pc.berth_start,
       pc.atb,
       pc.atb - pc.ata                                          AS waiting_time,
       round(EXTRACT(EPOCH FROM pc.atb - pc.ata) / 3600, 2)     AS waiting_hours,
       pc.atb - pc.berth_start                                  AS berthing_delay,
       pc.ata - pc.eta                                          AS agent_eta_error,
       pc.ata - pc.predicted_eta                                AS model_eta_error
FROM port_call pc
JOIN vessel v ON v.imo_number = pc.imo_number
WHERE pc.ata IS NOT NULL;

-- ---------------------------------------------------------------------
-- v_berth_occupancy : one row per berth.
--
--   occupied_by / occupied_since : the ship actually alongside now
--                                  (atb recorded, atd not yet)
--   next_*                       : the earliest planned booking whose
--                                  ship has not berthed yet
--   upcoming_bookings            : how many such bookings the berth has
--
-- "Occupied" is decided by facts (atb / atd), not by comparing the plan
-- with the clock, so the view is correct even when ships run late.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_berth_occupancy AS
SELECT b.berth_number,
       b.cargo_type,
       b.max_loa,
       b.max_draft,
       cur.call_id          AS occupied_by_call,
       cur.vessel_name      AS occupied_by,
       cur.atb              AS occupied_since,
       nxt.call_id          AS next_call,
       nxt.vessel_name      AS next_vessel,
       nxt.berth_start      AS next_berth_start,
       (SELECT count(*)
        FROM port_call u
        WHERE u.berth_number = b.berth_number
          AND u.atb IS NULL AND u.atd IS NULL)  AS upcoming_bookings
FROM berth b
LEFT JOIN LATERAL (
    SELECT pc.call_id, v.vessel_name, pc.atb
    FROM port_call pc
    JOIN vessel v ON v.imo_number = pc.imo_number
    WHERE pc.berth_number = b.berth_number
      AND pc.atb IS NOT NULL
      AND pc.atd IS NULL
    LIMIT 1
) cur ON TRUE
LEFT JOIN LATERAL (
    SELECT pc.call_id, v.vessel_name, pc.berth_start
    FROM port_call pc
    JOIN vessel v ON v.imo_number = pc.imo_number
    WHERE pc.berth_number = b.berth_number
      AND pc.atb IS NULL
      AND pc.atd IS NULL
      AND pc.berth_start IS NOT NULL
    ORDER BY pc.berth_start
    LIMIT 1
) nxt ON TRUE;

-- ---------------------------------------------------------------------
-- v_pending_customs : one row per customs filing that is not Cleared,
-- riskiest first, so officers work the queue top-down.
--
-- Pulls together the filing, the shipment (cargo, HS code, origin),
-- the consignee, the vessel it arrived on, how many containers it
-- covers, and the latest inspection result.  risk_score comes from the
-- ML risk model; unscored filings sort last.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_pending_customs AS
SELECT cf.filing_no,
       cf.filing_type,
       cf.filing_status,
       cf.filing_date,
       current_date - cf.filing_date     AS days_pending,
       cf.risk_score,
       cf.declared_value,
       s.shipment_no,
       s.cargo_description,
       s.hs_code,
       s.origin_port,
       cons.company_name                 AS consignee,
       v.vessel_name,
       pc.call_id,
       (SELECT count(*)
        FROM shipment_container sc
        WHERE sc.shipment_no = s.shipment_no)   AS containers,
       (SELECT count(*)
        FROM inspection i
        WHERE i.filing_no = cf.filing_no)       AS inspections,
       last_insp.result                  AS last_inspection_result
FROM customs_filing cf
JOIN shipment          s    ON s.shipment_no   = cf.shipment_no
JOIN company           cons ON cons.company_id = s.consignee_id
JOIN shipping_manifest m    ON m.manifest_no   = s.manifest_no
JOIN port_call         pc   ON pc.call_id      = m.call_id
JOIN vessel            v    ON v.imo_number    = pc.imo_number
LEFT JOIN LATERAL (
    SELECT i.result
    FROM inspection i
    WHERE i.filing_no = cf.filing_no
    ORDER BY i.inspection_no DESC
    LIMIT 1
) last_insp ON TRUE
WHERE cf.filing_status <> 'Cleared'
ORDER BY cf.risk_score DESC NULLS LAST, cf.filing_date;
