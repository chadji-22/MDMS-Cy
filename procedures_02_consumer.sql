/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_02_consumer.sql  -  Build Spec §9.2: premises and consumption
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf §1.1 p.5: a consumer registers one or more premises; UC-01]
CREATE OR ALTER PROCEDURE [dbo].[sp_AddPremise]
    @actor_user_id   INT,
    @address         NVARCHAR(250),
    @latitude        DECIMAL(9,6),
    @longitude       DECIMAL(9,6),
    @usage_type      VARCHAR(20),
    @district        NVARCHAR(30),
    @municipality    NVARCHAR(80),
    @parish          NVARCHAR(80),
    @postal_code     CHAR(4),
    @prosumer_scheme VARCHAR(20) = 'NONE',
    @supplier_org_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_AddPremise';

    SET @prosumer_scheme = ISNULL(@prosumer_scheme, 'NONE');
    IF @address IS NULL OR @municipality IS NULL OR @parish IS NULL
        THROW 50004, 'Invalid input: address, municipality and parish are required.', 1;
    IF @latitude IS NULL OR @longitude IS NULL OR @latitude NOT BETWEEN -90 AND 90 OR @longitude NOT BETWEEN -180 AND 180
        THROW 50004, 'Invalid input: the coordinates are not valid.', 1;
    IF @usage_type IS NULL OR @usage_type NOT IN ('RESIDENTIAL', 'COMMERCIAL', 'INDUSTRIAL', 'AGRICULTURAL')
        THROW 50004, 'Invalid input: unknown usage type.', 1;
    IF @district IS NULL OR @district NOT IN (N'Λευκωσία', N'Λεμεσός', N'Λάρνακα', N'Πάφος', N'Αμμόχωστος', N'Κερύνεια')
        THROW 50004, 'Invalid input: the district must be one of the 6 districts.', 1;
    IF @postal_code IS NULL OR @postal_code NOT LIKE '[0-9][0-9][0-9][0-9]'
        THROW 50004, 'Invalid input: the postal code needs 4 digits.', 1;
    IF @prosumer_scheme NOT IN ('NONE', 'NET_METERING', 'NET_BILLING')
        THROW 50004, 'Invalid input: unknown prosumer scheme.', 1;
    IF @supplier_org_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM [dbo].[ORGANIZATION] WHERE organization_id = @supplier_org_id AND org_type = 'SUPPLIER')
        THROW 50004, 'Invalid input: the supplier does not exist.', 1;

    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[PREMISE] (address, latitude, longitude, usage_type, district, municipality, parish,
                                     postal_code, prosumer_scheme, user_id, supplier_org_id)
        VALUES (@address, @latitude, @longitude, @usage_type, @district, @municipality, @parish,
                @postal_code, @prosumer_scheme, @actor_user_id, @supplier_org_id);
        SET @new_id = SCOPE_IDENTITY();
        EXEC [dbo].[sp__Log] 'CREATE', 'PREMISE', @new_id;
        COMMIT TRANSACTION;
        SELECT @new_id AS premise_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.1 p.5: the consumer keeps the premise details up to date]
CREATE OR ALTER PROCEDURE [dbo].[sp_UpdatePremise]
    @actor_user_id   INT,
    @premise_id      INT,
    @address         NVARCHAR(250),
    @latitude        DECIMAL(9,6),
    @longitude       DECIMAL(9,6),
    @usage_type      VARCHAR(20),
    @district        NVARCHAR(30),
    @municipality    NVARCHAR(80),
    @parish          NVARCHAR(80),
    @postal_code     CHAR(4),
    @prosumer_scheme VARCHAR(20) = 'NONE',
    @supplier_org_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_UpdatePremise';

    SET @prosumer_scheme = ISNULL(@prosumer_scheme, 'NONE');
    IF NOT EXISTS (SELECT 1 FROM [dbo].[PREMISE] WHERE premise_id = @premise_id)
        THROW 50001, 'Premise not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[PREMISE] WHERE premise_id = @premise_id AND user_id = @actor_user_id)
        THROW 50002, 'Permission denied: not your premise.', 1;
    IF @address IS NULL OR @municipality IS NULL OR @parish IS NULL
        THROW 50004, 'Invalid input: address, municipality and parish are required.', 1;
    IF @latitude IS NULL OR @longitude IS NULL OR @latitude NOT BETWEEN -90 AND 90 OR @longitude NOT BETWEEN -180 AND 180
        THROW 50004, 'Invalid input: the coordinates are not valid.', 1;
    IF @usage_type IS NULL OR @usage_type NOT IN ('RESIDENTIAL', 'COMMERCIAL', 'INDUSTRIAL', 'AGRICULTURAL')
        THROW 50004, 'Invalid input: unknown usage type.', 1;
    IF @district IS NULL OR @district NOT IN (N'Λευκωσία', N'Λεμεσός', N'Λάρνακα', N'Πάφος', N'Αμμόχωστος', N'Κερύνεια')
        THROW 50004, 'Invalid input: the district must be one of the 6 districts.', 1;
    IF @postal_code IS NULL OR @postal_code NOT LIKE '[0-9][0-9][0-9][0-9]'
        THROW 50004, 'Invalid input: the postal code needs 4 digits.', 1;
    IF @prosumer_scheme NOT IN ('NONE', 'NET_METERING', 'NET_BILLING')
        THROW 50004, 'Invalid input: unknown prosumer scheme.', 1;
    IF @supplier_org_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM [dbo].[ORGANIZATION] WHERE organization_id = @supplier_org_id AND org_type = 'SUPPLIER')
        THROW 50004, 'Invalid input: the supplier does not exist.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[PREMISE]
           SET address = @address, latitude = @latitude, longitude = @longitude, usage_type = @usage_type,
               district = @district, municipality = @municipality, parish = @parish, postal_code = @postal_code,
               prosumer_scheme = @prosumer_scheme, supplier_org_id = @supplier_org_id
         WHERE premise_id = @premise_id AND user_id = @actor_user_id;
        EXEC [dbo].[sp__Log] 'UPDATE', 'PREMISE', @premise_id;
        COMMIT TRANSACTION;
        SELECT @premise_id AS premise_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §II.Ε p.4: the consumer chooses a supplier] - old bills keep the supplier they were issued by
CREATE OR ALTER PROCEDURE [dbo].[sp_ChangeSupplier]
    @actor_user_id   INT,
    @premise_id      INT,
    @supplier_org_id INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_ChangeSupplier';

    DECLARE @old INT, @owner INT;
    SELECT @old = supplier_org_id, @owner = user_id FROM [dbo].[PREMISE] WHERE premise_id = @premise_id;
    IF @owner IS NULL
        THROW 50001, 'Premise not found.', 1;
    IF @owner <> @actor_user_id
        THROW 50002, 'Permission denied: not your premise.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[ORGANIZATION] WHERE organization_id = @supplier_org_id AND org_type = 'SUPPLIER')
        THROW 50004, 'Invalid input: the supplier does not exist.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[PREMISE] SET supplier_org_id = @supplier_org_id
         WHERE premise_id = @premise_id AND user_id = @actor_user_id;
        EXEC [dbo].[sp__Log] 'SUPPLIER_CHANGE', 'PREMISE', @premise_id, @old, @supplier_org_id;
        COMMIT TRANSACTION;
        SELECT @premise_id AS premise_id, @supplier_org_id AS supplier_org_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §5.1 p.10: a premise joins or leaves the portfolio of an aggregator]
CREATE OR ALTER PROCEDURE [dbo].[sp_SetPremiseAggregator]
    @actor_user_id     INT,
    @premise_id        INT,
    @aggregator_org_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_SetPremiseAggregator';

    DECLARE @old INT, @owner INT;
    SELECT @old = aggregator_org_id, @owner = user_id FROM [dbo].[PREMISE] WHERE premise_id = @premise_id;
    IF @owner IS NULL
        THROW 50001, 'Premise not found.', 1;
    IF @owner <> @actor_user_id
        THROW 50002, 'Permission denied: not your premise.', 1;
    IF @aggregator_org_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM [dbo].[ORGANIZATION] WHERE organization_id = @aggregator_org_id AND org_type = 'AGGREGATOR')
        THROW 50004, 'Invalid input: the aggregator does not exist.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[PREMISE] SET aggregator_org_id = @aggregator_org_id
         WHERE premise_id = @premise_id AND user_id = @actor_user_id;
        EXEC [dbo].[sp__Log] 'AGGREGATOR_CHANGE', 'PREMISE', @premise_id, @old, @aggregator_org_id;
        COMMIT TRANSACTION;
        SELECT @premise_id AS premise_id, @aggregator_org_id AS aggregator_org_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.2 p.6: the consumer sets a consumption threshold; UC-04] NULL switches it off
CREATE OR ALTER PROCEDURE [dbo].[sp_SetPremiseThreshold]
    @actor_user_id         INT,
    @premise_id            INT,
    @monthly_threshold_kwh DECIMAL(18,4) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_SetPremiseThreshold';

    DECLARE @old DECIMAL(18,4), @owner INT;
    SELECT @old = monthly_threshold_kwh, @owner = user_id FROM [dbo].[PREMISE] WHERE premise_id = @premise_id;
    IF @owner IS NULL
        THROW 50001, 'Premise not found.', 1;
    IF @owner <> @actor_user_id
        THROW 50002, 'Permission denied: not your premise.', 1;
    IF @monthly_threshold_kwh IS NOT NULL AND @monthly_threshold_kwh <= 0
        THROW 50004, 'Invalid input: the threshold must be greater than 0 (or NULL to switch it off).', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[PREMISE] SET monthly_threshold_kwh = @monthly_threshold_kwh
         WHERE premise_id = @premise_id AND user_id = @actor_user_id;
        EXEC [dbo].[sp__Log] 'THRESHOLD_CHANGE', 'PREMISE', @premise_id, @old, @monthly_threshold_kwh;
        COMMIT TRANSACTION;
        SELECT @premise_id AS premise_id, @monthly_threshold_kwh AS monthly_threshold_kwh;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.1 p.5: the consumer sees their premises and meters]
CREATE OR ALTER PROCEDURE [dbo].[sp_ListMyPremises]
    @actor_user_id INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';

    SELECT premise_id, address, latitude, longitude, usage_type, district, municipality, parish, postal_code,
           prosumer_scheme, monthly_threshold_kwh, supplier_org_id, supplier_name, aggregator_org_id, aggregator_name,
           meter_id, serial_number, meter_status, transformer_id
    FROM [dbo].[view_PREMISE_METER]
    WHERE user_id = @actor_user_id
    ORDER BY premise_id;
END;
GO

-- [project.pdf §1.2 p.5-6: the 15-minute series of a premise; UC-02]
-- Consumer: own premise, current month free, older days only if bought, never beyond retention (50008).
-- DSO and officer: any premise. Replaced meters are included, so the history of the premise survives.
-- [AR: at most 31 days per call, for the response time]
CREATE OR ALTER PROCEDURE [dbo].[sp_GetPremiseReadings]
    @actor_user_id INT,
    @premise_id    INT,
    @from          DATETIME2(0),
    @to            DATETIME2(0),
    @obis_list     NVARCHAR(200) = N'1.8.0,2.8.0'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER,DSO,SYSTEM_OFFICER';

    DECLARE @role VARCHAR(20), @owner INT, @scheme VARCHAR(20);
    SELECT @role = role_code FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;
    SELECT @owner = user_id, @scheme = prosumer_scheme FROM [dbo].[PREMISE] WHERE premise_id = @premise_id;

    IF @owner IS NULL
        THROW 50001, 'Premise not found.', 1;
    IF @role = 'CONSUMER' AND @owner <> @actor_user_id
        THROW 50002, 'Permission denied: not your premise.', 1;
    IF @from IS NULL OR @to IS NULL OR @to <= @from OR DATEDIFF(DAY, @from, @to) > 31
        THROW 50004, 'Invalid input: the window must have from < to and at most 31 days.', 1;

    IF @role = 'CONSUMER' AND EXISTS (
        SELECT 1 FROM [dbo].[METER] AS m
        WHERE m.premise_id = @premise_id
          -- every meter that was in service in the window, or simply has data in it
          AND (   (m.installed_at < @to AND (m.removed_at IS NULL OR m.removed_at > @from))
               OR EXISTS (SELECT 1 FROM [dbo].[METER_READING] AS x
                          WHERE x.meter_id = m.meter_id AND x.reading_timestamp >= @from AND x.reading_timestamp < @to))
          AND [dbo].[fn_CanViewReadings](@actor_user_id, m.meter_id, @from, @to) = 0)
        THROW 50008, 'Access to past data is not bought for this period, or the period is outside the retention time.', 1;

    SELECT r.reading_timestamp, r.obis_code, r.delta_value AS energy, r.[value], r.status, r.meter_id
    FROM [dbo].[METER] AS m
    JOIN [dbo].[METER_READING] AS r ON r.meter_id = m.meter_id
    WHERE m.premise_id = @premise_id
      AND r.reading_timestamp >= @from AND r.reading_timestamp < @to
      AND r.obis_code IN (SELECT LTRIM(RTRIM(s.[value])) FROM STRING_SPLIT(ISNULL(@obis_list, N'1.8.0,2.8.0'), ',') AS s)
      AND (r.obis_code <> '2.8.0' OR @scheme <> 'NONE')            -- export only for prosumers
    ORDER BY r.reading_timestamp, r.obis_code;
END;
GO

-- [project.pdf §1.2 p.6: totals per day, month and year; UC-03]
-- Final aggregates only. The same access rule as the readings: an aggregate does not change who may see what.
CREATE OR ALTER PROCEDURE [dbo].[sp_GetPremiseAggregates]
    @actor_user_id INT,
    @premise_id    INT,
    @period_type   VARCHAR(12),
    @from          DATETIME2(0),
    @to            DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER,DSO,SYSTEM_OFFICER';

    DECLARE @role VARCHAR(20), @owner INT, @scheme VARCHAR(20);
    SELECT @role = role_code FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;
    SELECT @owner = user_id, @scheme = prosumer_scheme FROM [dbo].[PREMISE] WHERE premise_id = @premise_id;

    IF @owner IS NULL
        THROW 50001, 'Premise not found.', 1;
    IF @role = 'CONSUMER' AND @owner <> @actor_user_id
        THROW 50002, 'Permission denied: not your premise.', 1;
    IF @period_type IS NULL OR @period_type NOT IN ('DAY', 'MONTH', 'YEAR')
        THROW 50004, 'Invalid input: the period type must be DAY, MONTH or YEAR.', 1;
    IF @from IS NULL OR @to IS NULL OR @to <= @from
        THROW 50004, 'Invalid input: the window must have from < to.', 1;

    IF @role = 'CONSUMER' AND EXISTS (
        SELECT 1 FROM [dbo].[METER] AS m
        WHERE m.premise_id = @premise_id
          AND (   (m.installed_at < @to AND (m.removed_at IS NULL OR m.removed_at > @from))
               OR EXISTS (SELECT 1 FROM [dbo].[AGGREGATE] AS x
                          WHERE x.meter_id = m.meter_id AND x.period_type = @period_type
                            AND x.period_start >= @from AND x.period_start < @to))
          AND [dbo].[fn_CanViewReadings](@actor_user_id, m.meter_id, @from, @to) = 0)
        THROW 50008, 'Access to past data is not bought for this period, or the period is outside the retention time.', 1;

    SELECT a.period_type, a.period_start, a.obis_code, SUM(a.[value]) AS [value], SUM(a.sample_count) AS sample_count
    FROM [dbo].[METER] AS m
    JOIN [dbo].[AGGREGATE] AS a ON a.meter_id = m.meter_id
    WHERE m.premise_id = @premise_id
      AND a.period_type = @period_type
      AND a.is_final = 1
      AND a.period_start >= @from AND a.period_start < @to
      AND (a.obis_code <> '2.8.0' OR @scheme <> 'NONE')
    GROUP BY a.period_type, a.period_start, a.obis_code       -- a replaced meter and its successor add up
    ORDER BY a.period_start, a.obis_code;
END;
GO

-- [project.pdf §1.2 p.5: the consumer is told about undervoltage / overvoltage; §1.2 p.6 thresholds; UC-02]
CREATE OR ALTER PROCEDURE [dbo].[sp_GetPremiseEvents]
    @actor_user_id INT,
    @premise_id    INT,
    @from          DATETIME2(0),
    @to            DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';

    IF NOT EXISTS (SELECT 1 FROM [dbo].[PREMISE] WHERE premise_id = @premise_id)
        THROW 50001, 'Premise not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[PREMISE] WHERE premise_id = @premise_id AND user_id = @actor_user_id)
        THROW 50002, 'Permission denied: not your premise.', 1;

    SELECT e.event_id, e.event_timestamp, e.event_type, e.severity, e.description, e.meter_id
    FROM [dbo].[METER] AS m
    JOIN [dbo].[EVENT] AS e ON e.meter_id = m.meter_id
    WHERE m.premise_id = @premise_id
      AND e.event_type IN ('VOLTAGE_SAG', 'VOLTAGE_SWELL', 'THRESHOLD_EXCEEDED')
      AND (@from IS NULL OR e.event_timestamp >= @from)
      AND (@to   IS NULL OR e.event_timestamp < @to)
    ORDER BY e.event_timestamp DESC;
END;
GO

-- [project.pdf §1.2 p.6: earlier months are available for an extra charge]
-- Price = months x HISTORICAL_ACCESS fee. Also returns the earliest date still kept (retention).
CREATE OR ALTER PROCEDURE [dbo].[sp_GetHistoricalAccessQuote]
    @actor_user_id INT,
    @meter_id      INT,
    @access_from   DATE,
    @access_to     DATE
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';

    DECLARE @retention TINYINT, @fee DECIMAL(10,2);
    SELECT @retention = m.retention_months
    FROM [dbo].[METER] AS m JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
    WHERE m.meter_id = @meter_id AND p.user_id = @actor_user_id;
    IF @retention IS NULL
        THROW 50002, 'Permission denied: not your meter.', 1;
    IF @access_from IS NULL OR @access_to IS NULL OR @access_to < @access_from
        THROW 50004, 'Invalid input: the period must have from <= to.', 1;

    SELECT @fee = fee FROM [dbo].[SERVICE_TYPE] WHERE service_name = N'HISTORICAL_ACCESS' AND is_active = 1;
    IF @fee IS NULL
        THROW 50001, 'The HISTORICAL_ACCESS service is not available.', 1;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @months INT = DATEDIFF(MONTH, @access_from, @access_to) + 1;

    SELECT @meter_id AS meter_id, @access_from AS access_from, @access_to AS access_to,
           @months AS months, @fee AS fee_per_month, CAST(@months * @fee AS DECIMAL(12,2)) AS amount,
           DATEADD(MONTH, -@retention, @today) AS earliest_date_kept,
           CAST(CASE WHEN @access_from >= DATEADD(MONTH, -@retention, @today)
                      AND @access_to < DATEFROMPARTS(YEAR(@today), MONTH(@today), 1) THEN 1 ELSE 0 END AS BIT) AS can_buy;
END;
GO

-- [project.pdf §1.2 p.6: the consumer buys access to earlier months; UC-03]
-- The period must be before the current month and inside the retention time (50008).
CREATE OR ALTER PROCEDURE [dbo].[sp_BuyHistoricalAccess]
    @actor_user_id         INT,
    @meter_id              INT,
    @access_from           DATE,
    @access_to             DATE,
    @method                VARCHAR(20),
    @transaction_reference VARCHAR(60) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_BuyHistoricalAccess';

    DECLARE @retention TINYINT, @fee DECIMAL(10,2), @service_id INT;
    SELECT @retention = m.retention_months
    FROM [dbo].[METER] AS m JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
    WHERE m.meter_id = @meter_id AND p.user_id = @actor_user_id;
    IF @retention IS NULL
        THROW 50002, 'Permission denied: not your meter.', 1;
    IF @access_from IS NULL OR @access_to IS NULL OR @access_to < @access_from
        THROW 50004, 'Invalid input: the period must have from <= to.', 1;
    IF @method IS NULL OR @method NOT IN ('BANK_TRANSFER', 'CARD', 'CASH', 'DIRECT_DEBIT')
        THROW 50004, 'Invalid input: unknown payment method.', 1;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    IF @access_to >= DATEFROMPARTS(YEAR(@today), MONTH(@today), 1)
        THROW 50008, 'The current month is free; only earlier months can be bought.', 1;
    IF @access_from < DATEADD(MONTH, -@retention, @today)
        THROW 50008, 'The period is outside the retention time of this meter.', 1;

    SELECT @service_id = service_type_id, @fee = fee
    FROM [dbo].[SERVICE_TYPE] WHERE service_name = N'HISTORICAL_ACCESS' AND is_active = 1;
    IF @service_id IS NULL
        THROW 50001, 'The HISTORICAL_ACCESS service is not available.', 1;

    DECLARE @amount DECIMAL(12,2) = (DATEDIFF(MONTH, @access_from, @access_to) + 1) * @fee;
    IF @amount <= 0
        THROW 50004, 'There is no charge for this service at the moment, so nothing can be bought.', 1;

    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[PAYMENT] (amount, method, status, transaction_reference, access_from, access_to,
                                     user_id, service_type_id, access_meter_id)
        VALUES (@amount, @method, 'COMPLETED', @transaction_reference, @access_from, @access_to,
                @actor_user_id, @service_id, @meter_id);
        SET @new_id = SCOPE_IDENTITY();
        EXEC [dbo].[sp__Log] 'PAYMENT', 'PAYMENT', @new_id, NULL, 'COMPLETED', N'historical access';
        COMMIT TRANSACTION;
        SELECT @new_id AS payment_id, @amount AS amount;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: this transaction reference was already used.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.2 p.6: alert when the consumption passes the threshold; UC-04]
-- Job. Complements TR21 for days that are not finalized yet: month-to-date = final DAY aggregates
-- plus the non-final (not SUSPECT) readings of the month. One event per meter per month.
-- Cursor over the premises that have a threshold (one short transaction each).
CREATE OR ALTER PROCEDURE [dbo].[sp_CheckConsumptionThresholds]
    @actor_user_id INT,
    @as_of         DATE = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_CheckConsumptionThresholds';

    SET @as_of = ISNULL(@as_of, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @month_start DATETIME2(0) = CAST(DATEFROMPARTS(YEAR(@as_of), MONTH(@as_of), 1) AS DATETIME2(0));
    DECLARE @until       DATETIME2(0) = DATEADD(DAY, 1, CAST(@as_of AS DATETIME2(0)));
    DECLARE @premise_id INT, @meter_id INT, @threshold DECIMAL(18,4), @total DECIMAL(20,4);
    DECLARE @checked INT = 0, @alerts INT = 0;

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT p.premise_id, p.monthly_threshold_kwh, m.meter_id
        FROM [dbo].[PREMISE] AS p
        JOIN [dbo].[METER] AS m ON m.premise_id = p.premise_id AND m.removed_at IS NULL
        WHERE p.monthly_threshold_kwh IS NOT NULL;
    OPEN c;
    FETCH NEXT FROM c INTO @premise_id, @threshold, @meter_id;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SET @checked = @checked + 1;

            SELECT @total =
                ISNULL((SELECT SUM(a.[value])
                        FROM [dbo].[AGGREGATE] AS a
                        JOIN [dbo].[METER] AS pm ON pm.meter_id = a.meter_id
                        WHERE pm.premise_id = @premise_id AND a.period_type = 'DAY' AND a.obis_code = '1.8.0'
                          AND a.is_final = 1 AND a.period_start >= @month_start AND a.period_start < @until), 0)
              + ISNULL((SELECT SUM(r.delta_value)
                        FROM [dbo].[METER_READING] AS r
                        JOIN [dbo].[METER] AS pm ON pm.meter_id = r.meter_id
                        WHERE pm.premise_id = @premise_id AND r.obis_code = '1.8.0'
                          AND r.is_final = 0 AND r.status <> 'SUSPECT'
                          AND r.reading_timestamp >= @month_start AND r.reading_timestamp < @until), 0);

            IF @total > @threshold
            BEGIN
                BEGIN TRANSACTION;
                INSERT INTO [dbo].[EVENT] (event_timestamp, event_type, severity, description, meter_id)
                SELECT CAST(@as_of AS DATETIME2(0)), 'THRESHOLD_EXCEEDED', 'INFO',
                       N'Month-to-date consumption ' + CAST(@total AS NVARCHAR(30)) + N' kWh is above the threshold of '
                       + CAST(@threshold AS NVARCHAR(30)) + N' kWh.',
                       @meter_id
                WHERE NOT EXISTS (SELECT 1 FROM [dbo].[EVENT] AS e WITH (UPDLOCK, HOLDLOCK)
                                  JOIN [dbo].[METER] AS pm ON pm.meter_id = e.meter_id
                                  WHERE pm.premise_id = @premise_id AND e.event_type = 'THRESHOLD_EXCEEDED'
                                    AND e.event_timestamp >= @month_start
                                    AND e.event_timestamp < DATEADD(MONTH, 1, @month_start));
                SET @alerts = @alerts + @@ROWCOUNT;
                COMMIT TRANSACTION;
            END
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            EXEC [dbo].[sp__Log] 'THRESHOLD_CHECK_FAILED', 'PREMISE', @premise_id;
        END CATCH
        FETCH NEXT FROM c INTO @premise_id, @threshold, @meter_id;
    END
    CLOSE c;
    DEALLOCATE c;

    SELECT @as_of AS as_of, @checked AS premises_checked, @alerts AS alerts_raised;
END;
GO

PRINT 'procedures_02_consumer.sql: 12 procedures created.';
GO
