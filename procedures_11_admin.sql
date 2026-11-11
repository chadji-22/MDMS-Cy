/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_11_admin.sql  -  Build Spec §9.11: reference data, audit, events, management report
   New meter types, services and OBIS codes are rows, not schema changes [§IV p.13 future extension].
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf Κοινές αρχές p.5: officers define the meter models; UC-20]
CREATE OR ALTER PROCEDURE [dbo].[sp_UpsertMeterType]
    @actor_user_id     INT,
    @meter_type_id     INT = NULL,
    @type_name         VARCHAR(50),
    @connection_phases TINYINT,
    @max_amps          DECIMAL(6,1)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_UpsertMeterType';

    IF @type_name IS NULL OR LTRIM(RTRIM(@type_name)) = '' OR @connection_phases IS NULL
       OR @connection_phases NOT IN (1, 3) OR @max_amps IS NULL OR @max_amps <= 0
        THROW 50004, 'Invalid input: name, phases (1 or 3) and max amps > 0 are required.', 1;
    IF @meter_type_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [dbo].[METER_TYPE] WHERE meter_type_id = @meter_type_id)
        THROW 50001, 'Meter type not found.', 1;
    IF EXISTS (SELECT 1 FROM [dbo].[METER_TYPE] WHERE type_name = LTRIM(RTRIM(@type_name)) AND meter_type_id <> ISNULL(@meter_type_id, 0))
        THROW 50005, 'Duplicate: a meter type with this name already exists.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        IF @meter_type_id IS NULL
        BEGIN
            INSERT INTO [dbo].[METER_TYPE] (type_name, connection_phases, max_amps)
            VALUES (LTRIM(RTRIM(@type_name)), @connection_phases, @max_amps);
            SET @meter_type_id = SCOPE_IDENTITY();
            EXEC [dbo].[sp__Log] 'CREATE', 'METER_TYPE', @meter_type_id, NULL, @type_name;
        END
        ELSE
        BEGIN
            UPDATE [dbo].[METER_TYPE]
               SET type_name = LTRIM(RTRIM(@type_name)), connection_phases = @connection_phases, max_amps = @max_amps
             WHERE meter_type_id = @meter_type_id;
            EXEC [dbo].[sp__Log] 'UPDATE', 'METER_TYPE', @meter_type_id, NULL, @type_name;
        END
        COMMIT TRANSACTION;
        SELECT @meter_type_id AS meter_type_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: a meter type with this name already exists.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf Κοινές αρχές p.5: officers define the service types and their fees; UC-20]
-- The seeded names HISTORICAL_ACCESS and METER_CHECK cannot be renamed: the procedures look them up by name.
CREATE OR ALTER PROCEDURE [dbo].[sp_UpsertServiceType]
    @actor_user_id   INT,
    @service_type_id INT = NULL,
    @service_name    NVARCHAR(100),
    @fee             DECIMAL(10,2),
    @is_active       BIT = 1
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_UpsertServiceType';

    IF @service_name IS NULL OR LTRIM(RTRIM(@service_name)) = N'' OR @fee IS NULL OR @fee < 0
        THROW 50004, 'Invalid input: a name and a fee >= 0 are required.', 1;
    SET @is_active = ISNULL(@is_active, 1);

    DECLARE @old_name NVARCHAR(100), @old_fee NVARCHAR(200), @new_fee NVARCHAR(200) = CAST(@fee AS NVARCHAR(30));
    IF @service_type_id IS NOT NULL
    BEGIN
        SELECT @old_name = service_name, @old_fee = CAST(fee AS NVARCHAR(30))
        FROM [dbo].[SERVICE_TYPE] WHERE service_type_id = @service_type_id;
        IF @old_name IS NULL
            THROW 50001, 'Service type not found.', 1;
        IF @old_name IN (N'HISTORICAL_ACCESS', N'METER_CHECK') AND @old_name <> LTRIM(RTRIM(@service_name))
            THROW 50003, 'The services HISTORICAL_ACCESS and METER_CHECK cannot be renamed.', 1;
    END
    IF EXISTS (SELECT 1 FROM [dbo].[SERVICE_TYPE] WHERE service_name = LTRIM(RTRIM(@service_name)) AND service_type_id <> ISNULL(@service_type_id, 0))
        THROW 50005, 'Duplicate: a service with this name already exists.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        IF @service_type_id IS NULL
        BEGIN
            INSERT INTO [dbo].[SERVICE_TYPE] (service_name, fee, is_active)
            VALUES (LTRIM(RTRIM(@service_name)), @fee, @is_active);
            SET @service_type_id = SCOPE_IDENTITY();
            EXEC [dbo].[sp__Log] 'CREATE', 'SERVICE_TYPE', @service_type_id, NULL, @new_fee, @service_name;
        END
        ELSE
        BEGIN
            UPDATE [dbo].[SERVICE_TYPE]
               SET service_name = LTRIM(RTRIM(@service_name)), fee = @fee, is_active = @is_active
             WHERE service_type_id = @service_type_id;
            EXEC [dbo].[sp__Log] 'UPDATE', 'SERVICE_TYPE', @service_type_id, @old_fee, @new_fee, @service_name;
        END
        COMMIT TRANSACTION;
        SELECT @service_type_id AS service_type_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: a service with this name already exists.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §3.1 p.8: new measurement types / codes can be added later; §IV p.13]
CREATE OR ALTER PROCEDURE [dbo].[sp_UpsertObisCode]
    @actor_user_id    INT,
    @obis_code        VARCHAR(20),
    @description      NVARCHAR(200),
    @unit             VARCHAR(10),
    @measurement_kind VARCHAR(15),
    @valid_min        DECIMAL(18,4) = NULL,
    @valid_max        DECIMAL(18,4) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_UpsertObisCode';

    IF @obis_code IS NULL OR LTRIM(RTRIM(@obis_code)) = '' OR @description IS NULL OR @unit IS NULL
        THROW 50004, 'Invalid input: code, description and unit are required.', 1;
    IF @measurement_kind IS NULL OR @measurement_kind NOT IN ('CUMULATIVE', 'INSTANTANEOUS')
        THROW 50004, 'Invalid input: the kind must be CUMULATIVE or INSTANTANEOUS.', 1;
    IF @valid_min IS NOT NULL AND @valid_max IS NOT NULL AND @valid_max < @valid_min
        THROW 50004, 'Invalid input: valid_max is below valid_min.', 1;
    IF EXISTS (SELECT 1 FROM [dbo].[OBIS_CODE] WHERE obis_code = @obis_code AND measurement_kind <> @measurement_kind)
       AND EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE obis_code = @obis_code)
        THROW 50003, 'The kind of a code that already has readings cannot change.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[OBIS_CODE]
           SET description = @description, unit = @unit, measurement_kind = @measurement_kind,
               valid_min = @valid_min, valid_max = @valid_max
         WHERE obis_code = @obis_code;
        IF @@ROWCOUNT = 0
        BEGIN
            INSERT INTO [dbo].[OBIS_CODE] (obis_code, description, unit, measurement_kind, valid_min, valid_max)
            VALUES (@obis_code, @description, @unit, @measurement_kind, @valid_min, @valid_max);
            EXEC [dbo].[sp__Log] 'CREATE', 'OBIS_CODE', @obis_code, NULL, @measurement_kind, @description;
        END
        ELSE
            EXEC [dbo].[sp__Log] 'UPDATE', 'OBIS_CODE', @obis_code, NULL, @measurement_kind, @description;
        COMMIT TRANSACTION;
        SELECT @obis_code AS obis_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf Κοινές αρχές p.5: every critical change can be traced]
CREATE OR ALTER PROCEDURE [dbo].[sp_GetAuditLog]
    @actor_user_id INT,
    @object_type   VARCHAR(30) = NULL,
    @object_id     VARCHAR(30) = NULL,
    @user_id       INT = NULL,
    @from          DATETIME2(0) = NULL,
    @to            DATETIME2(0) = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN,SYSTEM_OFFICER,DSO';
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 500 SET @page_size = 50;

    SELECT l.log_id, l.logged_at, l.actor_type, l.mechanism, l.action, l.object_type, l.object_id,
           l.old_state, l.new_state, l.comment, l.user_id, u.full_name AS user_name, u.role_code
    FROM [dbo].[AUDIT_LOG] AS l
    LEFT JOIN [dbo].[USER_ACCOUNT] AS u ON u.user_id = l.user_id
    WHERE (@object_type IS NULL OR l.object_type = @object_type)
      AND (@object_id IS NULL OR l.object_id = @object_id)
      AND (@user_id IS NULL OR l.user_id = @user_id)
      AND (@from IS NULL OR l.logged_at >= @from)
      AND (@to IS NULL OR l.logged_at <= @to)
    ORDER BY l.log_id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END;
GO

-- [project.pdf §2.4 p.8: the Event Log]
CREATE OR ALTER PROCEDURE [dbo].[sp_GetEvents]
    @actor_user_id INT,
    @event_type    VARCHAR(40) = NULL,
    @severity      VARCHAR(10) = NULL,
    @from          DATETIME2(0) = NULL,
    @to            DATETIME2(0) = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO,TSO';
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 500 SET @page_size = 50;

    SELECT e.event_id, e.event_timestamp, e.event_type, e.severity, e.description,
           e.meter_id, m.serial_number, e.transformer_id, t.name AS transformer_name, e.packet_id,
           (SELECT MAX(w.work_order_id) FROM [dbo].[WORK_ORDER] AS w WHERE w.event_id = e.event_id) AS work_order_id
    FROM [dbo].[EVENT] AS e
    LEFT JOIN [dbo].[METER] AS m ON m.meter_id = e.meter_id
    LEFT JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = e.transformer_id
    WHERE (@event_type IS NULL OR e.event_type = @event_type)
      AND (@severity IS NULL OR e.severity = @severity)
      AND (@from IS NULL OR e.event_timestamp >= @from)
      AND (@to IS NULL OR e.event_timestamp <= @to)
    ORDER BY e.event_timestamp DESC, e.event_id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END;
GO

-- [project.pdf p.2: reports for the management (analytic scenarios, OLAP)]
-- One result set in long form: section, label_1, label_2, value. PHP groups the rows by section.
CREATE OR ALTER PROCEDURE [dbo].[sp_ReportSystemStatistics]
    @actor_user_id INT,
    @from          DATETIME2(0),
    @to            DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN,SYSTEM_OFFICER';

    IF @from IS NULL OR @to IS NULL OR @to <= @from
        THROW 50004, 'Invalid input: the window must have from < to.', 1;

    SELECT x.section, x.label_1, x.label_2, x.[value]
    FROM (
        -- meters per district and status (today)
        SELECT CAST('METERS_BY_DISTRICT_STATUS' AS VARCHAR(40)) AS section, CAST(p.district AS NVARCHAR(100)) AS label_1,
               CAST(m.status AS NVARCHAR(100)) AS label_2, CAST(COUNT(*) AS DECIMAL(20,4)) AS [value]
        FROM [dbo].[METER] AS m JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
        GROUP BY p.district, m.status
        UNION ALL
        -- readings per status in the window
        SELECT 'READINGS_BY_STATUS', r.status, NULL, COUNT(*)
        FROM [dbo].[METER_READING] AS r
        WHERE r.reading_timestamp >= @from AND r.reading_timestamp < @to
        GROUP BY r.status
        UNION ALL
        -- VEE: share of each rule among the readings that VEE touched
        SELECT 'VEE_RULE_PCT', ISNULL(r.vee_rule, 'NONE'), NULL,
               CAST(COUNT(*) * 100.0 / NULLIF(SUM(COUNT(*)) OVER (), 0) AS DECIMAL(20,4))
        FROM [dbo].[METER_READING] AS r
        WHERE r.reading_timestamp >= @from AND r.reading_timestamp < @to AND r.status <> 'PENDING'
        GROUP BY ISNULL(r.vee_rule, 'NONE')
        UNION ALL
        -- consumption (kWh) per month and district, from the final DAY aggregates
        SELECT 'CONSUMPTION_BY_MONTH_DISTRICT', CONVERT(NVARCHAR(7), a.period_start, 120), p.district, SUM(a.[value])
        FROM [dbo].[AGGREGATE] AS a
        JOIN [dbo].[METER] AS m ON m.meter_id = a.meter_id
        JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
        WHERE a.period_type = 'DAY' AND a.obis_code = '1.8.0' AND a.is_final = 1
          AND a.period_start >= @from AND a.period_start < @to
        GROUP BY CONVERT(NVARCHAR(7), a.period_start, 120), p.district
        UNION ALL
        -- billed and collected amounts per supplier
        SELECT 'BILLED_BY_SUPPLIER', o.name, NULL, SUM(b.amount)
        FROM [dbo].[BILL] AS b JOIN [dbo].[ORGANIZATION] AS o ON o.organization_id = b.supplier_org_id
        WHERE b.status <> 'CANCELLED' AND b.issue_date >= CAST(@from AS DATE) AND b.issue_date < CAST(@to AS DATE)
        GROUP BY o.name
        UNION ALL
        SELECT 'COLLECTED_BY_SUPPLIER', o.name, NULL, SUM(pay.amount)
        FROM [dbo].[PAYMENT] AS pay
        JOIN [dbo].[BILL] AS b ON b.bill_id = pay.bill_id
        JOIN [dbo].[ORGANIZATION] AS o ON o.organization_id = b.supplier_org_id
        WHERE pay.status = 'COMPLETED' AND pay.payment_date >= @from AND pay.payment_date < @to
        GROUP BY o.name
        UNION ALL
        -- MDMS-Cy service fees collected
        SELECT 'SERVICE_FEES', s.service_name, NULL, SUM(pay.amount)
        FROM [dbo].[PAYMENT] AS pay JOIN [dbo].[SERVICE_TYPE] AS s ON s.service_type_id = pay.service_type_id
        WHERE pay.status = 'COMPLETED' AND pay.payment_date >= @from AND pay.payment_date < @to
        GROUP BY s.service_name
        UNION ALL
        -- work orders created in the window, per type and status
        SELECT 'WORK_ORDERS_BY_TYPE_STATUS', w.work_type, w.status, COUNT(*)
        FROM [dbo].[WORK_ORDER] AS w
        WHERE w.created_at >= @from AND w.created_at < @to
        GROUP BY w.work_type, w.status
        UNION ALL
        -- events in the window, per type
        SELECT 'EVENTS_BY_TYPE', e.event_type, e.severity, COUNT(*)
        FROM [dbo].[EVENT] AS e
        WHERE e.event_timestamp >= @from AND e.event_timestamp < @to
        GROUP BY e.event_type, e.severity
    ) AS x
    ORDER BY x.section, x.label_1, x.label_2;
END;
GO

PRINT 'procedures_11_admin.sql: 6 procedures created.';
GO
