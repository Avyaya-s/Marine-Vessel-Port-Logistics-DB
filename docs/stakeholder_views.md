# One Database, Many Stakeholders

The point of the project in one sentence: **several stakeholders with different goals work on one shared database, each through its own view of it, so every fact is stored once and everybody always sees the same truth.**

---

## 1. The stakeholders

| Stakeholder | Goal | Questions they ask | Home screen |
|---|---|---|---|
| **Port Operations** (berth planner) | keep berths busy, keep ships from waiting | Who is arriving? Who is waiting? Where can each ship go? | **Berth Planning**: queue + berth Gantt + *Allocate berth* |
| **Customs Officer** | clear legitimate cargo fast, catch fraud | What is risky? What is waiting on me? | **Customs Workbench**: risk-sorted inbox + filing detail + *Record inspection* / *Clear* |
| **Shipping Agent** | track its own ships and paperwork for its clients | Where is my ship? Has it got a berth? Is my cargo cleared? | **My Vessels**: progress tracker per ship, own calls only |
| **Harbour Master** (admin) | overall port performance | How is the port doing? | **Port Overview**: KPIs, berth schedule, waiting times, risk |

## 2. The same facts, seen differently

A ship's **actual arrival time** (`port_call.ata`) is stored **once**. It appears:

| Where | As what |
|---|---|
| Operations' queue (`v_berth_queue`) | its *ready time*: when the ship can berth, used for ordering |
| The agent's tracker (`v_agent_calls`) | the second step of the progress bar: "Arrived 16 Oct, 07:10" |
| The admin dashboard (`v_waiting_time`) | the start of its anchorage wait |
| `allocate_berth()` | the earliest time a berth can be booked |

When the geofence (or an operator) records the arrival, the `set_call_status` trigger moves the call to *Waiting*, and **all four stakeholders see it immediately**. Nobody re-types it, nothing is copied, so nothing can disagree. This is exactly what a DBMS gives over separate spreadsheets per department: **no redundancy, no inconsistency, one source of truth**.

## 3. Three-schema architecture

The design follows the ANSI/SPARC three-schema architecture taught in DBMS courses:

```
 External level      v_berth_queue   v_customs_workload   v_agent_calls   v_waiting_time ...
 (one per user)      (operations)    (customs)            (agents)        (admin)
                           \               |                   /
 Conceptual level     vessel, company, berth, port_call, shipping_manifest, shipment,
 (one schema)         container, shipment_container, customs_filing, inspection
                           |
 Internal level       PostgreSQL storage, indexes (port_call(berth_number, berth_start), ...)
```

- **Logical data independence:** a stakeholder's screen depends on its view, not directly on the tables. A table can be changed (for example splitting CONTAINER into CONTAINER + ISO_TYPE) and only the view definitions need updating, not the screens.
- **Physical data independence:** adding an index changes speed, not results; no view or screen changes.

## 4. Stakeholder views (`database/views.sql`)

| View | Stakeholder | What it computes |
|---|---|---|
| `v_berth_queue` | Operations | calls not yet berthed, ordered by ready time (`ata` → `predicted_eta` → `eta`, the same rule as `allocate_berth`), queue state (*Needs berth / Waiting for berth / Booked*), and `suitable_berths`: how many berths can physically take the ship (0 = escalate) |
| `v_customs_workload` | Customs | one row of counts: pending by status, high risk, unscored, awaiting inspection, value held at port |
| `v_agent_calls` | Agents | each call's progress (eta/ata/atb/atd), berth window, import/export manifests, shipments on board, customs cleared vs pending; filtered to the agent's company by the API |
| `v_pending_customs` | Customs | the risk-sorted work queue (from Step 4) |
| `v_waiting_time`, `v_berth_occupancy` | Admin / all | port-wide performance (from Step 4) |

## 5. Each stakeholder's actions are transactions

| Action | Who | Database object | What it guarantees |
|---|---|---|---|
| Allocate berth | Operations | `allocate_berth()` | earliest free berth that fits; overlap + fit triggers still check it |
| Record inspection | Customs | `record_inspection()` (new) | numbers the inspection (weak entity: next `inspection_no` per filing), inserts it and updates the filing status, in one transaction with the filing row locked |
| Clear filing | Customs | `clear_customs()` | filing Cleared + duty + containers Released, all or nothing |
| Upload Bill of Lading | Agent / Operations | `documents.confirm` | companies + shipment + containers + links in one transaction; agents only into their own manifests |

`record_inspection()` maps results to statuses: *Discrepancy → Held*, *Pending → Under Review*, *Clear → Under Review* (the officer then clears it). The lock matters: two officers recording at the same moment would otherwise both compute the same next `inspection_no`.

## 6. Tests

`database/tests/test_role_views.sql`: 14 tests (queue order and states, ready-time rule, suitable-berth counts including a ship no berth fits, agent call progress and cargo counts, workload counts, inspection numbering and status changes, and the error cases). The full suite is **104 tests**.
