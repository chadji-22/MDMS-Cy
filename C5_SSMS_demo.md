# C5 concurrency demo in SSMS

Open **two new SSMS query windows**, A and B, both connected to `egeorg28`. These examples use the local project’s demo data. Copy and execute **one code block at a time**. Keep A open while its transaction is running, and log in to SSMS with the database owner account used to build the schema.

## 1. Two payments for one bill

In either window, look up an unpaid demo bill for `consumer3@example.cy` that has no completed payments yet.

```sql
SELECT TOP (1) b.user_id AS consumer_id, b.bill_id, b.amount AS remaining
FROM dbo.BILL AS b
JOIN dbo.USER_ACCOUNT AS u ON u.user_id = b.user_id
WHERE u.email = 'consumer3@example.cy' AND b.status IN ('ISSUED', 'OVERDUE')
  AND b.amount > 0 AND dbo.fn_BillPaid(b.bill_id) = 0
ORDER BY b.bill_id;
```

If the lookup is empty, stop and choose another unpaid demo bill before running either payment. Replace the three `<...>` placeholders below with the returned numbers. Use the same bill and the same amount in both windows.

**A**

```sql
BEGIN TRANSACTION;
EXEC dbo.sp_PayBill <consumer_id>, <bill_id>, <remaining>, 'CARD', NULL;
-- Leave this window open. The outer transaction is still holding the bill lock.
```

**B**

```sql
EXEC dbo.sp_PayBill <consumer_id>, <bill_id>, <remaining>, 'CARD', NULL;
```

While B is waiting, run `COMMIT TRANSACTION;` in A. B should report `50003` because the bill is already paid. Capture A’s result, B’s error and this final check. The bill should be `PAID` with exactly one completed payment.

```sql
SELECT b.bill_id, b.status, b.amount,
       COUNT(p.payment_id) AS completed_payments, SUM(p.amount) AS total_paid
FROM dbo.BILL AS b
LEFT JOIN dbo.PAYMENT AS p ON p.bill_id = b.bill_id AND p.status = 'COMPLETED'
WHERE b.bill_id = <bill_id>
GROUP BY b.bill_id, b.status, b.amount;
```

## 2. Two VEE sessions for one meter

Use the seeded active meter `SN-2026-0001`. In either window, ingest one test reading and write down `meter_id` and `officer_id`. Use the same timestamp in each of the following VEE calls. If you already ran this setup, choose a fresh quarter-hour timestamp in all the blocks.

```sql
DECLARE @network VARCHAR(60), @meter INT, @officer INT;
DECLARE @slot DATETIME2(0) = '2025-06-17T10:00:00';
SELECT @network = network_id, @meter = meter_id
FROM dbo.METER WHERE serial_number = 'SN-2026-0001' AND status = 'ACTIVE';
SELECT @officer = user_id FROM dbo.USER_ACCOUNT WHERE email = 'officer1@mdms.cy';
IF @meter IS NULL OR @officer IS NULL
    THROW 54000, 'The demo meter or officer is missing.', 1;
IF EXISTS (SELECT 1 FROM dbo.METER_READING WHERE meter_id = @meter AND reading_timestamp = @slot)
    THROW 54001, 'Choose a fresh test timestamp.', 1;
DECLARE @payload NVARCHAR(4000) = CONCAT(
    N'{"Meter_Network_ID":"', @network, N'","Transmission_Timestamp":"', CONVERT(VARCHAR(19), @slot, 126),
    N'Z","Telemetry_Payload":[{"obis":"32.7.0","value":230,"unit":"V"}]}');
DECLARE @inserted INT;
EXEC dbo.sp_IngestTelemetryPacket @payload, @silent = 1, @readings_inserted = @inserted OUTPUT;
IF @inserted <> 1 THROW 54002, 'The test reading was not inserted.', 1;
SELECT @meter AS meter_id, @officer AS officer_id, @slot AS slot;
```

**A** acquires the same lock used by `sp_RunVEE`. This keeps the overlap reproducible without editing `sp_RunVEE`.

```sql
BEGIN TRANSACTION;
DECLARE @rc INT, @resource NVARCHAR(100) = CONCAT(N'VEE_', <meter_id>);
EXEC @rc = sys.sp_getapplock @Resource = @resource, @LockMode = 'Exclusive',
    @LockOwner = 'Transaction', @LockTimeout = 0;
IF @rc < 0
BEGIN
    ROLLBACK TRANSACTION;
    THROW 54003, 'Could not acquire the test lock.', 1;
END;
SELECT @resource AS locked_resource, @rc AS lock_result;
```

**B** attempts the real VEE procedure. Keep A’s transaction open until B finishes. Expect about 10 seconds of waiting followed by `meters_failed = 1` and `readings_valid = 0`.

```sql
EXEC dbo.sp_RunVEE <officer_id>, '2025-06-17T10:00:00', '2025-06-17T10:00:00', <meter_id>;
```

**A** now runs the same VEE procedure while owning the lock, then commits in the same window. Expect `meters_processed = 1` and `readings_valid = 1`.

```sql
EXEC dbo.sp_RunVEE <officer_id>, '2025-06-17T10:00:00', '2025-06-17T10:00:00', <meter_id>;
COMMIT TRANSACTION;
SELECT reading_timestamp, obis_code, status, vee_rule
FROM dbo.METER_READING
WHERE meter_id = <meter_id> AND reading_timestamp = '2025-06-17T10:00:00';
```

Capture B’s summary and A’s successful summary and `VALID/AUTO` reading.

## 3. Two officers assigning one work order

Create a new `TECHNICAL_CHECK` for a seeded demo premise in a district where `tech1` has both test slots available. If no existing slot fits, the setup adds a new demo availability slot in Nicosia. Save the IDs and date returned by the final `SELECT`.

```sql
DECLARE @officer1 INT, @officer2 INT, @tech INT, @premise INT, @visit DATE;
SELECT @officer1 = user_id FROM dbo.USER_ACCOUNT WHERE email = 'officer1@mdms.cy';
SELECT @officer2 = user_id FROM dbo.USER_ACCOUNT WHERE email = 'officer2@mdms.cy';
SELECT @tech = user_id FROM dbo.USER_ACCOUNT WHERE email = 'tech1@mdms.cy';
SELECT TOP (1) @visit = a.avail_date, @premise = p.premise_id
FROM dbo.TECHNICIAN_AVAILABILITY AS a
JOIN dbo.PREMISE AS p ON p.district = a.district
WHERE a.user_id = @tech AND a.start_time <= '13:00' AND a.end_time >= '14:30'
  AND a.avail_date > CAST(SYSUTCDATETIME() AS DATE)
  AND NOT EXISTS (
      SELECT 1 FROM dbo.WORK_ORDER AS w
      WHERE w.technician_user_id = @tech AND w.status IN ('ASSIGNED', 'ACCEPTED', 'IN_PROGRESS')
        AND w.scheduled_start < DATEADD(MINUTE, 870, CAST(a.avail_date AS DATETIME2(0)))
        AND w.scheduled_end > DATEADD(HOUR, 13, CAST(a.avail_date AS DATETIME2(0)))
  )
ORDER BY a.avail_date DESC, p.premise_id;

IF @officer1 IS NULL OR @officer2 IS NULL OR @tech IS NULL
    THROW 54004, 'The demo officers or technician are missing.', 1;

IF @visit IS NULL
BEGIN
    DECLARE @district NVARCHAR(30) = N'Λευκωσία';
    SELECT @premise = MIN(premise_id) FROM dbo.PREMISE WHERE district = @district;
    IF @premise IS NULL
        THROW 54004, 'The seeded Nicosia premises are missing.', 1;

    SELECT @visit = DATEADD(DAY, 1, MAX(last_date))
    FROM (
        SELECT CAST(SYSUTCDATETIME() AS date) AS last_date
        UNION ALL
        SELECT MAX(avail_date) FROM dbo.TECHNICIAN_AVAILABILITY WHERE user_id = @tech
        UNION ALL
        SELECT CAST(MAX(scheduled_end) AS date) FROM dbo.WORK_ORDER WHERE technician_user_id = @tech
    ) AS dates;

    EXEC dbo.sp_SetAvailability @tech, @visit, '13:00', '14:30', @district;
END;

DECLARE @job TABLE (work_order_id INT, status VARCHAR(20));
INSERT INTO @job
EXEC dbo.sp_CreateWorkOrder @officer1, 'TECHNICAL_CHECK', @premise,
    @description = N'C5 demo — two officers assigning one job';
SELECT work_order_id, @officer1 AS officer1_id, @officer2 AS officer2_id, @tech AS technician_id, @visit AS visit_date
FROM @job;
```

Replace `<visit_date>` with `YYYY-MM-DD` from the setup and substitute all IDs. The two proposals use different slots so that B reaches the work-order state guard after A commits.

**A**

```sql
BEGIN TRANSACTION;
EXEC dbo.sp_AssignWorkOrder <officer1_id>, <work_order_id>, <technician_id>,
    '<visit_date>T13:00:00', '<visit_date>T13:30:00';
```

**B**

```sql
EXEC dbo.sp_AssignWorkOrder <officer2_id>, <work_order_id>, <technician_id>,
    '<visit_date>T14:00:00', '<visit_date>T14:30:00';
```

While B is waiting, run `COMMIT TRANSACTION;` in A. B should report `50003`. Capture both results and this final check, which should show the `ASSIGNED` job at A’s 13:00 slot.

```sql
SELECT work_order_id, status, technician_user_id, scheduled_start, scheduled_end
FROM dbo.WORK_ORDER WHERE work_order_id = <work_order_id>;
```

If you stop mid-test while A is holding a lock, run `IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;` in A before closing it. Save the screenshots of each outcome for C5.
