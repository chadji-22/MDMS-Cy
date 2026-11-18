# MDMS-Cy — SQL Build Specification for the Implementation Agent

**Project:** EPL342 Databases, University of Cyprus — Smart National Meter Data Management System (MDMS-Cy), Group 10
**Target:** Microsoft SQL Server 2022/2025, T-SQL, run from SSMS; PHP front end via SQLSRV
**Schema baseline:** `create.sql` v6 (final), 24 tables. The project doc `claude/mdms_cy_schema_v6.sql` is the same file.
**Phase B deadline:** Friday 4/12/2026, 12:00

---

## 0. How to use this document

You are the agent that writes all of the database code for Phase B. This document is the contract. The schema (`create.sql` v6) is frozen: **do not add, remove or rename tables or columns**. If you believe a change is needed, stop and report it instead of making it. Everything else (functions, views, triggers, stored procedures, indexes, security, data, tests) is built from the catalogs below.

Work in this order and deliver one file per step (see §13 for the full file list):

1. `functions.sql` (§6)
2. `views.sql` (§7)
3. `triggers.sql` (§8)
4. `procedures_*.sql`, one file per module (§9)
5. `indexes.sql` (§10)
6. `security.sql` (§11)
7. `import.sql` (small data, **inserted only through the stored procedures**) and the bulk data generator (§12)
8. `tests.sql` and `perf.sql` (§14)

Every script must be **re-runnable**: `CREATE OR ALTER` for functions, views, triggers and procedures, `DROP ... IF EXISTS` / `IF NOT EXISTS` elsewhere. Every object carries a comment that cites the part of project.pdf it implements, in the form `-- [project.pdf §3.2 p.8-9]`. Anything that the PDF does not ask for is marked `-- [AR: <reason>]` (architectural rationale).

---

## 1. Hard rules (non-negotiable)

| # | Rule | Why |
|---|------|-----|
| R1 | **Every function of the system runs through a stored procedure.** The PHP code only ever executes `{call dbo.sp_Name(?, ?, ...)}`. No SELECT, INSERT, UPDATE or DELETE text in PHP. | Instructor's requirement; project.pdf p.2 ("το μεγαλύτερο σύνολο λειτουργίας ... είναι υλοποιημένο στην βάση"); security §IV p.13 |
| R2 | Every user-facing procedure takes **`@actor_user_id INT` as its first parameter**, checks the actor's role with `dbo.sp__AssertRole`, and records the actor in `SESSION_CONTEXT` so triggers can log who did it. | Κοινές αρχές p.5: identify the user before every protected operation; log the user who caused each change |
| R3 | Every procedure that changes more than one row or table runs **in one transaction** with `SET XACT_ABORT ON` and `TRY/CATCH` (template T2). | Κοινές αρχές p.5: atomic operations; lecture 20-43 |
| R4 | **Triggers are required.** They do auditing, cross-table integrity checks and derived updates (§8). Triggers never call procedures that open their own transactions. | Instructor; lecture 18; lab 10 (`tr_AUDIT_Employees`, `tr_ORDER_TOTAL`) |
| R5 | **Cursors** (`LOCAL FAST_FORWARD`) are used wherever the work is "for each meter / premise / tree node / command, do a workflow step" (§3.4 lists them). Inside a cursor loop, use set-based statements. Never use a cursor inside an OLTP read procedure that a web page calls. | Lab 10 (Hogwarts cursor and recursive tree); <2 s OLTP target §IV p.12 |
| R6 | No dynamic SQL built by string concatenation. If dynamic SQL is unavoidable (only `BULK INSERT` with a path), use `sp_executesql` with parameters, and validate the path. | Lecture 20-12, 20-20: SQL injection |
| R7 | Passwords exist only as `HASHBYTES('SHA2_512', salt + password)`. They are never returned by any procedure, never logged and never printed. | Κοινές αρχές p.5; lecture 20-76 |
| R8 | Finalized readings and final aggregates are never updated; `AUDIT_LOG` is never updated or deleted; users, bills and payments are never deleted (GDPR anonymizes instead). Triggers enforce this. | §3.2 p.9 immutability; §1.4 p.6 accounting data kept |
| R9 | All timestamps are UTC `DATETIME2(0)`. Every 15-minute reading is stored at the start of its slot (`dbo.fn_Floor15`). | §3.1 p.8 "στο αντίστοιχο 15-λεπτο" |
| R10 | Use only the column names and CHECK values that exist in `create.sql` v6. Status values must follow the state machines in §4 exactly. | Schema is frozen |

---

## 2. The instructor's style (copy it)

These patterns come from the course labs and lectures. Use them exactly, so the code reads like course code in the oral exam.

| Topic | Instructor's pattern | Source |
|---|---|---|
| Object names | Brackets and schema in DDL: `CREATE OR ALTER PROCEDURE [dbo].[sp_RegisterConsumer]`, `ALTER TABLE [dbo].[PROJECT] WITH CHECK ADD CONSTRAINT [FK_...]` | Lab 6 |
| Name prefixes | Views `view_...`, triggers `tr_...`, functions `fn_...`, procedures `sp_...`. Internal helper procedures that PHP must not call: `sp__...` (two underscores). | Lab 10 (`view_EmployeeFullNames`, `tr_AUDIT_Employees`, `fn_ABS`); lecture 20-67 (`sp_InsertAtomicTwoTables`) |
| Procedure body | `AS BEGIN SET NOCOUNT ON; ... END` | Lab 10 slide 9; lecture 20-43 |
| Atomic procedure | `SET XACT_ABORT ON; BEGIN TRY BEGIN TRANSACTION; ... IF @@ROWCOUNT = 0 THROW 5000x, '...', 1; COMMIT TRANSACTION; END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH` | Lecture 20-43 ("THROW instead of RAISERROR — modern"), 20-42 |
| User error numbers | `THROW` with numbers ≥ 50000 (the range below is reserved by SQL Server) | Lecture 20-43 |
| Variables from one row | `SELECT @id = ID, @name = Name FROM T WHERE ID = 1` | Lab 10 slide 22 |
| Cursor | `DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT ...; OPEN c; FETCH NEXT FROM c INTO ...; WHILE @@FETCH_STATUS = 0 BEGIN ... FETCH NEXT FROM c INTO ... END; CLOSE c; DEALLOCATE c;` | Lab 10 slides 11, 17 (`LOCAL` is required for recursion) |
| Recursive tree walk | A procedure that opens a `LOCAL` cursor over the children of `@sid` and calls itself for each child (`EXEC Hogwarts_Tree @ID`). Results go into a `#temp` table that the first call creates and returns. Indentation uses `SPACE(level * 2)`. | Lab 10 slides 13–21 |
| Guard trigger | `CREATE OR ALTER TRIGGER [dbo].[tr_...] ON [dbo].[T] AFTER INSERT, UPDATE AS BEGIN SET NOCOUNT ON; IF EXISTS (SELECT ... FROM inserted AS i JOIN ...) BEGIN RAISERROR('...', 16, 1); ROLLBACK TRANSACTION; RETURN; END END` | Lecture 18-15, 18-25 |
| Audit trigger | `INSERT INTO <audit table> (...) SELECT ... FROM inserted AS i [JOIN deleted AS d ON ...]` — the `inserted` / `deleted` tables | Lecture 18-22; lab 10 slides 3–5 |
| Derived-value trigger | Keep a stored total correct whenever child rows change (lab 10 `tr_ORDER_TOTAL`) | Lab 10 slide 5 |
| Functions | Scalar: `CREATE FUNCTION dbo.X (@p T) RETURNS T AS BEGIN ... RETURN @r END`. Table-valued: `RETURNS @records TABLE (...) AS BEGIN INSERT INTO @records ...; RETURN; END` | Lecture 20-23, 20-26 |
| Buffering | Build large results in `#temp` tables first, then write to real tables in one short transaction | Lecture 20-67 |
| Isolation levels | `SET TRANSACTION ISOLATION LEVEL ...` with READ COMMITTED as default | Lecture 20-44, 20-45 |
| Passwords | `HASHBYTES('SHA2_512', @Password)` stored as VARBINARY. We add a per-user salt [AR: stops equal passwords from having equal hashes]. | Lecture 20-76 |
| PHP call | `$tsql = "{call dbo.sp_X(?, ?)}"; $params = array(array($v1, SQLSRV_PARAM_IN), ...); $stmt = sqlsrv_query($conn, $tsql, $params);` | Lecture 20-90; lab 7 (`q3.php`) |

### 2.1 Templates

**T1 — read procedure (called by a web page; no transaction, no cursor):**

```sql
-- [project.pdf §1.2 p.5-6: consumer views the 15-min series of their own premise]
CREATE OR ALTER PROCEDURE [dbo].[sp_GetPremiseReadings]
    @actor_user_id INT,
    @premise_id    INT,
    @from          DATETIME2(0),
    @to            DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';
    IF NOT EXISTS (SELECT 1 FROM [dbo].[PREMISE] WHERE premise_id = @premise_id AND user_id = @actor_user_id)
        THROW 50002, 'Permission denied: not your premise.', 1;
    -- ... access-window check with dbo.fn_CanViewReadings, then one SELECT ...
END;
GO
```

**T2 — write procedure (atomic):**

```sql
-- [project.pdf §2.2 p.7: the technician accepts a job assigned to them]
CREATE OR ALTER PROCEDURE [dbo].[sp_AcceptWorkOrder]
    @actor_user_id INT,
    @work_order_id INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, N'sp_AcceptWorkOrder';
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[WORK_ORDER]
           SET status = 'ACCEPTED', accepted_at = SYSUTCDATETIME()
         WHERE work_order_id = @work_order_id
           AND technician_user_id = @actor_user_id
           AND status = 'ASSIGNED';                  -- the state check is part of the WHERE
        IF @@ROWCOUNT = 0
            THROW 50003, 'Work order is not assigned to you, or is not in ASSIGNED state.', 1;
        COMMIT TRANSACTION;
        SELECT @work_order_id AS work_order_id, 'ACCEPTED' AS status;   -- one-row result for PHP
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
```

**T3 — batch procedure with a cursor:**

```sql
-- [project.pdf §2.4 p.8: retries until ACK]
CREATE OR ALTER PROCEDURE [dbo].[sp_DispatchCommands]
    @actor_user_id INT,
    @max_attempts  SMALLINT = 3
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO,TSO,SYSTEM_ADMIN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, N'sp_DispatchCommands';
    DECLARE @command_id INT, @attempts SMALLINT;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT command_id, attempt_count FROM [dbo].[REMOTE_COMMAND]
        WHERE status IN ('APPROVED', 'SENT');
    OPEN c;
    FETCH NEXT FROM c INTO @command_id, @attempts;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;          -- one short transaction per command, not one for the whole loop
            -- ... one attempt, or FAILED when @attempts >= @max_attempts ...
            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            -- log the failure in AUDIT_LOG and continue with the next command
        END CATCH
        FETCH NEXT FROM c INTO @command_id, @attempts;
    END
    CLOSE c;
    DEALLOCATE c;
END;
GO
```

**T4 — recursive procedure over the transformer tree (the instructor's Hogwarts_Tree pattern):**

```sql
-- [project.pdf §4.1 p.9: hierarchy of arbitrary depth; lab 10 Hogwarts_Tree]
CREATE OR ALTER PROCEDURE [dbo].[sp__WalkTransformerTree]
    @parent_id INT,
    @depth     INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT, @name NVARCHAR(100), @level TINYINT;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR                 -- LOCAL: each recursive call has its own cursor
        SELECT transformer_id, name, [level] FROM [dbo].[TRANSFORMER]
        WHERE parent_transformer_id = @parent_id;
    OPEN c;
    FETCH NEXT FROM c INTO @id, @name, @level;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO #Tree (transformer_id, name, [level], depth, label)       -- #Tree is created by the caller
        VALUES (@id, @name, @level, @depth, SPACE(@depth * 2) + CAST(@id AS NVARCHAR(10)) + N' ' + @name);
        EXEC [dbo].[sp__WalkTransformerTree] @id, @depth + 1;                -- recursion, as in Hogwarts_Tree
        FETCH NEXT FROM c INTO @id, @name, @level;
    END
    CLOSE c;
    DEALLOCATE c;
END;
GO
```

Use an explicit `@depth` parameter instead of `@@NESTLEVEL`. When PHP or another procedure calls the walk, `@@NESTLEVEL` no longer starts at 1. SQL Server allows at most 32 nesting levels; the tree is at most 5 levels deep.

**T5 — guard trigger (lecture 18 style):**

```sql
-- [project.pdf §2.3 p.8: a meter becomes active only after the officer confirms its documents]
CREATE OR ALTER TRIGGER [dbo].[tr_METER_activation_guard]
ON [dbo].[METER]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 FROM inserted AS i
        WHERE i.status = 'ACTIVE'
          AND (SELECT COUNT(DISTINCT d.doc_type) FROM [dbo].[DOCUMENT] AS d
               WHERE d.meter_id = i.meter_id AND d.approval_status = 'APPROVED') < 3)
    BEGIN
        RAISERROR('[51004] A meter can become ACTIVE only with its 3 certificates approved.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO
```

**T6 — audit trigger (lab 10 `tr_AUDIT_Employees`, written to the shared AUDIT_LOG):**

```sql
-- [project.pdf Κοινές αρχές p.5: every critical state change is traceable]
CREATE OR ALTER TRIGGER [dbo].[tr_WORK_ORDER_audit]
ON [dbo].[WORK_ORDER]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @actor INT = CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);
    DECLARE @mech  VARCHAR(60) = ISNULL(CAST(SESSION_CONTEXT(N'mechanism') AS VARCHAR(60)), 'DIRECT_SQL');
    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    SELECT CASE WHEN @actor IS NULL THEN 'SYSTEM' ELSE 'USER' END,
           @mech,
           CASE WHEN d.work_order_id IS NULL THEN 'CREATE' ELSE 'STATUS_CHANGE' END,
           'WORK_ORDER', CAST(i.work_order_id AS VARCHAR(30)),
           d.status, i.status, NULL, @actor
    FROM inserted AS i
    LEFT JOIN deleted AS d ON d.work_order_id = i.work_order_id
    WHERE d.work_order_id IS NULL OR d.status <> i.status;
END;
GO
```

**T7 — PHP call (lecture 20-90):**

```php
$tsql   = "{call dbo.sp_AcceptWorkOrder(?, ?)}";
$params = array(
    array($_SESSION['user_id'], SQLSRV_PARAM_IN),
    array((int)$_POST['work_order_id'], SQLSRV_PARAM_IN)
);
$stmt = sqlsrv_query($conn, $tsql, $params);
if ($stmt === false) { show_error(sqlsrv_errors()); }   // codes 50001-51099 come from our THROW / RAISERROR
```

---

## 3. Shared conventions

### 3.1 Who is calling: actor and session context

* `sp_Login` returns `user_id`, `role_code`, `full_name` and `approval_status`. PHP stores them in `$_SESSION` and passes `user_id` as `@actor_user_id` on every call.
* `sp__AssertRole @actor_user_id, @roles` (CSV, for example `N'SYSTEM_OFFICER,SYSTEM_ADMIN'`) fails with **50002** unless the user exists, `is_active = 1`, `anonymized_at IS NULL`, `role_code` is in the list, and `approval_status = 'APPROVED'`. The last check is skipped when the list contains `TECHNICIAN_ANY`, which lets a pending technician manage their own registration.
* `sp__SetActor @actor_user_id, @mechanism` runs `EXEC sp_set_session_context @key = N'actor_user_id', @value = @actor_user_id;` and the same for `N'mechanism'`. Audit triggers read these values back. This replaces lab 10's `SELECT USER`: the web application connects with a single SQL login, so `USER` would always be the same person.
* System jobs (VEE, ingestion, purge, dispatch) set `actor_user_id` to the officer who started them; device calls set it to NULL with mechanism `INGESTION` or `DEVICE`. The audit row then has `actor_type = 'SYSTEM'` or `'DEVICE'`.

### 3.2 Results to PHP

* Read procedures return **one result set**. Lists take `@page INT = 1, @page_size INT = 50` and use `ORDER BY ... OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY`.
* Write procedures end with a **one-row result set** holding the new or changed key, for example `SELECT @new_id AS user_id;`. Do not rely on OUTPUT parameters, because PHP pages find result sets easier to read.
* Errors reach PHP as SQL errors with our numbers (§5). The PHP page shows the message text.

### 3.3 Transactions, isolation and locks

| Situation | Rule | Source |
|---|---|---|
| Default | READ COMMITTED. `security.sql` turns on `READ_COMMITTED_SNAPSHOT` for the database, so dashboards do not block ingestion. Skip this if the university server refuses the `ALTER DATABASE`, and write that down. | Lecture 20-44/45; §IV concurrency p.13 |
| Check-then-write on one row (assign, accept, approve, pay) | Put the expected state in the UPDATE's WHERE and test `@@ROWCOUNT`. A second user who loses the race gets **50003**. | [AR] optimistic concurrency |
| Paying a bill | Inside the transaction, read the bill `WITH (UPDLOCK, HOLDLOCK)` before summing payments, so two payments cannot overpay it. | §IV concurrency p.13 |
| Jobs that must not run twice at once (VEE for a meter, tree refresh, bill run, purge) | `EXEC sp_getapplock @Resource = N'VEE_<meter_id>' | N'TREE_REFRESH' | N'BILL_RUN' | N'PURGE', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;`. A timeout means **50007**. | [AR] supports §IV concurrency p.13 |
| Large computations (tree sums, aggregates, bill runs) | Compute into `#temp` tables outside the transaction, then write in one short transaction. | Lecture 20-67; §4.2 p.10 "ενδιάμεσος πίνακας" |
| Loops over many entities | One short transaction **per entity** inside the cursor loop, never one transaction around the whole loop. | Avoids long locks: contention point §IV p.12 |
| Nested calls | Internal helpers `sp__...` never open or commit transactions; they run inside the caller's. | Lecture 20-38: `@@TRANCOUNT` |

### 3.4 Where cursors are used

These are the cursor procedures; each is a "for each X, do a step" workflow. Everything else is set-based.

| Procedure | Cursor over | Why a cursor |
|---|---|---|
| `sp__WalkTransformerTree`, `sp_GetTransformerTree` | Children of a transformer (recursive) | Lab 10 Hogwarts_Tree, tree of arbitrary depth §4.1 |
| `sp_RefreshTransformerState` (via `sp__SumSubtree`) | Children of each node, post-order | Sums of every level §4.2 |
| `sp_RunVEE` | Meters with PENDING readings in the window | Per-meter time-series rules (spike, gap) §3.2 |
| `sp__EstimateGaps` (called by VEE) | The missing slots of one meter | Linear estimation slot by slot §3.2 p.9 |
| `sp_DispatchCommands` | APPROVED / SENT commands | One attempt per command with retries §2.4 |
| `sp_ShedTransformerLoad` | Active meters under a transformer subtree | One command per meter §II.Δ p.3 |
| `sp_IssueMonthlyBills` | Premises of a supplier | One bill per premise, own transaction §1.3 |
| `sp_PurgeExpiredReadings` | Meters grouped by retention | Different cut-off per meter §1.4 p.6-7 |
| `sp_IngestTelemetryBatch` | Packets inside a JSON array | Calls the single-packet procedure for each one §3.1 |
| `sp_CheckConsumptionThresholds` | Premises with a threshold | One alert per premise per month §1.2 p.6 |
| `sp_MarkOverdueBills` | Overdue bills | Status change plus audit per bill §1.3 |
| `tr_TRANSFORMER_tree_guard` | Rows of `inserted` | Walks up each new parent chain to find cycles §4.1 |

---

## 4. Schema reference (v6) and state machines

### 4.1 Tables and columns

PK = primary key. "→" marks a foreign key. Exact types and CHECKs are in `create.sql`.

| Table | Columns |
|---|---|
| ROLE | **role_code** PK (`SYSTEM_ADMIN, SYSTEM_OFFICER, CONSUMER, TECHNICIAN, DSO, TSO, SUPPLIER, AGGREGATOR`), description |
| ORGANIZATION | **organization_id**, name UQ, org_type (`SUPPLIER, AGGREGATOR`) |
| USER_ACCOUNT | **user_id**, email UQ, password_hash VARBINARY(64), password_salt VARBINARY(16), full_name, phone, approval_status (`PENDING, APPROVED, REJECTED, SUSPENDED`), is_active, created_at, anonymized_at, iban (consumer only), notify_email, notify_sms, birth_date / photo_path / specialty (technician only, all three required), role_code→ROLE, organization_id→ORGANIZATION (supplier / aggregator users only) |
| TECHNICIAN_AVAILABILITY | **user_id→, avail_date, start_time**, end_time, district (one of the 6 districts) |
| TRANSFORMER | **transformer_id**, name UQ, level (1 = LV transformer that meters hang on; parent = level + 1), capacity_kva, latitude, longitude, min_lat/min_lon/max_lat/max_lon (geofence rectangle, all four or none), parent_transformer_id→TRANSFORMER |
| PREMISE | **premise_id**, address, latitude, longitude, usage_type (`RESIDENTIAL, COMMERCIAL, INDUSTRIAL, AGRICULTURAL`), district, municipality, parish, postal_code CHAR(4), prosumer_scheme (`NONE, NET_METERING, NET_BILLING`), monthly_threshold_kwh, user_id→ (consumer), supplier_org_id→, aggregator_org_id→ |
| METER_TYPE | **meter_type_id**, type_name UQ, connection_phases (1 or 3), max_amps |
| METER | **meter_id**, serial_number UQ, network_id UQ, firmware_version, communication_type (`CELLULAR, NB_IOT, PLC`), latitude, longitude, status (`PENDING, ACTIVE, INACTIVE, FAULTY, REMOVED`), activated_at, installed_at, removed_at, installation_photo, retention_months (36 or 1), meter_type_id→, transformer_id→ (level 1), premise_id→, installed_by_user_id→. At most one meter per premise has `removed_at IS NULL` (filtered unique index). |
| DOCUMENT | **document_id**, doc_type, doc_code, issue_date, expiry_date, file_path, approval_status (`PENDING, APPROVED, REJECTED`), user_id→ (technician docs: `ID_CARD, INSTALLER_LICENSE, TRAINING_CERT`) **or** meter_id→ (meter certificates: `CALIBRATION_CERT, CE_DECLARATION, ENCRYPTION_CERT`); UQ (doc_type, doc_code) |
| OBIS_CODE | **obis_code**, description, unit, measurement_kind (`CUMULATIVE, INSTANTANEOUS`), valid_min, valid_max. Seeded: 1.8.0, 1.8.1, 1.8.2, 2.8.0, 3.8.0, 4.8.0, 32.7.0, 52.7.0, 72.7.0, 31.7.0, 51.7.0, 71.7.0, 14.7.0 |
| TELEMETRY_PACKET | **packet_id**, meter_network_id, transmission_timestamp, received_at, network_type, signal_dbm, raw_payload (JSON), match_status (`MATCHED, UNMATCHED, COMM_ERROR, QUARANTINED`), meter_id→ |
| METER_READING | **reading_id**, reading_timestamp (15-min slot start), value, delta_value, status (`PENDING, VALID, SUSPECT, ESTIMATED, EDITED`), original_value, vee_rule, vee_note, is_final, finalized_at, meter_id→, obis_code→, packet_id→ (NULL when ESTIMATED), edited_by_user_id→; UQ (meter_id, obis_code, reading_timestamp) |
| TRANSFORMER_READING | **transformer_reading_id**, reading_timestamp, value, transformer_id→, obis_code→; UQ (transformer_id, obis_code, reading_timestamp). Kept forever. |
| AGGREGATE | **aggregate_id**, period_type (`QUARTER_HOUR, DAY, MONTH, YEAR`), period_start, value, sample_count, is_final, calculated_at, meter_id→ **or** transformer_id→, obis_code→. Filtered UQ per owner / OBIS / period. |
| TRANSFORMER_CURRENT_STATE | **state_id**, reference_15_min, sum_value, meter_count, computed_at, transformer_id→, obis_code→ (`1.8.0` or `2.8.0` only); UQ (transformer_id, obis_code) = one current row each |
| EVENT | **event_id**, event_timestamp, event_type (free text, catalog in §4.3), severity (`INFO, WARNING, CRITICAL`), description, meter_id→ / transformer_id→ / packet_id→ (at least one) |
| SERVICE_TYPE | **service_type_id**, service_name UQ (seeded `HISTORICAL_ACCESS` fee per month, `METER_CHECK`), fee, is_active |
| WORK_ORDER | **work_order_id**, work_type (`INSTALLATION, REPLACEMENT, TECHNICAL_CHECK, FAULT_REPAIR, ANTI_TAMPER`), origin (`CONSUMER_REQUEST, EVENT, OFFICER`), description, status (§4.2), created_at, scheduled_start, scheduled_end, accepted_at, completed_at, findings, evidence_path, persons_to_notify, requested_by_user_id→, technician_user_id→, premise_id→, meter_id→ (at least one of the two), event_id→ (required when origin = EVENT), service_type_id→ |
| REMOTE_COMMAND | **command_id**, command_type (`DISCONNECT, RECONNECT, FIRMWARE_UPGRADE`), parameters, status (§4.2), requested_at, attempt_count, last_attempt_at, ack_at (set exactly when ACKNOWLEDGED), result, meter_id→, requested_by_user_id→, executed_by_user_id→ |
| TARIFF | **tariff_id**, tariff_name, rate (per kWh), valid_from, valid_to; UQ (tariff_name, valid_from) |
| BILL | **bill_id**, issue_date, due_date, period_start, period_end, amount, status (§4.2), premise_id→, user_id→, supplier_org_id→, tariff_id→ |
| PAYMENT | **payment_id**, payment_date, amount > 0, method (`BANK_TRANSFER, CARD, CASH, DIRECT_DEBIT`), status (`PENDING, COMPLETED, FAILED, REFUNDED`), transaction_reference (UQ when present), access_from, access_to, user_id→, bill_id→ **xor** service_type_id→, access_meter_id→ (with access_from/to only for historical access) |
| GDPR_REQUEST | **gdpr_request_id**, request_type (`RIGHT_TO_BE_FORGOTTEN, RETENTION_REDUCTION`), status (§4.2), submitted_at, decided_at, user_id→, meter_id→ (required for RETENTION_REDUCTION) |
| AUDIT_LOG | **log_id**, logged_at, actor_type (`USER, SYSTEM, DEVICE`), mechanism, action, object_type, object_id, old_state, new_state, comment, user_id→ (required when actor_type = USER; otherwise mechanism is required) |

### 4.2 State machines (every status change goes through these and nothing else)

| Object | Allowed transitions | Procedure that makes the change |
|---|---|---|
| USER_ACCOUNT.approval_status | Consumer, staff and organization users are created `APPROVED`. A technician is created `PENDING`, then `PENDING → APPROVED | REJECTED`; later `APPROVED ↔ SUSPENDED`; `REJECTED → PENDING` on re-submission. | `sp_RegisterTechnician`, `sp_DecideTechnician`, `sp_ResubmitTechnician` |
| DOCUMENT.approval_status | `PENDING → APPROVED | REJECTED`; `REJECTED → PENDING` (new file uploaded) | `sp_DecideDocument`, `sp_ResubmitDocument` |
| METER.status | Created `PENDING`; `PENDING → ACTIVE` (officer confirms; 3 certificates approved; sets activated_at); `PENDING → INACTIVE` (officer rejects); `ACTIVE ↔ INACTIVE`; `ACTIVE → FAULTY → ACTIVE`; any → `REMOVED` (final; sets removed_at) | `sp_InstallMeter`, `sp_ConfirmMeter`, `sp_SetMeterStatus`, `sp_ReplaceMeter` |
| METER_READING.status | Inserted `PENDING` (from a packet) or `ESTIMATED` (by VEE). `PENDING → VALID | SUSPECT`; `SUSPECT → VALID` (officer accepts) or `→ EDITED` (officer corrects; original_value kept); `ESTIMATED → EDITED`. Then `is_final 0 → 1` for VALID / ESTIMATED / EDITED only. After that, no change at all. | `sp_IngestTelemetryPacket`, `sp_RunVEE`, `sp_AcceptSuspectReading`, `sp_EditReading`, `sp_FinalizeReadings` |
| WORK_ORDER.status | `SUBMITTED → ASSIGNED → ACCEPTED → IN_PROGRESS → COMPLETED`; `ASSIGNED → SUBMITTED` (technician declines; technician cleared); `SUBMITTED | ASSIGNED | ACCEPTED → CANCELLED` | `sp_SubmitServiceRequest`, `sp_CreateWorkOrder`, `sp_AssignWorkOrder`, `sp_AcceptWorkOrder`, `sp_DeclineWorkOrder`, `sp_StartWorkOrder`, `sp_CompleteWorkOrder`, `sp_CancelWorkOrder` |
| REMOTE_COMMAND.status | `PENDING_APPROVAL → APPROVED | REJECTED`; DSO / TSO / officer commands are created `APPROVED`; `APPROVED → SENT` (attempt 1); `SENT → SENT` (attempt n, attempt_count + 1); `SENT → ACKNOWLEDGED` (ack_at) `| FAILED` (attempts used up) | `sp_RequestRemoteCommand`, `sp_DecideRemoteCommand`, `sp_DispatchCommands`, `sp_AcknowledgeCommand`, `sp_ShedTransformerLoad` |
| BILL.status | Created `ISSUED`; `ISSUED → PARTIALLY_PAID → PAID` (set by trigger from payments); `ISSUED | PARTIALLY_PAID → OVERDUE` (due date passed) `→ PAID`; `ISSUED → CANCELLED` | `sp_IssueMonthlyBills`, `tr_PAYMENT_bill_status`, `sp_MarkOverdueBills`, `sp_CancelBill` |
| GDPR_REQUEST.status | `SUBMITTED → UNDER_REVIEW → PRE_APPROVED → APPROVED → EXECUTED`; `SUBMITTED | UNDER_REVIEW | PRE_APPROVED → REJECTED`. The officer who gives final approval must differ from the one who pre-approved [AR: two-person rule]. | `sp_SubmitGdprRequest`, `sp_AdvanceGdprRequest`, `sp_ExecuteGdprRequest` |
| TELEMETRY_PACKET.match_status | Set once at insert: `MATCHED` (network_id belongs to an ACTIVE meter), `QUARANTINED` (meter exists but is not ACTIVE), `UNMATCHED` (no such network_id), `COMM_ERROR` (malformed JSON or missing fields; raw text kept, wrapped as a JSON string) | `sp_IngestTelemetryPacket` |

### 4.3 EVENT types

`event_type` has no CHECK, so new types can be added without a schema change (§IV p.13 future extension). Use these names:

| event_type | Severity | Raised by | Spec |
|---|---|---|---|
| PACKET_UNMATCHED, PACKET_QUARANTINED, PACKET_COMM_ERROR | WARNING | `tr_TELEMETRY_PACKET_failure_event` | §3.1 p.8 "όχι να χάνονται σιωπηρά" |
| UNSUPPORTED_OBIS, DUPLICATE_READING | INFO | `sp_IngestTelemetryPacket` | §3.2 p.8 |
| VOLTAGE_SAG (< 207 V), VOLTAGE_SWELL (> 253 V) | WARNING | `sp_IngestTelemetryPacket` (230 V ±10 %) | §1.2 p.5; §II.Γ p.3 |
| FREQUENCY_DEVIATION (\|f − 50\| > 0.2 Hz) | CRITICAL | `sp_RecordTransformerReading` | §II.Δ p.3 |
| TAMPER_ALERT | CRITICAL | `sp_RaiseTamperEvent` (device / DSO) → `tr_EVENT_work_order` | §2.4 p.8 |
| THRESHOLD_EXCEEDED | INFO | `tr_AGGREGATE_threshold_alert`, `sp_CheckConsumptionThresholds` | §1.2 p.6 |
| COMMAND_FAILED | WARNING | `sp_DispatchCommands` | §2.4 p.8 |
| PHASE_UNBALANCE, TECHNICAL_LOSS_HIGH | WARNING | DSO report procedures, when `@raise_events = 1` | §II.Γ p.3 |

### 4.4 Role matrix (which role may call which module)

| Module (§9) | ADMIN | OFFICER | CONSUMER | TECHNICIAN | DSO | TSO | SUPPLIER | AGGREGATOR |
|---|---|---|---|---|---|---|---|---|
| 9.1 Accounts and login | all | approve, list | self | self | self | self | self | self |
| 9.2 Premises and consumption | read | read | own premises | — | read | — | — | — |
| 9.3 Work orders | read | full | submit, own | own jobs | create | — | — | — |
| 9.4 Meters | read | confirm, status | own meters (read) | install, replace, documents | status, read | read | — | — |
| 9.5 Remote commands | — | approve, dispatch | — | request | request (approved) | shed, request | — | — |
| 9.6 Ingestion and VEE | — | run, edit, finalize | — | — | run, edit, finalize | — | — | — |
| 9.7 Grid and analytics | read | read | — | — | analytics | tree, refresh | — | — |
| 9.8 Billing | read | full | own bills, pay | — | — | — | own customers: issue, list | — |
| 9.9 GDPR | — | review, execute | submit, own | — | — | — | — | — |
| 9.10 Market data | — | — | — | — | — | — | own customers | own portfolio |
| 9.11 Reference data and audit | all | all | — | — | read audit | — | — | — |

---

## 5. Error catalog

| Number | Meaning | Raised with |
|---|---|---|
| 50001 | Object not found | `THROW` in procedures |
| 50002 | Permission denied (wrong role, not owner, inactive, not approved) | `sp__AssertRole`, ownership checks |
| 50003 | Invalid state transition, or another user changed the row first | `@@ROWCOUNT = 0` after a guarded UPDATE |
| 50004 | Invalid input (range, format, missing value, date order) | Parameter checks at the top of each procedure |
| 50005 | Duplicate (email, serial number, slot, code) | Before INSERT; or on catching errors 2627/2601 |
| 50006 | Login failed. Use the same message for "no such email" and "wrong password". | `sp_Login` |
| 50007 | Busy: a job is already running (`sp_getapplock` timeout) | Batch procedures |
| 50008 | Access to past data not bought, or outside retention | `sp_GetPremiseReadings`, `sp_GetPremiseAggregates` |
| 51001–51099 | Trigger rules (number in the message text: `'[51004] ...'`) | `RAISERROR(..., 16, 1); ROLLBACK TRANSACTION; RETURN;` |

---

## 6. Functions (`functions.sql`)

| Function | Type | Signature → result | Logic | Spec |
|---|---|---|---|---|
| `fn_HashPassword` | scalar | `(@password NVARCHAR(128), @salt VARBINARY(16)) → VARBINARY(64)` | `RETURN HASHBYTES('SHA2_512', @salt + CAST(@password AS VARBINARY(256)))` | Κοινές αρχές p.5; lecture 20-76 |
| `fn_Floor15` | scalar | `(@ts DATETIME2(0)) → DATETIME2(0)` | Start of the 15-minute slot: `DATEADD(MINUTE, (DATEDIFF(MINUTE, '2000-01-01', @ts) / 15) * 15, '2000-01-01')` | §3.1 p.8 |
| `fn_UserHasRole` | scalar | `(@user_id INT, @roles NVARCHAR(200)) → BIT` | 1 if the user is active, not anonymized, and `role_code` is in `STRING_SPLIT(@roles, ',')`, and approved. The pseudo-role `TECHNICIAN_ANY` matches a technician in any approval status. | Κοινές αρχές p.5 |
| `fn_TransformerSubtree` | multi-statement TVF | `(@root_id INT) → @records TABLE (transformer_id INT PRIMARY KEY, [level] TINYINT, depth INT)` | Insert the root at depth 0, then `WHILE @@ROWCOUNT > 0` insert the children of the rows added in the last round (breadth-first, no recursion, so no 32-level limit) | §4.1–4.2 p.9-10: "άμεσα ή έμμεσα ... ανεξαρτήτως βάθους" |
| `fn_TransformerAncestors` | multi-statement TVF | `(@transformer_id INT) → @records TABLE (transformer_id INT, [level] TINYINT, distance INT)` | Walk up `parent_transformer_id` with a WHILE loop, stopping at the root (or after 50 steps, as a cycle guard) | §4.2 p.10 "ancestors" |
| `fn_FindGeofence` | scalar | `(@lat DECIMAL(9,6), @lon DECIMAL(9,6)) → INT` | The level-1 transformer whose rectangle contains the point; if several match, the smallest rectangle; NULL if none | §4.1 p.9 "με βάση τις συντεταγμένες ... σε ποιο Geofence εμπίπτει" |
| `fn_CanViewReadings` | scalar | `(@user_id INT, @meter_id INT, @from DATETIME2(0), @to DATETIME2(0)) → BIT` | 1 when (a) the meter belongs to a premise of the user; (b) every day of [@from, @to] is either in the current calendar month **or** covered by a COMPLETED `HISTORICAL_ACCESS` payment for this meter (`access_from <= day <= access_to`); and (c) @from is not older than `retention_months` before today | §1.2 p.6 (free current month, paid history, limited by retention) |
| `fn_ActiveTariff` | scalar | `(@day DATE) → INT` | The tariff with `valid_from <= @day AND (valid_to IS NULL OR valid_to >= @day)`, latest valid_from first | §1.3 p.6 |
| `fn_BillPaid` | scalar | `(@bill_id INT) → DECIMAL(12,2)` | `SUM(amount)` of COMPLETED payments for the bill (0 if none) | §1.3 p.6 |
| `fn_DATE_ONLY` | scalar | `(@d DATETIME2) → CHAR(10)` | `dd/mm/yyyy`, for PHP display (lab 10 exercise, reused) | Lab 10 |

---

## 7. Views (`views.sql`)

The per-role views are the "interfaces" the instructor described over the single user table. Every view is read-only and is used by procedures, never by PHP directly. Create the user-related views `WITH ENCRYPTION`, as in lab 10 exercise 5 [AR: hides the column list of personal data from users with view access].

| View | Columns | Source / filter | Spec |
|---|---|---|---|
| `view_CONSUMER` | user_id, email, full_name, phone, iban, notify_email, notify_sms, is_active, created_at, anonymized_at | USER_ACCOUNT where role_code = 'CONSUMER' | §1.1 p.5 |
| `view_TECHNICIAN` | user_id, email, full_name, phone, birth_date, photo_path, specialty, approval_status, is_active | role_code = 'TECHNICIAN' | §2.1 p.7 |
| `view_ORGANIZATION_USER` | user_id, email, full_name, role_code, organization_id, organization_name, org_type | USER_ACCOUNT JOIN ORGANIZATION | §5.1 p.10 |
| `view_STAFF` | user_id, email, full_name, phone, role_code, is_active | role_code IN ('SYSTEM_ADMIN','SYSTEM_OFFICER','DSO','TSO') | Κοινές αρχές p.5 |
| `view_PREMISE_METER` | premise columns + current meter (meter_id, serial_number, status, transformer_id) + supplier and aggregator names | PREMISE LEFT JOIN METER (removed_at IS NULL) LEFT JOIN ORGANIZATION ×2 | §1.1 p.5, §2.3 p.8 |
| `view_METER_LOCATION` | meter_id, serial_number, status, latitude, longitude, premise address, transformer name, level-1 rectangle | For Leaflet maps (+10 % bonus, project.pdf p.2) and for technicians' visits (§2.2 p.7) | §2.2 p.7, §4.1 p.9 |
| `view_OPEN_WORK_ORDER` | work order + premise address + meter lat/lon + technician name | status NOT IN ('COMPLETED','CANCELLED') | §2.2 p.7 |
| `view_BILL_BALANCE` | bill columns + paid = `dbo.fn_BillPaid(bill_id)` + remaining = amount − paid | BILL | §1.3 p.6 |

---

## 8. Triggers (`triggers.sql`)

Trigger rules, shared by all triggers:

* Every trigger handles **many rows at once**: work with `inserted` / `deleted` as sets. Use a cursor over `inserted` only where the row-by-row walk is the point (`tr_TRANSFORMER_tree_guard`).
* Guard triggers use template T5 (`RAISERROR('[51xxx] ...', 16, 1); ROLLBACK TRANSACTION; RETURN;`).
* Audit triggers use template T6 and take the actor from `SESSION_CONTEXT`. They never write passwords, IBANs or other personal values into `old_state` / `new_state`; for those they write only the column name, for example `'iban changed'`.
* Triggers never call procedures that open transactions.

| # | Trigger | Table, event | Does | Error | Spec |
|---|---|---|---|---|---|
| TR01 | `tr_METER_READING_immutable` | METER_READING AFTER UPDATE | Reject if any `deleted.is_final = 1` (a finalized reading cannot change; DELETE stays allowed for the retention purge) | 51001 | §3.2 p.9 |
| TR02 | `tr_AGGREGATE_immutable` | AGGREGATE AFTER UPDATE, DELETE | Reject if any `deleted.is_final = 1` | 51002 | §3.2 p.9, §4.2 p.10 |
| TR03 | `tr_AUDIT_LOG_append_only` | AUDIT_LOG AFTER UPDATE, DELETE | Always reject | 51003 | Κοινές αρχές p.5 |
| TR04 | `tr_METER_activation_guard` | METER AFTER INSERT, UPDATE | Status ACTIVE requires the 3 meter certificates APPROVED (template T5) | 51004 | §2.3 p.8 |
| TR05 | `tr_WORK_ORDER_technician_guard` | WORK_ORDER AFTER INSERT, UPDATE | If technician_user_id is set: that user must have role TECHNICIAN, approval_status APPROVED, is_active = 1 | 51005 | §2.1 p.7 "δεν μπορεί να εκτελεί εργασίες πριν εγκριθεί" |
| TR06 | `tr_PAYMENT_bill_status` | PAYMENT AFTER INSERT, UPDATE | For each affected bill: compute paid = `fn_BillPaid`. Reject if paid > amount (overpayment). Set status `PAID` if paid = amount, `PARTIALLY_PAID` if 0 < paid < amount (an OVERDUE bill becomes PAID only when fully paid). This is lab 10's `tr_ORDER_TOTAL` pattern. | 51006 | §1.3 p.6 (several payments per bill) |
| TR07 | `tr_PREMISE_guard` | PREMISE AFTER INSERT, UPDATE | user_id must be a CONSUMER; supplier_org_id must be an ORGANIZATION of type SUPPLIER; aggregator_org_id of type AGGREGATOR | 51007 | §1.1 p.5; §II.Ε p.4 |
| TR08 | `tr_METER_transformer_guard` | METER AFTER INSERT, UPDATE | transformer_id must point to a level-1 transformer | 51008 | §4.1 p.9 "συνδέεται με ... μετασχηματιστή χαμηλής τάσης" |
| TR09 | `tr_TRANSFORMER_tree_guard` | TRANSFORMER AFTER INSERT, UPDATE | **Cursor over `inserted`**: (a) if a parent exists, `parent.level = level + 1`; (b) walk up from the parent with a WHILE loop; finding the row's own id means a cycle. Also reject an UPDATE of `level` on a transformer that has meters (meters require level 1). | 51009 | §4.1 p.9 tree |
| TR10 | `tr_USER_ACCOUNT_audit` | USER_ACCOUNT AFTER INSERT, UPDATE | Log REGISTER on insert; log changes of approval_status, is_active, role_code (old/new), and ANONYMIZE when anonymized_at is set. Never log password values. | — | §2.1 p.7 "μεταβολές της κατάστασης ... να καταγράφονται"; §1.4 p.6 |
| TR11 | `tr_USER_ACCOUNT_no_delete` | USER_ACCOUNT AFTER DELETE | Always reject: users are anonymized, never deleted | 51010 | §1.4 p.6 (bills and payments must keep their user) |
| TR12 | `tr_DOCUMENT_audit` | DOCUMENT AFTER INSERT, UPDATE | Log UPLOAD and approval_status changes (object_type 'DOCUMENT') | — | Κοινές αρχές p.5: officers record their check results |
| TR13 | `tr_METER_audit` | METER AFTER INSERT, UPDATE | Log INSTALL; status changes; and **technical data changes** of firmware_version, communication_type, meter_type_id, transformer_id, retention_months (one row per changed column, old → new) | — | Κοινές αρχές p.5 "μεταβολή τεχνικών στοιχείων" |
| TR14 | `tr_WORK_ORDER_audit` | WORK_ORDER AFTER INSERT, UPDATE | Template T6: CREATE and every status change; also log a change of technician_user_id (ASSIGN / UNASSIGN) | — | §1.3 p.6 "το αίτημα αποκτά κατάσταση και ιστορικό"; §2.2 p.7 |
| TR15 | `tr_REMOTE_COMMAND_audit` | REMOTE_COMMAND AFTER INSERT, UPDATE | Log CREATE, every status change, and **every attempt** (when attempt_count increases: action 'COMMAND_ATTEMPT', comment 'attempt n') | — | §2.4 p.8 "διαδοχικές προσπάθειες ... μέχρι ACK" |
| TR16 | `tr_REMOTE_COMMAND_guard` | REMOTE_COMMAND AFTER INSERT | The target meter must be ACTIVE | 51011 | §2.4 p.8 |
| TR17 | `tr_GDPR_REQUEST_audit` | GDPR_REQUEST AFTER INSERT, UPDATE | Log SUBMIT and every status change; these rows are the four review stages | — | §1.4 p.6 "καταγραφή σε log ... σε κάθε στάδιο" |
| TR18 | `tr_METER_READING_edit_audit` | METER_READING AFTER UPDATE | For rows whose status became EDITED or changed from SUSPECT: log object 'METER_READING', old value → new value, vee_rule, edited_by. (Automatic VALID results are not logged one by one; the reading row itself keeps status and rule. `sp_RunVEE` writes one summary row per run.) | — | §3.2 p.9 "αρχική τιμή, διορθωμένη τιμή, προέλευση" |
| TR19 | `tr_TELEMETRY_PACKET_failure_event` | TELEMETRY_PACKET AFTER INSERT | For every packet with match_status ≠ MATCHED, insert EVENT `PACKET_<status>` (WARNING) with packet_id | — | §3.1 p.8 |
| TR20 | `tr_EVENT_work_order` | EVENT AFTER INSERT | For CRITICAL events of type TAMPER_ALERT with a meter_id: create WORK_ORDER (ANTI_TAMPER, origin EVENT, status SUBMITTED, meter and its premise, event_id). requested_by_user_id = the session actor, or the first SYSTEM_ADMIN if there is none. | — | §2.4 p.8 "να οδηγήσουν σε νέα εργασία πεδίου" |
| TR21 | `tr_AGGREGATE_threshold_alert` | AGGREGATE AFTER INSERT | For new DAY rows with obis 1.8.0 and a meter: month-to-date = SUM of that meter's DAY 1.8.0 aggregates in the month. If it exceeds the premise's monthly_threshold_kwh and no THRESHOLD_EXCEEDED event exists for that meter this month, insert an EVENT (INFO). PHP then emails or texts the consumer according to notify_email / notify_sms. | — | §1.2 p.6 |
| TR22 | `tr_BILL_PAYMENT_no_delete` | BILL and PAYMENT AFTER DELETE (two triggers) | Always reject: accounting data is kept | 51012 | §1.4 p.6 |

---

## 9. Stored procedure catalog (`procedures_*.sql`)

Each table below is one file. "Actor" lists the roles passed to `sp__AssertRole`. Unless a row says otherwise, parameters come after `@actor_user_id INT`. The UC numbers point to the use cases in the verification document (§15 maps them all).

### 9.0 Internal helpers (`procedures_00_internal.sql`) — never called by PHP

| Procedure | Parameters | Does |
|---|---|---|
| `sp__AssertRole` | `@user_id INT, @roles NVARCHAR(200)` | THROW 50002 unless `dbo.fn_UserHasRole(@user_id, @roles) = 1` (handles the `TECHNICIAN_ANY` exception of §3.1) |
| `sp__SetActor` | `@user_id INT, @mechanism VARCHAR(60)` | Sets `SESSION_CONTEXT` keys `actor_user_id` and `mechanism` |
| `sp__Log` | `@action, @object_type, @object_id, @old, @new, @comment` | INSERT into AUDIT_LOG using the session actor (for logs that no trigger writes, for example LOGIN, VEE_RUN, TREE_REFRESH) |
| `sp__NewUser` | `@email, @password, @full_name, @phone, @role_code, @approval_status, @organization_id = NULL, @birth_date = NULL, @photo_path = NULL, @specialty = NULL, @iban = NULL, @new_id INT OUTPUT` | Validates the email format and uniqueness (50005), and the password length (≥ 8, 50004); creates the salt with `CRYPT_GEN_RANDOM(16)`; stores `fn_HashPassword`; inserts the row. Used by every registration procedure. |
| `sp__WalkTransformerTree` | `@parent_id INT, @depth INT` | Template T4 (recursive cursor into `#Tree`) |
| `sp__SumSubtree` | `@transformer_id INT, @obis VARCHAR(20)` | Recursive cursor in post-order: first calls itself for each child, then sets this node's row in `#State` = own meters' sum (from `#Leaf`) + SUM of children rows in `#State` |
| `sp__EstimateGaps` | `@meter_id INT, @from DATETIME2(0), @to DATETIME2(0)` | Gap estimation of Algorithm B (cursor over the missing slots); kept separate so that `tests.sql` can test it alone |
| `sp__PurgeMeter` | `@meter_id INT, @keep_months TINYINT` | Deletes that meter's raw readings older than the cut-off, in `TOP (5000)` batches, only for days that already have a final DAY aggregate |

### 9.1 Accounts, login and staff (`procedures_01_accounts.sql`)

| Procedure | Actor | Parameters | Rules and steps | Spec / UC |
|---|---|---|---|---|
| `sp_BootstrapAdmin` | none | `@email, @password, @full_name` | Works **only** while no SYSTEM_ADMIN exists; creates the root user | Κοινές αρχές p.5 "ο ΔΣ ... χειρωνακτικά" |
| `sp_Login` | none | `@email, @password` | Finds the user; compares `fn_HashPassword(@password, password_salt)` with password_hash; requires is_active = 1 and anonymized_at IS NULL; otherwise THROW 50006 (same message for every failure). Logs LOGIN_OK (actor = the user) or LOGIN_FAIL (actor_type SYSTEM, mechanism 'LOGIN', the attempted email not stored) through `sp__Log`. Returns user_id, role_code, full_name, approval_status, organization_id. | Κοινές αρχές p.5; §IV p.12 |
| `sp_ChangePassword` | any | `@old_password, @new_password` | Checks the old hash, then sets a new salt and hash | Κοινές αρχές p.5 |
| `sp_RegisterConsumer` | none (self-registration) | `@email, @password, @full_name, @phone, @iban, @notify_email BIT, @notify_sms BIT` | `sp__NewUser` with CONSUMER, APPROVED. Returns user_id. | §1.1 p.5 "χωρίς προέγκριση"; UC-01 |
| `sp_RegisterTechnician` | none | `@email, @password, @full_name, @phone, @birth_date, @photo_path, @specialty` | CONSUMER rules plus: age ≥ 18 (50004); creates TECHNICIAN with **PENDING**. Documents and availability are added next with the procedures below. | §2.1 p.7; UC-09 |
| `sp_UpdateMyProfile` | any | `@full_name, @phone, @iban, @notify_email, @notify_sms` | Updates own row. IBAN and notify flags for consumers only (the CHECKs enforce this). | §1.1 p.5, §1.2 p.6 |
| `sp_GetMyProfile` | any | — | Own row from the matching `view_...`, without hash or salt | §1.1 |
| `sp_CreateStaffUser` | SYSTEM_ADMIN | `@email, @password, @full_name, @phone, @role_code` | role_code ∈ {SYSTEM_OFFICER, DSO, TSO}; APPROVED | Κοινές αρχές p.5 "ΛΣ δημιουργούνται από ΔΣ"; UC-20 |
| `sp_CreateOrganization` | SYSTEM_ADMIN, SYSTEM_OFFICER | `@name, @org_type` | Inserts ORGANIZATION | §II.Ε p.3-4, §5.1 p.10 |
| `sp_CreateOrganizationUser` | SYSTEM_ADMIN, SYSTEM_OFFICER | `@organization_id, @email, @password, @full_name, @phone` | role_code = org_type of the organization; APPROVED | §5.1 p.10 |
| `sp_SetUserActive` | SYSTEM_ADMIN | `@user_id, @is_active BIT` | Cannot deactivate the last active admin (50003) | [AR] account management |
| `sp_ListUsers` | SYSTEM_ADMIN, SYSTEM_OFFICER | `@role_code = NULL, @approval_status = NULL, @search = NULL, @page, @page_size` | Paged list without hash or salt | Κοινές αρχές p.5 |
| `sp_AddTechnicianDocument` | TECHNICIAN_ANY (self) | `@doc_type, @doc_code, @issue_date, @expiry_date, @file_path` | doc_type ∈ the 3 technician types; expiry ≥ issue; PENDING | §2.1 p.7; UC-09 |
| `sp_ResubmitDocument` | TECHNICIAN_ANY (owner) | `@document_id, @file_path, @issue_date, @expiry_date` | Only when REJECTED → PENDING | §2.1 p.7 |
| `sp_DecideDocument` | SYSTEM_OFFICER | `@document_id, @decision ('APPROVED'/'REJECTED'), @comment` | Guarded UPDATE `WHERE approval_status = 'PENDING'`; the comment goes into AUDIT_LOG through `sp__Log` | Κοινές αρχές p.5; T-05; UC-09, UC-10 |
| `sp_ListPendingTechnicians` | SYSTEM_OFFICER | `@page, @page_size` | PENDING technicians with a count of their documents per status | §2.1 p.7 |
| `sp_DecideTechnician` | SYSTEM_OFFICER | `@technician_user_id, @decision ('APPROVED','REJECTED','SUSPENDED'), @comment` | APPROVED requires all 3 technician documents APPROVED and not expired (50004); follows the state machine | §2.1 p.7; UC-09 |
| `sp_ResubmitTechnician` | TECHNICIAN_ANY (self) | — | REJECTED → PENDING after new documents | §2.1 p.7 |
| `sp_SetAvailability` | TECHNICIAN_ANY (self) | `@avail_date, @start_time, @end_time, @district` | Upsert of one slot (PK user, date, start); the date is today or later; no overlap with the technician's other slots that day (50004) | §2.1 p.7 "ημερήσια χρονική και γεωγραφική διαθεσιμότητα" |
| `sp_DeleteAvailability` | TECHNICIAN_ANY (self) | `@avail_date, @start_time` | Deletes the slot | §2.1 |
| `sp_GetMyAvailability` | TECHNICIAN_ANY | `@from DATE, @to DATE` | Own slots | §2.1 |
| `sp_FindAvailableTechnicians` | SYSTEM_OFFICER | `@date, @start_time, @end_time, @district, @specialty = NULL` | APPROVED technicians with a slot that covers the time in that district, the requested specialty first, and no other ASSIGNED/ACCEPTED job overlapping that time | §1.3 p.6 "κατάλληλο Τεχνικό"; §2.1 |

### 9.2 Premises and consumption (`procedures_02_consumer.sql`)

| Procedure | Actor | Parameters | Rules and steps | Spec / UC |
|---|---|---|---|---|
| `sp_AddPremise` | CONSUMER | `@address, @latitude, @longitude, @usage_type, @district, @municipality, @parish, @postal_code, @prosumer_scheme = 'NONE', @supplier_org_id = NULL` | Inserts with user_id = actor (one consumer, many premises) | §1.1 p.5; UC-01 |
| `sp_UpdatePremise` | CONSUMER (owner) | same as above + `@premise_id` | Owner only (50002) | §1.1 |
| `sp_ChangeSupplier` | CONSUMER (owner) | `@premise_id, @supplier_org_id` | Supplier choice; old bills keep the old supplier | §II.Ε p.4 |
| `sp_SetPremiseAggregator` | CONSUMER (owner) | `@premise_id, @aggregator_org_id NULL` | Joins or leaves an aggregator's portfolio | §5.1 p.10 |
| `sp_SetPremiseThreshold` | CONSUMER (owner) | `@premise_id, @monthly_threshold_kwh NULL` | > 0, or NULL to switch it off | §1.2 p.6; UC-04 |
| `sp_ListMyPremises` | CONSUMER | — | From `view_PREMISE_METER` for the actor | §1.1 |
| `sp_GetPremiseReadings` | CONSUMER (owner); DSO, SYSTEM_OFFICER (any premise) | `@premise_id, @from, @to, @obis_list NVARCHAR(200) = '1.8.0,2.8.0'` | For a consumer, every meter of the premise in the window (including replaced meters, so history survives) must pass `fn_CanViewReadings`; otherwise 50008. Returns the 15-min series: timestamp, obis, delta_value as energy, value, status. 2.8.0 is included only for prosumers. Window ≤ 31 days per call [AR: response time]. | §1.2 p.5-6; UC-02 |
| `sp_GetPremiseAggregates` | same | `@premise_id, @period_type ('DAY','MONTH','YEAR'), @from, @to` | Final meter aggregates of the premise's meters; the same access rule as readings (aggregates do not change who may see what) | §1.2 p.6 last paragraph; UC-03 |
| `sp_GetPremiseEvents` | CONSUMER (owner) | `@premise_id, @from, @to` | Voltage and threshold events of the premise's meters | §1.2 p.5 "υπόταση ή υπέρταση"; UC-02 |
| `sp_GetHistoricalAccessQuote` | CONSUMER (owner) | `@meter_id, @access_from DATE, @access_to DATE` | Months × HISTORICAL_ACCESS fee; also returns the earliest date still kept (retention) | §1.2 p.6 |
| `sp_BuyHistoricalAccess` | CONSUMER (owner) | `@meter_id, @access_from, @access_to, @method, @transaction_reference = NULL` | The window must lie before the current month and within retention (50008); amount = quote; inserts a PAYMENT with service_type_id, access_meter_id, access_from, access_to; status COMPLETED | §1.2 p.6; UC-03 |
| `sp_CheckConsumptionThresholds` | SYSTEM_OFFICER (job) | `@as_of DATE = NULL` | **Cursor** over premises with a threshold: month-to-date import from final DAY aggregates plus today's non-final readings; raises THRESHOLD_EXCEEDED once per meter per month. Complements TR21 for the current, not yet finalized day. | §1.2 p.6; UC-04 |

### 9.3 Requests and work orders (`procedures_03_workorders.sql`)

| Procedure | Actor | Parameters | Rules and steps | Spec / UC |
|---|---|---|---|---|
| `sp_SubmitServiceRequest` | CONSUMER | `@premise_id, @meter_id = NULL, @work_type ('TECHNICAL_CHECK','FAULT_REPAIR'), @description` | Owner of the premise; WORK_ORDER SUBMITTED, origin CONSUMER_REQUEST; service_type_id = METER_CHECK for TECHNICAL_CHECK | §1.3 p.6; UC-05 |
| `sp_CreateWorkOrder` | SYSTEM_OFFICER, DSO | `@work_type, @premise_id, @meter_id, @event_id = NULL, @description, @scheduled_start = NULL, @scheduled_end = NULL` | origin OFFICER (or EVENT when @event_id is given). INSTALLATION needs a premise; REPLACEMENT and ANTI_TAMPER need a meter. | §2.2 p.7; UC-10, UC-14 |
| `sp_AssignWorkOrder` | SYSTEM_OFFICER | `@work_order_id, @technician_user_id, @scheduled_start, @scheduled_end` | Guarded `WHERE status = 'SUBMITTED'`; the technician must be returned by `sp_FindAvailableTechnicians` for that time and the premise's district (50004); → ASSIGNED (TR05 checks approval) | §1.3 p.6; §2.2 p.7; UC-05 |
| `sp_AcceptWorkOrder` | TECHNICIAN | `@work_order_id` | Template T2 → ACCEPTED, accepted_at | §2.2 p.7 "να αποδέχεται" |
| `sp_DeclineWorkOrder` | TECHNICIAN | `@work_order_id, @reason` | ASSIGNED → SUBMITTED, technician cleared; reason logged | §2.2 p.7 |
| `sp_StartWorkOrder` | TECHNICIAN | `@work_order_id` | ACCEPTED → IN_PROGRESS | §2.2 |
| `sp_CompleteWorkOrder` | TECHNICIAN | `@work_order_id, @findings, @evidence_path, @persons_to_notify` | IN_PROGRESS → COMPLETED, completed_at; findings required; persons_to_notify required for ANTI_TAMPER | §2.2 p.7; §2.4 p.8; UC-05, UC-14 |
| `sp_CancelWorkOrder` | CONSUMER (own request, still SUBMITTED), SYSTEM_OFFICER | `@work_order_id, @reason` | → CANCELLED | §1.3 |
| `sp_ListMyWorkOrders` | TECHNICIAN, CONSUMER | `@status = NULL, @page, @page_size` | Technician: own jobs from `view_OPEN_WORK_ORDER` **with meter / premise latitude and longitude**. Consumer: own requests. | §2.2 p.7 "να βλέπει τη γεωγραφική θέση"; §1.3 |
| `sp_ListWorkOrders` | SYSTEM_OFFICER, DSO | `@status, @work_type, @district, @page, @page_size` | Officer dashboard | §2.2 |
| `sp_GetWorkOrderHistory` | owner, assigned technician, SYSTEM_OFFICER | `@work_order_id` | The work order plus its AUDIT_LOG rows in time order | §1.3 p.6 "κατάσταση και ιστορικό" |

### 9.4 Meters (`procedures_04_meters.sql`)

| Procedure | Actor | Parameters | Rules and steps | Spec / UC |
|---|---|---|---|---|
| `sp_InstallMeter` | TECHNICIAN | `@work_order_id, @serial_number, @network_id, @firmware_version, @communication_type, @latitude, @longitude, @meter_type_id, @installation_photo, @transformer_id = NULL` | The work order is INSTALLATION, ACCEPTED or IN_PROGRESS, assigned to the actor. The premise must have no meter in service. transformer_id = @transformer_id or `fn_FindGeofence(lat, lon)` (50004 if neither). Inserts METER PENDING with installed_at = now and installed_by = actor; sets the work order's meter_id. Returns meter_id. | §2.3 p.7; §4.1 p.9; UC-10 |
| `sp_AddMeterDocument` | TECHNICIAN (installer) | `@meter_id, @doc_type, @doc_code, @issue_date, @expiry_date, @file_path` | One of the 3 meter certificate types; PENDING | §2.3 p.7; UC-10 |
| `sp_ConfirmMeter` | SYSTEM_OFFICER | `@meter_id, @decision ('APPROVE','REJECT'), @comment` | APPROVE: `PENDING → ACTIVE`, activated_at = now (TR04 checks the documents). REJECT: `→ INACTIVE`. The comment is logged. | §2.3 p.8 "επιβεβαιώνει ... μόνο μετά ... ενεργή"; UC-10 |
| `sp_ReplaceMeter` | TECHNICIAN | `@work_order_id, @old_meter_id, @serial_number, @network_id, @firmware_version, @communication_type, @latitude, @longitude, @meter_type_id, @installation_photo` | One transaction: old meter → REMOVED with removed_at = now (**first**, because of the one-meter-per-premise index), then the new meter PENDING on the same premise and transformer. The old meter's readings stay, so the premise's series continues. | §2.3 p.8; T-16; UC-11 |
| `sp_SetMeterStatus` | SYSTEM_OFFICER, DSO | `@meter_id, @status ('ACTIVE','INACTIVE','FAULTY'), @comment` | Follows the state machine | §2.3 |
| `sp_UpdateMeterTechnicalData` | TECHNICIAN (assigned job on this meter), SYSTEM_OFFICER | `@meter_id, @firmware_version, @communication_type, @meter_type_id` | TR13 logs each changed field | Κοινές αρχές p.5; §II.Β p.3 |
| `sp_GetMeter` | owner consumer, staff | `@meter_id` | Meter, its type, documents, transformer and premise | §2.3 |
| `sp_ListMeters` | staff | `@status, @transformer_id, @district, @page, @page_size` | From `view_METER_LOCATION` (also used for the Leaflet map) | §4.1 p.9; p.2 maps bonus |

### 9.5 Remote commands (`procedures_05_commands.sql`)

| Procedure | Actor | Parameters | Rules and steps | Spec / UC |
|---|---|---|---|---|
| `sp_RequestRemoteCommand` | TECHNICIAN, DSO, TSO, SYSTEM_OFFICER | `@meter_id, @command_type, @parameters = NULL` | Technician → PENDING_APPROVAL (needs an officer). DSO / TSO / officer → APPROVED immediately ("where the role allows"). FIRMWARE_UPGRADE needs `@parameters` = target version. | §2.4 p.8; UC-12 |
| `sp_DecideRemoteCommand` | SYSTEM_OFFICER | `@command_id, @decision ('APPROVED','REJECTED'), @comment` | Guarded `WHERE status = 'PENDING_APPROVAL'` | §2.4 p.8 "έγκριση"; UC-12 |
| `sp_DispatchCommands` | SYSTEM_OFFICER, DSO, TSO, SYSTEM_ADMIN | `@max_attempts SMALLINT = 3` | Template T3. **Cursor** over APPROVED or SENT commands: if attempt_count ≥ @max_attempts → FAILED + EVENT COMMAND_FAILED; else attempt_count + 1, last_attempt_at = now, status SENT, executed_by = actor. TR15 logs every attempt. In the demo, the device answers through `sp_AcknowledgeCommand`. | §2.4 p.8 "διαδοχικές προσπάθειες ... μέχρι ACK"; UC-12 |
| `sp_AcknowledgeCommand` | none (device; mechanism DEVICE) | `@network_id, @command_id, @result` | The command's meter must have this network_id; `SENT → ACKNOWLEDGED`, ack_at = now, result. For FIRMWARE_UPGRADE also sets METER.firmware_version (TR13 logs it). | §2.4 p.8 |
| `sp_ShedTransformerLoad` | TSO | `@transformer_id, @command_type ('DISCONNECT','RECONNECT'), @reason` | **Cursor** over ACTIVE meters whose transformer is in `fn_TransformerSubtree(@transformer_id)`; one APPROVED command per meter (requested_by = actor); one transaction for the whole set; returns the number of commands. Then `sp_DispatchCommands` sends them. | §II.Δ p.3 "remote shedding σε όλους τους μετρητές ... μετασχηματιστή"; S-08; UC-13 |
| `sp_ListCommands` | staff | `@status, @meter_id, @page, @page_size` | Commands plus their attempt history from AUDIT_LOG | §2.4 |

### 9.6 Ingestion, VEE and aggregates (`procedures_06_telemetry.sql`)

| Procedure | Actor | Parameters | Rules and steps | Spec / UC |
|---|---|---|---|---|
| `sp_IngestTelemetryPacket` | none (mechanism INGESTION) | `@payload NVARCHAR(4000)` | Algorithm A below | §3.1 p.8; Appendix p.15; UC-15 |
| `sp_IngestTelemetryBatch` | SYSTEM_OFFICER, DSO | `@payload_array NVARCHAR(MAX)` | **Cursor** over `OPENJSON(@payload_array)` elements → `sp_IngestTelemetryPacket` for each (each in its own transaction); returns counts per match_status | §3.1 |
| `sp_RaiseTamperEvent` | none (device) or DSO | `@network_id, @description` | EVENT TAMPER_ALERT, CRITICAL → TR20 creates the anti-tamper job | §2.4 p.8; UC-14 |
| `sp_RunVEE` | SYSTEM_OFFICER, DSO | `@from DATETIME2(0), @to DATETIME2(0), @meter_id INT = NULL` | Algorithm B below | §3.2 p.8-9; UC-16 |
| `sp_ListSuspectReadings` | SYSTEM_OFFICER, DSO | `@from, @to, @page, @page_size` | SUSPECT readings, with the previous and next values for context | §3.2 |
| `sp_AcceptSuspectReading` | SYSTEM_OFFICER, DSO | `@reading_id, @note` | `SUSPECT → VALID`, vee_note, edited_by = actor (TR18 logs it) | §3.2 |
| `sp_EditReading` | SYSTEM_OFFICER, DSO | `@reading_id, @new_value, @note` | Not final (TR01 enforces this too). original_value = value if still NULL; value = new; status EDITED; edited_by; vee_rule 'MANUAL_EDIT'. Recomputes delta_value of this reading and of the next one. | §3.2 p.9 "αρχική τιμή, διορθωμένη τιμή, προέλευση"; UC-16 |
| `sp_FinalizeReadings` | SYSTEM_OFFICER, DSO | `@day DATE, @meter_id INT = NULL` | Algorithm C below | §3.2 p.9; UC-16 |
| `sp_BuildTransformerAggregates` | SYSTEM_OFFICER, DSO, TSO | `@day DATE, @force BIT = 0` | Algorithm D below | §4.2 p.10 "ιστορικά aggregates ... immutable"; UC-17 |
| `sp_PurgeExpiredReadings` | SYSTEM_OFFICER (job) | — | `sp_getapplock 'PURGE'`. **Cursor** over meters → `sp__PurgeMeter @meter_id, retention_months`. Then deletes MATCHED packets that no reading or event references any more and that are older than the meter's retention. Transformer readings are never purged. Returns rows deleted. | §1.4 p.6-7 (3 years, or 1 month after GDPR; aggregates stay; transformer data kept forever); UC-08 |

**Algorithm A — `sp_IngestTelemetryPacket`** (§3.1 p.8, Appendix p.15)

1. `EXEC sp__SetActor NULL, 'INGESTION'`.
2. If `ISJSON(@payload) = 0`, or `$.Meter_Network_ID` or `$.Transmission_Timestamp` is missing or unparsable: insert TELEMETRY_PACKET with match_status `COMM_ERROR`, meter_network_id = the value or 'UNKNOWN', transmission_timestamp = now, and raw_payload = `(SELECT @payload AS raw FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)` so the ISJSON CHECK passes. TR19 raises the event. Return.
3. Parse with `JSON_VALUE`: network id; timestamp via `TRY_CONVERT(DATETIMEOFFSET, ...)` converted to UTC `DATETIME2(0)`; `$.Network_Type`; `$.Cell_Signal_Strength_dBm`.
4. Look up the meter by network_id: ACTIVE → `MATCHED`; exists but not ACTIVE → `QUARANTINED`; none → `UNMATCHED`.
5. `BEGIN TRANSACTION`; insert the packet. If MATCHED:
   * `@slot = dbo.fn_Floor15(@ts)`.
   * Read the pairs with `OPENJSON(@payload, '$.Telemetry_Payload') WITH (obis VARCHAR(20) '$.obis', [value] DECIMAL(18,4) '$.value', unit VARCHAR(10) '$.unit')` into `#pairs`.
   * Codes not in OBIS_CODE → one EVENT `UNSUPPORTED_OBIS` listing them; they are not stored.
   * A unit that differs from OBIS_CODE.unit → stored with status SUSPECT and vee_rule `UNIT_MISMATCH`.
   * Pairs whose (meter, obis, slot) already exists → one EVENT `DUPLICATE_READING`; skipped.
   * Insert the rest as PENDING with packet_id. For CUMULATIVE codes, delta_value = value − the value of the same meter and code at `@slot − 15 min` (NULL when there is no previous reading). If a later slot already exists (a late packet) and is not final, recompute that reading's delta too.
   * For 32.7.0 / 52.7.0 / 72.7.0: value < 207 → EVENT VOLTAGE_SAG; value > 253 → VOLTAGE_SWELL (230 V ±10 %).
6. `COMMIT`. Return packet_id, match_status, readings_inserted.

Note: a packet does not have to contain every code ("δεν παρέχονται τιμές για κάθε κωδικό"), so missing pairs are not errors.

**Algorithm B — `sp_RunVEE`** (§3.2 p.8-9)

**Cursor** over the meters that have PENDING readings in [@from, @to]. For each meter: `sp_getapplock 'VEE_<meter_id>'`, then one short transaction:

1. **Range** — the value is outside OBIS_CODE valid_min / valid_max → SUSPECT, vee_rule `RANGE`.
2. **Negative delta** on a CUMULATIVE register (the counter went down) → SUSPECT, `NEGATIVE_DELTA`.
3. **Spike** — for CUMULATIVE codes: delta > 5 × the average of the previous 4 non-suspect deltas **and** delta > 1 kWh → SUSPECT, `SPIKE`. The spec's example 1.8, 2.0, 1.9, **25.4** must be flagged.
4. **Over capacity** — the delta of 1.8.0 > max_amps × 230 V × connection_phases × 0.25 h / 1000 (kWh possible in 15 minutes for this meter type) → SUSPECT, `OVER_CAPACITY`.
5. **Gaps** — `EXEC sp__EstimateGaps @meter_id, @from, @to` (below).
6. Every remaining PENDING reading → VALID, vee_rule `AUTO`.
7. `sp__Log 'VEE_RUN'` with counts (valid, suspect, estimated) for this meter.

`sp__EstimateGaps @meter_id, @from, @to` (internal helper, §9.0): for each CUMULATIVE code the meter reports, build the expected 15-min slots of the window with a numbers table (`GENERATE_SERIES` on SQL 2022+, or a tally CTE). **Cursor** over the missing slots that have a reading before them (t_a, R_a) and after them (t_b, R_b). Insert an ESTIMATED reading with packet_id NULL, value = `R_a + (R_b − R_a) × (t − t_a) / (t_b − t_a)` (linear interpolation, as in the spec's 2.0 / ? / 2.2 → 2.1 example), vee_rule `LINEAR_INTERPOLATION`. Then recompute the deltas of the estimated slots and of the reading at t_b. Slots with no reading on one side (the edge of the window) are left for a later run.

**Algorithm C — `sp_FinalizeReadings`** (§3.2 p.9: after VEE the readings are immutable, and finalization triggers the aggregates)

1. Meter-days to finalize = (meter, @day) where the meter has **no PENDING or SUSPECT** readings that day and has 96 slots of 1.8.0 (measured or estimated). Report the meter-days that were skipped and why.
2. One transaction per meter-day: set `is_final = 1, finalized_at = now` on that day's VALID / ESTIMATED / EDITED readings. Then insert **final DAY aggregates** (is_final = 1) for every CUMULATIVE code: value = SUM(delta_value), sample_count = number of readings.
3. If @day is the last day of its month and every day of that month has a final DAY aggregate for the meter → insert the MONTH aggregate (SUM of the DAY rows). Same for YEAR on 31 December.
4. TR21 checks the consumption thresholds when the DAY rows are inserted.

**Algorithm D — `sp_BuildTransformerAggregates`** (§4.2 p.10)

1. Unless @force = 1, stop with 50003 if any ACTIVE meter under a level-1 transformer still has non-final readings on @day.
2. In `#temp`: for every level-1 transformer and each code 1.8.0 and 2.8.0, per 15-min slot, SUM(delta_value) of the **final** readings of its meters, plus the number of meters.
3. Roll up to every ancestor (join with `fn_TransformerAncestors`, or the recursive `sp__SumSubtree`).
4. One transaction: insert final QUARTER_HOUR and DAY aggregates for every transformer (transformer_id set, meter_id NULL). They are immutable from then on (TR02). Build MONTH and YEAR rows the same way as in Algorithm C.

### 9.7 Grid, TSO and DSO analytics (`procedures_07_grid.sql`)

| Procedure | Actor | Parameters | Rules and steps | Spec / UC |
|---|---|---|---|---|
| `sp_UpsertTransformer` | TSO | `@transformer_id NULL, @name, @level, @capacity_kva, @latitude, @longitude, @min_lat, @min_lon, @max_lat, @max_lon, @parent_transformer_id` | Insert or update; TR09 checks levels and cycles. A child's rectangle must lie inside its parent's rectangle when both exist (50004). | §4.1 p.9; G-01 – G-07 |
| `sp_GetTransformerTree` | TSO, DSO, SYSTEM_OFFICER | `@root_id` | Creates `#Tree`, inserts the root (depth 0), calls `sp__WalkTransformerTree @root_id, 1` (**recursive cursor**, template T4), then returns `#Tree` with each node's current-state sums and its number of meters | §4.1 p.9; lab 10 Hogwarts_Tree; UC-17 |
| `sp_FindGeofenceForPoint` | staff | `@latitude, @longitude` | `fn_FindGeofence`, plus that transformer's ancestors (the L2 … Ln geofences) | §4.1 p.9 |
| `sp_RefreshTransformerState` | TSO, DSO | `@reference_15_min DATETIME2(0) = NULL` | Algorithm E below | §4.2 p.10 "χειροκίνητα από εξουσιοδοτημένο χρήστη"; UC-17 |
| `sp_RefreshTransformerAncestors` | TSO, DSO | `@transformer_id, @reference_15_min` | Recomputes one level-1 node and then walks up its parents with a WHILE loop (each parent = SUM of its children's rows) — the "a reading affects an L1 geofence and its ancestors" path | §4.2 p.10 |
| `sp_GetTransformerState` | TSO, DSO | `@root_id = NULL, @level = NULL` | TRANSFORMER_CURRENT_STATE rows with name, level, load % = (1.8.0 kWh × 4) / capacity_kva × 100, and the latest 14.7.0 frequency | §II.Δ p.3; §4.2; UC-17 |
| `sp_RecordTransformerReading` | none (grid equipment; mechanism DEVICE), DSO | `@transformer_id, @reading_timestamp, @obis_code, @value` | Insert at fn_Floor15. For 1.8.0 / 2.8.0 the value is the energy of the 15-min slot. For 14.7.0, a deviation > 0.2 Hz from 50 Hz → EVENT FREQUENCY_DEVIATION (CRITICAL). | §II.Δ p.3; §1.4 p.7 (kept forever) |
| `sp_ReportVoltageEvents` | DSO | `@root_transformer_id, @from, @to` | Sags and swells per meter and transformer in the subtree (events plus readings outside 207–253 V) | §II.Γ p.3 "βυθίσεις και υπερτάσεις"; UC-19 |
| `sp_ReportPhaseUnbalance` | DSO | `@root_transformer_id, @from, @to, @threshold_pct = 20, @raise_events BIT = 0` | Three-phase meters: per slot, unbalance % = (max − min) / avg × 100 of 31.7.0 / 51.7.0 / 71.7.0; lists slots above the threshold | §II.Γ p.3; Appendix p.15 (phase currents); UC-19 |
| `sp_ReportTechnicalLosses` | DSO | `@transformer_id (level 1), @from, @to, @raise_events BIT = 0` | Input = SUM of TRANSFORMER_READING 1.8.0 in the window. Delivered = SUM of the meters' 1.8.0 deltas − 2.8.0 deltas. Loss = input − delivered; loss % = loss / input. Flags loss % > 8 % as a possible non-technical loss (theft), together with the TAMPER_ALERT events under that transformer. | §II.Γ p.3 "τεχνικών απωλειών ... ρευματοκλοπή"; UC-19 |
| `sp_GetGridOverview` | TSO | `@reference_15_min = NULL` | One row per transformer: current sums, load %, overload flag (> 100 %), latest frequency, open CRITICAL events | §II.Δ p.3 "ανά 15 λεπτά συγκεντρωτική εικόνα" |

**Algorithm E — `sp_RefreshTransformerState`** (§4.2 p.10)

1. `sp_getapplock 'TREE_REFRESH'`. @ref = the given slot, or the latest slot that has VEE-verified readings.
2. Outside any transaction, build `#Leaf (transformer_id, obis_code, sum_value, meter_count)` set-based: for each level-1 transformer and each code 1.8.0 and 2.8.0, SUM(delta_value) and COUNT(DISTINCT meter) of readings at @ref with status IN ('VALID','ESTIMATED','EDITED') ("VEE-verified"). Missing readings are simply ignored, as the spec says.
3. Create `#State`; for each root (parent NULL) call `sp__SumSubtree @root, @obis` — a **recursive cursor** in post-order (children first, then the node = own `#Leaf` + SUM of the children in `#State`). This gives the sums of **every** level (L1 … Ln), "regardless of depth".
4. One short transaction: `MERGE` `#State` into TRANSFORMER_CURRENT_STATE on (transformer_id, obis_code), setting reference_15_min = @ref (the same for everyone), sum_value, meter_count, computed_at. `sp__Log 'TREE_REFRESH'`.

### 9.8 Billing and payments (`procedures_08_billing.sql`)

| Procedure | Actor | Parameters | Rules and steps | Spec / UC |
|---|---|---|---|---|
| `sp_UpsertTariff` | SYSTEM_OFFICER | `@tariff_id NULL, @tariff_name, @rate, @valid_from, @valid_to` | No overlapping periods for the same tariff_name (50004) | Κοινές αρχές p.5 "τύπους ... τιμολογίων"; UC-20 |
| `sp_IssueMonthlyBills` | SUPPLIER (own organization), SYSTEM_OFFICER | `@year INT, @month INT, @supplier_org_id NULL` | `sp_getapplock 'BILL_RUN'`. **Cursor** over the premises of the supplier with no bill for that month yet. For each, one transaction: import = SUM of the final MONTH 1.8.0 aggregates of all meters of the premise (including a meter replaced that month); export = the same for 2.8.0. Billable kWh: NONE → import; NET_METERING or NET_BILLING → max(import − export, 0) [AR: the spec does not ask for a pricing algorithm, §1.3 p.6]. tariff = `fn_ActiveTariff(first day of month)`; amount = kWh × rate; issue_date = today; due_date = +30 days; ISSUED. Premises without final MONTH aggregates are skipped and listed. | §1.3 p.6; §1.2 p.5 net metering / billing; UC-06 |
| `sp_PayBill` | CONSUMER (bill's user) | `@bill_id, @amount, @method, @transaction_reference = NULL` | Bill not CANCELLED or PAID; read with `UPDLOCK, HOLDLOCK`; amount ≤ remaining (50004); inserts PAYMENT COMPLETED; TR06 updates the bill status. Several payments per bill are allowed (instalments). | §1.3 p.6; UC-06 |
| `sp_PayServiceFee` | CONSUMER | `@service_type_id, @amount, @method, @transaction_reference = NULL` | For fees such as METER_CHECK; the amount must equal the fee | §1.3 p.6 "τέλος υπηρεσίας MDMS-Cy" |
| `sp_MarkOverdueBills` | SYSTEM_OFFICER (job) | `@as_of DATE = NULL` | **Cursor** over ISSUED / PARTIALLY_PAID bills past their due date → OVERDUE (audited) | §1.3 |
| `sp_CancelBill` | SYSTEM_OFFICER | `@bill_id, @reason` | Only ISSUED with no payments | §1.3 |
| `sp_GetMyBillsAndPayments` | CONSUMER | `@from DATE = NULL, @to DATE = NULL` | Two result sets: bills from `view_BILL_BALANCE` and the user's payments (bills, services and history access) | §1.3 p.6 "ιστορικό χρεώσεων και πληρωμών"; UC-06 |
| `sp_ListSupplierBills` | SUPPLIER (own organization), SYSTEM_OFFICER | `@status, @year, @month, @page, @page_size` | Bills of the supplier with their balance | §1.3 |

### 9.9 GDPR (`procedures_09_gdpr.sql`)

| Procedure | Actor | Parameters | Rules and steps | Spec / UC |
|---|---|---|---|---|
| `sp_SubmitGdprRequest` | CONSUMER | `@request_type, @meter_id = NULL` | RETENTION_REDUCTION needs a meter on one of the user's premises; no second open request of the same type | §1.4 p.6-7; UC-07, UC-08 |
| `sp_AdvanceGdprRequest` | SYSTEM_OFFICER | `@gdpr_request_id, @new_status ('UNDER_REVIEW','PRE_APPROVED','APPROVED','REJECTED'), @comment` | Guarded UPDATE that follows the state machine exactly; decided_at on APPROVED / REJECTED; the APPROVED officer ≠ the PRE_APPROVED officer (looked up in AUDIT_LOG; 50002) | §1.4 p.6 "υποβολής, εξέτασης, προέγκρισης και τελικής έγκρισης"; UC-07 |
| `sp_ExecuteGdprRequest` | SYSTEM_OFFICER | `@gdpr_request_id` | Only APPROVED. One transaction (algorithm F) → EXECUTED | §1.4 p.6-7; UC-07, UC-08 |
| `sp_ListGdprRequests` | SYSTEM_OFFICER; CONSUMER (own) | `@status, @page, @page_size` | With stage history from AUDIT_LOG | §1.4 |

**Algorithm F — executing a GDPR request**

* **RETENTION_REDUCTION:** `METER.retention_months = 1` (TR13 logs it), then `sp__PurgeMeter @meter_id, 1`. Aggregates stay.
* **RIGHT_TO_BE_FORGOTTEN:**
  1. Anonymize USER_ACCOUNT: email = `'forgotten_' + user_id + '@anon.invalid'`; full_name = `N'FORGOTTEN USER'`; phone, iban = NULL; new random salt and hash (no one can log in); notify flags = 0; is_active = 0; anonymized_at = now (TR10 logs ANONYMIZE).
  2. For every meter on the user's premises: retention_months = 1 and `sp__PurgeMeter` (the detailed 15-min data reveals activity patterns, §1.4 p.6).
  3. PREMISE.monthly_threshold_kwh = NULL.
  4. Kept on purpose: BILL, PAYMENT (accounting), aggregates, EVENT, AUDIT_LOG, and the premise row (it now points to an anonymous user).

### 9.10 Market data for suppliers and aggregators (`procedures_10_market.sql`)

The actor's organization comes from USER_ACCOUNT.organization_id, **never from a parameter**. A supplier sees only premises with `supplier_org_id` = their organization; an aggregator only those with `aggregator_org_id` = theirs. There is no access to raw rows of individual meters. [AR: groups with fewer than 3 meters are suppressed, so no single household can be singled out — supports §1.4 p.6 "να προτιμώνται συγκεντρωτικά δεδομένα".]

| Procedure | Actor | Parameters | Rules and steps | Spec / UC |
|---|---|---|---|---|
| `sp_GetDayAheadAggregates` | SUPPLIER, AGGREGATOR | `@from DATE, @to DATE, @group_level TINYINT = 1, @root_transformer_id = NULL` | From **final DAY aggregates** of the organization's meters, grouped per day and per transformer at @group_level (the meter's ancestor at that level, via `fn_TransformerAncestors`): import (1.8.0), export (2.8.0), net = import − export, meter_count | §5.1 p.10-11; §5.2 p.11 Day-Ahead "σε ημερήσια ... μορφή ... επικυρωμένα"; UC-18 |
| `sp_GetIntradayProvisional` | SUPPLIER, AGGREGATOR | `@from DATETIME2(0), @to DATETIME2(0), @group_level TINYINT = 1` | From **METER_READING directly**, before VEE is complete (any status except SUSPECT; window ≤ 24 h): per 15-min slot and transformer, import, export, net, meter_count, `is_provisional = 1` | §5.2 p.11 Intraday "χωρίς ... ολοκλήρωση ... VEE"; UC-18 |
| `sp_GetPortfolioSummary` | AGGREGATOR, SUPPLIER | — | Number of customers and prosumers, schemes, installed meters per district | §5.1 p.10 |

### 9.11 Reference data, audit and reports (`procedures_11_admin.sql`)

| Procedure | Actor | Parameters | Rules and steps | Spec / UC |
|---|---|---|---|---|
| `sp_UpsertMeterType` | SYSTEM_OFFICER | `@meter_type_id NULL, @type_name, @connection_phases, @max_amps` | New meter types are rows, not schema changes | Κοινές αρχές p.5 "πρότυπα μετρητών"; §IV p.13 future extension; UC-20 |
| `sp_UpsertServiceType` | SYSTEM_OFFICER | `@service_type_id NULL, @service_name, @fee, @is_active` | The seeded names `HISTORICAL_ACCESS` and `METER_CHECK` cannot be renamed | Κοινές αρχές p.5 "τύπους υπηρεσιών"; UC-20 |
| `sp_UpsertObisCode` | SYSTEM_OFFICER | `@obis_code, @description, @unit, @measurement_kind, @valid_min, @valid_max` | New measured quantities without a schema change | §3.1 p.8 "μελλοντική προσθήκη νέων τύπων/κωδικών"; §IV p.13 |
| `sp_GetAuditLog` | SYSTEM_ADMIN, SYSTEM_OFFICER, DSO | `@object_type = NULL, @object_id = NULL, @user_id = NULL, @from, @to, @page, @page_size` | Paged trail | Κοινές αρχές p.5 |
| `sp_GetEvents` | SYSTEM_OFFICER, DSO, TSO | `@event_type, @severity, @from, @to, @page, @page_size` | Event log | §2.4 p.8 "Event Log" |
| `sp_ReportSystemStatistics` | SYSTEM_ADMIN, SYSTEM_OFFICER | `@from, @to` | Management report (OLAP): meters per status and district, readings per status, VEE rates, consumption per month and district, revenue per supplier | p.2 "αναφορών στην διοίκηση" (analytic scenarios) |

---

## 10. Indexes (`indexes.sql`)

The PDF asks for the **three most important indexes, documented**: which index, why, and how it was created; plus at least one measured before/after case (§IV p.12). Build all of them; document the first three in detail.

| # | Index | Definition | Serves | Spec |
|---|---|---|---|---|
| **IX1** | `IX_METER_READING_obis_slot` | `ON [dbo].[METER_READING] (obis_code, reading_timestamp) INCLUDE (meter_id, delta_value, status)` | Tree refresh and transformer aggregates read every meter at one slot (Algorithms D, E); intraday provisional data | §4.2 p.10; §5.2 p.11 |
| **IX2** | `IX_METER_READING_not_final` | `ON [dbo].[METER_READING] (meter_id, reading_timestamp) INCLUDE (obis_code, [value], delta_value, status) WHERE is_final = 0` (filtered) | VEE and finalization touch only non-final rows, a small part of the table | §3.2 p.8-9 |
| **IX3** | `IX_PREMISE_supplier` and `IX_PREMISE_aggregator` | `ON [dbo].[PREMISE] (supplier_org_id) INCLUDE (prosumer_scheme)`; same for aggregator_org_id | Market procedures and the bill run start from "all premises of my organization" | §5.1 p.10; §1.3 p.6 |
| 4 | `IX_METER_transformer` | `ON [dbo].[METER] (transformer_id) INCLUDE (status, premise_id)` | Shedding, tree sums | §II.Δ p.3 |
| 5 | `IX_METER_premise` | `ON [dbo].[METER] (premise_id) INCLUDE (status, removed_at)` | Consumer screens | §1.2 |
| 6 | `IX_WORK_ORDER_open` | `ON [dbo].[WORK_ORDER] (technician_user_id, status) WHERE status IN ('ASSIGNED','ACCEPTED','IN_PROGRESS')` (filtered) | Technician job list; overlap check | §2.2 p.7 |
| 7 | `IX_AUDIT_LOG_object` | `ON [dbo].[AUDIT_LOG] (object_type, object_id, logged_at)` | Work order, command and GDPR history | Κοινές αρχές p.5 |
| 8 | `IX_EVENT_meter_time` | `ON [dbo].[EVENT] (meter_id, event_timestamp) INCLUDE (event_type, severity)` | Consumer events, theft report | §1.2, §II.Γ |
| 9 | `IX_TELEMETRY_PACKET_network` | `ON [dbo].[TELEMETRY_PACKET] (meter_network_id, received_at)` | Investigating unmatched packets | §3.1 |
| 10 | `IX_TRANSFORMER_parent` | `ON [dbo].[TRANSFORMER] (parent_transformer_id)` | Every tree walk | §4.1 |
| 11 | `UQ_BILL_premise_period` | `UNIQUE ON [dbo].[BILL] (premise_id, period_start) WHERE status <> 'CANCELLED'` (filtered unique) | No duplicate bill when two bill runs race | §IV concurrency p.13 |
| 12 | `IX_PAYMENT_bill` | `ON [dbo].[PAYMENT] (bill_id) INCLUDE (amount, status) WHERE bill_id IS NOT NULL` | `fn_BillPaid`, TR06 | §1.3 |

**Contention point to document** (§IV p.12, §V docx a): METER_READING is clustered on an IDENTITY key, so every packet inserts on the last page. Apply `ALTER INDEX [PK_METER_READING] ON [dbo].[METER_READING] SET (OPTIMIZE_FOR_SEQUENTIAL_KEY = ON);` (SQL Server 2019+). Do the same for TELEMETRY_PACKET and AUDIT_LOG. The second contention point is TRANSFORMER_CURRENT_STATE (every refresh updates the same rows). It is solved by computing in `#temp` tables and writing with one short MERGE under an app lock (Algorithm E).

**Before/after proof** (§IV p.12 "τουλάχιστον μία περίπτωση"): in `perf.sql`, run the Algorithm E leaf query and `sp_GetIntradayProvisional` without IX1 (`DROP INDEX`), then with it. Capture `SET STATISTICS TIME, IO ON` output (logical reads, CPU ms, elapsed ms) and the actual execution plans (Ctrl+M: Clustered Index Scan before, Index Seek after) on the large data set.

---

## 11. Security (`security.sql`)

| Measure | How | Spec |
|---|---|---|
| Application login can only execute procedures | `CREATE ROLE [mdms_app];` `GRANT EXECUTE ON SCHEMA::[dbo] TO [mdms_app];` `DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::[dbo] TO [mdms_app];`. The PHP SQL user is a member of `mdms_app`. Ownership chaining lets the procedures reach the tables. | §IV p.13 unauthorised access; R1 |
| Internal procedures hidden | `DENY EXECUTE ON [dbo].[sp__...] TO [mdms_app]` for every `sp__` helper | [AR] least privilege |
| SQL injection | Static, parameterized SQL in every procedure; PHP uses `{call ...}` with `$params`; no `EXEC(@string)` | §IV p.13; lecture 20-12, 20-20 |
| Passwords | Salted SHA2_512 in the database; never returned; same error for every login failure | Κοινές αρχές p.5; lecture 20-76 |
| Row-level authorization | Every procedure checks role and ownership (premise owner, assigned technician, own organization) | §1.4 p.6; §5.1 p.10 |
| Personal data in views | `WITH ENCRYPTION` on the user views; market data only aggregated (k ≥ 3) | §1.4 p.6; lab 10 |
| Snapshot reads | `ALTER DATABASE CURRENT SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;` (skip if the course server does not allow it, and write that down) | §IV p.13 concurrency |

If the course server does not allow `CREATE ROLE` for students, keep the script and document it as the production setting.

---

## 12. Data (`import.sql`, `data/`, `sp_GenerateSyntheticData`)

**Small data set — `import.sql`** (built **only through the stored procedures**, which also tests them; §IV p.12):

1. `sp_BootstrapAdmin`; with it: 2 officers, 1 DSO, 1 TSO (`sp_CreateStaffUser`).
2. 2 suppliers and 1 aggregator (`sp_CreateOrganization`), each with one user.
3. Meter types: Single-Phase 1×60 A, Three-Phase 3×80 A. Tariffs: one standard and one older period. (`sp_UpsertMeterType`, `sp_UpsertTariff`)
4. A transformer tree: 1 root at level 4 → 2 at level 3 → 4 at level 2 → 8 at level 1, each with a rectangle around Nicosia, Limassol or Larnaca (`sp_UpsertTransformer`).
5. 3 technicians with 3 documents each, approved; availability for the next 7 days.
6. 10 consumers with 12 premises (3 prosumers: 2 NET_METERING, 1 NET_BILLING); every premise with a supplier, 4 also with the aggregator.
7. For each premise: officer work order INSTALLATION → assign → accept → `sp_InstallMeter` → 3 certificates → approve → `sp_ConfirmMeter`.
8. Two days of packets in the Appendix JSON format through `sp_IngestTelemetryBatch`. Include one spike (25.4 kWh), one missing slot, one unknown network id, one unknown OBIS code, one voltage of 198.5 V (the spec's own example), and one malformed packet.
9. `sp_RunVEE`, then edit or accept the suspect readings, then `sp_FinalizeReadings` for day 1, `sp_BuildTransformerAggregates`, `sp_RefreshTransformerState`.
10. One bill run, one bill paid in two instalments, one history purchase, one GDPR right-to-be-forgotten request taken through all stages, one retention reduction.

**Large data set** (§IV p.12 "της τάξης χιλιάδων γραμμών", part of the grade):

* `sp_GenerateSyntheticData @consumers INT = 2000, @days INT = 30, @seed INT = 342` (SYSTEM_ADMIN only), in `procedures_12_generator.sql`. It creates transformers (about 1 per 40 meters, 4 levels), consumers, premises, active meters with approved certificates, and readings for 1.8.0, 1.8.1, 1.8.2, 2.8.0 (25 % prosumers), 32.7.0 and three-phase currents. Readings follow a daily load curve with noise, ~0.5 % gaps and ~0.1 % spikes.
* Here **bulk speed matters, so it is set-based**: users and premises through a tally CTE, readings with `CROSS JOIN` of meters × slots, 50,000 rows per transaction (lecture 20-67 buffering). It writes the user rows directly through `sp__NewUser` logic in set form; this is the one place allowed to bypass the per-row procedures, because it is an admin load tool. Document this in the report.
* 2,000 meters × 30 days × 96 slots × ~5 codes ≈ 29 million rows; scale @days down if the server is small (7 days ≈ 6.7 million).
* `data/`: export each table with `bcp ... queryout ... -w` (UTF-16, keeps Greek text) into `data/<TABLE>.dat`. `bulk_import.sql` reloads them with `BULK INSERT [dbo].[T] FROM '<path>' WITH (DATAFILETYPE = 'widechar', KEEPIDENTITY, TABLOCK);` in foreign-key order (§V p.14 "αρχεία .dat ... να μπορούν να εισαχθούν").

---

## 13. Files and build order

```
sql/
  create.sql                  -- given (schema v6): tables, CHECKs, FKs, filtered unique indexes, reference data
  drop.sql                    -- given
  functions.sql               -- §6
  views.sql                   -- §7
  procedures_00_internal.sql  -- §9.0 (before the triggers, which do not call them, and before every other procedure)
  triggers.sql                -- §8
  procedures_01_accounts.sql ... procedures_11_admin.sql, procedures_12_generator.sql
  indexes.sql                 -- §10
  security.sql                -- §11
  import.sql                  -- §12 small data, through procedures
  bulk_import.sql             -- §12 .dat reload
  select.sql                  -- one demo call per use case (§15), for the oral exam
  tests.sql                   -- §14
  perf.sql                    -- §14 and §10 before/after
  build_all.sql               -- :r includes in the order above (SQLCMD mode in SSMS)
data/   *.dat
```

`build_all.sql` must run from an empty database in SSMS **SQLCMD mode** with zero errors. Run it twice in a row to prove the scripts are re-runnable.

---

## 14. Tests (`tests.sql`) and performance (`perf.sql`)

**tests.sql** — one block per rule, each printing `PASS` or `FAIL`. Expected errors are caught with `BEGIN TRY ... END TRY BEGIN CATCH IF ERROR_NUMBER() = <n> OR ERROR_MESSAGE() LIKE '[51004]%' PRINT 'PASS' ... END CATCH`. At minimum:

* Each state machine: one valid transition, one invalid one (expect 50003).
* Each guard trigger (51001–51012): one violating statement.
* Permissions: a consumer reading another consumer's premise (50002); a supplier reading another supplier's customers (expect no rows); a pending technician accepting a job (50002 / 51005).
* Login: right password, wrong password, anonymized user (50006).
* VEE: the spec's example 1.8 / 2.0 / 1.9 / 25.4 → the last value is SUSPECT (SPIKE); slots 10:15 = 2.0, 10:30 missing, 10:45 = 2.2 → an ESTIMATED 10:30 row is inserted.
* Immutability: UPDATE of a final reading or aggregate fails (51001 / 51002).
* Atomicity: a bill run where one premise fails leaves the other bills in place, and the failed premise has no partial rows.
* Concurrency: in two SSMS windows, both pay the remaining amount of the same bill at once; one succeeds, and the other gets 50004 or 51006 (lecture 20-45 two-window method).
* GDPR: after execution, the user cannot log in, bills and payments still exist, and raw readings older than 1 month are gone while aggregates remain.

**perf.sql** — the 2-second goal (§IV p.12: 95 % of OLTP queries under 2 s for 10,000 requests):

* `#calls` holds a mix of 10,000 OLTP calls with random valid parameters: 40 % `sp_GetPremiseReadings` (1 day), 15 % `sp_GetPremiseAggregates`, 15 % `sp_ListMyWorkOrders`, 10 % `sp_IngestTelemetryPacket`, 10 % `sp_GetTransformerState`, 10 % `sp_GetDayAheadAggregates`.
* A WHILE loop runs each call and stores `DATEDIFF(MICROSECOND, @t0, SYSDATETIME())` in `#timings`.
* The report shows `PERCENTILE_CONT(0.95)` overall and per procedure, plus the maximum; the target is p95 < 2,000 ms on the large data set. Batch jobs (VEE, bill run, refresh) are timed separately; they are not OLTP.

---

## 15. Traceability: use cases → procedures → criteria

| UC | Flow | Procedures (in order) | Triggers involved | Criteria |
|---|---|---|---|---|
| UC-01 | Consumer registers and adds premises | sp_RegisterConsumer → sp_Login → sp_AddPremise | TR07, TR10 | C1-01 – C1-07 |
| UC-02 | Views the current month's 15-min series and voltage events | sp_GetPremiseReadings, sp_GetPremiseEvents | — | C1-08 – C1-10 |
| UC-03 | Buys past months | sp_GetHistoricalAccessQuote → sp_BuyHistoricalAccess → sp_GetPremiseReadings / sp_GetPremiseAggregates | — | C1-12 – C1-14 |
| UC-04 | Sets a threshold and is alerted | sp_SetPremiseThreshold, sp_UpdateMyProfile → (sp_FinalizeReadings) / sp_CheckConsumptionThresholds | TR21 | C1-11 |
| UC-05 | Fault request → assignment → completion | sp_SubmitServiceRequest → sp_FindAvailableTechnicians → sp_AssignWorkOrder → sp_AcceptWorkOrder → sp_StartWorkOrder → sp_CompleteWorkOrder → sp_GetWorkOrderHistory | TR05, TR14 | C1-15, C1-16, T-07 – T-10 |
| UC-06 | Monthly bill paid in instalments | sp_IssueMonthlyBills → sp_PayBill ×2 → sp_GetMyBillsAndPayments | TR06, TR22 | C1-17 – C1-19, S-12 |
| UC-07 | Right to be forgotten | sp_SubmitGdprRequest → sp_AdvanceGdprRequest ×3 → sp_ExecuteGdprRequest | TR10, TR17 | C1-20 – C1-23 |
| UC-08 | Retention reduced to 1 month | sp_SubmitGdprRequest (RETENTION_REDUCTION) → … → sp_ExecuteGdprRequest; sp_PurgeExpiredReadings | TR13, TR17 | C1-24, C1-25 |
| UC-09 | Technician registration and approval | sp_RegisterTechnician → sp_AddTechnicianDocument ×3 → sp_SetAvailability → sp_DecideDocument ×3 → sp_DecideTechnician | TR10, TR12 | T-01 – T-06, CP-04 |
| UC-10 | Meter installation and activation | sp_CreateWorkOrder → sp_AssignWorkOrder → sp_AcceptWorkOrder → sp_InstallMeter → sp_AddMeterDocument ×3 → sp_DecideDocument ×3 → sp_ConfirmMeter | TR04, TR08, TR13 | T-11 – T-15 |
| UC-11 | Meter replacement, history kept | sp_CreateWorkOrder (REPLACEMENT) → … → sp_ReplaceMeter → sp_ConfirmMeter | TR04, TR13 | T-16 |
| UC-12 | Remote command with retries | sp_RequestRemoteCommand → sp_DecideRemoteCommand → sp_DispatchCommands ×n → sp_AcknowledgeCommand | TR15, TR16 | T-17 – T-19 |
| UC-13 | Remote shedding of a transformer | sp_ShedTransformerLoad → sp_DispatchCommands | TR15, TR16 | S-08 |
| UC-14 | Tamper event → anti-tamper job | sp_RaiseTamperEvent → (TR20 creates the job) → sp_AssignWorkOrder → … → sp_CompleteWorkOrder (persons to notify) | TR20, TR14 | T-20, T-21, S-05 |
| UC-15 | Packet ingestion (matched / unmatched / malformed) | sp_IngestTelemetryPacket, sp_IngestTelemetryBatch | TR19 | D-01 – D-07 |
| UC-16 | VEE: validate, estimate, edit, finalize, aggregate | sp_RunVEE → sp_ListSuspectReadings → sp_EditReading / sp_AcceptSuspectReading → sp_FinalizeReadings | TR01, TR02, TR18, TR21 | D-08 – D-14 |
| UC-17 | Tree state and transformer history | sp_RefreshTransformerState, sp_RefreshTransformerAncestors, sp_GetTransformerTree, sp_GetTransformerState, sp_BuildTransformerAggregates | TR02, TR09 | G-08 – G-16 |
| UC-18 | Day-Ahead and Intraday market data | sp_GetDayAheadAggregates, sp_GetIntradayProvisional | — | M-01 – M-07 |
| UC-19 | DSO analytics | sp_ReportVoltageEvents, sp_ReportPhaseUnbalance, sp_ReportTechnicalLosses, sp_GetGridOverview | — | S-02 – S-04 |
| UC-20 | Admin and officer setup | sp_CreateStaffUser, sp_UpsertMeterType, sp_UpsertServiceType, sp_UpsertTariff, sp_UpsertObisCode | TR10 | CP-03, CP-05 |

---

## 16. Definition of done (check every line before handing over)

- [ ] `build_all.sql` runs twice on an empty database without errors.
- [ ] Every procedure in §9 exists, with a spec citation comment, and is called at least once in `import.sql` or `select.sql`.
- [ ] No PHP page contains SQL text other than `{call dbo.sp_...}`.
- [ ] Every trigger TR01–TR22 exists (TR22 is two triggers, one on BILL and one on PAYMENT); `tests.sql` has a passing test for each guard (51001–51012).
- [ ] The cursor procedures of §3.4 use `CURSOR LOCAL FAST_FORWARD` with CLOSE and DEALLOCATE on every path. Procedures that can fail inside the loop use TRY/CATCH so that the cursor is still closed.
- [ ] Every write procedure follows template T2 or T3 (XACT_ABORT, TRY/CATCH, rollback, THROW).
- [ ] No status value outside §4.2; no column outside `create.sql`.
- [ ] `tests.sql`: every block prints PASS.
- [ ] `perf.sql`: p95 < 2 s on the large data set; IX1 before/after numbers recorded.
- [ ] The three documented indexes, the two contention points, the security measures and the future-extension story (new rows in METER_TYPE, OBIS_CODE, SERVICE_TYPE, TARIFF, event types; `prosumer_scheme` and `communication_type` as CHECK lists that grow with one ALTER) are written up for `docx/` (§V p.14).

**Known limits to state in the report** (decided in the verification document): one specialty per technician; one evidence file per job; no history of supplier changes (bills keep it); no tenant history; address parts kept on PREMISE on purpose; delta_value stored for speed; a geofence is the subtree of a transformer, with an optional rectangle.
