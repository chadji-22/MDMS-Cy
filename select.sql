/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   select.sql  -  Build Spec §13 / §15: one demo per use case (UC-01 ... UC-20), for the oral exam.
   Runs on the data of import.sql. Together with import.sql it calls every procedure of §9 at least once.
   Re-runnable: one-off flows (meter replacement, demo technician) are skipped when already done.
   PHP makes the same calls as  {call dbo.sp_X(?, ?, ...)}  with @actor_user_id = $_SESSION['user_id'].
   ============================================================================ */
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM [dbo].[USER_ACCOUNT] WHERE email = 'admin@mdms.cy')
BEGIN
    PRINT 'select.sql: run import.sql first.';
    SET NOEXEC ON;
END
GO

DECLARE @pw NVARCHAR(128) = N'Passw0rd!23';
DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
DECLARE @d2 DATE = EOMONTH(@today, -1), @d1 DATE = DATEADD(DAY, -1, EOMONTH(@today, -1));
DECLARE @t0 DATETIME2(0) = CAST(@d1 AS DATETIME2(0));                  -- start of the imported telemetry
DECLARE @t2 DATETIME2(0) = DATEADD(DAY, 2, @t0);                       -- its end (exclusive)
DECLARE @t_mid DATETIME2(0) = DATEADD(DAY, 1, @t0);
DECLARE @month_start DATETIME2(0) = CAST(DATEFROMPARTS(YEAR(@today), MONTH(@today), 1) AS DATETIME2(0));
DECLARE @tomorrow DATETIME2(0) = DATEADD(DAY, 1, CAST(@today AS DATETIME2(0)));
DECLARE @visit DATE = DATEADD(DAY, 3, @today);
DECLARE @s DATETIME2(0), @e DATETIME2(0);

DECLARE @admin INT, @off1 INT, @off2 INT, @dso INT, @tso INT, @tech1 INT, @c1 INT, @c2 INT, @c3 INT, @c4 INT,
        @sup1_user INT, @sup2_user INT, @agg_user INT, @sup1 INT, @sup2 INT;
SELECT @admin = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'admin@mdms.cy';
SELECT @off1  = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'officer1@mdms.cy';
SELECT @off2  = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'officer2@mdms.cy';
SELECT @dso   = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'dso@mdms.cy';
SELECT @tso   = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'tso@mdms.cy';
SELECT @tech1 = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'tech1@mdms.cy';
SELECT @c1    = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer1@example.cy';
SELECT @c2    = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer2@example.cy';
SELECT @c3    = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer3@example.cy';
SELECT @c4    = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer4@example.cy';
SELECT @sup1_user = user_id, @sup1 = organization_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'billing@eacsupply.cy';
SELECT @sup2_user = user_id, @sup2 = organization_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'billing@greenenergy.cy';
SELECT @agg_user  = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'desk@flexpool.cy';

DECLARE @p1 INT, @p3 INT, @p4 INT, @p5 INT, @p6 INT, @m1 INT, @m3 INT, @m4 INT, @m5 INT, @m6 INT, @m8 INT;
SELECT @m1 = meter_id, @p1 = premise_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0001';
SELECT @m3 = meter_id, @p3 = premise_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0003';
SELECT @m4 = meter_id, @p4 = premise_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0004';
SELECT @m5 = meter_id, @p5 = premise_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0005';
SELECT @m6 = meter_id, @p6 = premise_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0006';
SELECT @m8 = meter_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0008';

DECLARE @root INT, @l1 INT, @l3 INT;
SELECT @root = transformer_id FROM [dbo].[TRANSFORMER] WHERE parent_transformer_id IS NULL;
SELECT @l1 = transformer_id FROM [dbo].[TRANSFORMER] WHERE name = N'TX-L1 Strovolos';
SELECT @l3 = transformer_id FROM [dbo].[TRANSFORMER] WHERE name = N'TX-L3 Nicosia';

DECLARE @wo INT, @doc INT, @cmd INT, @bill INT, @id INT, @tech INT, @new_meter INT, @email VARCHAR(255),
        @fee DECIMAL(10,2), @service INT, @json NVARCHAR(4000), @net VARCHAR(60);

EXEC [dbo].[sp_SetAvailability] @tech1, @visit, '08:00', '16:00', N'Λευκωσία';

PRINT '=== UC-01  Consumer: login, profile, premises ===';
EXEC [dbo].[sp_Login] 'consumer1@example.cy', @pw;
EXEC [dbo].[sp_GetMyProfile] @c1;
EXEC [dbo].[sp_UpdateMyProfile] @c1, N'Νίκος Παναγιώτου', '99400001', 'CY17002001280000001200527600', 1, 1;
EXEC [dbo].[sp_ChangePassword] @c1, @pw, N'NewPassw0rd!45';
EXEC [dbo].[sp_ChangePassword] @c1, N'NewPassw0rd!45', @pw;             -- back to the demo password
EXEC [dbo].[sp_ListMyPremises] @c1;
EXEC [dbo].[sp_UpdatePremise] @c1, @p1, N'Λεωφ. Στροβόλου 101', 35.100, 33.250, 'RESIDENTIAL', N'Λευκωσία', N'Στρόβολος', N'Άγιος Δημήτριος', '2018', 'NONE', @sup1;
EXEC [dbo].[sp_ChangeSupplier] @c1, @p1, @sup2;                         -- the consumer changes supplier ...
EXEC [dbo].[sp_ChangeSupplier] @c1, @p1, @sup1;                         -- ... and comes back; old bills keep their supplier

PRINT '=== UC-02  Consumer: 15-minute series and voltage events ===';
-- current month: free (no rows here, the demo telemetry is from last month)
EXEC [dbo].[sp_GetPremiseReadings] @c1, @p1, @month_start, @tomorrow, N'1.8.0';
-- the same screen for the DSO, on the imported days
EXEC [dbo].[sp_GetPremiseReadings] @dso, @p3, @t0, @t_mid, N'1.8.0,2.8.0';
EXEC [dbo].[sp_GetPremiseEvents] @c2, @p3, NULL, NULL;                  -- the 198.5 V sag of meter 3

PRINT '=== UC-03  Consumer: past months after buying access (bought in import.sql for meter 3) ===';
EXEC [dbo].[sp_GetPremiseAggregates] @c2, @p3, 'DAY', @t0, @t2;
EXEC [dbo].[sp_GetPremiseAggregates] @off1, @p1, 'MONTH', @t0, @t2;

PRINT '=== UC-04  Consumer: consumption threshold and alert ===';
EXEC [dbo].[sp_SetPremiseThreshold] @c1, @p1, 10.0;                     -- 10 kWh a month: passed already
EXEC [dbo].[sp_CheckConsumptionThresholds] @off1, @d2;                  -- job for the previous month -> THRESHOLD_EXCEEDED
EXEC [dbo].[sp_GetPremiseEvents] @c1, @p1, NULL, NULL;

PRINT '=== UC-05  Fault request -> assignment -> decline -> history -> cancel ===';
EXEC [dbo].[sp_SubmitServiceRequest] @c3, @p5, NULL, 'FAULT_REPAIR', N'Ο μετρητής δεν δείχνει ενδείξεις στην οθόνη';
SELECT @wo = MAX(work_order_id) FROM [dbo].[WORK_ORDER] WHERE premise_id = @p5 AND origin = 'CONSUMER_REQUEST';
EXEC [dbo].[sp_FindAvailableTechnicians] @off1, @visit, '13:00', '14:00', N'Λευκωσία', N'Ηλεκτρολόγος Α΄';
SET @s = DATEADD(HOUR, 13, CAST(@visit AS DATETIME2(0)));  SET @e = DATEADD(HOUR, 1, @s);
EXEC [dbo].[sp_AssignWorkOrder] @off1, @wo, @tech1, @s, @e;
EXEC [dbo].[sp_ListMyWorkOrders] @tech1, NULL, 1, 50;                   -- the technician sees it, with coordinates
EXEC [dbo].[sp_DeclineWorkOrder] @tech1, @wo, N'Άλλη επείγουσα εργασία την ίδια ώρα';
EXEC [dbo].[sp_ListMyWorkOrders] @c3, NULL, 1, 50;                      -- the consumer sees the request back in SUBMITTED
EXEC [dbo].[sp_CancelWorkOrder] @c3, @wo, N'Το πρόβλημα λύθηκε';
EXEC [dbo].[sp_GetWorkOrderHistory] @c3, @wo;
EXEC [dbo].[sp_ListWorkOrders] @off1, NULL, NULL, N'Λευκωσία', 1, 50;

PRINT '=== UC-06  Bills and payments ===';
EXEC [dbo].[sp_GetMyBillsAndPayments] @c1, NULL, NULL;
EXEC [dbo].[sp_ListSupplierBills] @sup1_user, NULL, NULL, NULL, 1, 50;
EXEC [dbo].[sp_MarkOverdueBills] @off1, NULL;                           -- nothing is past its due date yet
SELECT @service = service_type_id, @fee = fee FROM [dbo].[SERVICE_TYPE] WHERE service_name = N'METER_CHECK';
EXEC [dbo].[sp_PayServiceFee] @c1, @service, @fee, 'CARD', NULL;
-- a wrong bill is cancelled (never deleted) and the next bill run issues it again
SELECT TOP (1) @bill = bill_id FROM [dbo].[BILL] WHERE user_id = @c4 AND status = 'ISSUED' ORDER BY bill_id DESC;
IF @bill IS NOT NULL
BEGIN
    DECLARE @by INT = YEAR(@d2), @bm INT = MONTH(@d2);
    EXEC [dbo].[sp_CancelBill] @off1, @bill, N'Λάθος τιμολόγιο';
    EXEC [dbo].[sp_IssueMonthlyBills] @off1, @by, @bm, @sup1;
END

PRINT '=== UC-07 / UC-08  GDPR requests with the history of their stages ===';
EXEC [dbo].[sp_ListGdprRequests] @off1, NULL, 1, 50;
EXEC [dbo].[sp_PurgeExpiredReadings] @off1;                             -- retention job (3 years, or 1 month after GDPR)

PRINT '=== UC-09  Technician registration: rejected document, resubmission, rejection, resubmission ===';
IF NOT EXISTS (SELECT 1 FROM [dbo].[USER_ACCOUNT] WHERE email = 'demo.tech@mdms.cy')
BEGIN
    EXEC [dbo].[sp_RegisterTechnician] 'demo.tech@mdms.cy', @pw, N'Λουκάς Νεοφύτου', '99300009', '1995-05-05', '/uploads/tech/photo_demo.jpg', N'Ηλεκτρολόγος Β΄';
    SELECT @tech = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'demo.tech@mdms.cy';
    EXEC [dbo].[sp_AddTechnicianDocument] @tech, 'ID_CARD', 'ID-DEMO-1', '2021-01-01', '2031-01-01', '/uploads/tech/id_demo_blurred.pdf';
    SELECT @doc = MAX(document_id) FROM [dbo].[DOCUMENT] WHERE user_id = @tech;
    EXEC [dbo].[sp_ListPendingTechnicians] @off1, 1, 50;
    EXEC [dbo].[sp_DecideDocument] @off1, @doc, 'REJECTED', N'Το αντίγραφο δεν είναι ευανάγνωστο';
    EXEC [dbo].[sp_ResubmitDocument] @tech, @doc, '/uploads/tech/id_demo_clear.pdf', '2021-01-01', '2031-01-01';
    EXEC [dbo].[sp_DecideTechnician] @off1, @tech, 'REJECTED', N'Λείπουν η άδεια και το πιστοποιητικό εκπαίδευσης';
    EXEC [dbo].[sp_ResubmitTechnician] @tech;
END
SELECT @tech = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'demo.tech@mdms.cy';
EXEC [dbo].[sp_SetAvailability] @tech, @visit, '09:00', '12:00', N'Πάφος';
EXEC [dbo].[sp_GetMyAvailability] @tech, NULL, NULL;
EXEC [dbo].[sp_DeleteAvailability] @tech, @visit, '09:00';
EXEC [dbo].[sp_GetMyProfile] @tech;                                     -- a PENDING technician can still see their own data

PRINT '=== UC-10  Meter data (installed and activated in import.sql) ===';
EXEC [dbo].[sp_GetMeter] @c1, @m1;
EXEC [dbo].[sp_ListMeters] @off1, 'ACTIVE', NULL, N'Λευκωσία', 1, 50;
EXEC [dbo].[sp_FindGeofenceForPoint] @off1, 35.100, 33.250;             -- the L1 geofence and the geofences above it

PRINT '=== UC-11  Meter replacement: the old meter and its readings stay ===';
IF NOT EXISTS (SELECT 1 FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0006R')
BEGIN
    EXEC [dbo].[sp_CreateWorkOrder] @off1, 'REPLACEMENT', @p6, @m6, NULL, N'Αντικατάσταση μετρητή λόγω βλάβης οθόνης', NULL, NULL;
    SELECT @wo = MAX(work_order_id) FROM [dbo].[WORK_ORDER] WHERE meter_id = @m6 AND work_type = 'REPLACEMENT';
    SET @s = DATEADD(HOUR, 9, CAST(@visit AS DATETIME2(0)));  SET @e = DATEADD(HOUR, 1, @s);
    EXEC [dbo].[sp_AssignWorkOrder] @off1, @wo, @tech1, @s, @e;
    EXEC [dbo].[sp_AcceptWorkOrder] @tech1, @wo;
    EXEC [dbo].[sp_StartWorkOrder] @tech1, @wo;
    EXEC [dbo].[sp_UpdateMeterTechnicalData] @tech1, @m6, 'FW-1.0.2', NULL, NULL;      -- last firmware note before removal (TR13 logs it)
    EXEC [dbo].[sp_ReplaceMeter] @tech1, @wo, @m6, 'SN-2026-0006R', 'NET-0006R', 'FW-2.0.0', 'CELLULAR', 35.220, 33.420, 1, '/uploads/meters/replace_6.jpg';
    SELECT @new_meter = meter_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0006R';
    EXEC [dbo].[sp_AddMeterDocument] @tech1, @new_meter, 'CALIBRATION_CERT', 'CAL-6R', '2026-06-01', '2031-06-01', '/uploads/meters/cal_6r.pdf';
    EXEC [dbo].[sp_AddMeterDocument] @tech1, @new_meter, 'CE_DECLARATION',   'CE-6R',  '2026-06-01', NULL,         '/uploads/meters/ce_6r.pdf';
    EXEC [dbo].[sp_AddMeterDocument] @tech1, @new_meter, 'ENCRYPTION_CERT',  'ENC-6R', '2026-06-01', '2028-06-01', '/uploads/meters/enc_6r.pdf';
    WHILE EXISTS (SELECT 1 FROM [dbo].[DOCUMENT] WHERE meter_id = @new_meter AND approval_status = 'PENDING')
    BEGIN
        SELECT TOP (1) @doc = document_id FROM [dbo].[DOCUMENT] WHERE meter_id = @new_meter AND approval_status = 'PENDING' ORDER BY document_id;
        EXEC [dbo].[sp_DecideDocument] @off1, @doc, 'APPROVED', NULL;
    END
    EXEC [dbo].[sp_ConfirmMeter] @off1, @new_meter, 'APPROVE', N'Νέος μετρητής μετά από αντικατάσταση';
    EXEC [dbo].[sp_CompleteWorkOrder] @tech1, @wo, N'Ο παλιός μετρητής αφαιρέθηκε, ο νέος λειτουργεί.', '/uploads/evidence/replace_6.jpg', NULL;
END
-- the premise keeps one series: the removed meter's days are still there
EXEC [dbo].[sp_GetPremiseAggregates] @dso, @p6, 'DAY', @t0, @t2;
EXEC [dbo].[sp_GetMeter] @off1, @m6;

PRINT '=== UC-12  Remote command: request, approval, attempts, ACK ===';
EXEC [dbo].[sp_RequestRemoteCommand] @tech1, @m1, 'RECONNECT', NULL;    -- a technician needs approval
SELECT @cmd = MAX(command_id) FROM [dbo].[REMOTE_COMMAND] WHERE meter_id = @m1;
EXEC [dbo].[sp_DecideRemoteCommand] @off1, @cmd, 'APPROVED', N'Εγκρίνεται';
EXEC [dbo].[sp_DispatchCommands] @off1, 3;                              -- attempt 1
EXEC [dbo].[sp_DispatchCommands] @off1, 3;                              -- attempt 2 (no ACK yet)
EXEC [dbo].[sp_AcknowledgeCommand] 'NET-0001', @cmd, N'Relay closed';   -- the meter answers
EXEC [dbo].[sp_ListCommands] @off1, NULL, @m1, 1, 50;

PRINT '=== UC-13  Remote shedding of a transformer (TSO) ===';
EXEC [dbo].[sp_ShedTransformerLoad] @tso, @l1, 'DISCONNECT', N'Υπερφόρτωση γραμμής';
EXEC [dbo].[sp_DispatchCommands] @tso, 3;
-- the meters answer
DECLARE c_ack CURSOR LOCAL FAST_FORWARD FOR
    SELECT c.command_id, m.network_id FROM [dbo].[REMOTE_COMMAND] AS c JOIN [dbo].[METER] AS m ON m.meter_id = c.meter_id
    WHERE c.status = 'SENT' AND m.transformer_id = @l1;
OPEN c_ack;
FETCH NEXT FROM c_ack INTO @cmd, @net;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC [dbo].[sp_AcknowledgeCommand] @net, @cmd, N'Relay open';
    FETCH NEXT FROM c_ack INTO @cmd, @net;
END
CLOSE c_ack; DEALLOCATE c_ack;
EXEC [dbo].[sp_ShedTransformerLoad] @tso, @l1, 'RECONNECT', N'Τέλος υπερφόρτωσης';
EXEC [dbo].[sp_DispatchCommands] @tso, 3;
EXEC [dbo].[sp_ListCommands] @tso, 'SENT', NULL, 1, 50;

PRINT '=== UC-14  Tamper alert -> anti-tamper job -> completion with the persons to notify ===';
EXEC [dbo].[sp_RaiseTamperEvent] @dso, 'NET-0004', N'Άνοιγμα καλύμματος ακροδεκτών';
SELECT @wo = MAX(work_order_id) FROM [dbo].[WORK_ORDER] WHERE meter_id = @m4 AND work_type = 'ANTI_TAMPER' AND status = 'SUBMITTED';
SET @s = DATEADD(HOUR, 11, CAST(@visit AS DATETIME2(0)));  SET @e = DATEADD(HOUR, 1, @s);
EXEC [dbo].[sp_AssignWorkOrder] @off1, @wo, @tech1, @s, @e;
EXEC [dbo].[sp_AcceptWorkOrder] @tech1, @wo;
EXEC [dbo].[sp_StartWorkOrder] @tech1, @wo;
EXEC [dbo].[sp_SetMeterStatus] @dso, @m4, 'FAULTY', N'Ύποπτη παρέμβαση';
EXEC [dbo].[sp_CompleteWorkOrder] @tech1, @wo, N'Σπασμένη σφραγίδα· δεν βρέθηκε παράκαμψη.', '/uploads/evidence/tamper_4.jpg', N'Αστυνομία, Τμήμα Απωλειών ΔΣΔ';
EXEC [dbo].[sp_SetMeterStatus] @dso, @m4, 'ACTIVE', N'Νέα σφραγίδα';
EXEC [dbo].[sp_GetWorkOrderHistory] @off1, @wo;

PRINT '=== UC-15  One packet from a meter (the JSON of the Appendix) ===';
SET @json = CONCAT(N'{"Meter_Network_ID":"NET-0001","Transmission_Timestamp":"', CONVERT(VARCHAR(19), @now, 126),
                   N'Z","Network_Type":"NB-IoT","Cell_Signal_Strength_dBm":-92,"Telemetry_Payload":[',
                   N'{"obis":"1.8.0","value":1099.5,"unit":"kWh"},{"obis":"32.7.0","value":231.2,"unit":"V"}]}');
EXEC [dbo].[sp_IngestTelemetryPacket] @json;

PRINT '=== UC-16  VEE is shown in import.sql; here the list of what still waits for a decision ===';
EXEC [dbo].[sp_ListSuspectReadings] @dso, NULL, NULL, 1, 50;

PRINT '=== UC-17  Transformer tree and its current state ===';
EXEC [dbo].[sp_GetTransformerTree] @tso, NULL;                          -- recursive cursor (lab 10 Hogwarts_Tree)
EXEC [dbo].[sp_GetTransformerTree] @dso, @l3;                           -- a subtree
DECLARE @ref DATETIME2(0) = DATEADD(MINUTE, -15, @t2);
EXEC [dbo].[sp_RefreshTransformerAncestors] @dso, @l1, @ref;            -- one L1 geofence and its ancestors
EXEC [dbo].[sp_RefreshTransformerState] @tso, @ref;                     -- the whole hierarchy
EXEC [dbo].[sp_GetTransformerState] @tso, NULL, NULL;
EXEC [dbo].[sp_GetTransformerState] @dso, @l3, 1;

PRINT '=== UC-18  Market data: Day-Ahead (final) and Intraday (provisional) ===';
EXEC [dbo].[sp_GetDayAheadAggregates] @sup1_user, @d1, @d2, 3, NULL;
EXEC [dbo].[sp_GetDayAheadAggregates] @agg_user, @d1, @d2, 4, NULL;
EXEC [dbo].[sp_GetIntradayProvisional] @sup2_user, @t_mid, @t2, 4;
EXEC [dbo].[sp_GetPortfolioSummary] @agg_user;
EXEC [dbo].[sp_GetPortfolioSummary] @sup1_user;

PRINT '=== UC-19  DSO analytics ===';
-- what the transformer itself measured in the last imported slot, and its frequency
IF NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER_READING] WHERE transformer_id = @l1 AND obis_code = '1.8.0' AND reading_timestamp = @ref)
    EXEC [dbo].[sp_RecordTransformerReading] @dso, @l1, @ref, '1.8.0', 0.50;
IF NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER_READING] WHERE transformer_id = @root AND obis_code = '14.7.0' AND reading_timestamp = @ref)
    EXEC [dbo].[sp_RecordTransformerReading] NULL, @root, @ref, '14.7.0', 49.72;       -- grid equipment: FREQUENCY_DEVIATION
EXEC [dbo].[sp_ReportVoltageEvents] @dso, @root, @t0, @t2;
EXEC [dbo].[sp_ReportPhaseUnbalance] @dso, @root, @t0, @t2, 20, 1;
EXEC [dbo].[sp_ReportTechnicalLosses] @dso, @l1, @ref, @t2, 1;         -- input 0.50 kWh against 0.44 kWh at the meters
EXEC [dbo].[sp_GetGridOverview] @tso, @ref;
EXEC [dbo].[sp_GetEvents] @dso, NULL, NULL, NULL, NULL, 1, 50;

PRINT '=== UC-20  Administrator and officer set-up ===';
EXEC [dbo].[sp_ListUsers] @admin, NULL, NULL, NULL, 1, 50;
EXEC [dbo].[sp_SetUserActive] @admin, @c4, 0;
EXEC [dbo].[sp_SetUserActive] @admin, @c4, 1;
SET @id = NULL;
SELECT @id = service_type_id FROM [dbo].[SERVICE_TYPE] WHERE service_name = N'RECONNECTION_FEE';
EXEC [dbo].[sp_UpsertServiceType] @off1, @id, N'RECONNECTION_FEE', 15.00, 1;
EXEC [dbo].[sp_UpsertObisCode] @off1, '13.7.0', N'Power factor', '-', 'INSTANTANEOUS', 0, 1;   -- a new quantity, no schema change
EXEC [dbo].[sp_GetAuditLog] @admin, 'METER', NULL, NULL, NULL, NULL, 1, 50;
EXEC [dbo].[sp_ReportSystemStatistics] @admin, @t0, @tomorrow;
GO

SET NOEXEC OFF;
GO
PRINT 'select.sql finished.';
GO
