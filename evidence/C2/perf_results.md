# C2 — OLTP performance: 10,000 requests, p95 < 2 s

**Requirement** [project.pdf §IV p.12]: response time under 2 seconds for at least 95 % of the usual OLTP queries,
over 10,000 requests on our machine.

**Result: MET.** 10,000 calls, **0 failed**, overall **p95 = 22.71 ms** (88× under the 2,000 ms limit), maximum 199.12 ms.
Every procedure meets the target on its own.

## Setup
| Item | Value |
|---|---|
| Date | 22/11/2026 |
| Server | `mssql.cs.ucy.ac.cy`, SQL Server 2022 (16.0.4295.3), database `ichara09`, compatibility 160, READ_COMMITTED_SNAPSHOT on |
| Data | C1 set: 16,127 `METER_READING`, 5,929 `AGGREGATE`, 25 meters, 2026-10-27 … 2026-11-22 (see `evidence/C1/row_counts.md`) |
| Script | `perf.sql` PART 1 (settings `calls = 10000`, `run_index_test = 0`; PART 3 is C3) |
| Client | go-sqlcmd 1.10 over the UCY VPN; timings are taken **inside** the server (`SYSDATETIME()` around each call), so network time is not included |
| Output | `perf_part1_10000_output.txt` |

Write calls run inside a transaction that is rolled back (timed with their writes, nothing stays). Checked after the run: no `perf.sql`
work orders, no 0.01 payments, no extra login rows.

## Results (ms)
| Procedure | Use case | Calls | Mean | p50 | **p95** | Max | Failed |
|---|---|---:|---:|---:|---:|---:|---:|
| `sp_GetPremiseReadings` (1 day) | premise readings §1.2, **called as DSO** ¹ | 3,000 | 8.02 | 4.24 | **18.00** | 199.12 | 0 |
| `sp_GetPremiseAggregates` (whole range, DAY) | premise totals §1.2, **called as DSO** ¹ | 1,000 | 3.84 | 4.19 | **5.41** | 9.64 | 0 |
| `sp_ListMyWorkOrders` | technician jobs §2.2 | 1,000 | 3.60 | 3.33 | **4.81** | 50.55 | 0 |
| `sp_IngestTelemetryPacket` | packet ingestion §3.1 | 1,000 | 11.49 | 11.06 | **13.96** | 84.96 | 0 |
| `sp_GetTransformerState` | TSO tree state §4.2 | 1,000 | 6.39 | 6.31 | **8.48** | 13.26 | 0 |
| `sp_Login` | login, Κοινές αρχές p.5 | 1,000 | 4.49 | 4.21 | **6.34** | 12.20 | 0 |
| `sp_GetDayAheadAggregates` (7 days) | market §5.2 | 500 | 28.22 | 27.61 | **37.31** | 53.88 | 0 |
| `sp_ListSupplierBills` | bills §1.3 | 500 | 7.52 | 7.33 | **10.14** | 55.49 | 0 |
| `sp_PayBill` | payment §1.3 | 500 | 8.33 | 8.08 | **10.22** | 75.21 | 0 |
| `sp_SubmitServiceRequest` | request §1.3 | 500 | 6.84 | 6.36 | **9.03** | 11.36 | 0 |
| **ALL** | | **10,000** | **7.93** | **5.49** | **22.71** | **199.12** | **0** |

Batch job, timed separately (not OLTP): `sp_RefreshTransformerState` on the whole tree, 193.84 ms.

## Notes
- ¹ `perf.sql` calls the two premise procedures with the DSO as actor, so any premise can be read. The consumer's
  extra step, the past-data purchase check (`fn_CanViewReadings`), is therefore **not** in these timings. The consumer path
  is exercised functionally by `sources/tests/consumer_pages.sh` (current month free, past month refused / bought).
- **Two earlier runs were not counted.** The 300-call trial and the first 10,000 run had failed calls (wrong parameter
  pools: aggregator users for the supplier bill list, and bills / premises of the forgotten user). A failed call is fast
  and makes p95 look better, so `perf.sql` now lists every failure and the pools only use active users of the right role.
  The run above has 0 failures.
- The consumer's own bill list (`sp_GetMyBillsAndPayments`) returns two result sets of different shapes, which
  `INSERT … EXEC` cannot catch, so the bill list is timed through `sp_ListSupplierBills` (same view `view_BILL_BALANCE`).
- **Limit of this evidence:** the data set is the one the course database can hold (27 MB cap): thousands of readings,
  as p.12 asks, not millions. The slowest procedure is `sp_GetDayAheadAggregates`; with a much larger set it is the
  first to watch (its plan was not analysed, since it is 50× under the limit).
- No procedure missed the target, so no fix was needed.
