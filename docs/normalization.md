# Normalization (up to 3NF / BCNF)

Marine Vessel Traffic & Port Logistics Tracking System, PostgreSQL schema (10 tables).

This document lists the functional dependencies (FDs) of every relation, checks each normal form, and records the two places where a non-key attribute depends on another non-key attribute. Both are handled on purpose, with the database guaranteeing consistency:

- **CONTAINER.size** depends on `iso_type`, so it is a **generated column** computed by PostgreSQL (section 4).
- **PORT_CALL.call_status** depends on `ata` / `atb` / `atd`, so it is kept in sync by a **trigger** (section 5).

Notation: `A → B` means "the value of A determines the value of B". Keys are **bold**.

---

## 1. Definitions used

| Normal form | Condition |
|---|---|
| **1NF** | Every attribute holds one atomic value; no repeating groups; each row is identified by a key. |
| **2NF** | 1NF, and no non-key attribute depends on only *part* of a composite key (no partial dependency). |
| **3NF** | 2NF, and no non-key attribute depends on another non-key attribute (no transitive dependency). |
| **BCNF** | For every non-trivial FD `X → Y`, X is a superkey. |

2NF only matters for relations with a composite key. Here those are SHIPMENT_CONTAINER and INSPECTION.

---

## 2. First normal form

All 10 relations are in 1NF:

- **Atomic values.** Every column holds one value of a single type. Codes that could have been packed into one string are kept separate (`iso_type` vs `container_no`; `hs_code` vs `cargo_description`).
- **No repeating groups.** A shipment can travel in many containers and a container can carry many shipments. Instead of a list column such as `containers = 'MSCU1234565, MSCU7654321'`, the M:N relationship COVERS is its own relation, SHIPMENT_CONTAINER, with one row per (shipment, container) pair.
- **Multiple inspections** per customs filing are rows in INSPECTION (a weak entity), not columns like `inspection1_date`, `inspection2_date`.
- **Every relation has a primary key**, enforced with `PRIMARY KEY`.

---

## 3. Functional dependencies and normal form, per relation

### 3.1 VESSEL (**imo_number**, mmsi, vessel_name, flag, vessel_type, loa, draft)

```
imo_number → mmsi, vessel_name, flag, vessel_type, loa, draft
mmsi       → imo_number, vessel_name, flag, vessel_type, loa, draft
```

Candidate keys: `imo_number` (primary) and `mmsi` (UNIQUE NOT NULL). Both determinants are candidate keys, so the relation is in **BCNF**.

### 3.2 COMPANY (**company_id**, company_name, iec_code, company_type)

```
company_id → company_name, iec_code, company_type
iec_code   → company_id, company_name, company_type      (when not NULL)
```

`iec_code` is UNIQUE (a nullable alternate key; foreign companies and agents have none). **BCNF.**

### 3.3 BERTH (**berth_number**, max_loa, max_draft, cargo_type)

```
berth_number → max_loa, max_draft, cargo_type
```

**BCNF.** (`cargo_type` uses the domain `cargo_category`, shared with `vessel.vessel_type`; it is a value, not a determinant.)

### 3.4 PORT_CALL (**call_id**, imo_number, agent_id, berth_number, berth_start, berth_end, eta, predicted_eta, ata, atb, atd, call_status)

```
call_id        → every other attribute
ata, atb, atd  → call_status                              (transitive)
```

`call_status` is a function of the actual-time columns: `atd` set → Departed, else `atb` set → Berthed, else `ata` set → Waiting, else Expected. This is a transitive dependency, so PORT_CALL is **not strictly 3NF**. It is kept **on purpose**; see section 5.

Everything else depends only on `call_id`. Note what is **not** stored here:

- No vessel or berth attributes (name, LOA, max draft): they are reached through the foreign keys `imo_number` and `berth_number`. Copying them would create update anomalies.
- No `waiting_time`. It is derived (`atb - ata`) and computed in the view `v_waiting_time`, so it can never disagree with `ata` and `atb`.

### 3.5 SHIPPING_MANIFEST (**manifest_no**, call_id, manifest_type, filing_date)

```
manifest_no              → call_id, manifest_type, filing_date
(call_id, manifest_type) → manifest_no, filing_date
```

`(call_id, manifest_type)` is UNIQUE (one import and one export manifest per call), so it is a second candidate key. Both determinants are keys: **BCNF.**

### 3.6 SHIPMENT (**shipment_no**, manifest_no, shipper_id, consignee_id, cargo_description, origin_port, hs_code, cargo_quantity, gross_weight)

```
shipment_no → every other attribute
```

Checked for hidden dependencies:

- `hs_code → cargo_description`? **No.** The description is the free text on each Bill of Lading; two shipments with the same HS code describe their goods differently.
- `origin_port` and `hs_code` are standard codes (UN/LOCODE, ITC-HS) stored as values; no other column depends on them.

**BCNF.**

### 3.7 CONTAINER (**container_no**, iso_type, size)

```
container_no → iso_type, size
iso_type     → size                                       (transitive)
```

`size` is fixed by the first character of the ISO 6346 code (2 = 20 ft, 4 = 40 ft, L = 45 ft). It is a **generated column**, so it is **not strictly 3NF** but cannot become inconsistent; see section 4.

### 3.8 SHIPMENT_CONTAINER (**shipment_no, container_no**, seal_no, container_status)

```
(shipment_no, container_no) → seal_no, container_status
```

2NF check (composite key): does either attribute depend on only part of the key?

- `container_status` is per shipment-in-container (one shipment in a shared container can be released while another is held), so it needs the whole key.
- `seal_no`: a seal belongs to a container **for one voyage**. `container_no` alone does not determine it, because the same container gets a new seal on every trip. So there is no partial dependency.

**BCNF.** (Section 6 covers one redundancy that remains for shared containers.)

### 3.9 CUSTOMS_FILING (**filing_no**, shipment_no, filing_type, filing_date, declared_value, duty_amount, filing_status, risk_score)

```
filing_no   → every other attribute
shipment_no → every other attribute                       (UNIQUE: 1:1 with SHIPMENT)
```

`duty_amount` is the amount *assessed* by customs, not a fixed formula of `declared_value` and `hs_code` (exemptions and penalties apply), so it is not a derived attribute. **BCNF.**

### 3.10 INSPECTION (**filing_no, inspection_no**, inspection_date, officer_name, result, remarks)

```
(filing_no, inspection_no) → inspection_date, officer_name, result, remarks
```

Weak entity: `inspection_no` (1, 2, 3, ...) is only unique within a filing. No attribute depends on `filing_no` alone, so it is in 2NF. **BCNF.**

---

## 4. CONTAINER.size: a generated column

### The problem

A container's length is determined by its ISO 6346 type code, not by the container itself:

```
container_no → iso_type → size        (2 = 20 ft, 4 = 40 ft, L = 45 ft)
```

**size depends on the key only through a non-key attribute (a transitive dependency).** If `size` were an ordinary column, the same fact ("22G1 is 20 ft") would be typed in again on every 22G1 container, and nothing would stop one row from saying `22G1, 40`. That is an **update anomaly**.

### The fix used: let PostgreSQL compute it

```sql
size SMALLINT GENERATED ALWAYS AS (
    CASE left(iso_type, 1) WHEN '2' THEN 20 WHEN '4' THEN 40 WHEN 'L' THEN 45 END
) STORED
```

- **No one can set `size` by hand.** INSERT and UPDATE are rejected (`cannot insert a non-DEFAULT value into column "size"`). The value is always computed from `iso_type`, so it can never contradict it.
- **Changing `iso_type` recomputes `size`** automatically.
- **The rule lives in the schema, not in the data.** The mapping "first character → length" is written once, in the column definition. So there are no insertion or deletion anomalies either: a new code can be used straight away, and deleting containers loses nothing.
- `STORED` means the value is computed on write and saved, so it can be read and filtered like a normal column.

Formally the relation still contains the FD `iso_type → size`, so CONTAINER is **not strictly 3NF**. In practice the redundancy is harmless, because the stored value is computed by the database and cannot be wrong.

`tests/test_container_size.sql` checks all of this.

**Issue found while building it:** the first version declared `size NOT NULL`. A bad code such as `9XG1` was then rejected with the confusing message *"null value in column size"* (the CASE returned NULL), because PostgreSQL checks NOT NULL **before** CHECK constraints. NOT NULL was removed: the CHECK on `iso_type` already guarantees the first character is 2, 4 or L, so `size` is never NULL for a valid row, and the user now gets the real error ("invalid iso_type").

### Alternative (to explore later): a lookup table

The textbook 3NF fix is to decompose on `iso_type → size`:

```
ISO_TYPE  (iso_type PK, size, description)
CONTAINER (container_no PK, iso_type FK → ISO_TYPE)
```

This is lossless (the join attribute `iso_type` is the key of ISO_TYPE) and dependency preserving, makes both relations BCNF, and can store extra information per type (a `description`). It costs an extra table and an extra entity in the ER diagram. The generated column was chosen for now because it keeps the schema at 10 tables while still making inconsistent sizes impossible. The lookup-table version is saved in `git stash` ("Option 1: iso_type lookup table").

| | Generated column (used) | Lookup table (alternative) |
|---|---|---|
| Strictly 3NF | No | Yes |
| Wrong size possible | No | No |
| Extra table / ER entity | No | Yes |
| Can store a description per type | No | Yes |
| Changing the rule | `ALTER TABLE` | `UPDATE` a row |

---

## 5. Controlled redundancy: PORT_CALL.call_status

`call_status` depends on `ata`, `atb`, `atd` (section 3.4), so strictly it should not be stored. It is kept on purpose:

- **Why store it:** the dashboard and the NL assistant constantly filter port calls by status (`WHERE call_status = 'Waiting'`). A stored column is simple to query and can be indexed. Recomputing it with a CASE expression in every query would spread the rule across the application.
- **Why it cannot go wrong:** the trigger `set_call_status` sets the column from `ata` / `atb` / `atd` on every INSERT and UPDATE, and **rejects** a manual status that contradicts them. The stored value is therefore always equal to the derived one, which removes the update anomaly that normally makes denormalization risky.

Why a trigger here but a generated column for `size`? A generated column can only use columns of its own row and immutable expressions. That would actually work for `call_status` too, but the trigger was built first (Step 3) and also gives a clear error when someone tries to set the status by hand. Either way, the principle is the same: **denormalization is acceptable when the database itself guarantees consistency.**

---

## 6. Other design points checked

- **Derived attributes are not stored.** `waiting_time` (`atb - ata`), `berthing_delay` (`atb - berth_start`) and ETA errors are computed in `v_waiting_time`. `days_pending` is computed in `v_pending_customs`.
- **No duplicated entity data.** Names of vessels, agents and consignees are stored once (VESSEL, COMPANY) and reached through foreign keys and joins.
- **Company roles.** One COMPANY table holds agents, shippers and consignees (`company_type`). The foreign keys say *which* company; triggers T4 and T5 make sure it has the right type for the role it plays.
- **Remaining redundancy for shared containers (LCL).** When several shipments share one container on the same voyage, each SHIPMENT_CONTAINER row repeats that container's `seal_no`. Formally this is not a 2NF/3NF violation (the determinant would be "container + voyage", which is not an attribute of the relation). Removing it would need a CONTAINER_VOYAGE relation, which is not worth the extra complexity at this scale. Most containers in the data carry a single shipment (FCL).

---

## 7. Summary

| # | Relation | Highest normal form | Note |
|---|---|---|---|
| 1 | VESSEL | BCNF | two candidate keys (IMO, MMSI) |
| 2 | COMPANY | BCNF | |
| 3 | BERTH | BCNF | |
| 4 | PORT_CALL | 2NF (deliberate) | `call_status` derived from `ata`/`atb`/`atd`, kept in sync by a trigger |
| 5 | SHIPPING_MANIFEST | BCNF | two candidate keys |
| 6 | SHIPMENT | BCNF | |
| 7 | CONTAINER | 2NF (deliberate) | `size` generated from `iso_type`, cannot be set by hand |
| 8 | SHIPMENT_CONTAINER | BCNF | M:N junction |
| 9 | CUSTOMS_FILING | BCNF | 1:1 with SHIPMENT |
| 10 | INSPECTION | BCNF | weak entity |

Eight of ten relations are in BCNF. The other two each keep one derived column by design, and in both cases the database (a generated column, a trigger) guarantees the value is always correct.
