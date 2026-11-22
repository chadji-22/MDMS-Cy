# Open questions (for Ioannis)

**Answered 22/11:** Q1 → use the course DB with small data · Q2 → NOTIFICATION table (done, B11) · Q3 → two read procedures (done, B3) · Q4 → sized by measurement (done, C1).

## Q5 (open) — the fresh-database proof and the merges
- `build_all.sql` twice + all tests on a fresh database is required before merging SQL changes into `io` (brief §1). The only database is the shared `ichara09`; rebuilding it was blocked by the permission system because it drops every table.
- Important for option 3: the edits to `create.sql`, `drop.sql` and `build_all.sql` (B11) have **never been executed as
  written**. The shared DB received the B11 objects from a separate scratch script with its own `ALTER TABLE`. Only a
  fresh `build_all.sql` run proves the committed scripts.
- Options: (1) **you allow one rebuild cycle of `ichara09`** (back to the `import.sql` state, then I rerun C1, ~6 s, and the tests); (2) a local SQL Server 2022 in Podman (no admin), then the proof runs there; (3) merge on the strength of the additive deploy + 82/82 tests, and let Eliana's C6 fresh-database run be the proof.

Format: what I tried · what failed · options. Recommended option first.

## Q1 — No local SQL Server (blocks C1, C2, C3 and testing every page)
- Tried: Windows services (no `MSSQL*`), Podman containers/images (none for SQL Server). Podman VM has ~15.8 GB RAM,
  enough for SQL Server 2022 (needs 2 GB).
- Options:
  1. **Podman container, no admin rights (recommended):**
     ```
     podman volume create mdms-sql
     podman run -d --name mdms-sql -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD=<local-only password> \
       -e MSSQL_PID=Developer -p 127.0.0.1:14333:1433 -v mdms-sql:/var/opt/mssql \
       mcr.microsoft.com/mssql/server:2022-latest
     ```
     The password lives only in the environment / a git-ignored file. The web container is then recreated on the same
     Podman network pointing at `mdms-sql`. pandoc the same way: `podman run --rm -v ...:/data pandoc/core:3.5 ...`.
  2. SQL Server 2022 Developer/Express installed on Windows (needs admin; you run the installer).
  3. Course DB over the VPN: ruled out by the brief for large data (27 MB data / 12 MB log caps).

## Q2 — B11: where is a SIMULATED notification recorded?
- Found: TR21 inserts `EVENT` `THRESHOLD_EXCEEDED`; no table can hold channel / recipient / status / time / event id.
- Options:
  1. **New table `NOTIFICATION` (outbox) + `sp_DispatchNotifications` (officer/DSO job, or run after finalize) +
     `sp_ListMyNotifications` (consumer).** A real record, status `SIMULATED`. Schema change: touches `create.sql`, `drop.sql`,
     the expected counts in `build_all.sql` (24 → 25 tables, 110 → 112 procedures), `tests.sql` (new test), Eliana's data
     dictionary (D6 "24 tables"), the `.dat` list / `bulk_import.sql` (C4). Done idempotently, tested twice from fresh.
  2. No DB change: the events page derives "SIMULATED · EMAIL · recipient · event #" from `sp_GetPremiseEvents` +
     `sp_GetMyProfile`. Not a record: it changes after the fact if the preferences change.
  3. PHP append-only file outbox outside the DB. A record, but not in the DB, not audited, lost with the container.

## Q3 — Read procedures the consumer pages cannot do without
- `sp_PayServiceFee` needs a `service_type_id`; no CONSUMER-callable procedure returns one (UC-06 in `select.sql` reads
  `SERVICE_TYPE` directly; the PHP user is EXECUTE-only).
- `sp_AddPremise` / `sp_ChangeSupplier` take a `supplier_org_id`; no CONSUMER procedure lists suppliers (optional for
  `sp_AddPremise`).
- Options:
  1. **Add two new read-only procedures** `sp_ListServiceTypes` (active types with fee) and `sp_ListSuppliers`
     (id + name), roles CONSUMER and staff. New objects only; no existing signature changes. +1 test each.
  2. Only `sp_ListServiceTypes`; premises are added without a supplier (the officer sets it).
  3. No DB change: drop "pay a service fee" from the page and document it as a limit.

## Q4 — C1 size: the brief contradicts itself
- The generator writes ≈ 437 readings per meter per day. "A few hundred meters × 2–4 weeks" ≈ 2–4 million rows;
  "tens of thousands" of readings ≈ 5–10 meters × a few days.
- Constraints: history-access page needs data in October (`@days ≥ 22` now); ≥ 80 consumers gives a tree with ≥ 2 leaves;
  a visible scan-vs-seek needs a table much larger than one page range.
- Options (readings ≈ consumers × days × 437):
  1. **100 consumers × 25 days ≈ 1.1 M readings** (3 leaf transformers, reaches October, clear index effect; local only).
  2. 30 consumers × 25 days ≈ 330 k readings (one leaf transformer, still reaches October).
  3. 300 consumers × 28 days ≈ 3.7 M readings (the brief's "few hundred × 4 weeks").
  4. 8 consumers × 25 days ≈ 90 k readings (literally "tens of thousands"; weak index evidence).

## Note — team status (not a decision for me)
- B5, B6, C4, C5, C6 are on no remote branch; D1 skeleton does not exist. If they exist unpushed, they should be pushed
  before E1 moves the files.
