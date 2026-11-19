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


-- =====================================================================
-- Stakeholder views (external schemas)
--
-- One conceptual schema (the 10 tables), one external view per
-- stakeholder.  Each view answers that stakeholder's questions from the
-- SAME rows: a ship's arrival time is stored once in port_call and shows
-- up as a planning input for operations, as progress for the agent and as
-- context for customs.  Nothing is copied, so nothing can disagree.
-- (ANSI/SPARC three-schema architecture: external / conceptual / internal.)
-- =====================================================================

-- ---------------------------------------------------------------------
-- v_berth_queue : PORT OPERATIONS.  "Which ships need my attention?"
--
-- Every call that has not berthed yet (Expected or Waiting), in the order
-- the ships will be ready, with:
--   queue_state      Needs berth | Waiting for berth | Booked
--   ready_time       ata, else ML predicted_eta, else agent eta
--                    (the same rule allocate_berth() uses)
--   suitable_berths  how many berths could physically take the ship:
--                    0 means no berth in the port fits it (escalate!)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_berth_queue AS
SELECT pc.call_id,
       v.vessel_name,
       v.vessel_type,
       v.loa,
       v.draft,
       c.company_name                              AS agent,
       pc.call_status,
       pc.eta,
       pc.predicted_eta,
       pc.ata,
       COALESCE(pc.ata, pc.predicted_eta, pc.eta)  AS ready_time,
       pc.berth_number,
       pc.berth_start,
       CASE
           WHEN pc.berth_number IS NULL   THEN 'Needs berth'
           WHEN pc.call_status = 'Waiting' THEN 'Waiting for berth'
           ELSE 'Booked'
       END                                         AS queue_state,
       (SELECT count(*)
        FROM berth b
        WHERE b.cargo_type = v.vessel_type
          AND b.max_loa   >= v.loa
          AND b.max_draft >= v.draft)              AS suitable_berths
FROM port_call pc
JOIN vessel  v ON v.imo_number = pc.imo_number
JOIN company c ON c.company_id = pc.agent_id
WHERE pc.call_status IN ('Expected', 'Waiting')
ORDER BY ready_time;

-- ---------------------------------------------------------------------
-- v_agent_calls : SHIPPING AGENT.  "Where is my ship, and my paperwork?"
--
-- One row per port call (the API filters it to the agent's own company),
-- with the call's progress, its import / export manifests and the
-- customs status of the cargo on board.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_agent_calls AS
SELECT pc.call_id,
       pc.agent_id,
       v.vessel_name,
       v.imo_number,
       v.vessel_type,
       v.flag,
       pc.call_status,
       pc.eta,
       pc.predicted_eta,
       pc.ata,
       pc.atb,
       pc.atd,
       pc.berth_number,
       pc.berth_start,
       pc.berth_end,
       igm.manifest_no                      AS import_manifest,
       egm.manifest_no                      AS export_manifest,
       COALESCE(cargo.shipments, 0)         AS shipments,
       COALESCE(cargo.customs_cleared, 0)   AS customs_cleared,
       COALESCE(cargo.customs_pending, 0)   AS customs_pending
FROM port_call pc
JOIN vessel v ON v.imo_number = pc.imo_number
LEFT JOIN shipping_manifest igm ON igm.call_id = pc.call_id AND igm.manifest_type = 'IGM'
LEFT JOIN shipping_manifest egm ON egm.call_id = pc.call_id AND egm.manifest_type = 'EGM'
LEFT JOIN LATERAL (
    SELECT count(*)                                              AS shipments,
           count(*) FILTER (WHERE cf.filing_status = 'Cleared')  AS customs_cleared,
           count(*) FILTER (WHERE cf.filing_status <> 'Cleared') AS customs_pending
    FROM shipping_manifest m
    JOIN shipment s            ON s.manifest_no = m.manifest_no
    LEFT JOIN customs_filing cf ON cf.shipment_no = s.shipment_no
    WHERE m.call_id = pc.call_id
) cargo ON TRUE;

-- ---------------------------------------------------------------------
-- v_customs_workload : CUSTOMS OFFICER.  "How much is waiting on me?"
--
-- A single row of counts for the officer's home screen.
-- awaiting_inspection = filings whose latest inspection is still Pending.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_customs_workload AS
SELECT count(*) FILTER (WHERE cf.filing_status <> 'Cleared')                       AS pending_total,
       count(*) FILTER (WHERE cf.filing_status = 'Filed')                          AS filed,
       count(*) FILTER (WHERE cf.filing_status = 'Under Review')                   AS under_review,
       count(*) FILTER (WHERE cf.filing_status = 'Held')                           AS held,
       count(*) FILTER (WHERE cf.filing_status <> 'Cleared' AND cf.risk_score >= 0.7) AS high_risk,
       count(*) FILTER (WHERE cf.filing_status <> 'Cleared' AND cf.risk_score IS NULL) AS unscored,
       count(*) FILTER (WHERE cf.filing_status <> 'Cleared' AND last_insp.result = 'Pending')
                                                                                   AS awaiting_inspection,
       count(*) FILTER (WHERE cf.filing_status = 'Cleared')                        AS cleared_total,
       COALESCE(sum(cf.declared_value) FILTER (WHERE cf.filing_status <> 'Cleared'), 0)
                                                                                   AS pending_value
FROM customs_filing cf
LEFT JOIN LATERAL (
    SELECT i.result FROM inspection i
    WHERE i.filing_no = cf.filing_no
    ORDER BY i.inspection_no DESC
    LIMIT 1
) last_insp ON TRUE;
