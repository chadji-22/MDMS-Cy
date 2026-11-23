# The three most important indexes

*Spec: project.pdf §IV p.12 — "declare the three most important cases and explain (in the documentation) exactly which indexes you chose, why you chose them and how you implemented them"; also "at least one case where a suitable index … lowers the execution cost". Code: `sql/indexes.sql` (IX1–IX3). Measurements: `evidence/C2`, `evidence/C3`.*

SQL Server already gives every primary key a clustered index and every UNIQUE constraint a unique index (`create.sql`). For `METER_READING`, the table that grows fastest (one row per meter, OBIS code and 15-minute slot), those are:

- `PK_METER_READING` on `reading_id`, the clustered key, in arrival order;
- `UQ_METER_READING_slot` on `(meter_id, obis_code, reading_timestamp)`.

These two serve "one meter over time" well. They serve badly the two other ways the system reads the data: "every meter at one time", and "only what is not final yet". The foreign keys of `PREMISE` towards suppliers and aggregators have no index at all, because SQL Server does not index foreign keys on its own. The three indexes below fill exactly these gaps.

---

## IX1 — `IX_METER_READING_obis_slot`: every meter at one time

| | |
|---|---|
| **Which** | `METER_READING (obis_code, reading_timestamp) INCLUDE (meter_id, delta_value, status)`; non-clustered, covering, no filter. |
| **Why** | Three functions read *all meters at one slot or over a few hours* for OBIS 1.8.0 / 2.8.0: the current state of the geofence tree (§4.2 p.10, `sp_RefreshTransformerState`), the immutable transformer aggregates (§4.2 p.10, `sp_BuildTransformerAggregates`) and the Intraday market data (§5.2 p.11, `sp_GetIntradayProvisional`). With 400,000 meters (§I p.1), these are the heaviest readings queries of the system. |
| **How** | The key starts with the two columns in the WHERE clause (OBIS code by equality, then the time range). The engine therefore jumps straight to "1.8.0 between t1 and t2". The INCLUDE columns contain everything else the queries need, so there is no lookup back to the table. |

**How we know it helps** (worked example, `evidence/C3`, actual execution plans on 16,127 readings). We ran the Intraday query (every meter over 6 hours) with and without the index:

| | Without IX1 | With IX1 |
|---|---|---|
| Operator on `METER_READING` | **Clustered Index Scan** | **Index Seek** on IX1 |
| Rows read to answer 288 rows | 16,127 (the whole table) | 288 |
| Logical reads | 391 | **7** (÷ 56) |
| Estimated plan cost | 0.427 | **0.078** (÷ 5.5) |

For the tree-refresh query (every meter at one slot), the plan without IX1 seeks the unique key once per meter (25 seeks) and then looks up each row: 149 logical reads, cost 0.173. With IX1 it is one covering seek: 28 logical reads, cost 0.032.

The scan grows with the size of the table, while the seek grows only with the size of the answer.

## IX2 — `IX_METER_READING_not_final`: only what VEE still has to process

| | |
|---|---|
| **Which** | `METER_READING (meter_id, reading_timestamp) INCLUDE (obis_code, value, delta_value, status) WHERE is_final = 0`; a **filtered** non-clustered index. |
| **Why** | Validation, estimation and editing (VEE, §3.2 pp. 8–9) and finalization (`sp_RunVEE`, `sp_FinalizeReadings`, the suspect list) work only on readings that are **not final yet**. After VEE the readings become immutable, and the table keeps them for 3 years (§1.4 p.6). VEE should not have to step over years of final rows to find the last day's raw ones. |
| **How** | The filter `WHERE is_final = 0` keeps in the index only the rows that are still open. When `sp_FinalizeReadings` sets `is_final = 1`, the row leaves the index. The index therefore stays the size of "today's raw data", however large the table becomes. The key (meter, time) matches how VEE walks a meter's series to find gaps and spikes. |

**How we know it helps.** On the C1 data set after the pipeline, the index holds **12 rows in 3 pages**, while the table has 16,127 rows in 391 pages (`sys.partitions`, 22/11/2026). A VEE run touches only that small structure. A normal index on the same key would hold all 16,127 rows and keep growing for three years. We did not time VEE with and without IX2. The benefit is shown by the index size, not by a timing.

## IX3 — `IX_PREMISE_supplier` and `IX_PREMISE_aggregator`: "all the premises of my organization"

| | |
|---|---|
| **Which** | `PREMISE (supplier_org_id) INCLUDE (prosumer_scheme)` and `PREMISE (aggregator_org_id) INCLUDE (prosumer_scheme)`; two non-clustered indexes on the foreign keys. |
| **Why** | Every request of a supplier or aggregator starts by finding "the premises (and so the meters) of my organization" (§5.1 p.10): portfolio, Day-Ahead, Intraday and the supplier's bill list. So does the monthly bill run per supplier (§1.3 p.6). Without an index, each of those requests reads the whole `PREMISE` table, which has one row per premise (≈ 400,000). |
| **How** | One index per foreign key, because a query filters on either the supplier or the aggregator, never both. `prosumer_scheme` is included because the portfolio counts prosumers by scheme without reading the table. |

**How we know it helps.** On the course database `PREMISE` has only 24 rows (2 pages), so no difference can be measured; this choice rests on the access pattern above. In the 10,000-request run (`evidence/C2`) the procedures that start from the organization's premises stayed far below the limit: `sp_GetDayAheadAggregates` p95 37.31 ms and `sp_ListSupplierBills` p95 10.14 ms, against a target of 2,000 ms.

---

## The performance target as a whole

`perf.sql` PART 1 ran **10,000 OLTP requests**. The mix covered readings, totals, job lists, packet ingestion, tree state, Day-Ahead, login, bill list, payment and service request. **0 calls failed**, and **95 % finished within 22.71 ms**; the slowest of all took 199 ms. The requirement is < 2 s for 95 % of requests (§IV p.12). Details per procedure: `evidence/C2/perf_results.md`.

**Limits.**

- The measurements were made on the course database, whose size cap (27 MB) allows a data set of thousands of readings, as p.12 asks, but not millions.
- IX2 and IX3 are justified by size and access pattern, not by a timed before/after; only IX1 has a measured before/after.
