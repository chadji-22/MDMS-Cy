"""Generate the SQL timing scripts for SQL2025 (python make_sql.py <out dir>).

reads.sql   every read procedure, 3 times each, as the web app runs it (EXECUTE AS USER = 'mdms_php'), no transaction.
writes.sql  every write procedure in short chains. Each chain runs in ONE transaction that is ALWAYS rolled back.
            Guards: after every call @@TRANCOUNT is checked (a procedure that catches errors per item rolls back the
            outer transaction; the chain then stops with 50999 and sqlcmd -b ends the run). Destructive steps use only
            rows created inside the same transaction. Every batch starts with IF @@TRANCOUNT > 0 ROLLBACK.
pilot.sql   one trivial chain, to prove the harness before the full run.
Output rows start with "RES|": group|seq|function|ms|note. Times are server-side (SYSDATETIME around the EXEC).
"""
import json
import os
import sys

OUT = sys.argv[1]
PW = "N'Passw0rd!23'"
HEX = '0123456789abcdef0123456789abcdef'


def step(label, call, after=''):
    """One timed call as mdms_php. 'after' runs as the owner (look-ups), outside the timing."""
    return f"""
    SET @cur = '{label}';
    EXECUTE AS USER = 'mdms_php';
    SET @t = SYSDATETIME();
    {call};
    INSERT @r(fn, ms) VALUES (@cur, DATEDIFF_BIG(MICROSECOND, @t, SYSDATETIME()) / 1000.0);
    REVERT;
    IF @@TRANCOUNT = 0 THROW 50999, 'outer transaction lost', 1;
    {after}"""


def raw(sql):
    return '\n    ' + sql


HEAD = """SET NOCOUNT ON;
DECLARE @g VARCHAR(60) = '{g}';
DECLARE @r TABLE(seq INT IDENTITY, fn VARCHAR(200), ms DECIMAL(12,1), note NVARCHAR(500));
DECLARE @t DATETIME2(7), @cur VARCHAR(200), @lost BIT = 0, @pw NVARCHAR(128) = {pw};
DECLARE @u INT, @u2 INT, @org INT, @p INT, @w INT, @w2 INT, @w3 INT, @m INT, @d1 INT, @d2 INT, @d3 INT, @c INT, @c2 INT,
        @gr INT, @tx INT, @rd BIGINT, @rd2 BIGINT, @svc INT, @fee DECIMAL(10,2), @fn NVARCHAR(150), @ph VARCHAR(20),
        @iban VARCHAR(34), @json NVARCHAR(MAX), @b INT, @ems DECIMAL(12,1), @en INT, @em NVARCHAR(300), @tc INT;
"""

TAIL = """
END TRY
BEGIN CATCH
    -- read everything first: a doomed transaction (XACT_ABORT) allows no write, not even to a table variable
    SELECT @ems = DATEDIFF_BIG(MICROSECOND, @t, SYSDATETIME()) / 1000.0, @en = ERROR_NUMBER(),
           @em = LEFT(ERROR_MESSAGE(), 300), @tc = @@TRANCOUNT;
    IF @@TRANCOUNT > 0 ROLLBACK;                 -- before REVERT: a doomed transaction refuses even REVERT (3930)
    IF USER_NAME() = 'mdms_php' REVERT;
    INSERT @r(fn, ms, note) VALUES (@cur, @ems, CONCAT('ERROR ', @en, ': ', @em, ' | trancount at error ', @tc));
    IF @en = 50999 SET @lost = 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
SELECT CONCAT('RES|', @g, '|', seq, '|', fn, '|', ms, '|', ISNULL(note, '')) AS res FROM @r ORDER BY seq;
IF @lost = 1 RAISERROR('LOST TRANSACTION in group %s: stopping the run', 16, 1, @g);
GO
"""


def chain(g, steps):
    return ('IF @@TRANCOUNT > 0 ROLLBACK;\nGO\n' + HEAD.format(g=g, pw=PW) + 'BEGIN TRY\n    BEGIN TRANSACTION;'
            + ''.join(steps) + TAIL)


# ---------------------------------------------------------------- reads (no transaction, each call in its own TRY)
READS = [
    ('consumer', 'sp_GetMyProfile 12', 'EXEC dbo.sp_GetMyProfile 12'),
    ('consumer', 'sp_ListMyPremises 12', 'EXEC dbo.sp_ListMyPremises 12'),
    ('consumer', 'sp_ListSuppliers', 'EXEC dbo.sp_ListSuppliers 12'),
    ('consumer', 'sp_GetPremiseReadings p3 2 days', "EXEC dbo.sp_GetPremiseReadings 13, 3, '2026-10-30', '2026-11-01'"),
    ('consumer', 'sp_GetPremiseReadings p3 31 days', "EXEC dbo.sp_GetPremiseReadings 13, 3, '2026-10-01', '2026-11-01'"),
    ('consumer', 'sp_GetPremiseReadings p1 not bought (50008)', "EXEC dbo.sp_GetPremiseReadings 12, 1, '2026-10-30', '2026-11-01'"),
    ('consumer', 'sp_GetPremiseAggregates DAY', "EXEC dbo.sp_GetPremiseAggregates 13, 3, 'DAY', '2026-10-01', '2026-11-01'"),
    ('consumer', 'sp_GetPremiseAggregates MONTH', "EXEC dbo.sp_GetPremiseAggregates 13, 3, 'MONTH', '2026-10-01', '2026-11-01'"),
    ('consumer', 'sp_GetHistoricalAccessQuote', "EXEC dbo.sp_GetHistoricalAccessQuote 13, 4, '2026-10-01', '2026-10-31'"),
    ('consumer', 'sp_GetPremiseEvents', 'EXEC dbo.sp_GetPremiseEvents 13, 3, NULL, NULL'),
    ('consumer', 'sp_ListMyNotifications', 'EXEC dbo.sp_ListMyNotifications 13, 3'),
    ('consumer', 'sp_ListMyWorkOrders (consumer)', 'EXEC dbo.sp_ListMyWorkOrders 12'),
    ('consumer', 'sp_GetWorkOrderHistory (consumer)', 'EXEC dbo.sp_GetWorkOrderHistory 12, 1'),
    ('consumer', 'sp_GetMyBillsAndPayments', 'EXEC dbo.sp_GetMyBillsAndPayments 12, NULL, NULL'),
    ('consumer', 'sp_ListServiceTypes', 'EXEC dbo.sp_ListServiceTypes 12'),
    ('consumer', 'sp_ListGdprRequests (consumer)', 'EXEC dbo.sp_ListGdprRequests 20'),
    ('technician', 'sp_ListMyWorkOrders (technician)', 'EXEC dbo.sp_ListMyWorkOrders 9'),
    ('technician', 'sp_GetWorkOrderHistory (technician)', 'EXEC dbo.sp_GetWorkOrderHistory 9, 1'),
    ('technician', 'sp_GetMyAvailability', 'EXEC dbo.sp_GetMyAvailability 9, NULL, NULL'),
    ('technician', 'sp_ListMyDocuments', 'EXEC dbo.sp_ListMyDocuments 9'),
    ('technician', 'sp_GetMeter (technician)', 'EXEC dbo.sp_GetMeter 9, 1'),
    ('staff', 'sp_ListOrganizations', 'EXEC dbo.sp_ListOrganizations 1'),
    ('staff', 'sp_GetAuditLog page 1', 'EXEC dbo.sp_GetAuditLog 1'),
    ('staff', 'sp_GetAuditLog page 5', 'EXEC dbo.sp_GetAuditLog 1, NULL, NULL, NULL, NULL, NULL, 5, 50'),
    ('staff', 'sp_ReportSystemStatistics', "EXEC dbo.sp_ReportSystemStatistics 1, '2026-10-01', '2026-12-01'"),
] + [('staff', f'sp_ListReferenceCatalog {c}', f"EXEC dbo.sp_ListReferenceCatalog 2, '{c}'") for c in ('meter-types', 'service-types', 'obis', 'tariffs')] + [
    ('staff', 'sp_ListGdprRequests (officer)', 'EXEC dbo.sp_ListGdprRequests 2'),
    ('staff', 'sp_ListMeters (officer)', 'EXEC dbo.sp_ListMeters 2'),
    ('staff', 'sp_GetMeter (officer)', 'EXEC dbo.sp_GetMeter 2, 1'),
    ('staff', 'sp_ListPendingTechnicians', 'EXEC dbo.sp_ListPendingTechnicians 2'),
    ('staff', 'sp_GetTechnicianReview', 'EXEC dbo.sp_GetTechnicianReview 2, 9'),
    ('staff', 'sp_ListWorkOrders', 'EXEC dbo.sp_ListWorkOrders 2'),
    ('staff', 'sp_FindAvailableTechnicians', "EXEC dbo.sp_FindAvailableTechnicians 2, '2026-12-02', '09:00', '10:00', N'Λευκωσία', NULL"),
    ('staff', 'sp_ListCommands', 'EXEC dbo.sp_ListCommands 2'),
    ('staff', 'sp_ListUsers (SQL only)', 'EXEC dbo.sp_ListUsers 1'),
    ('dso', 'sp_ListSuspectReadings', 'EXEC dbo.sp_ListSuspectReadings 4'),
    ('dso', 'sp_GetEvents', 'EXEC dbo.sp_GetEvents 4'),
    ('dso', 'sp_ReportVoltageEvents root', "EXEC dbo.sp_ReportVoltageEvents 4, 1, '2026-10-01', '2026-11-28'"),
    ('dso', 'sp_ReportPhaseUnbalance root', "EXEC dbo.sp_ReportPhaseUnbalance 4, 1, '2026-10-01', '2026-11-28', 20, 0"),
    ('dso', 'sp_ReportTechnicalLosses tx15', "EXEC dbo.sp_ReportTechnicalLosses 4, 15, '2026-10-01', '2026-11-28', 0"),
    ('tso', 'sp_GetGridOverview', 'EXEC dbo.sp_GetGridOverview 5, NULL'),
    ('tso', 'sp_GetTransformerTree', 'EXEC dbo.sp_GetTransformerTree 5, NULL'),
    ('tso', 'sp_GetTransformerState', 'EXEC dbo.sp_GetTransformerState 5, NULL, NULL'),
    ('tso', 'sp_FindGeofenceForPoint', 'EXEC dbo.sp_FindGeofenceForPoint 5, 35.185600, 33.382300'),
    ('tso', 'sp_ListMeters (map)', 'EXEC dbo.sp_ListMeters 5, NULL, NULL, NULL, 1, 500'),
    ('market', 'sp_GetPortfolioSummary supplier', 'EXEC dbo.sp_GetPortfolioSummary 6'),
    ('market', 'sp_GetPortfolioSummary aggregator', 'EXEC dbo.sp_GetPortfolioSummary 8'),
] + [('market', f'sp_GetDayAheadAggregates level {l}', f"EXEC dbo.sp_GetDayAheadAggregates 6, '2026-10-01', '2026-11-27', {l}, NULL") for l in (1, 2, 3)] + [
    ('market', 'sp_GetIntradayProvisional', "DECLARE @a DATETIME2(0) = DATEADD(DAY, -1, SYSUTCDATETIME()), @z DATETIME2(0) = SYSUTCDATETIME(); EXEC dbo.sp_GetIntradayProvisional 6, @a, @z, 1"),
    ('market', 'sp_ListSupplierBills', 'EXEC dbo.sp_ListSupplierBills 6'),
]


def reads():
    out = ['SET NOCOUNT ON;\nIF @@TRANCOUNT > 0 ROLLBACK;\nGO\n']
    for rep in (1, 2, 3):
        for g, label, call in READS:
            out.append(f"""DECLARE @t DATETIME2(7), @ms DECIMAL(12,1), @note NVARCHAR(500) = '';
BEGIN TRY
    EXECUTE AS USER = 'mdms_php';
    SET @t = SYSDATETIME();
    {call};
    SET @ms = DATEDIFF_BIG(MICROSECOND, @t, SYSDATETIME()) / 1000.0;
    REVERT;
END TRY
BEGIN CATCH
    SET @ms = DATEDIFF_BIG(MICROSECOND, @t, SYSDATETIME()) / 1000.0;
    IF USER_NAME() = 'mdms_php' REVERT;
    SET @note = CONCAT('ERROR ', ERROR_NUMBER(), ': ', LEFT(ERROR_MESSAGE(), 200));
END CATCH
SELECT CONCAT('RES|read-{g}|{rep}|{label}|', @ms, '|', @note) AS res;
GO
""")
    return ''.join(out)


# ---------------------------------------------------------------- writes
def packets(network, day, n=96, spikes=(50, 70), gap_at=60):
    """One meter-day: slots 00:00 .. 23:45, two spikes (VEE: SUSPECT) and one missing slot (VEE: ESTIMATED)."""
    arr, reg = [], 1000.0
    for k in range(n):
        reg += 25.0 if k in spikes else 0.5
        if k == gap_at:
            continue
        h, mi = divmod(15 * k, 60)
        ts = f'{day}T{h:02d}:{mi:02d}:00Z'
        arr.append({'Meter_Network_ID': network, 'Transmission_Timestamp': ts,
                    'Telemetry_Payload': [{'obis': '1.8.0', 'value': round(reg, 3), 'unit': 'kWh'}]})
    return json.dumps(arr, separators=(',', ':'))


def tsql_str(s):
    return "N'" + s.replace("'", "''") + "'"


BATCH = packets('NET-0001', '2026-11-26')
NPACK = BATCH.count('Meter_Network_ID')

W = []
W.append(chain('W01 accounts', [
    step('sp_Login (right password)', f"EXEC dbo.sp_Login 'consumer1@example.cy', @pw"),
    step('sp_RegisterConsumer', "EXEC dbo.sp_RegisterConsumer 'perf.c@example.cy', @pw, N'Δοκιμή Απόδοσης', '99000001', NULL, 1, 1",
         "SELECT @u = user_id FROM dbo.USER_ACCOUNT WHERE email = 'perf.c@example.cy';"),
    step('sp_UpdateMyProfile', "EXEC dbo.sp_UpdateMyProfile @u, N'Δοκιμή Απόδοσης Β', '99000002', NULL, 1, 0"),
    step('sp_ChangePassword', "EXEC dbo.sp_ChangePassword @u, @pw, N'Passw0rd!99'"),
    step('sp_CreateOrganization', "EXEC dbo.sp_CreateOrganization 1, N'Perf Supply Ltd', 'SUPPLIER'",
         "SELECT @org = organization_id FROM dbo.ORGANIZATION WHERE name = N'Perf Supply Ltd';"),
    step('sp_CreateStaffUser', "EXEC dbo.sp_CreateStaffUser 1, 'perf.staff@mdms.cy', @pw, N'Perf Staff', NULL, 'SYSTEM_OFFICER'"),
    step('sp_CreateOrganizationUser', "EXEC dbo.sp_CreateOrganizationUser 1, @org, 'perf.user@perfsupply.cy', @pw, N'Perf User', NULL"),
    step('sp_SetUserActive off (SQL only)', 'EXEC dbo.sp_SetUserActive 1, @u, 0'),
    step('sp_SetUserActive on (SQL only)', 'EXEC dbo.sp_SetUserActive 1, @u, 1'),
]))
W.append(chain('W02 login refused', [step('sp_Login (wrong password, error path)', "EXEC dbo.sp_Login 'consumer1@example.cy', N'wrong-password'")]))
W.append(chain('W03 technician onboarding', [
    step('sp_RegisterTechnician', f"EXEC dbo.sp_RegisterTechnician 'perf.t@mdms.cy', @pw, N'Perf Tech', '99000003', '1990-01-01', 'technician-photos/{HEX}.jpg', N'Ηλεκτρολόγος'",
         "SELECT @u = user_id FROM dbo.USER_ACCOUNT WHERE email = 'perf.t@mdms.cy';"),
    step('sp_AddTechnicianDocument', f"EXEC dbo.sp_AddTechnicianDocument @u, 'ID_CARD', 'ID-PERF-1', '2020-01-01', '2030-01-01', 'technician-documents/{HEX}.pdf'",
         "SELECT @d1 = MAX(document_id) FROM dbo.DOCUMENT WHERE user_id = @u;"),
    step('sp_ListMyDocuments (new technician)', 'EXEC dbo.sp_ListMyDocuments @u'),
    step('sp_GetTechnicianReview (new technician)', 'EXEC dbo.sp_GetTechnicianReview 2, @u'),
    step('sp_DecideDocument REJECTED', "EXEC dbo.sp_DecideDocument 2, @d1, 'REJECTED', N'perf: blurred'"),
    step('sp_ResubmitDocument', f"EXEC dbo.sp_ResubmitDocument @u, @d1, 'technician-documents/{HEX[::-1]}.pdf', '2020-01-01', '2030-01-01'"),
    step('sp_DecideDocument APPROVED', "EXEC dbo.sp_DecideDocument 2, @d1, 'APPROVED', NULL"),
    step('sp_AddTechnicianDocument (licence)', f"EXEC dbo.sp_AddTechnicianDocument @u, 'INSTALLER_LICENSE', 'LIC-PERF-1', '2020-01-01', '2030-01-01', 'technician-documents/{HEX[1:]}1.pdf'"),
    step('sp_AddTechnicianDocument (training)', f"EXEC dbo.sp_AddTechnicianDocument @u, 'TRAINING_CERT', 'TRN-PERF-1', '2020-01-01', '2030-01-01', 'technician-documents/{HEX[2:]}22.pdf'",
         "SELECT @d2 = MIN(document_id), @d3 = MAX(document_id) FROM dbo.DOCUMENT WHERE user_id = @u AND document_id > @d1;"),
    step('sp_DecideDocument APPROVED (licence)', "EXEC dbo.sp_DecideDocument 2, @d2, 'APPROVED', NULL"),
    step('sp_DecideDocument APPROVED (training)', "EXEC dbo.sp_DecideDocument 2, @d3, 'APPROVED', NULL"),
    step('sp_DecideTechnician REJECTED', "EXEC dbo.sp_DecideTechnician 2, @u, 'REJECTED', N'perf: licence missing'"),
    step('sp_ResubmitTechnician', 'EXEC dbo.sp_ResubmitTechnician @u'),
    step('sp_DecideTechnician APPROVED', "EXEC dbo.sp_DecideTechnician 2, @u, 'APPROVED', NULL"),
]))
W.append(chain('W04 availability', [
    step('sp_SetAvailability', "EXEC dbo.sp_SetAvailability 9, '2026-12-15', '08:00', '16:00', N'Λευκωσία'"),
    step('sp_FindAvailableTechnicians (with the slot)', "EXEC dbo.sp_FindAvailableTechnicians 2, '2026-12-15', '09:00', '10:00', N'Λευκωσία', NULL"),
    step('sp_DeleteAvailability', "EXEC dbo.sp_DeleteAvailability 9, '2026-12-15', '08:00'"),
]))
PREM = "N'Λευκωσία', N'Στρόβολος', N'Άγιος Δημήτριος', '2001', 'NONE'"
W.append(chain('W05 consumer premises and payments', [
    step('sp_AddPremise', f"EXEC dbo.sp_AddPremise 12, N'Perf premise A', 35.170000, 33.360000, 'RESIDENTIAL', {PREM}, 1",
         "SELECT @p = premise_id FROM dbo.PREMISE WHERE address = N'Perf premise A';"),
    step('sp_UpdatePremise (SQL only)', f"EXEC dbo.sp_UpdatePremise 12, @p, N'Perf premise A2', 35.170000, 33.360000, 'RESIDENTIAL', {PREM}, 1"),
    step('sp_ChangeSupplier (SQL only)', 'EXEC dbo.sp_ChangeSupplier 12, @p, 2'),
    step('sp_SetPremiseAggregator (SQL only)', 'EXEC dbo.sp_SetPremiseAggregator 12, @p, 3'),
    step('sp_SetPremiseThreshold', 'EXEC dbo.sp_SetPremiseThreshold 12, 2, 10',
         "SELECT @fn = full_name, @ph = phone, @iban = iban FROM dbo.USER_ACCOUNT WHERE user_id = 12;"),
    step('sp_UpdateMyProfile (notification preferences)', 'EXEC dbo.sp_UpdateMyProfile 12, @fn, @ph, @iban, 1, 1'),
    step('sp_BuyHistoricalAccess', "EXEC dbo.sp_BuyHistoricalAccess 13, 4, '2026-10-01', '2026-10-31', 'CARD', NULL"),
    step('sp_PayBill (part payment)', "EXEC dbo.sp_PayBill 12, 2, 1.00, 'CARD', NULL",
         "SELECT @svc = service_type_id, @fee = fee FROM dbo.SERVICE_TYPE WHERE service_name = 'METER_CHECK';"),
    step('sp_PayServiceFee', "EXEC dbo.sp_PayServiceFee 12, @svc, @fee, 'CARD', NULL"),
    step('sp_SubmitGdprRequest RETENTION_REDUCTION', "EXEC dbo.sp_SubmitGdprRequest 12, 'RETENTION_REDUCTION', 1"),
]))
W.append(chain('W06 threshold check', [
    step('sp_SetPremiseThreshold (premise 2, 10 kWh)', 'EXEC dbo.sp_SetPremiseThreshold 12, 2, 10'),
    step('sp_CheckConsumptionThresholds (SQL only; raises event + notifications)', "EXEC dbo.sp_CheckConsumptionThresholds 2, '2026-10-31'"),
]))
W.append(chain('W07 work orders', [
    step('sp_SetAvailability (for the jobs)', "EXEC dbo.sp_SetAvailability 9, '2026-12-16', '08:00', '16:00', N'Λευκωσία'"),
    step('sp_SubmitServiceRequest FAULT_REPAIR', "EXEC dbo.sp_SubmitServiceRequest 12, 1, NULL, 'FAULT_REPAIR', N'perf: display blank'",
         "SELECT @w = MAX(work_order_id) FROM dbo.WORK_ORDER WHERE description = N'perf: display blank';"),
    step('sp_AssignWorkOrder', "EXEC dbo.sp_AssignWorkOrder 2, @w, 9, '2026-12-16 09:00', '2026-12-16 10:00'"),
    step('sp_AcceptWorkOrder', 'EXEC dbo.sp_AcceptWorkOrder 9, @w'),
    step('sp_StartWorkOrder', 'EXEC dbo.sp_StartWorkOrder 9, @w'),
    step('sp_CompleteWorkOrder', "EXEC dbo.sp_CompleteWorkOrder 9, @w, N'perf: fuse replaced', NULL, NULL"),
    step('sp_SubmitServiceRequest TECHNICAL_CHECK', "EXEC dbo.sp_SubmitServiceRequest 12, 1, NULL, 'TECHNICAL_CHECK', N'perf: check'",
         "SELECT @w2 = MAX(work_order_id) FROM dbo.WORK_ORDER WHERE description = N'perf: check';"),
    step('sp_AssignWorkOrder (2nd)', "EXEC dbo.sp_AssignWorkOrder 2, @w2, 9, '2026-12-16 11:00', '2026-12-16 12:00'"),
    step('sp_DeclineWorkOrder', "EXEC dbo.sp_DeclineWorkOrder 9, @w2, N'perf: busy'"),
    step('sp_CancelWorkOrder', "EXEC dbo.sp_CancelWorkOrder 12, @w2, N'perf: not needed'"),
    step('sp_CreateWorkOrder ANTI_TAMPER (SQL only)', "EXEC dbo.sp_CreateWorkOrder 2, 'ANTI_TAMPER', 1, 1, NULL, N'perf: seal check', NULL, NULL"),
]))
W.append(chain('W08 meter installation and approval', [
    step('sp_SetAvailability (install day)', "EXEC dbo.sp_SetAvailability 9, '2026-12-17', '08:00', '16:00', N'Λευκωσία'"),
    step('sp_AddPremise (for the new meter)', f"EXEC dbo.sp_AddPremise 12, N'Perf premise B', 35.170000, 33.360000, 'RESIDENTIAL', {PREM}, 1",
         "SELECT @p = premise_id FROM dbo.PREMISE WHERE address = N'Perf premise B';"),
    step('sp_CreateWorkOrder INSTALLATION', "EXEC dbo.sp_CreateWorkOrder 2, 'INSTALLATION', @p, NULL, NULL, N'perf: install', NULL, NULL",
         "SELECT @w = MAX(work_order_id) FROM dbo.WORK_ORDER WHERE description = N'perf: install';"),
    step('sp_AssignWorkOrder (installation)', "EXEC dbo.sp_AssignWorkOrder 2, @w, 9, '2026-12-17 09:00', '2026-12-17 10:00'"),
    step('sp_AcceptWorkOrder (installation)', 'EXEC dbo.sp_AcceptWorkOrder 9, @w'),
    step('sp_InstallMeter', "EXEC dbo.sp_InstallMeter 9, @w, 'SN-PERF-0001', 'NET-PERF-0001', 'FW-1.0.0', 'PLC', 35.170000, 33.360000, 1, NULL, NULL",
         "SELECT @m = meter_id FROM dbo.METER WHERE serial_number = 'SN-PERF-0001';"),
    step('sp_AddMeterDocument CALIBRATION_CERT', f"EXEC dbo.sp_AddMeterDocument 9, @m, 'CALIBRATION_CERT', 'CAL-PERF', '2026-01-01', '2030-01-01', 'meter-certificates/{HEX}.pdf'"),
    step('sp_AddMeterDocument CE_DECLARATION', f"EXEC dbo.sp_AddMeterDocument 9, @m, 'CE_DECLARATION', 'CE-PERF', '2026-01-01', '2030-01-01', 'meter-certificates/{HEX[1:]}0.pdf'"),
    step('sp_AddMeterDocument ENCRYPTION_CERT', f"EXEC dbo.sp_AddMeterDocument 9, @m, 'ENCRYPTION_CERT', 'ENC-PERF', '2026-01-01', '2030-01-01', 'meter-certificates/{HEX[2:]}00.pdf'",
         "SELECT @d1 = MIN(document_id), @d3 = MAX(document_id) FROM dbo.DOCUMENT WHERE meter_id = @m; SET @d2 = @d1 + 1;"),
    step('sp_GetMeter (pending meter)', 'EXEC dbo.sp_GetMeter 2, @m'),
    step('sp_DecideDocument meter doc 1', "EXEC dbo.sp_DecideDocument 2, @d1, 'APPROVED', NULL"),
    step('sp_DecideDocument meter doc 2', "EXEC dbo.sp_DecideDocument 2, @d2, 'APPROVED', NULL"),
    step('sp_DecideDocument meter doc 3', "EXEC dbo.sp_DecideDocument 2, @d3, 'APPROVED', NULL"),
    step('sp_ConfirmMeter', "EXEC dbo.sp_ConfirmMeter 2, @m, 'APPROVE', NULL"),
    step('sp_UpdateMeterTechnicalData (SQL only)', "EXEC dbo.sp_UpdateMeterTechnicalData 2, @m, 'FW-1.0.1', NULL, NULL"),
    step('sp_SetMeterStatus (SQL only)', "EXEC dbo.sp_SetMeterStatus 4, @m, 'FAULTY', N'perf'"),
    step('sp_CreateWorkOrder REPLACEMENT (SQL only)', "EXEC dbo.sp_CreateWorkOrder 2, 'REPLACEMENT', @p, @m, NULL, N'perf: replace', NULL, NULL",
         "SELECT @w3 = MAX(work_order_id) FROM dbo.WORK_ORDER WHERE description = N'perf: replace';"),
    step('sp_AssignWorkOrder (replacement)', "EXEC dbo.sp_AssignWorkOrder 2, @w3, 9, '2026-12-17 11:00', '2026-12-17 12:00'"),
    step('sp_AcceptWorkOrder (replacement)', 'EXEC dbo.sp_AcceptWorkOrder 9, @w3'),
    step('sp_ReplaceMeter (SQL only)', "EXEC dbo.sp_ReplaceMeter 9, @w3, @m, 'SN-PERF-0002', 'NET-PERF-0002', 'FW-1.0.0', 'PLC', 35.170000, 33.360000, 1, NULL"),
]))
W.append(chain('W09 remote commands', [
    step('sp_RequestRemoteCommand (SQL only)', "EXEC dbo.sp_RequestRemoteCommand 9, 1, 'FIRMWARE_UPGRADE', N'FW-1.0.1'",
         "SELECT @c = MAX(command_id) FROM dbo.REMOTE_COMMAND WHERE meter_id = 1;"),
    step('sp_DecideRemoteCommand APPROVED', "EXEC dbo.sp_DecideRemoteCommand 2, @c, 'APPROVED', N'perf'"),
    step('sp_DispatchCommands (one command)', 'EXEC dbo.sp_DispatchCommands 2, 3, @c'),
    step('sp_SimulateCommandAcknowledgment', "EXEC dbo.sp_SimulateCommandAcknowledgment 2, @c, N'OK'"),
    step('sp_RequestRemoteCommand (2nd)', "EXEC dbo.sp_RequestRemoteCommand 9, 2, 'FIRMWARE_UPGRADE', N'FW-1.0.1'",
         "SELECT @c2 = MAX(command_id) FROM dbo.REMOTE_COMMAND WHERE meter_id = 2;"),
    step('sp_DecideRemoteCommand APPROVED (2nd)', "EXEC dbo.sp_DecideRemoteCommand 2, @c2, 'APPROVED', NULL"),
    step('sp_DispatchCommands (2nd)', 'EXEC dbo.sp_DispatchCommands 2, 3, @c2'),
    step('sp_AcknowledgeCommand (device ACK, SQL only)', "EXEC dbo.sp_AcknowledgeCommand 'NET-0002', @c2, N'OK'"),
    step('sp_RequestRemoteCommand (3rd)', "EXEC dbo.sp_RequestRemoteCommand 9, 3, 'FIRMWARE_UPGRADE', N'FW-1.0.1'",
         "SELECT @c = MAX(command_id) FROM dbo.REMOTE_COMMAND WHERE meter_id = 3;"),
    step('sp_DecideRemoteCommand REJECTED', "EXEC dbo.sp_DecideRemoteCommand 2, @c, 'REJECTED', N'perf'"),
]))
W.append(chain('W10 load shedding (1 level-1 transformer)', [
    step('sp_ShedTransformerLoad tx15', "EXEC dbo.sp_ShedTransformerLoad 5, 15, 'DISCONNECT', N'perf: shed tx15'"),
    step('sp_ListCommands (TSO)', 'EXEC dbo.sp_ListCommands 5'),
    step('sp_DispatchCommands (all approved)', 'EXEC dbo.sp_DispatchCommands 5, 3, NULL'),
]))
W.append(chain('W11 load shedding (whole grid)', [
    step('sp_ShedTransformerLoad root (all meters)', "EXEC dbo.sp_ShedTransformerLoad 5, 1, 'DISCONNECT', N'perf: shed root'"),
    step('sp_DispatchCommands (all, after root shed)', 'EXEC dbo.sp_DispatchCommands 5, 3, NULL'),
]))
W.append(chain('W12 telemetry single packet', [
    step('sp_IngestTelemetryPacket', "EXEC dbo.sp_IngestTelemetryPacket N'{\"Meter_Network_ID\":\"NET-0003\",\"Transmission_Timestamp\":\"2026-11-26T00:15:00Z\",\"Telemetry_Payload\":[{\"obis\":\"1.8.0\",\"value\":5000.5,\"unit\":\"kWh\"},{\"obis\":\"2.8.0\",\"value\":10.1,\"unit\":\"kWh\"}]}', 0"),
]))
W.append(chain('W13 telemetry day: batch, VEE, suspects, finalize, transformer totals', [
    raw(f'SET @json = {tsql_str(BATCH)};'),
    step(f'sp_IngestTelemetryBatch ({NPACK} packets, 1 meter-day)', 'EXEC dbo.sp_IngestTelemetryBatch 4, @json'),
    step('sp_RunVEE (meter 1, the day)', "EXEC dbo.sp_RunVEE 4, '2026-11-26 00:00', '2026-11-27 00:00', 1"),
    step('sp_ListSuspectReadings (the day)', "EXEC dbo.sp_ListSuspectReadings 4, '2026-11-26', '2026-11-27'",
         "SELECT @rd = MIN(reading_id), @rd2 = MAX(reading_id) FROM dbo.METER_READING WHERE meter_id = 1 AND status = 'SUSPECT' AND reading_timestamp >= '2026-11-26' AND reading_timestamp < '2026-11-27';"
         " INSERT @r(fn, note) VALUES ('(suspects after VEE)', CONCAT((SELECT COUNT(*) FROM dbo.METER_READING WHERE meter_id = 1 AND status = 'SUSPECT' AND reading_timestamp >= '2026-11-26' AND reading_timestamp < '2026-11-27'), ' suspect, ', (SELECT COUNT(*) FROM dbo.METER_READING WHERE meter_id = 1 AND reading_timestamp >= '2026-11-26' AND reading_timestamp < '2026-11-27'), ' readings'));"),
    raw("IF @rd IS NULL THROW 50998, 'no suspect reading to decide', 1;"),
    step('sp_AcceptSuspectReading', "EXEC dbo.sp_AcceptSuspectReading 4, @rd, N'perf'"),
    raw("IF @rd2 <> @rd BEGIN"),
    step('sp_EditReading', "EXEC dbo.sp_EditReading 4, @rd2, 0.5, N'perf'"),
    raw("END"),
    raw("WHILE EXISTS (SELECT 1 FROM dbo.METER_READING WHERE meter_id = 1 AND status = 'SUSPECT' AND reading_timestamp >= '2026-11-26' AND reading_timestamp < '2026-11-27') "
        "BEGIN SELECT @rd = MIN(reading_id) FROM dbo.METER_READING WHERE meter_id = 1 AND status = 'SUSPECT' AND reading_timestamp >= '2026-11-26' AND reading_timestamp < '2026-11-27'; "
        "EXECUTE AS USER = 'mdms_php'; EXEC dbo.sp_AcceptSuspectReading 4, @rd, N'perf'; REVERT; IF @@TRANCOUNT = 0 THROW 50999, 'outer transaction lost', 1; END"),
    step('sp_FinalizeReadings (meter 1, the day)', "EXEC dbo.sp_FinalizeReadings 4, '2026-11-26', 1"),
    step('sp_BuildTransformerAggregates (the day)', "EXEC dbo.sp_BuildTransformerAggregates 4, '2026-11-26', 0"),
]))
W.append(chain('W14 tamper and reports with events', [
    step('sp_RaiseTamperEvent', "EXEC dbo.sp_RaiseTamperEvent 4, 'NET-0002', N'perf: cover opened'"),
    step('sp_ReportPhaseUnbalance (raise events)', "EXEC dbo.sp_ReportPhaseUnbalance 4, 1, '2026-10-01', '2026-11-28', 20, 1"),
    step('sp_ReportTechnicalLosses (raise events)', "EXEC dbo.sp_ReportTechnicalLosses 4, 15, '2026-10-01', '2026-11-28', 1"),
]))
W.append(chain('W15 grid (TSO / DSO)', [
    step('sp_RefreshTransformerState', 'EXEC dbo.sp_RefreshTransformerState 5, NULL'),
    step('sp_RefreshTransformerAncestors', "EXEC dbo.sp_RefreshTransformerAncestors 5, 15, '2026-10-31 12:00'"),
    step('sp_RecordTransformerReading', "EXEC dbo.sp_RecordTransformerReading 4, 15, '2026-11-26 12:00', '14.7.0', 50.01"),
    # TX-L3 South (3) has free space between Larnaca (4) and Limassol (5): longitude 33.15 - 33.55
    step('sp_UpsertTransformer (new)', "EXEC dbo.sp_UpsertTransformer 5, NULL, N'TX-L2 Perf', 2, 2000.00, 34.750000, 33.250000, 34.700000, 33.200000, 34.800000, 33.300000, 3",
         "SELECT @tx = transformer_id FROM dbo.TRANSFORMER WHERE name = N'TX-L2 Perf';"),
    step('sp_UpsertTransformer (edit)', "EXEC dbo.sp_UpsertTransformer 5, @tx, N'TX-L2 Perf', 2, 2500.00, 34.750000, 33.250000, 34.700000, 33.200000, 34.800000, 33.300000, 3"),
]))
W.append(chain('W16 catalogs', [
    step('sp_UpsertMeterType', "EXEC dbo.sp_UpsertMeterType 2, NULL, 'PERF-1P', 1, 60.0"),
    step('sp_UpsertServiceType', "EXEC dbo.sp_UpsertServiceType 2, NULL, N'PERF_SERVICE', 12.50, 1"),
    step('sp_UpsertObisCode', "EXEC dbo.sp_UpsertObisCode 2, '99.9.9', N'perf code', 'kWh', 'CUMULATIVE', 0, 1000, 1"),
    step('sp_UpsertTariff', "EXEC dbo.sp_UpsertTariff 2, NULL, N'Perf tariff', 0.2500, '2027-01-01', NULL"),
]))
W.append(chain('W17 GDPR right to be forgotten (throw-away consumer)', [
    step('sp_RegisterConsumer (throw-away)', "EXEC dbo.sp_RegisterConsumer 'perf.g@example.cy', @pw, N'Perf Forget', '99000004', NULL, 1, 0",
         "SELECT @u = user_id FROM dbo.USER_ACCOUNT WHERE email = 'perf.g@example.cy';"),
    step('sp_SubmitGdprRequest RIGHT_TO_BE_FORGOTTEN', "EXEC dbo.sp_SubmitGdprRequest @u, 'RIGHT_TO_BE_FORGOTTEN', NULL",
         "SELECT @gr = MAX(gdpr_request_id) FROM dbo.GDPR_REQUEST WHERE user_id = @u;"),
    step('sp_AdvanceGdprRequest UNDER_REVIEW', "EXEC dbo.sp_AdvanceGdprRequest 2, @gr, 'UNDER_REVIEW', NULL"),
    step('sp_AdvanceGdprRequest PRE_APPROVED', "EXEC dbo.sp_AdvanceGdprRequest 2, @gr, 'PRE_APPROVED', NULL"),
    step('sp_AdvanceGdprRequest APPROVED (2nd officer)', "EXEC dbo.sp_AdvanceGdprRequest 3, @gr, 'APPROVED', NULL"),
    step('sp_ExecuteGdprRequest (SQL only)', 'EXEC dbo.sp_ExecuteGdprRequest 3, @gr'),
]))
W.append(chain('W18 purge (alone)', [step('sp_PurgeExpiredReadings (SQL only)', 'EXEC dbo.sp_PurgeExpiredReadings 2')]))
W.append(chain('W19 bootstrap admin (refused: an admin exists)', [step('sp_BootstrapAdmin (error path)', "EXEC dbo.sp_BootstrapAdmin 'perf.admin@mdms.cy', @pw, N'Perf Admin'")]))
W.append(chain('W20 bills: cancel 6, re-issue October', [
    step('sp_CancelBill (bill 2)', "EXEC dbo.sp_CancelBill 2, 2, N'perf'"),
] + [step(f'sp_CancelBill (bill {b})', f"EXEC dbo.sp_CancelBill 2, {b}, N'perf'") for b in (3, 4, 5, 6, 7)] + [
    step('sp_IssueMonthlyBills (October, supplier 1: 6 premises)', 'EXEC dbo.sp_IssueMonthlyBills 6, 2026, 10, NULL'),
    step('sp_ListSupplierBills (after issuing)', 'EXEC dbo.sp_ListSupplierBills 6'),
]))
W.append(chain('W21 overdue bills (alone)', [step('sp_MarkOverdueBills (SQL only, as of 2027-02-01)', "EXEC dbo.sp_MarkOverdueBills 2, '2027-02-01'")]))

os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, 'reads.sql'), 'w', encoding='utf-8').write(reads())
open(os.path.join(OUT, 'writes.sql'), 'w', encoding='utf-8').write('SET NOCOUNT ON;\nGO\n' + ''.join(W))
open(os.path.join(OUT, 'pilot.sql'), 'w', encoding='utf-8').write('SET NOCOUNT ON;\nGO\n' + chain('P01 pilot', [
    step('sp_SetPremiseThreshold (pilot)', 'EXEC dbo.sp_SetPremiseThreshold 12, 2, 10')]))
print(f'{len(READS)} read calls x 3, {len(W)} write chains, batch of {NPACK} packets')
