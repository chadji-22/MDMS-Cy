# C3 — One index that lowers the cost: `IX_METER_READING_obis_slot` before / after

**Requirement** [project.pdf §IV p.12]: document at least one case where a suitable index or a better query lowers the
execution cost.

**Index (IX1 of `indexes.sql`):** `METER_READING (obis_code, reading_timestamp) INCLUDE (meter_id, delta_value, status)`,
non-clustered, covering.

## How it was measured
- 22/11/2026, `ichara09` on SQL Server 2022, C1 data set (16,127 readings, 25 meters; `evidence/C1`).
- `c3_queries.sql` = the two queries of `perf.sql` PART 3, each run once to warm the cache and once measured with
  `SET STATISTICS IO, TIME, XML ON` (XML = the **actual** execution plan). Run with the index, then the index was dropped,
  run again, and the index created again (checked present afterwards).
- Plans: `queryA_with_index.sqlplan`, `queryA_without_index.sqlplan`, `queryB_with_index.sqlplan`,
  `queryB_without_index.sqlplan` (open in SSMS for the graphical plan). Raw statistics: `stats_with_index.txt`,
  `stats_without_index.txt`. Operators below were read from the plan XML.

## Worked example — Query B: every meter over 6 hours (core of `sp_GetIntradayProvisional`, §5.2 p.11)
| | Without the index | With the index | Change |
|---|---|---|---|
| Operator on METER_READING | **Clustered Index Scan** (`PK_METER_READING`) | **Index Seek** (`IX_METER_READING_obis_slot`) | Scan → Seek |
| Rows read to return 288 rows | 16,127 (the whole table) | 288 (exactly the needed ones) | ÷ 56 |
| Logical reads, METER_READING | 391 | 7 | ÷ 56 |
| Estimated plan cost | 0.427 | 0.078 | ÷ 5.5 |
| CPU / elapsed (ms) | 78 / 106 | 16 / 77 | |

Why: without the index the only way to find "OBIS 1.8.0 / 2.8.0 between two times" is to read every row, because the
clustered key is `reading_id` and the unique key starts with `meter_id`. The index starts with exactly the two columns of the
WHERE clause, so the engine jumps to the range; the INCLUDE columns answer the query without going back to the table.

## Second case — Query A: every meter at one slot (tree refresh, Algorithm E, §4.2 p.10)
| | Without the index | With the index |
|---|---|---|
| Plan | 25 × Index Seek on `UQ_METER_READING_slot` (once per meter) + 12 key lookups on `PK_METER_READING` | 1 × Index Seek on `IX_METER_READING_obis_slot` (covering, no lookup) |
| Logical reads (METER_READING + METER) | 147 + 2 = 149 | 4 + 24 = 28 |
| Estimated plan cost | 0.173 | 0.032 (÷ 5.4) |

Here the optimizer avoids a full scan even without IX1 (it walks the meters and seeks the unique key of each one), but
needs one seek per meter plus lookups; with IX1 it is one seek. With 400,000 meters (§I p.1) the first plan grows with the
number of meters, the second with the number of rows of that one slot.

## Honest limits
- Elapsed times of a few ms on a shared server are noisy; logical reads and plan cost are the reliable measure.
- The table holds 16 thousand rows (course DB cap); on a larger table the scan in Query B grows linearly while the seek
  stays at the size of the answer.
- TODO (Ioannis, 2 min): open the four `.sqlplan` files in SSMS 22 and save a screenshot of each graphical plan for the
  document (headless rendering of SSMS plans is not available here).
