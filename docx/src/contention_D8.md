# (a) Contention points and how we handle them

*Second document, part (a). Spec: project.pdf §IV pp. 12–13 (physical design, concurrency), §V p. 14.*

A **contention point** is a place where many sessions need the same page, row or job at the same moment, so they wait for each other. MDMS-Cy has two kinds of load that meet: meters that send packets all day, and people and jobs (VEE, finalization, the grid state, bills) that read and change the same data.

| # | Point | Who competes | Measure |
|-|------------|------------|---------------|
| 1 | Last page of the big tables | many packets inserted together | `OPTIMIZE_FOR_SEQUENTIAL_KEY` |
| 2 | `TRANSFORMER_CURRENT_STATE` | refresh of the tree against every screen of the grid | temporary tables, one short write, application lock |
| 3 | Readers against writers | dashboards against ingestion | `READ_COMMITTED_SNAPSHOT` |
| 4 | Jobs that must not run twice | VEE, bill run, purge, tree refresh | application locks (`sp_getapplock`) |
| 5 | Long jobs over many meters | VEE, finalization, bills, purge | one short transaction per meter or premise |
| 6 | Two people on the same row | payments, officers' decisions | row lock or guarded `UPDATE` |

## 1. Last-page inserts

`METER_READING`, `TELEMETRY_PACKET` and `AUDIT_LOG` are clustered on an `IDENTITY` key. Every new row therefore goes to the **last page** of the table. When many packets arrive together, their sessions queue for that one page.

**Measure.** The three primary keys are set to `OPTIMIZE_FOR_SEQUENTIAL_KEY = ON` (`indexes.sql`). SQL Server then controls how many sessions try for the last page at once, which keeps throughput steady. We kept the `IDENTITY` key because it is narrow (every other index carries it) and does not split pages. Each packet is also one short transaction.

**Checked.** On our database `sys.indexes` shows the option on for `PK_METER_READING`, `PK_TELEMETRY_PACKET` and `PK_AUDIT_LOG`. In the performance run, 1,000 ingestions had a 95th percentile of 13.96 ms (`evidence/C2`). Those calls ran one after the other: we did **not** measure many sessions inserting in parallel.

## 2. The current state of the grid

`TRANSFORMER_CURRENT_STATE` holds one row per transformer and energy code. Every operator screen reads it, and each refresh rewrites it. Computing it inside one transaction would lock the table while the whole tree is summed.

**Measure** (`sp_RefreshTransformerState`):

1. The sums of the level-1 transformers go to a temporary table `#Leaf`. No transaction is open.
2. The tree is summed bottom-up into `#State`, still with no transaction.
3. Only then **one short transaction** writes the result with a single `MERGE`.
4. The application lock `TREE_REFRESH` allows one refresh at a time.

This is the "intermediate table" of §IV p. 13. The refresh of the whole tree took 194 ms in `evidence/C2`.

## 3. Readers do not wait for writers

`READ_COMMITTED` stays the isolation level. `security.sql` turns on `READ_COMMITTED_SNAPSHOT`, so a reader sees the last committed version of a row instead of waiting for the writer. Only the few places that decide something from what they read ask for a lock explicitly (point 6). If a server refuses this option, the script says so and the system works, but readers may then wait.

## 4. Jobs that must not run twice

| Lock | Scope | Job |
|------|------|------------------|
| `VEE_<meter>` | one meter | `sp_RunVEE` |
| `TREE_REFRESH` | whole tree | `sp_RefreshTransformerState`, `sp_RefreshTransformerAncestors` |
| `BILL_RUN` | all bills | `sp_IssueMonthlyBills` |
| `PURGE` | all readings | `sp_PurgeExpiredReadings` |

The second caller waits at most 10 seconds and then gets error **50007 "Busy"**. The VEE lock is per meter, so two people can validate different meters together.

## 5. Short transactions

VEE, finalization, bill runs and the purge visit many meters. They use **one transaction per meter or premise**, never one around the whole loop, so locks last for one step and an error in one meter does not undo the others. The purge also deletes old packets in groups of 5,000.

Shedding is the deliberate exception: `sp_ShedTransformerLoad` creates the commands of all the meters in one transaction, because a half-created shedding would be wrong.

## 6. Two people on the same row

- **Payments.** `sp_PayBill` reads the bill `WITH (UPDLOCK, HOLDLOCK)` before it adds up the earlier payments. A second payment waits, then sees the new remainder, so a bill cannot be overpaid. Trigger TR06 is the second line of defence.
- **Decisions.** Decisions and steps of a process are **guarded updates**: `UPDATE … WHERE status = <expected>`. If someone else was faster, no row matches and the user gets error 50003. This covers jobs (assign, accept, start, complete, cancel), documents, technicians, remote commands and GDPR requests.
- **"Only if it does not exist yet"** checks (availability, open GDPR request, first administrator) use `UPDLOCK, HOLDLOCK`, so two sessions cannot both find nothing.
- **The same reading twice.** A unique constraint on meter, code and slot is the last guarantee behind the check of the ingestion.

## 7. The demonstration

Two connections were opened on SQL Server 2025 on 25/11/2026. Session 1 starts and keeps its transaction open; session 2 starts 2 seconds later. Script and output: `evidence/D8`.

| Case | Session 1 | Session 2 | Result |
|--------|----------|----------|-----------|
| Same bill (19.33 left) | pays 0.01, commits after 6 s | pays 19.33, the amount it saw as left | waited **4.1 s**, then refused with 50004: not overpaid |
| Grid refresh | holds `TREE_REFRESH` for 15 s | starts a refresh | waited **10.0 s**, then 50007 "Busy" |
| Same GDPR request | officer 1 moves it to UNDER_REVIEW | officer 2 does the same | waited **4.0 s**, then 50003: the step happened once |
| Reading during ingestion | a packet is stored but not committed | counts readings and reads the grid state | **15 ms**, no waiting |

In the first case session 2 read the remainder *before* session 1 committed, which is exactly the situation that would overpay a bill without the lock.

## 8. Limits

- Parallel ingestion by many sessions was not load-tested; point 1 rests on the documented behaviour of the option.
- The application locks of the tree, bills and purge are global. With very many transformers the tree lock could be split per root.
- The performance run used thousands of rows, as p. 12 asks, not millions.
