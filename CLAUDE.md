# Marine Vessel Traffic & Port Logistics Tracking System

DBMS lab project (RVCE, CSE, course CD252IA). Team of 2:
- **Avyaya S Yekkar (1RV24CS057)**: database side (schema, constraints, triggers, procedure, views, transaction, normalization, synthetic data generator, NLP features).
- **Bhuvan K K (1RV24CS060)**: ML side (AIS replay/simulator, weather job, MongoDB, geofence + ETA write-back, ETA model, customs risk model, frontend).
- Together: FastAPI endpoints, testing, report, demo.

## Department rules (must hold)
- SQL + NoSQL integration is mandatory.
- Innovative component required: we use AIML + NLP.
- **No PHP** for server-side code.
- ER diagram needs at least 5-6 entity types (we have 11).
- **No hardware** (no AIS receivers, sensors, IoT). All data comes from datasets, a simulator, or web APIs.
- Evaluation follows the DBMS lab manual's component list; check it before finalizing DB features.

## Design decisions (settled, do not change without asking)
- **Single port only.** There is no PORT table; the system *is* the port. Loading port is a plain attribute (`origin_port`) on SHIPMENT.
- **One berth per visit.** No BERTH_ALLOCATION table; the berth is a nullable FK in PORT_CALL with `berth_start`, `berth_end`.
- `waiting_time` is a **derived** attribute (`atb - ata`), computed in a view, never stored.
- Port call status values: `Expected` -> `Waiting` -> `Berthed` -> `Departed`.
- **Plan vs fact times (decided 2026-10-18):** `berth_start`/`berth_end` are the *planned* window (set by `allocate_berth`). `ata`/`atb`/`atd` are *actual* times. `call_status` is derived from the facts by a trigger (ata -> Waiting, atb -> Berthed, atd -> Departed). CHECKs compare facts with facts only.
- Names kept simple: SHIP_LOCATION (AIS positions), COMPANY (agents/shippers/consignees), SHIPMENT (one Bill of Lading).

## Stack
- PostgreSQL 16+ (structured, transactional data)
- MongoDB 7+ (time-series collections + 2dsphere index)
- Backend: Python 3.11+, FastAPI, psycopg / SQLAlchemy, PyMongo
- Frontend: React + Vite, Leaflet (map), Chart.js
- ML: scikit-learn, XGBoost, pandas
- NLP: pdfplumber (+ Tesseract OCR), an LLM API (provider not chosen yet; needed only in weeks 7-8)
- Tools: Git/GitHub, pgAdmin 4, MongoDB Compass, Postman

## Relational schema (PostgreSQL, 10 tables)
1. `vessel` (**imo_number** PK, mmsi UNIQUE, vessel_name, flag, vessel_type, loa, draft)
2. `company` (**company_id** PK, company_name, iec_code, company_type: agent/shipper/consignee)
3. `berth` (**berth_number** PK, max_loa, max_draft, cargo_type)
4. `port_call` (**call_id** PK, imo_number FK->vessel NOT NULL, agent_id FK->company NOT NULL, berth_number FK->berth NULL, berth_start, berth_end, eta, predicted_eta, ata, atb, atd, call_status)
5. `shipping_manifest` (**manifest_no** PK, call_id FK->port_call, manifest_type IGM/EGM, filing_date) - max 2 per call (one import, one export)
6. `shipment` (**shipment_no** PK, manifest_no FK, shipper_id FK->company, consignee_id FK->company, cargo_description, origin_port, hs_code, cargo_quantity, gross_weight)
7. `container` (**container_no** PK, iso_type, size) - container_no format: 4 letters + 7 digits
8. `shipment_container` (**shipment_no + container_no** PK, both FKs, seal_no, container_status) - M:N junction (COVERS relationship)
9. `customs_filing` (**filing_no** PK, shipment_no FK UNIQUE (1:1), filing_type Bill of Entry/Shipping Bill, filing_date, declared_value, duty_amount, filing_status, risk_score 0-1)
10. `inspection` (**filing_no + inspection_no** PK, filing_no FK, inspection_date, officer_name, result, remarks) - weak entity

Create tables in the order above (parents before children).

## MongoDB collections
- `ship_location`: time-series (timeField `ts`, metaField `mmsi`); fields mmsi, ts, loc (GeoJSON Point), speed, course, heading, nav_status. 2dsphere index on `loc`. Linked to `vessel` by MMSI.
- `weather_log`: time-series (timeField `ts`, metaField `zone`); fields zone, ts, wind_speed, wave_height, visibility, condition. From Open-Meteo API.

## Database features to implement
- Constraints: PK, FK, UNIQUE, NOT NULL, CHECK (loa > 0, risk_score between 0 and 1, status values).
- Trigger: reject overlapping berth bookings on the same berth.
- Trigger: reject a vessel whose loa/draft exceeds the berth's max_loa/max_draft.
- Trigger: update call_status from ata / atb / atd (Waiting / Berthed / Departed).
- Trigger/CHECK: at most 2 manifests per port call.
- Stored procedure `allocate_berth(call_id)`: earliest free berth matching cargo_type, loa, draft.
- Transaction: customs clearance = filing Cleared + duty recorded + containers Released, all-or-nothing, with a rollback demo.
- Views: v_waiting_time, v_berth_occupancy, v_pending_customs.
- Indexes: port_call(berth_number, berth_start), shipment(hs_code), customs_filing(filing_status).
- Read-only DB user for the NL query assistant.
- Normalization write-up to 3NF.

## SQL-NoSQL integration points
- Arrival detection: `$geoWithin` on ship_location vs anchorage polygon -> set port_call.ata, call_status = 'Waiting'.
- ETA prediction: reads ship_location + weather_log + berth occupancy -> writes port_call.predicted_eta (used by allocate_berth).
- Dashboard map: latest position per MMSI joined with vessel names.

## AIML / NLP features
- ETA prediction (regression: Linear baseline, then Random Forest / XGBoost; metric MAE vs agent ETA).
- Customs risk scoring (classification; precision/recall). Inspection results are training labels.
- Document extraction (PDF -> fields -> user confirms -> insert) + HS code suggestion.
- NL query assistant (question -> SQL; SELECT only; read-only user; show generated SQL).

## Data
- AIS: public archive (NOAA MarineCadastre / Danish Maritime Authority) or own simulator (source not yet decided).
- Weather: Open-Meteo marine + weather API.
- Everything else synthetic (Python + Faker, fixed seed 42), with planted customs risk patterns
  (undervalued vs typical HS value, risky origins/HS chapters, importers with past discrepancies, plus noise; ~5-10% discrepancy rate).

## Planned folder structure
```
database/  schema.sql constraints.sql triggers.sql procedures.sql views.sql mongo_setup.js
data/      generate_data.py ais_replay.py weather_fetch.py
ml/        eta_model.ipynb risk_model.ipynb models/
backend/   main.py db.py routers/ services/
frontend/  src/pages/ (Map, BerthSchedule, PortCalls, Upload, Customs, Ask)
```

## First task
Write `database/schema.sql` from the schema above, load 5-10 sample rows, and get the double-booking trigger working.
