/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   tests.sql  -  Build Spec §14
   Runs on the data of import.sql. Re-runnable: what a test creates it either cancels again,
   or finds and reuses on the next run. One row per test in the result at the end: PASS or FAIL.
   Expected errors are caught and compared with the error catalog (§5):
     50001-50008 = THROW in procedures;  '[51001]'..'[51012]' = guard triggers.
   The procedures also return their normal result sets; read the summary at the end.
   ============================================================================ */
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM [dbo].[USER_ACCOUNT] WHERE email = 'admin@mdms.cy')
BEGIN
    PRINT 'tests.sql: run import.sql first.';
    SET NOEXEC ON;
END
GO

CREATE TABLE #results (seq INT IDENTITY(1,1), test VARCHAR(120), result VARCHAR(4), detail NVARCHAR(400));

DECLARE @pw NVARCHAR(128) = N'Passw0rd!23';
DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @visit DATE = DATEADD(DAY, 2, @today);
DECLARE @admin INT, @off1 INT, @off2 INT, @dso INT, @tso INT, @tech1 INT, @tech3 INT,
        @c1 INT, @c2 INT, @c3 INT, @sup1_user INT, @sup1 INT;
SELECT @admin = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'admin@mdms.cy';
SELECT @off1  = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'officer1@mdms.cy';
SELECT @off2  = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'officer2@mdms.cy';
SELECT @dso   = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'dso@mdms.cy';
SELECT @tso   = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'tso@mdms.cy';
SELECT @tech1 = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'tech1@mdms.cy';
SELECT @tech3 = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'tech3@mdms.cy';
SELECT @c1    = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer1@example.cy';
SELECT @c2    = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer2@example.cy';
SELECT @c3    = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer3@example.cy';
SELECT @sup1_user = user_id, @sup1 = organization_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'billing@eacsupply.cy';

DECLARE @p1 INT, @m1 INT, @m2 INT, @m3 INT, @m5 INT, @p3 INT;
SELECT @m1 = meter_id, @p1 = premise_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0001';
SELECT @m2 = meter_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0002';
SELECT @m3 = meter_id, @p3 = premise_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0003';
SELECT @m5 = meter_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0005';

DECLARE @wo INT, @doc INT, @cmd INT, @bill INT, @gdpr INT, @reading BIGINT, @agg BIGINT, @n INT, @n2 INT,
        @s DATETIME2(0), @e DATETIME2(0), @txt NVARCHAR(400), @email VARCHAR(255), @uid INT, @id INT;

-- tech1 is available on the visit day (the availability of import.sql covers only its first 7 days)
EXEC [dbo].[sp_SetAvailability] @tech1, @visit, '08:00', '16:00', N'Λευκωσία';

/* ===========================================================================
   A. FIXTURE: a premise with a meter that is installed but still PENDING (no certificates)
   =========================================================================== */
DECLARE @tp INT, @tm INT;
SELECT @tp = premise_id FROM [dbo].[PREMISE] WHERE address = N'TEST premise (tests.sql)';
IF @tp IS NULL
BEGIN
    EXEC [dbo].[sp_AddPremise] @c3, N'TEST premise (tests.sql)', 35.090, 33.260, 'RESIDENTIAL', N'Λευκωσία', N'Στρόβολος', N'Τεστ', '2000', 'NONE', @sup1;
    SELECT @tp = premise_id FROM [dbo].[PREMISE] WHERE address = N'TEST premise (tests.sql)';
    EXEC [dbo].[sp_CreateWorkOrder] @off1, 'INSTALLATION', @tp, NULL, NULL, N'tests.sql fixture', NULL, NULL;
    SELECT @wo = MAX(work_order_id) FROM [dbo].[WORK_ORDER] WHERE premise_id = @tp;
    SET @s = DATEADD(HOUR, 10, CAST(@visit AS DATETIME2(0)));  SET @e = DATEADD(HOUR, 1, @s);
    EXEC [dbo].[sp_AssignWorkOrder] @off1, @wo, @tech1, @s, @e;
    EXEC [dbo].[sp_AcceptWorkOrder] @tech1, @wo;
    EXEC [dbo].[sp_InstallMeter] @tech1, @wo, 'SN-TEST-0001', 'NET-TEST-0001', 'FW-1.0.0', 'PLC', 35.090, 33.260, 1, NULL, NULL;
END
SELECT @tm = meter_id FROM [dbo].[METER] WHERE serial_number = 'SN-TEST-0001';
INSERT INTO #results VALUES ('A0 fixture: PENDING meter exists', CASE WHEN (SELECT status FROM [dbo].[METER] WHERE meter_id = @tm) = 'PENDING' THEN 'PASS' ELSE 'FAIL' END, NULL);

/* ===========================================================================
   B. STATE MACHINES: one valid transition and one invalid one (50003)
   =========================================================================== */
-- B1 WORK_ORDER
BEGIN TRY
    EXEC [dbo].[sp_CreateWorkOrder] @off1, 'TECHNICAL_CHECK', @p1, @m1, NULL, N'tests.sql B1', NULL, NULL;
    SELECT @wo = MAX(work_order_id) FROM [dbo].[WORK_ORDER] WHERE premise_id = @p1;
    SET @s = DATEADD(HOUR, 12, CAST(@visit AS DATETIME2(0)));  SET @e = DATEADD(HOUR, 1, @s);
    EXEC [dbo].[sp_AssignWorkOrder] @off1, @wo, @tech1, @s, @e;
    EXEC [dbo].[sp_AcceptWorkOrder] @tech1, @wo;
    INSERT INTO #results VALUES ('B1a work order SUBMITTED->ASSIGNED->ACCEPTED', CASE WHEN (SELECT status FROM [dbo].[WORK_ORDER] WHERE work_order_id = @wo) = 'ACCEPTED' THEN 'PASS' ELSE 'FAIL' END, NULL);
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B1a work order SUBMITTED->ASSIGNED->ACCEPTED', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_AcceptWorkOrder] @tech1, @wo;
    INSERT INTO #results VALUES ('B1b work order accept twice -> 50003', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B1b work order accept twice -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_CompleteWorkOrder] @tech1, @wo, N'x', NULL, NULL;       -- ACCEPTED -> COMPLETED skips IN_PROGRESS
    INSERT INTO #results VALUES ('B1c work order complete before start -> 50003', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B1c work order complete before start -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_CancelWorkOrder] @off1, @wo, N'tests.sql clean-up';
    SELECT @n = COUNT(*) FROM [dbo].[AUDIT_LOG] WHERE object_type = 'WORK_ORDER' AND object_id = CAST(@wo AS VARCHAR(30));
    INSERT INTO #results VALUES ('B1d work order cancelled, history has every step (TR14)', CASE WHEN @n >= 5 THEN 'PASS' ELSE 'FAIL' END, N'audit rows: ' + CAST(@n AS NVARCHAR(10)));
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B1d work order cancelled, history has every step (TR14)', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- B2 METER.status
BEGIN TRY
    EXEC [dbo].[sp_SetMeterStatus] @dso, @m2, 'FAULTY', N'tests.sql B2';
    INSERT INTO #results VALUES ('B2a meter ACTIVE->FAULTY', CASE WHEN (SELECT status FROM [dbo].[METER] WHERE meter_id = @m2) = 'FAULTY' THEN 'PASS' ELSE 'FAIL' END, NULL);
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B2a meter ACTIVE->FAULTY', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_SetMeterStatus] @dso, @m2, 'INACTIVE', NULL;
    INSERT INTO #results VALUES ('B2b meter FAULTY->INACTIVE -> 50003', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B2b meter FAULTY->INACTIVE -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_SetMeterStatus] @dso, @m2, 'ACTIVE', N'tests.sql B2 restore';
    INSERT INTO #results VALUES ('B2c meter FAULTY->ACTIVE', CASE WHEN (SELECT status FROM [dbo].[METER] WHERE meter_id = @m2) = 'ACTIVE' THEN 'PASS' ELSE 'FAIL' END, NULL);
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B2c meter FAULTY->ACTIVE', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- B3 DOCUMENT
SELECT TOP (1) @doc = document_id FROM [dbo].[DOCUMENT] WHERE approval_status = 'APPROVED' ORDER BY document_id;
BEGIN TRY
    EXEC [dbo].[sp_DecideDocument] @off1, @doc, 'REJECTED', NULL;
    INSERT INTO #results VALUES ('B3 document decided twice -> 50003', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B3 document decided twice -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- B4 USER_ACCOUNT.approval_status of a technician
BEGIN TRY
    EXEC [dbo].[sp_DecideTechnician] @off1, @tech3, 'REJECTED', NULL;      -- APPROVED -> REJECTED is not allowed
    INSERT INTO #results VALUES ('B4a technician APPROVED->REJECTED -> 50003', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B4a technician APPROVED->REJECTED -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_DecideTechnician] @off1, @tech3, 'SUSPENDED', N'tests.sql B4';
    EXEC [dbo].[sp_DecideTechnician] @off1, @tech3, 'APPROVED', N'tests.sql B4 restore';
    INSERT INTO #results VALUES ('B4b technician APPROVED<->SUSPENDED', CASE WHEN (SELECT approval_status FROM [dbo].[USER_ACCOUNT] WHERE user_id = @tech3) = 'APPROVED' THEN 'PASS' ELSE 'FAIL' END, NULL);
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B4b technician APPROVED<->SUSPENDED', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- B5 REMOTE_COMMAND: request (technician) -> approve -> attempt -> ACK; then the same steps again are refused
BEGIN TRY
    EXEC [dbo].[sp_RequestRemoteCommand] @tech1, @m1, 'FIRMWARE_UPGRADE', N'FW-1.0.1';
    SELECT @cmd = MAX(command_id) FROM [dbo].[REMOTE_COMMAND] WHERE meter_id = @m1;
    EXEC [dbo].[sp_DecideRemoteCommand] @off1, @cmd, 'APPROVED', N'tests.sql B5';
    EXEC [dbo].[sp_DispatchCommands] @off1, 3;
    EXEC [dbo].[sp_DispatchCommands] @off1, 3;                              -- second attempt, no ACK yet
    SELECT @n = attempt_count FROM [dbo].[REMOTE_COMMAND] WHERE command_id = @cmd;
    SELECT @n2 = COUNT(*) FROM [dbo].[AUDIT_LOG] WHERE object_type = 'REMOTE_COMMAND' AND object_id = CAST(@cmd AS VARCHAR(30)) AND action = 'COMMAND_ATTEMPT';
    EXEC [dbo].[sp_AcknowledgeCommand] 'NET-0001', @cmd, N'OK';
    INSERT INTO #results VALUES ('B5a command PENDING_APPROVAL->APPROVED->SENT x2->ACKNOWLEDGED',
        CASE WHEN @n = 2 AND @n2 = 2 AND (SELECT status FROM [dbo].[REMOTE_COMMAND] WHERE command_id = @cmd) = 'ACKNOWLEDGED'
                  AND (SELECT firmware_version FROM [dbo].[METER] WHERE meter_id = @m1) = 'FW-1.0.1' THEN 'PASS' ELSE 'FAIL' END,
        N'attempts ' + CAST(@n AS NVARCHAR(10)) + N', attempt audit rows ' + CAST(@n2 AS NVARCHAR(10)));
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B5a command PENDING_APPROVAL->APPROVED->SENT x2->ACKNOWLEDGED', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_DecideRemoteCommand] @off1, @cmd, 'REJECTED', NULL;
    INSERT INTO #results VALUES ('B5b command decided after ACK -> 50003', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B5b command decided after ACK -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_AcknowledgeCommand] 'NET-0001', @cmd, N'OK';
    INSERT INTO #results VALUES ('B5c command ACK twice -> 50003', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B5c command ACK twice -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
-- B5d a command that never gets an ACK fails after the attempts are used up, with an event
BEGIN TRY
    EXEC [dbo].[sp_RequestRemoteCommand] @dso, @m2, 'DISCONNECT', NULL;     -- DSO: APPROVED at once
    SELECT @cmd = MAX(command_id) FROM [dbo].[REMOTE_COMMAND] WHERE meter_id = @m2;
    EXEC [dbo].[sp_DispatchCommands] @off1, 2;
    EXEC [dbo].[sp_DispatchCommands] @off1, 2;
    EXEC [dbo].[sp_DispatchCommands] @off1, 2;
    INSERT INTO #results VALUES ('B5d command without ACK -> FAILED + COMMAND_FAILED event',
        CASE WHEN (SELECT status FROM [dbo].[REMOTE_COMMAND] WHERE command_id = @cmd) = 'FAILED'
                  AND EXISTS (SELECT 1 FROM [dbo].[EVENT] WHERE event_type = 'COMMAND_FAILED' AND meter_id = @m2) THEN 'PASS' ELSE 'FAIL' END, NULL);
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B5d command without ACK -> FAILED + COMMAND_FAILED event', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- B6 BILL
SELECT TOP (1) @bill = bill_id FROM [dbo].[BILL] WHERE status = 'PAID' ORDER BY bill_id;
BEGIN TRY
    EXEC [dbo].[sp_PayBill] @c1, @bill, 1.00, 'CARD', NULL;
    INSERT INTO #results VALUES ('B6a pay a PAID bill -> 50003', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B6a pay a PAID bill -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_CancelBill] @off1, @bill, N'tests.sql B6';
    INSERT INTO #results VALUES ('B6b cancel a PAID bill -> 50003', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B6b cancel a PAID bill -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
INSERT INTO #results
SELECT 'B6c bill paid in two instalments is PAID (TR06)',
       CASE WHEN (SELECT COUNT(*) FROM [dbo].[PAYMENT] WHERE bill_id = @bill AND status = 'COMPLETED') = 2
                 AND (SELECT remaining FROM [dbo].[view_BILL_BALANCE] WHERE bill_id = @bill) = 0 THEN 'PASS' ELSE 'FAIL' END, NULL;
-- B6d paying more than what is left is refused (the sequential form of the two-window test below)
SELECT TOP (1) @bill = bill_id, @uid = user_id FROM [dbo].[BILL] WHERE status = 'ISSUED' AND user_id = @c2 ORDER BY bill_id;
BEGIN TRY
    EXEC [dbo].[sp_PayBill] @c2, @bill, 99999.00, 'CARD', NULL;
    INSERT INTO #results VALUES ('B6d overpayment -> 50004', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B6d overpayment -> 50004', CASE WHEN ERROR_NUMBER() = 50004 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- B7 GDPR_REQUEST
SELECT TOP (1) @gdpr = gdpr_request_id FROM [dbo].[GDPR_REQUEST] WHERE status = 'EXECUTED' ORDER BY gdpr_request_id;
BEGIN TRY
    EXEC [dbo].[sp_AdvanceGdprRequest] @off1, @gdpr, 'UNDER_REVIEW', NULL;
    INSERT INTO #results VALUES ('B7a GDPR EXECUTED->UNDER_REVIEW -> 50003', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B7a GDPR EXECUTED->UNDER_REVIEW -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
-- two-person rule: the officer who pre-approved cannot give the final approval; a skipped stage is refused
BEGIN TRY
    EXEC [dbo].[sp_SubmitGdprRequest] @c3, 'RIGHT_TO_BE_FORGOTTEN', NULL;
    SELECT @gdpr = MAX(gdpr_request_id) FROM [dbo].[GDPR_REQUEST] WHERE user_id = @c3;
    BEGIN TRY
        EXEC [dbo].[sp_AdvanceGdprRequest] @off1, @gdpr, 'PRE_APPROVED', NULL;      -- skips UNDER_REVIEW
        INSERT INTO #results VALUES ('B7b GDPR skipped stage -> 50003', 'FAIL', N'no error');
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B7b GDPR skipped stage -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
    EXEC [dbo].[sp_AdvanceGdprRequest] @off1, @gdpr, 'UNDER_REVIEW', NULL;
    EXEC [dbo].[sp_AdvanceGdprRequest] @off1, @gdpr, 'PRE_APPROVED', NULL;
    BEGIN TRY
        EXEC [dbo].[sp_AdvanceGdprRequest] @off1, @gdpr, 'APPROVED', NULL;
        INSERT INTO #results VALUES ('B7c GDPR same officer pre-approves and approves -> 50002', 'FAIL', N'no error');
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B7c GDPR same officer pre-approves and approves -> 50002', CASE WHEN ERROR_NUMBER() = 50002 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
    BEGIN TRY
        EXEC [dbo].[sp_ExecuteGdprRequest] @off2, @gdpr;                            -- not APPROVED yet
        INSERT INTO #results VALUES ('B7d GDPR execute before approval -> 50003', 'FAIL', N'no error');
    END TRY
    BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B7d GDPR execute before approval -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
    EXEC [dbo].[sp_AdvanceGdprRequest] @off2, @gdpr, 'REJECTED', N'tests.sql clean-up';   -- consumer 3 stays
    SELECT @n = COUNT(*) FROM [dbo].[AUDIT_LOG] WHERE object_type = 'GDPR_REQUEST' AND object_id = CAST(@gdpr AS VARCHAR(30)) AND action IN ('SUBMIT', 'STATUS_CHANGE');
    INSERT INTO #results VALUES ('B7e GDPR every stage is logged (TR17)', CASE WHEN @n = 4 THEN 'PASS' ELSE 'FAIL' END, N'stage rows: ' + CAST(@n AS NVARCHAR(10)));
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B7 GDPR flow', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- B8 METER_READING: a final reading cannot be edited through the procedure either
SELECT TOP (1) @reading = reading_id FROM [dbo].[METER_READING] WHERE is_final = 1 AND status = 'ESTIMATED' ORDER BY reading_id;
BEGIN TRY
    EXEC [dbo].[sp_EditReading] @dso, @reading, 1.0, N'tests.sql B8';
    INSERT INTO #results VALUES ('B8 edit a final reading -> 50003', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('B8 edit a final reading -> 50003', CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ===========================================================================
   C. GUARD TRIGGERS 51001 - 51012: one violating statement each
   =========================================================================== */
-- 51001 a finalized reading cannot change
SELECT TOP (1) @reading = reading_id FROM [dbo].[METER_READING] WHERE is_final = 1 ORDER BY reading_id;
BEGIN TRY
    UPDATE [dbo].[METER_READING] SET [value] = [value] + 1 WHERE reading_id = @reading;
    INSERT INTO #results VALUES ('C01 [51001] update of a final reading', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C01 [51001] update of a final reading', CASE WHEN ERROR_MESSAGE() LIKE '%51001%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- 51002 a final aggregate cannot change or be deleted
SELECT TOP (1) @agg = aggregate_id FROM [dbo].[AGGREGATE] WHERE is_final = 1 ORDER BY aggregate_id;
BEGIN TRY
    UPDATE [dbo].[AGGREGATE] SET [value] = 0 WHERE aggregate_id = @agg;
    INSERT INTO #results VALUES ('C02a [51002] update of a final aggregate', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C02a [51002] update of a final aggregate', CASE WHEN ERROR_MESSAGE() LIKE '%51002%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    DELETE FROM [dbo].[AGGREGATE] WHERE aggregate_id = @agg;
    INSERT INTO #results VALUES ('C02b [51002] delete of a final aggregate', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C02b [51002] delete of a final aggregate', CASE WHEN ERROR_MESSAGE() LIKE '%51002%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- 51003 the audit log is append-only
BEGIN TRY
    DELETE FROM [dbo].[AUDIT_LOG] WHERE log_id = (SELECT MIN(log_id) FROM [dbo].[AUDIT_LOG]);
    INSERT INTO #results VALUES ('C03a [51003] delete from the audit log', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C03a [51003] delete from the audit log', CASE WHEN ERROR_MESSAGE() LIKE '%51003%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    UPDATE [dbo].[AUDIT_LOG] SET comment = N'changed' WHERE log_id = (SELECT MIN(log_id) FROM [dbo].[AUDIT_LOG]);
    INSERT INTO #results VALUES ('C03b [51003] update of the audit log', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C03b [51003] update of the audit log', CASE WHEN ERROR_MESSAGE() LIKE '%51003%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- 51004 + ATOMICITY: confirming a meter without certificates fails inside the transaction of the procedure;
--       the meter stays PENDING and no audit row of the attempt is left
SELECT @n = COUNT(*) FROM [dbo].[AUDIT_LOG] WHERE object_type = 'METER' AND object_id = CAST(@tm AS VARCHAR(30));
BEGIN TRY
    EXEC [dbo].[sp_ConfirmMeter] @off1, @tm, 'APPROVE', N'tests.sql C04';
    INSERT INTO #results VALUES ('C04a [51004] activate a meter without certificates', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C04a [51004] activate a meter without certificates', CASE WHEN ERROR_MESSAGE() LIKE '%51004%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
SELECT @n2 = COUNT(*) FROM [dbo].[AUDIT_LOG] WHERE object_type = 'METER' AND object_id = CAST(@tm AS VARCHAR(30));
INSERT INTO #results VALUES ('C04b atomicity: failed confirm left no partial rows',
    CASE WHEN @n = @n2 AND (SELECT status FROM [dbo].[METER] WHERE meter_id = @tm) = 'PENDING'
              AND (SELECT activated_at FROM [dbo].[METER] WHERE meter_id = @tm) IS NULL THEN 'PASS' ELSE 'FAIL' END, NULL);

-- 51005 a job can go only to an approved technician
SELECT TOP (1) @wo = work_order_id FROM [dbo].[WORK_ORDER] WHERE status = 'COMPLETED' ORDER BY work_order_id;
BEGIN TRY
    UPDATE [dbo].[WORK_ORDER] SET technician_user_id = @c1 WHERE work_order_id = @wo;
    INSERT INTO #results VALUES ('C05 [51005] job given to a non-technician', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C05 [51005] job given to a non-technician', CASE WHEN ERROR_MESSAGE() LIKE '%51005%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- 51006 payments above the amount of the bill
SELECT TOP (1) @bill = bill_id FROM [dbo].[BILL] WHERE status = 'PAID' ORDER BY bill_id;
BEGIN TRY
    INSERT INTO [dbo].[PAYMENT] (amount, method, status, user_id, bill_id) VALUES (0.01, 'CASH', 'COMPLETED', @c1, @bill);
    INSERT INTO #results VALUES ('C06 [51006] overpayment inserted directly', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C06 [51006] overpayment inserted directly', CASE WHEN ERROR_MESSAGE() LIKE '%51006%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- 51007 the owner of a premise is a consumer; the supplier is an organization of type SUPPLIER
BEGIN TRY
    UPDATE [dbo].[PREMISE] SET user_id = @off1 WHERE premise_id = @p1;
    INSERT INTO #results VALUES ('C07a [51007] premise owned by an officer', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C07a [51007] premise owned by an officer', CASE WHEN ERROR_MESSAGE() LIKE '%51007%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    UPDATE [dbo].[PREMISE] SET supplier_org_id = (SELECT TOP (1) organization_id FROM [dbo].[ORGANIZATION] WHERE org_type = 'AGGREGATOR') WHERE premise_id = @p1;
    INSERT INTO #results VALUES ('C07b [51007] aggregator used as supplier', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C07b [51007] aggregator used as supplier', CASE WHEN ERROR_MESSAGE() LIKE '%51007%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- 51008 a meter hangs on a level-1 transformer
BEGIN TRY
    UPDATE [dbo].[METER] SET transformer_id = (SELECT TOP (1) transformer_id FROM [dbo].[TRANSFORMER] WHERE [level] = 2) WHERE meter_id = @m1;
    INSERT INTO #results VALUES ('C08 [51008] meter on a level-2 transformer', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C08 [51008] meter on a level-2 transformer', CASE WHEN ERROR_MESSAGE() LIKE '%51008%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- 51009 the tree: the parent is one level above; no cycles; a transformer with meters stays level 1
BEGIN TRY
    UPDATE [dbo].[TRANSFORMER] SET parent_transformer_id = (SELECT TOP (1) transformer_id FROM [dbo].[TRANSFORMER] WHERE [level] = 1)
    WHERE [level] = 4;                                          -- the root under a leaf: a cycle, and wrong levels
    INSERT INTO #results VALUES ('C09a [51009] root placed under a leaf', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C09a [51009] root placed under a leaf', CASE WHEN ERROR_MESSAGE() LIKE '%51009%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_UpsertTransformer] @tso, NULL, N'TEST wrong level', 1, 100, 35.1, 33.3, NULL, NULL, NULL, NULL,
         1;                                                     -- parent id 1 is the level-4 root: 1 + 1 <> 4
    INSERT INTO #results VALUES ('C09b [51009] level-1 child of the level-4 root (procedure)', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C09b [51009] level-1 child of the level-4 root (procedure)', CASE WHEN ERROR_MESSAGE() LIKE '%51009%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- 51010 users are never deleted (a fresh user without any references, so only the trigger can refuse)
SET @email = 'deltest_' + LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', '')) + '@example.cy';
EXEC [dbo].[sp_RegisterConsumer] @email, @pw, N'Delete Test', NULL, NULL, 1, 0;
SELECT @uid = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = @email;
BEGIN TRY
    DELETE FROM [dbo].[USER_ACCOUNT] WHERE user_id = @uid;
    INSERT INTO #results VALUES ('C10 [51010] delete of a user', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C10 [51010] delete of a user', CASE WHEN ERROR_MESSAGE() LIKE '%51010%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- 51011 a remote command only for an ACTIVE meter (the fixture meter is PENDING)
BEGIN TRY
    EXEC [dbo].[sp_RequestRemoteCommand] @dso, @tm, 'DISCONNECT', NULL;
    INSERT INTO #results VALUES ('C11 [51011] command for a meter that is not ACTIVE', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C11 [51011] command for a meter that is not ACTIVE', CASE WHEN ERROR_MESSAGE() LIKE '%51011%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- 51012 bills and payments are never deleted
SELECT TOP (1) @bill = b.bill_id FROM [dbo].[BILL] AS b WHERE NOT EXISTS (SELECT 1 FROM [dbo].[PAYMENT] AS p WHERE p.bill_id = b.bill_id) ORDER BY b.bill_id;
BEGIN TRY
    DELETE FROM [dbo].[BILL] WHERE bill_id = @bill;
    INSERT INTO #results VALUES ('C12a [51012] delete of a bill', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C12a [51012] delete of a bill', CASE WHEN ERROR_MESSAGE() LIKE '%51012%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    DELETE FROM [dbo].[PAYMENT] WHERE payment_id = (SELECT MIN(payment_id) FROM [dbo].[PAYMENT]);
    INSERT INTO #results VALUES ('C12b [51012] delete of a payment', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('C12b [51012] delete of a payment', CASE WHEN ERROR_MESSAGE() LIKE '%51012%' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ===========================================================================
   D. PERMISSIONS
   =========================================================================== */
DECLARE @from DATETIME2(0) = CAST(@today AS DATETIME2(0)), @to DATETIME2(0) = DATEADD(DAY, 1, CAST(@today AS DATETIME2(0)));
BEGIN TRY
    EXEC [dbo].[sp_GetPremiseReadings] @c3, @p1, @from, @to, N'1.8.0';      -- premise 1 belongs to consumer 1
    INSERT INTO #results VALUES ('D1 consumer reads another consumer''s premise -> 50002', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('D1 consumer reads another consumer''s premise -> 50002', CASE WHEN ERROR_NUMBER() = 50002 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- a supplier sees only the bills of its own organization
CREATE TABLE #bills (bill_id INT, issue_date DATE, due_date DATE, period_start DATE, period_end DATE, amount DECIMAL(12,2),
                     paid DECIMAL(12,2), remaining DECIMAL(12,2), status VARCHAR(20), premise_id INT, user_id INT,
                     supplier_org_id INT, supplier_name NVARCHAR(150));
BEGIN TRY
    INSERT INTO #bills EXEC [dbo].[sp_ListSupplierBills] @sup1_user, NULL, NULL, NULL, 1, 500;
    INSERT INTO #results
    SELECT 'D2 supplier sees only its own customers'' bills',
           CASE WHEN EXISTS (SELECT 1 FROM #bills) AND NOT EXISTS (SELECT 1 FROM #bills WHERE supplier_org_id <> @sup1) THEN 'PASS' ELSE 'FAIL' END,
           N'rows: ' + CAST((SELECT COUNT(*) FROM #bills) AS NVARCHAR(10));
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('D2 supplier sees only its own customers'' bills', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- a technician who is still PENDING cannot take jobs
SET @email = 'pendingtech_' + LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', '')) + '@example.cy';
EXEC [dbo].[sp_RegisterTechnician] @email, @pw, N'Pending Tech', NULL, '1990-01-01', '/uploads/tech/p.jpg', N'Ηλεκτρολόγος';
SELECT @uid = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = @email;
SELECT TOP (1) @wo = work_order_id FROM [dbo].[WORK_ORDER] ORDER BY work_order_id;
BEGIN TRY
    EXEC [dbo].[sp_AcceptWorkOrder] @uid, @wo;
    INSERT INTO #results VALUES ('D3 pending technician accepts a job -> 50002', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('D3 pending technician accepts a job -> 50002', CASE WHEN ERROR_NUMBER() = 50002 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_GetMyAvailability] @uid, NULL, NULL;                     -- but may manage their own registration
    INSERT INTO #results VALUES ('D4 pending technician manages own registration (TECHNICIAN_ANY)', 'PASS', NULL);
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('D4 pending technician manages own registration (TECHNICIAN_ANY)', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_ListUsers] @c1, NULL, NULL, NULL, 1, 10;
    INSERT INTO #results VALUES ('D5 consumer calls an officer procedure -> 50002', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('D5 consumer calls an officer procedure -> 50002', CASE WHEN ERROR_NUMBER() = 50002 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_RegisterConsumer] 'consumer1@example.cy', @pw, N'Duplicate', NULL, NULL, 1, 0;
    INSERT INTO #results VALUES ('D6 duplicate email -> 50005', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('D6 duplicate email -> 50005', CASE WHEN ERROR_NUMBER() = 50005 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- paid access to past data (50008): consumer 1 did not buy the previous month, consumer 2 did (for meter 3)
DECLARE @pm_from DATETIME2(0) = CAST(DATEADD(DAY, -1, EOMONTH(@today, -1)) AS DATETIME2(0));
DECLARE @pm_to   DATETIME2(0) = DATEADD(DAY, 1, @pm_from);
BEGIN TRY
    EXEC [dbo].[sp_GetPremiseReadings] @c1, @p1, @pm_from, @pm_to, N'1.8.0';
    INSERT INTO #results VALUES ('D7 past month without purchase -> 50008', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('D7 past month without purchase -> 50008', CASE WHEN ERROR_NUMBER() = 50008 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
CREATE TABLE #rd (reading_timestamp DATETIME2(0), obis_code VARCHAR(20), energy DECIMAL(18,4), [value] DECIMAL(18,4), status VARCHAR(20), meter_id INT);
BEGIN TRY
    INSERT INTO #rd EXEC [dbo].[sp_GetPremiseReadings] @c2, @p3, @pm_from, @pm_to, N'1.8.0,2.8.0';
    SELECT @n = COUNT(*) FROM #rd;
    INSERT INTO #results VALUES ('D8 past month after purchase: 96 slots x 2 codes (prosumer)', CASE WHEN @n = 192 THEN 'PASS' ELSE 'FAIL' END, N'rows: ' + CAST(@n AS NVARCHAR(10)));
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('D8 past month after purchase: 96 slots x 2 codes (prosumer)', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ===========================================================================
   E. LOGIN
   =========================================================================== */
CREATE TABLE #login (user_id INT, role_code VARCHAR(20), full_name NVARCHAR(150), approval_status VARCHAR(20), organization_id INT);
BEGIN TRY
    INSERT INTO #login EXEC [dbo].[sp_Login] 'consumer1@example.cy', @pw;
    INSERT INTO #results SELECT 'E1 login with the right password', CASE WHEN (SELECT COUNT(*) FROM #login WHERE user_id = @c1 AND role_code = 'CONSUMER') = 1 THEN 'PASS' ELSE 'FAIL' END, NULL;
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('E1 login with the right password', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_Login] 'consumer1@example.cy', N'wrong-password';
    INSERT INTO #results VALUES ('E2 login with a wrong password -> 50006', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('E2 login with a wrong password -> 50006', CASE WHEN ERROR_NUMBER() = 50006 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_Login] 'nobody@example.cy', @pw;
    INSERT INTO #results VALUES ('E3 login with an unknown email -> 50006 (same message)', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('E3 login with an unknown email -> 50006 (same message)', CASE WHEN ERROR_NUMBER() = 50006 AND ERROR_MESSAGE() = 'Login failed.' THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
BEGIN TRY
    EXEC [dbo].[sp_Login] 'consumer1@example.cy', NULL;
    INSERT INTO #results VALUES ('E4 login with a NULL password -> 50006', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('E4 login with a NULL password -> 50006', CASE WHEN ERROR_NUMBER() = 50006 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH
SELECT TOP (1) @email = email FROM [dbo].[USER_ACCOUNT] WHERE anonymized_at IS NOT NULL ORDER BY user_id;
BEGIN TRY
    EXEC [dbo].[sp_Login] @email, @pw;
    INSERT INTO #results VALUES ('E5 login of an anonymized user -> 50006', 'FAIL', N'no error');
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('E5 login of an anonymized user -> 50006', CASE WHEN ERROR_NUMBER() = 50006 THEN 'PASS' ELSE 'FAIL' END, LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ===========================================================================
   F. VEE: the two examples of the spec, on meter 5, three days before the imported data
   =========================================================================== */
DECLARE @vd DATETIME2(0) = DATEADD(DAY, -3, CAST(DATEADD(DAY, -1, EOMONTH(@today, -1)) AS DATETIME2(0)));
DECLARE @p NVARCHAR(4000), @k INT = 0, @reg DECIMAL(18,4);
DECLARE @vals TABLE (k INT, reg DECIMAL(18,4));
-- register values whose 15-min energies are 1.8, 2.0, 1.9 and then 25.4  (09:00 is the starting value)
INSERT INTO @vals VALUES (0, 100.0), (1, 101.8), (2, 103.8), (3, 105.7), (4, 131.1);
WHILE @k <= 4
BEGIN
    SELECT @reg = reg FROM @vals WHERE k = @k;
    SET @p = CONCAT(N'{"Meter_Network_ID":"NET-0005","Transmission_Timestamp":"', CONVERT(VARCHAR(19), DATEADD(MINUTE, 540 + 15 * @k, @vd), 126),
                    N'Z","Telemetry_Payload":[{"obis":"1.8.0","value":', @reg, N',"unit":"kWh"}]}');
    EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1;
    SET @k = @k + 1;
END
-- 12:15 = 2.0, 12:30 missing, 12:45 = 2.2
SET @p = CONCAT(N'{"Meter_Network_ID":"NET-0005","Transmission_Timestamp":"', CONVERT(VARCHAR(19), DATEADD(MINUTE, 735, @vd), 126), N'Z","Telemetry_Payload":[{"obis":"2.8.0","value":2.0,"unit":"kWh"}]}');
EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1;
SET @p = CONCAT(N'{"Meter_Network_ID":"NET-0005","Transmission_Timestamp":"', CONVERT(VARCHAR(19), DATEADD(MINUTE, 765, @vd), 126), N'Z","Telemetry_Payload":[{"obis":"2.8.0","value":2.2,"unit":"kWh"}]}');
EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1;

SET @s = DATEADD(MINUTE, 540, @vd);  SET @e = DATEADD(MINUTE, 765, @vd);
BEGIN TRY
    EXEC [dbo].[sp_RunVEE] @off1, @s, @e, @m5;
    INSERT INTO #results
    SELECT 'F1 VEE: 1.8 / 2.0 / 1.9 / 25.4 -> the last one is SUSPECT (SPIKE)',
           CASE WHEN r.status = 'SUSPECT' AND r.vee_rule = 'SPIKE' AND r.delta_value = 25.4 THEN 'PASS' ELSE 'FAIL' END,
           r.status + N' / ' + ISNULL(r.vee_rule, N'-') + N' / energy ' + CAST(r.delta_value AS NVARCHAR(30))
    FROM [dbo].[METER_READING] AS r
    WHERE r.meter_id = @m5 AND r.obis_code = '1.8.0' AND r.reading_timestamp = DATEADD(MINUTE, 600, @vd);
    INSERT INTO #results
    SELECT 'F2 VEE: the three readings before the spike are VALID',
           CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END, N'valid: ' + CAST(COUNT(*) AS NVARCHAR(10))
    FROM [dbo].[METER_READING] AS r
    WHERE r.meter_id = @m5 AND r.obis_code = '1.8.0' AND r.status = 'VALID'
      AND r.reading_timestamp BETWEEN DATEADD(MINUTE, 555, @vd) AND DATEADD(MINUTE, 585, @vd);
    INSERT INTO #results
    SELECT 'F3 VEE: 2.0 / missing / 2.2 -> an ESTIMATED 2.1 is inserted',
           CASE WHEN MAX(r.status) = 'ESTIMATED' AND MAX(r.[value]) = 2.1 AND MAX(r.vee_rule) = 'LINEAR_INTERPOLATION'
                     AND MAX(CAST(r.packet_id AS BIGINT)) IS NULL AND COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END,
           ISNULL(MAX(r.status), N'no row') + N' / ' + ISNULL(CAST(MAX(r.[value]) AS NVARCHAR(30)), N'-')
    FROM [dbo].[METER_READING] AS r
    WHERE r.meter_id = @m5 AND r.obis_code = '2.8.0' AND r.reading_timestamp = DATEADD(MINUTE, 750, @vd);
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('F VEE run', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- the import data: the planted spike was edited (original value kept, editor recorded) and logged
SET @reading = NULL;
SELECT TOP (1) @reading = reading_id FROM [dbo].[METER_READING]
WHERE meter_id = @m1 AND status = 'EDITED' AND original_value IS NOT NULL AND edited_by_user_id = @dso ORDER BY reading_id;
INSERT INTO #results VALUES ('F4 Editing keeps original value, new value and editor (TR18)',
    CASE WHEN @reading IS NOT NULL
              AND EXISTS (SELECT 1 FROM [dbo].[AUDIT_LOG] AS l WHERE l.object_type = 'METER_READING' AND l.action = 'VEE_EDIT'
                            AND l.object_id = CAST(@reading AS VARCHAR(30)) AND l.user_id = @dso) THEN 'PASS' ELSE 'FAIL' END, NULL);

/* ===========================================================================
   G. INGESTION: every packet is kept; the ones that do not match raise an event
   =========================================================================== */
CREATE TABLE #pk (packet_id BIGINT, match_status VARCHAR(20), readings_inserted INT);
BEGIN TRY
    INSERT INTO #pk EXEC [dbo].[sp_IngestTelemetryPacket] N'{"Meter_Network_ID":"NET-NOBODY","Transmission_Timestamp":"2026-01-01T00:00:00Z","Telemetry_Payload":[]}';
    INSERT INTO #pk EXEC [dbo].[sp_IngestTelemetryPacket] N'<<not json>>';
    INSERT INTO #pk EXEC [dbo].[sp_IngestTelemetryPacket] N'{"Meter_Network_ID":"NET-TEST-0001","Transmission_Timestamp":"2026-01-01T00:00:00Z","Telemetry_Payload":[{"obis":"1.8.0","value":1,"unit":"kWh"}]}';
    INSERT INTO #results
    SELECT 'G1 packets: UNMATCHED / COMM_ERROR / QUARANTINED stored with an event (TR19)',
           CASE WHEN (SELECT COUNT(DISTINCT match_status) FROM #pk WHERE match_status IN ('UNMATCHED', 'COMM_ERROR', 'QUARANTINED')) = 3
                     AND (SELECT COUNT(*) FROM #pk AS x JOIN [dbo].[EVENT] AS e ON e.packet_id = x.packet_id AND e.event_type = 'PACKET_' + x.match_status) = 3
                     AND (SELECT SUM(readings_inserted) FROM #pk) = 0 THEN 'PASS' ELSE 'FAIL' END,
           (SELECT STRING_AGG(CAST(match_status AS NVARCHAR(400)), N', ') FROM #pk);
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('G1 packets: UNMATCHED / COMM_ERROR / QUARANTINED stored with an event (TR19)', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH
INSERT INTO #results
SELECT 'G2 voltage 198.5 V -> VOLTAGE_SAG event', CASE WHEN EXISTS (SELECT 1 FROM [dbo].[EVENT] WHERE event_type = 'VOLTAGE_SAG' AND meter_id = @m3) THEN 'PASS' ELSE 'FAIL' END, NULL;
INSERT INTO #results
SELECT 'G3 unknown OBIS code -> UNSUPPORTED_OBIS event, not stored',
       CASE WHEN EXISTS (SELECT 1 FROM [dbo].[EVENT] WHERE event_type = 'UNSUPPORTED_OBIS')
                 AND NOT EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE obis_code = '99.9.9') THEN 'PASS' ELSE 'FAIL' END, NULL;

/* ===========================================================================
   H. TAMPER -> anti-tamper job (TR20); tree; aggregates
   =========================================================================== */
BEGIN TRY
    EXEC [dbo].[sp_RaiseTamperEvent] NULL, 'NET-0002', N'tests.sql: cover opened';
    SELECT TOP (1) @id = w.work_order_id FROM [dbo].[WORK_ORDER] AS w JOIN [dbo].[EVENT] AS e ON e.event_id = w.event_id
    WHERE e.event_type = 'TAMPER_ALERT' AND w.meter_id = @m2 AND w.work_type = 'ANTI_TAMPER' AND w.origin = 'EVENT' AND w.status = 'SUBMITTED'
    ORDER BY w.work_order_id DESC;
    INSERT INTO #results VALUES ('H1 tamper alert creates an ANTI_TAMPER work order (TR20)', CASE WHEN @id IS NOT NULL THEN 'PASS' ELSE 'FAIL' END, NULL);
    EXEC [dbo].[sp_CancelWorkOrder] @off1, @id, N'tests.sql clean-up';
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('H1 tamper alert creates an ANTI_TAMPER work order (TR20)', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

-- the sum of a parent in the current state = the sum of its children, at every level
INSERT INTO #results
SELECT 'H2 tree state: every parent = sum of its children',
       CASE WHEN COUNT(*) > 0 AND SUM(CASE WHEN x.parent_sum = x.children_sum THEN 0 ELSE 1 END) = 0 THEN 'PASS' ELSE 'FAIL' END,
       N'parents checked: ' + CAST(COUNT(*) AS NVARCHAR(10))
FROM (SELECT s.transformer_id, s.obis_code, s.sum_value AS parent_sum,
             (SELECT SUM(cs.sum_value) FROM [dbo].[TRANSFORMER] AS ch
              JOIN [dbo].[TRANSFORMER_CURRENT_STATE] AS cs ON cs.transformer_id = ch.transformer_id AND cs.obis_code = s.obis_code
              WHERE ch.parent_transformer_id = s.transformer_id) AS children_sum
      FROM [dbo].[TRANSFORMER_CURRENT_STATE] AS s
      JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = s.transformer_id
      WHERE t.[level] > 1) AS x;

-- the root's DAY aggregate = the sum of the meters' DAY aggregates of that day
INSERT INTO #results
SELECT 'H3 transformer DAY aggregate of the root = sum of the meter DAY aggregates',
       CASE WHEN COUNT(*) > 0 AND SUM(CASE WHEN x.root_value = x.meters_value THEN 0 ELSE 1 END) = 0 THEN 'PASS' ELSE 'FAIL' END,
       N'days checked: ' + CAST(COUNT(*) AS NVARCHAR(10))
FROM (SELECT a.period_start, a.[value] AS root_value,
             (SELECT SUM(m.[value]) FROM [dbo].[AGGREGATE] AS m
              WHERE m.meter_id IS NOT NULL AND m.period_type = 'DAY' AND m.obis_code = '1.8.0' AND m.period_start = a.period_start) AS meters_value
      FROM [dbo].[AGGREGATE] AS a
      JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = a.transformer_id AND t.parent_transformer_id IS NULL
      WHERE a.period_type = 'DAY' AND a.obis_code = '1.8.0') AS x;

-- the recursive tree walk returns every transformer once
CREATE TABLE #tree_out (seq INT, transformer_id INT, name NVARCHAR(100), [level] TINYINT, depth INT, label NVARCHAR(200),
                    parent_transformer_id INT, capacity_kva DECIMAL(10,2), latitude DECIMAL(9,6), longitude DECIMAL(9,6),
                    min_lat DECIMAL(9,6), min_lon DECIMAL(9,6), max_lat DECIMAL(9,6), max_lon DECIMAL(9,6),
                    reference_15_min DATETIME2(0), import_kwh DECIMAL(20,4), export_kwh DECIMAL(20,4),
                    meters_reporting INT, meters_connected INT);
BEGIN TRY
    INSERT INTO #tree_out EXEC [dbo].[sp_GetTransformerTree] @tso, NULL;
    INSERT INTO #results
    SELECT 'H4 recursive tree walk: every transformer once, depth = distance from the root',
           CASE WHEN (SELECT COUNT(*) FROM #tree_out) = (SELECT COUNT(*) FROM [dbo].[TRANSFORMER])
                     AND (SELECT COUNT(DISTINCT transformer_id) FROM #tree_out) = (SELECT COUNT(*) FROM [dbo].[TRANSFORMER])
                     AND NOT EXISTS (SELECT 1 FROM #tree_out AS x WHERE x.depth <> (SELECT MAX([level]) FROM [dbo].[TRANSFORMER]) - x.[level]) THEN 'PASS' ELSE 'FAIL' END,
           N'rows: ' + CAST((SELECT COUNT(*) FROM #tree_out) AS NVARCHAR(10));
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('H4 recursive tree walk', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ===========================================================================
   I. GDPR after execution; retention purge
   =========================================================================== */
SELECT TOP (1) @uid = user_id FROM [dbo].[USER_ACCOUNT] WHERE anonymized_at IS NOT NULL ORDER BY user_id;
INSERT INTO #results
SELECT 'I1 forgotten user: anonymized, inactive, bills and aggregates kept, retention 1 month',
       CASE WHEN u.full_name = N'FORGOTTEN USER' AND u.is_active = 0 AND u.phone IS NULL AND u.iban IS NULL
                 AND EXISTS (SELECT 1 FROM [dbo].[BILL] AS b WHERE b.user_id = u.user_id)
                 AND EXISTS (SELECT 1 FROM [dbo].[AGGREGATE] AS a JOIN [dbo].[METER] AS m ON m.meter_id = a.meter_id
                             JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id WHERE p.user_id = u.user_id)
                 AND NOT EXISTS (SELECT 1 FROM [dbo].[METER] AS m JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
                                 WHERE p.user_id = u.user_id AND m.retention_months <> 1)
                 AND EXISTS (SELECT 1 FROM [dbo].[AUDIT_LOG] AS l WHERE l.object_type = 'USER_ACCOUNT' AND l.action = 'ANONYMIZE' AND l.object_id = CAST(u.user_id AS VARCHAR(30)))
            THEN 'PASS' ELSE 'FAIL' END, NULL
FROM [dbo].[USER_ACCOUNT] AS u WHERE u.user_id = @uid;

-- the purge deletes raw readings that are older than the cut-off and have a final DAY aggregate; aggregates stay.
-- Run with a cut-off of 0 months inside a transaction that is rolled back, so the demo data stays.
BEGIN TRY
    BEGIN TRANSACTION;
    SELECT @n2 = COUNT(*) FROM [dbo].[AGGREGATE] WHERE meter_id = @m3;
    EXEC [dbo].[sp__PurgeMeter] @m3, 0, @n OUTPUT;
    SET @id = CASE WHEN @n > 0 AND NOT EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE meter_id = @m3 AND is_final = 1)
                        AND (SELECT COUNT(*) FROM [dbo].[AGGREGATE] WHERE meter_id = @m3) = @n2 THEN 1 ELSE 0 END;
    ROLLBACK TRANSACTION;                 -- variables keep their values; the deleted readings come back
    INSERT INTO #results VALUES ('I2 purge: final days deleted from METER_READING, aggregates remain',
           CASE WHEN @id = 1 AND EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE meter_id = @m3 AND is_final = 1) THEN 'PASS' ELSE 'FAIL' END,
           N'readings deleted (rolled back): ' + CAST(@n AS NVARCHAR(10)));
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('I2 purge: final days deleted from METER_READING, aggregates remain', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ===========================================================================
   J. MARKET DATA: an organization sees only its own portfolio, never single meters
   =========================================================================== */
CREATE TABLE #da ([day] DATE, transformer_id INT, transformer_name NVARCHAR(100), import_kwh DECIMAL(20,4),
                  export_kwh DECIMAL(20,4), net_kwh DECIMAL(20,4), meter_count INT);
DECLARE @da_from DATE = DATEADD(DAY, -1, EOMONTH(@today, -1)), @da_to DATE = EOMONTH(@today, -1);
BEGIN TRY
    INSERT INTO #da EXEC [dbo].[sp_GetDayAheadAggregates] @sup1_user, @da_from, @da_to, 3, NULL;
    INSERT INTO #results
    SELECT 'J1 day-ahead data: only groups of 3 meters or more, only own customers',
           CASE WHEN EXISTS (SELECT 1 FROM #da) AND NOT EXISTS (SELECT 1 FROM #da WHERE meter_count < 3)
                     AND (SELECT MAX(meter_count) FROM #da) <= (SELECT COUNT(*) FROM [dbo].[PREMISE] WHERE supplier_org_id = @sup1) THEN 'PASS' ELSE 'FAIL' END,
           N'rows: ' + CAST((SELECT COUNT(*) FROM #da) AS NVARCHAR(10));
    DELETE FROM #da;
    INSERT INTO #da EXEC [dbo].[sp_GetDayAheadAggregates] @sup1_user, @da_from, @da_to, 1, NULL;
    INSERT INTO #results
    SELECT 'J2 day-ahead data at level 1: small groups are suppressed', CASE WHEN NOT EXISTS (SELECT 1 FROM #da WHERE meter_count < 3) THEN 'PASS' ELSE 'FAIL' END,
           N'rows: ' + CAST((SELECT COUNT(*) FROM #da) AS NVARCHAR(10));
END TRY
BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; INSERT INTO #results VALUES ('J market data', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ===========================================================================
   SUMMARY
   =========================================================================== */
SELECT seq, result, test, detail FROM #results ORDER BY seq;
SELECT result, COUNT(*) AS tests FROM #results GROUP BY result;
DECLARE @fails INT = (SELECT COUNT(*) FROM #results WHERE result <> 'PASS');
DECLARE @total INT = (SELECT COUNT(*) FROM #results);
PRINT 'tests.sql: ' + CAST(@total AS VARCHAR(10)) + ' tests, ' + CAST(@fails AS VARCHAR(10)) + ' not passed.';
DROP TABLE #results;
GO
SET NOEXEC OFF;
GO

/* ---------------------------------------------------------------------------
   CONCURRENCY (two SSMS windows, lecture 20-45) - cannot run inside one script:
     Window 1:  BEGIN TRANSACTION;
                EXEC dbo.sp_PayBill @actor_user_id = <consumer>, @bill_id = <bill>, @amount = <all that is left>, @method = 'CARD';
                -- do not commit yet
     Window 2:  EXEC dbo.sp_PayBill (the same call)     -- waits: the bill row is locked WITH (UPDLOCK, HOLDLOCK)
     Window 1:  COMMIT;
     Window 2:  now fails with 50003 (the bill is already PAID) - or 50004 after a partial first payment.
   The bill is never overpaid; TR06 (51006) is the second line of defence.
   --------------------------------------------------------------------------- */
