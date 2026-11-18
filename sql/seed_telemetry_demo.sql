/* ============================================================================
   seed_telemetry_demo.sql  -  the demo meter DEMO-NET-001 for the telemetry tests

   Ported to the io schema (v6). What changed against the first version:
     * METER has no approval_status / retention_policy_id; it has network_id, installed_at,
       premise_id, transformer_id and retention_months.
     * TR04 refuses an ACTIVE meter without 3 approved certificates, so a direct
       INSERT ... status = 'ACTIVE' fails. The meter is created the way import.sql does it:
       premise -> installation work order -> technician installs the meter -> 3 certificates
       -> officer approves the documents and confirms the meter.
     * the meter hangs on the level-1 transformer DEMO_TX_L1 (seed_grid.sql).

   Needs: import.sql and seed_grid.sql. Re-runnable: nothing happens when DEMO-NET-001 exists.
   Users: officer1 (work order), officer2 (documents + confirmation), tech1, consumer9, EAC Supply.
   If an earlier run stopped half way (meter exists but is not ACTIVE) the script says so and stops.
   ============================================================================ */
SET NOCOUNT ON;

DECLARE @existing VARCHAR(20) = (SELECT status FROM [dbo].[METER] WHERE network_id = 'DEMO-NET-001');
IF @existing IS NOT NULL AND @existing <> 'ACTIVE'
    -- an earlier run stopped half way (the technician registered the meter, the approval did not finish)
    THROW 54000, 'seed_telemetry_demo.sql: DEMO-NET-001 exists but is not ACTIVE (an earlier run stopped half way). Approve its 3 documents with sp_DecideDocument and call sp_ConfirmMeter as officer2@mdms.cy, or remove the half-made demo rows and run this script again.', 1;

IF @existing = 'ACTIVE'
BEGIN
    PRINT 'seed_telemetry_demo.sql: DEMO-NET-001 already exists and is ACTIVE - nothing to do.';
END
ELSE
BEGIN
    DECLARE @off1 INT, @off2 INT, @tech INT, @consumer INT, @supplier INT, @tx INT, @type INT;
    SELECT @off1     = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'officer1@mdms.cy';
    SELECT @off2     = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'officer2@mdms.cy';
    SELECT @tech     = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'tech1@mdms.cy';
    -- consumer9 is not used by tests.sql / select.sql (consumer3 goes through a GDPR flow there; consumer10 of import.sql is anonymized)
    SELECT @consumer = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer9@example.cy';
    SELECT @supplier = organization_id FROM [dbo].[ORGANIZATION] WHERE name = N'EAC Supply';
    SELECT @tx       = transformer_id FROM [dbo].[TRANSFORMER] WHERE name = N'DEMO_TX_L1' AND [level] = 1;
    SELECT @type     = meter_type_id FROM [dbo].[METER_TYPE] WHERE type_name = 'Single-Phase 1x60A';

    IF @off1 IS NULL OR @off2 IS NULL OR @tech IS NULL OR @consumer IS NULL OR @supplier IS NULL OR @type IS NULL
        THROW 54000, 'seed_telemetry_demo.sql: run import.sql first (staff, consumer, supplier or meter type missing).', 1;
    IF @tx IS NULL
        THROW 54000, 'seed_telemetry_demo.sql: run seed_grid.sql first (DEMO_TX_L1 is missing).', 1;

    DECLARE @addr NVARCHAR(250) = N'DEMO premise (seed_telemetry_demo.sql)';
    DECLARE @premise INT, @wo INT, @meter INT, @doc INT;
    DECLARE @visit DATE = DATEADD(DAY, 2, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @s DATETIME2(0) = DATEADD(HOUR, 15, CAST(@visit AS DATETIME2(0)));   -- 15:00 - 16:00, inside the availability
    DECLARE @e DATETIME2(0) = DATEADD(HOUR, 1, @s);

    -- the technician must be available on the visit day (the availability of import.sql covers only its first days)
    EXEC [dbo].[sp_SetAvailability] @tech, @visit, '08:00', '16:00', N'Λευκωσία';

    EXEC [dbo].[sp_AddPremise] @consumer, @addr, 35.160, 33.370, 'RESIDENTIAL',
         N'Λευκωσία', N'Λευκωσία', N'Δοκιμή', '1010', 'NONE', @supplier;
    SELECT @premise = MAX(premise_id) FROM [dbo].[PREMISE] WHERE address = @addr;

    EXEC [dbo].[sp_CreateWorkOrder] @off1, 'INSTALLATION', @premise, NULL, NULL, N'seed_telemetry_demo.sql', NULL, NULL;
    SELECT @wo = MAX(work_order_id) FROM [dbo].[WORK_ORDER] WHERE premise_id = @premise;
    EXEC [dbo].[sp_AssignWorkOrder] @off1, @wo, @tech, @s, @e;
    EXEC [dbo].[sp_AcceptWorkOrder] @tech, @wo;
    EXEC [dbo].[sp_StartWorkOrder]  @tech, @wo;

    -- the transformer is given explicitly (the demo rectangle may not be the smallest one around the point)
    EXEC [dbo].[sp_InstallMeter] @tech, @wo, 'DEMO-SERIAL-001', 'DEMO-NET-001', '1.0', 'NB_IOT',
         35.160, 33.370, @type, '/uploads/meters/demo_install.jpg', @tx;
    SELECT @meter = meter_id FROM [dbo].[METER] WHERE network_id = 'DEMO-NET-001';

    EXEC [dbo].[sp_AddMeterDocument] @tech, @meter, 'CALIBRATION_CERT', 'DEMO-CAL-001', '2026-01-10', '2031-01-10', '/uploads/meters/demo_cal.pdf';
    EXEC [dbo].[sp_AddMeterDocument] @tech, @meter, 'CE_DECLARATION',   'DEMO-CE-001',  '2026-01-10', NULL,         '/uploads/meters/demo_ce.pdf';
    EXEC [dbo].[sp_AddMeterDocument] @tech, @meter, 'ENCRYPTION_CERT',  'DEMO-ENC-001', '2026-01-10', '2028-01-10', '/uploads/meters/demo_enc.pdf';

    WHILE EXISTS (SELECT 1 FROM [dbo].[DOCUMENT] WHERE meter_id = @meter AND approval_status = 'PENDING')
    BEGIN
        SELECT TOP (1) @doc = document_id FROM [dbo].[DOCUMENT]
        WHERE meter_id = @meter AND approval_status = 'PENDING' ORDER BY document_id;
        EXEC [dbo].[sp_DecideDocument] @off2, @doc, 'APPROVED', NULL;
    END
    EXEC [dbo].[sp_ConfirmMeter] @off2, @meter, 'APPROVE', N'Demo meter for the telemetry tests';
    EXEC [dbo].[sp_CompleteWorkOrder] @tech, @wo, N'Demo meter installed.', '/uploads/evidence/demo_install.jpg', NULL;
END

SELECT meter_id, serial_number, network_id, status, activated_at, transformer_id, premise_id, retention_months
FROM [dbo].[METER]
WHERE network_id = 'DEMO-NET-001';
