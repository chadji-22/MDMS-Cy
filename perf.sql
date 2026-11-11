/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   perf.sql  -  Build Spec §14 and §10
   [project.pdf §IV p.12: 95 % of the OLTP queries under 2 seconds for 10,000 requests;
    at least one measured before / after case for an index]

   PART 1  a mix of OLTP calls with random valid parameters, each one timed:
             40 % sp_GetPremiseReadings (1 day)   15 % sp_GetPremiseAggregates   15 % sp_ListMyWorkOrders
             10 % sp_IngestTelemetryPacket        10 % sp_GetTransformerState    10 % sp_GetDayAheadAggregates
           Report: p95 overall and per procedure, plus the maximum. Target: p95 < 2000 ms.
   PART 2  batch jobs, timed separately (they are not OLTP).
   PART 3  IX1 before / after: the two queries it serves, with the index, without it, and with it again.
           It DROPS and recreates IX_METER_READING_obis_slot, so it runs only when run_index_test = 1.

   Settings: change the two values in #cfg below.
   Notes
     * The result sets of the calls are caught in temp tables (INSERT ... EXEC), so the times include
       producing the rows but not sending them to the client.
     * The packet calls run inside a transaction that is rolled back, so the test leaves no rows behind.
     * Run it on the large data set (sp_GenerateSyntheticData); on the small one every call is trivially fast.
   ============================================================================ */
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM [dbo].[USER_ACCOUNT] WHERE role_code = 'DSO')
BEGIN
    PRINT 'perf.sql: run import.sql first.';
    SET NOEXEC ON;
END
GO

IF OBJECT_ID('tempdb..#cfg') IS NOT NULL DROP TABLE #cfg;
CREATE TABLE #cfg (calls INT NOT NULL, run_index_test BIT NOT NULL);
INSERT INTO #cfg (calls, run_index_test) VALUES (10000, 1);          -- <== settings
GO

/* ===========================================================================
   PART 1  -  the OLTP mix
   =========================================================================== */
DECLARE @calls INT = (SELECT calls FROM #cfg);
DECLARE @dso INT, @tso INT;
SELECT TOP (1) @dso = user_id FROM [dbo].[USER_ACCOUNT] WHERE role_code = 'DSO' AND is_active = 1 ORDER BY user_id;
SELECT TOP (1) @tso = user_id FROM [dbo].[USER_ACCOUNT] WHERE role_code = 'TSO' AND is_active = 1 ORDER BY user_id;

DECLARE @data_from DATE, @data_to DATE, @days INT;
SELECT @data_from = CAST(MIN(reading_timestamp) AS DATE), @data_to = CAST(MAX(reading_timestamp) AS DATE) FROM [dbo].[METER_READING];
SET @days = DATEDIFF(DAY, @data_from, @data_to) + 1;

-- pools of valid parameters
SELECT ROW_NUMBER() OVER (ORDER BY premise_id) AS rn, premise_id INTO #premises
FROM [dbo].[PREMISE] AS p WHERE EXISTS (SELECT 1 FROM [dbo].[METER] AS m WHERE m.premise_id = p.premise_id);
SELECT ROW_NUMBER() OVER (ORDER BY user_id) AS rn, user_id INTO #technicians
FROM [dbo].[USER_ACCOUNT] WHERE role_code = 'TECHNICIAN' AND approval_status = 'APPROVED' AND is_active = 1;
SELECT ROW_NUMBER() OVER (ORDER BY user_id) AS rn, user_id INTO #org_users
FROM [dbo].[USER_ACCOUNT] WHERE role_code IN ('SUPPLIER', 'AGGREGATOR') AND is_active = 1;
SELECT ROW_NUMBER() OVER (ORDER BY meter_id) AS rn, network_id INTO #meters
FROM [dbo].[METER] WHERE status = 'ACTIVE';
SELECT ROW_NUMBER() OVER (ORDER BY transformer_id) AS rn, transformer_id INTO #transformers
FROM [dbo].[TRANSFORMER] WHERE [level] >= 2;
DECLARE @n_premises INT = (SELECT COUNT(*) FROM #premises), @n_tech INT = (SELECT COUNT(*) FROM #technicians),
        @n_org INT = (SELECT COUNT(*) FROM #org_users), @n_meters INT = (SELECT COUNT(*) FROM #meters),
        @n_tr INT = (SELECT COUNT(*) FROM #transformers);

-- the calls, in random order
CREATE TABLE #calls (id INT IDENTITY(1,1) PRIMARY KEY, proc_name VARCHAR(40) NOT NULL, r1 INT NOT NULL, r2 INT NOT NULL);
WITH d AS (SELECT v FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS x(v)),
n AS (SELECT TOP (@calls) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM d AS a CROSS JOIN d AS b CROSS JOIN d AS c CROSS JOIN d AS e CROSS JOIN d AS f)
INSERT INTO #calls (proc_name, r1, r2)
SELECT CASE WHEN (n.n * 37) % 100 < 40 THEN 'sp_GetPremiseReadings'
            WHEN (n.n * 37) % 100 < 55 THEN 'sp_GetPremiseAggregates'
            WHEN (n.n * 37) % 100 < 70 THEN 'sp_ListMyWorkOrders'
            WHEN (n.n * 37) % 100 < 80 THEN 'sp_IngestTelemetryPacket'
            WHEN (n.n * 37) % 100 < 90 THEN 'sp_GetTransformerState'
            ELSE 'sp_GetDayAheadAggregates' END,
       ABS(CHECKSUM(NEWID())) % 1000000, ABS(CHECKSUM(NEWID())) % 1000000
FROM n
ORDER BY NEWID();

-- sinks for the result sets
CREATE TABLE #s_read (reading_timestamp DATETIME2(0), obis_code VARCHAR(20), energy DECIMAL(18,4), [value] DECIMAL(18,4), status VARCHAR(20), meter_id INT);
CREATE TABLE #s_agg (period_type VARCHAR(12), period_start DATETIME2(0), obis_code VARCHAR(20), [value] DECIMAL(38,4), sample_count INT);
CREATE TABLE #s_wo (work_order_id INT, work_type VARCHAR(20), origin VARCHAR(20), description NVARCHAR(1000), status VARCHAR(20), created_at DATETIME2(0),
                    scheduled_start DATETIME2(0), scheduled_end DATETIME2(0), accepted_at DATETIME2(0), premise_id INT, premise_address NVARCHAR(250),
                    district NVARCHAR(30), premise_latitude DECIMAL(9,6), premise_longitude DECIMAL(9,6), meter_id INT,
                    meter_latitude DECIMAL(9,6), meter_longitude DECIMAL(9,6));
CREATE TABLE #s_state (transformer_id INT, name NVARCHAR(100), [level] TINYINT, parent_transformer_id INT, capacity_kva DECIMAL(10,2),
                       reference_15_min DATETIME2(0), import_kwh DECIMAL(20,4), export_kwh DECIMAL(20,4), meter_count INT, computed_at DATETIME2(0),
                       load_pct DECIMAL(9,2), frequency_hz DECIMAL(18,4), frequency_at DATETIME2(0));
CREATE TABLE #s_da ([day] DATE, transformer_id INT, transformer_name NVARCHAR(100), import_kwh DECIMAL(38,4), export_kwh DECIMAL(38,4), net_kwh DECIMAL(38,4), meter_count INT);
CREATE TABLE #timings (id INT PRIMARY KEY, proc_name VARCHAR(40) NOT NULL, ms DECIMAL(12,3) NOT NULL, failed BIT NOT NULL);

DECLARE @id INT, @proc VARCHAR(40), @r1 INT, @r2 INT, @t0 DATETIME2(7), @failed BIT;
DECLARE @premise INT, @actor INT, @from DATETIME2(0), @to DATETIME2(0), @d_from DATE, @d_to DATE, @root INT, @json NVARCHAR(4000), @net VARCHAR(60);
DECLARE @range_from DATETIME2(0) = CAST(@data_from AS DATETIME2(0)), @range_to DATETIME2(0) = DATEADD(DAY, 1, CAST(@data_to AS DATETIME2(0)));
DECLARE @future DATETIME2(0) = DATEADD(YEAR, 1, CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATETIME2(0)));
DECLARE @run_start DATETIME2(3) = SYSDATETIME();

DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT id, proc_name, r1, r2 FROM #calls ORDER BY id;
OPEN c;
FETCH NEXT FROM c INTO @id, @proc, @r1, @r2;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @failed = 0;
    -- parameters first, so the timer covers only the call
    IF @proc IN ('sp_GetPremiseReadings', 'sp_GetPremiseAggregates')
    BEGIN
        SELECT @premise = premise_id FROM #premises WHERE rn = @r1 % @n_premises + 1;
        SET @from = DATEADD(DAY, @r2 % @days, CAST(@data_from AS DATETIME2(0)));
        SET @to = DATEADD(DAY, 1, @from);
    END
    ELSE IF @proc = 'sp_ListMyWorkOrders'
        SELECT @actor = user_id FROM #technicians WHERE rn = @r1 % @n_tech + 1;
    ELSE IF @proc = 'sp_IngestTelemetryPacket'
    BEGIN
        SELECT @net = network_id FROM #meters WHERE rn = @r1 % @n_meters + 1;
        SET @json = CONCAT(N'{"Meter_Network_ID":"', @net, N'","Transmission_Timestamp":"',
                           CONVERT(VARCHAR(19), DATEADD(MINUTE, 15 * (@r2 % 96), @future), 126),
                           N'Z","Network_Type":"NB-IoT","Cell_Signal_Strength_dBm":-90,"Telemetry_Payload":[',
                           N'{"obis":"1.8.0","value":', 100000 + @r2, N',"unit":"kWh"},{"obis":"1.8.1","value":', 60000 + @r2,
                           N',"unit":"kWh"},{"obis":"1.8.2","value":', 40000 + @r2, N',"unit":"kWh"},{"obis":"32.7.0","value":230.5,"unit":"V"}]}');
    END
    ELSE IF @proc = 'sp_GetTransformerState'
        SELECT @root = transformer_id FROM #transformers WHERE rn = @r1 % @n_tr + 1;
    ELSE
    BEGIN
        SELECT @actor = user_id FROM #org_users WHERE rn = @r1 % @n_org + 1;
        SET @d_from = DATEADD(DAY, @r2 % @days, @data_from);
        SET @d_to = CASE WHEN DATEADD(DAY, 6, @d_from) > @data_to THEN @data_to ELSE DATEADD(DAY, 6, @d_from) END;
    END

    SET @t0 = SYSDATETIME();
    BEGIN TRY
        IF @proc = 'sp_GetPremiseReadings'
            INSERT INTO #s_read EXEC [dbo].[sp_GetPremiseReadings] @dso, @premise, @from, @to, N'1.8.0,2.8.0';
        ELSE IF @proc = 'sp_GetPremiseAggregates'
            INSERT INTO #s_agg EXEC [dbo].[sp_GetPremiseAggregates] @dso, @premise, 'DAY', @range_from, @range_to;
        ELSE IF @proc = 'sp_ListMyWorkOrders'
            INSERT INTO #s_wo EXEC [dbo].[sp_ListMyWorkOrders] @actor, NULL, 1, 50;
        ELSE IF @proc = 'sp_IngestTelemetryPacket'
        BEGIN
            BEGIN TRANSACTION;
            EXEC [dbo].[sp_IngestTelemetryPacket] @json, 1;
            ROLLBACK TRANSACTION;                     -- timed with the insert; nothing stays in the database
        END
        ELSE IF @proc = 'sp_GetTransformerState'
            INSERT INTO #s_state EXEC [dbo].[sp_GetTransformerState] @tso, @root, NULL;
        ELSE
            INSERT INTO #s_da EXEC [dbo].[sp_GetDayAheadAggregates] @actor, @d_from, @d_to, 2, NULL;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @failed = 1;
    END CATCH
    INSERT INTO #timings (id, proc_name, ms, failed) VALUES (@id, @proc, DATEDIFF(MICROSECOND, @t0, SYSDATETIME()) / 1000.0, @failed);

    IF @id % 500 = 0
    BEGIN
        TRUNCATE TABLE #s_read; TRUNCATE TABLE #s_agg; TRUNCATE TABLE #s_wo; TRUNCATE TABLE #s_state; TRUNCATE TABLE #s_da;
    END
    FETCH NEXT FROM c INTO @id, @proc, @r1, @r2;
END
CLOSE c;
DEALLOCATE c;

PRINT 'PART 1: ' + CAST(@calls AS VARCHAR(10)) + ' calls in ' + CAST(DATEDIFF(SECOND, @run_start, SYSDATETIME()) AS VARCHAR(10)) + ' s.';

SELECT (SELECT COUNT(*) FROM [dbo].[METER_READING]) AS meter_reading_rows, (SELECT COUNT(*) FROM [dbo].[METER]) AS meters,
       (SELECT COUNT(*) FROM [dbo].[AGGREGATE]) AS aggregate_rows, @data_from AS data_from, @data_to AS data_to;

SELECT DISTINCT 'ALL' AS proc_name,
       COUNT(*) OVER () AS calls,
       CAST(AVG(ms) OVER () AS DECIMAL(12,2)) AS avg_ms,
       CAST(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ms) OVER () AS DECIMAL(12,2)) AS p50_ms,
       CAST(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ms) OVER () AS DECIMAL(12,2)) AS p95_ms,
       CAST(MAX(ms) OVER () AS DECIMAL(12,2)) AS max_ms,
       SUM(CAST(failed AS INT)) OVER () AS failed_calls,
       CASE WHEN PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ms) OVER () < 2000 THEN 'MET' ELSE 'NOT MET' END AS target_p95_under_2s
FROM #timings
UNION ALL
SELECT DISTINCT proc_name,
       COUNT(*) OVER (PARTITION BY proc_name),
       CAST(AVG(ms) OVER (PARTITION BY proc_name) AS DECIMAL(12,2)),
       CAST(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ms) OVER (PARTITION BY proc_name) AS DECIMAL(12,2)),
       CAST(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ms) OVER (PARTITION BY proc_name) AS DECIMAL(12,2)),
       CAST(MAX(ms) OVER (PARTITION BY proc_name) AS DECIMAL(12,2)),
       SUM(CAST(failed AS INT)) OVER (PARTITION BY proc_name),
       CASE WHEN PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ms) OVER (PARTITION BY proc_name) < 2000 THEN 'MET' ELSE 'NOT MET' END
FROM #timings
ORDER BY proc_name;
GO

/* ===========================================================================
   PART 2  -  batch jobs, timed separately (they are not OLTP)
   Only jobs that can run any number of times are run here.
   To time VEE and finalization on the raw day of the synthetic data, run by hand:
       EXEC dbo.sp_RunVEE @officer, @raw_day_start, @raw_day_end;   EXEC dbo.sp_FinalizeReadings @officer, @raw_day;
   =========================================================================== */
DECLARE @tso INT, @t0 DATETIME2(7);
SELECT TOP (1) @tso = user_id FROM [dbo].[USER_ACCOUNT] WHERE role_code = 'TSO' AND is_active = 1 ORDER BY user_id;
CREATE TABLE #batch (job VARCHAR(60), ms DECIMAL(12,2));
CREATE TABLE #b1 (reference_15_min DATETIME2(0), rows_written INT);

SET @t0 = SYSDATETIME();
INSERT INTO #b1 EXEC [dbo].[sp_RefreshTransformerState] @tso, NULL;
INSERT INTO #batch VALUES ('sp_RefreshTransformerState (whole tree)', DATEDIFF(MICROSECOND, @t0, SYSDATETIME()) / 1000.0);

SELECT job, ms FROM #batch;
GO

/* ===========================================================================
   PART 3  -  IX1 before / after   [project.pdf §IV p.12: "at least one case"]
   Query A = the leaf query of Algorithm E (every meter at one slot).
   Query B = the core of sp_GetIntradayProvisional (every meter over 6 hours).
   The messages show logical reads and CPU / elapsed time (SET STATISTICS IO, TIME);
   in SSMS switch on "Include Actual Execution Plan" (Ctrl+M) to see the scan become a seek.
   =========================================================================== */
IF (SELECT run_index_test FROM #cfg) = 0
    PRINT 'PART 3 skipped (run_index_test = 0).';
GO
CREATE TABLE #ix (step VARCHAR(30), query VARCHAR(10), ms DECIMAL(12,2), result_rows INT);
GO
-- step 1: WITH the index
IF (SELECT run_index_test FROM #cfg) = 1
BEGIN
    DECLARE @ref DATETIME2(0) = (SELECT MAX(reading_timestamp) FROM [dbo].[METER_READING] WHERE obis_code = '1.8.0' AND status IN ('VALID', 'ESTIMATED', 'EDITED'));
    DECLARE @from DATETIME2(0) = DATEADD(HOUR, -6, @ref), @t0 DATETIME2(7), @n INT;
    PRINT '--- WITH IX_METER_READING_obis_slot ---';
    SET STATISTICS IO ON; SET STATISTICS TIME ON;
    SET @t0 = SYSDATETIME();
    SELECT m.transformer_id, r.obis_code, SUM(ISNULL(r.delta_value, 0)) AS sum_value, COUNT(DISTINCT r.meter_id) AS meter_count
    INTO #a1
    FROM [dbo].[METER_READING] AS r JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
    WHERE r.obis_code IN ('1.8.0', '2.8.0') AND r.reading_timestamp = @ref AND r.status IN ('VALID', 'ESTIMATED', 'EDITED')
    GROUP BY m.transformer_id, r.obis_code
    OPTION (RECOMPILE);
    SET @n = @@ROWCOUNT;
    INSERT INTO #ix VALUES ('1 with index', 'A', DATEDIFF(MICROSECOND, @t0, SYSDATETIME()) / 1000.0, @n);
    SET @t0 = SYSDATETIME();
    SELECT r.reading_timestamp, m.transformer_id, SUM(ISNULL(r.delta_value, 0)) AS kwh, COUNT(DISTINCT r.meter_id) AS meter_count
    INTO #b1x
    FROM [dbo].[METER_READING] AS r JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
    WHERE r.obis_code IN ('1.8.0', '2.8.0') AND r.reading_timestamp >= @from AND r.reading_timestamp < @ref AND r.status <> 'SUSPECT'
    GROUP BY r.reading_timestamp, m.transformer_id
    OPTION (RECOMPILE);
    SET @n = @@ROWCOUNT;
    INSERT INTO #ix VALUES ('1 with index', 'B', DATEDIFF(MICROSECOND, @t0, SYSDATETIME()) / 1000.0, @n);
    SET STATISTICS IO OFF; SET STATISTICS TIME OFF;
END
GO
-- step 2: WITHOUT the index
IF (SELECT run_index_test FROM #cfg) = 1
BEGIN
    DROP INDEX IF EXISTS [IX_METER_READING_obis_slot] ON [dbo].[METER_READING];
    DECLARE @ref DATETIME2(0) = (SELECT MAX(reading_timestamp) FROM [dbo].[METER_READING] WHERE obis_code = '1.8.0' AND status IN ('VALID', 'ESTIMATED', 'EDITED'));
    DECLARE @from DATETIME2(0) = DATEADD(HOUR, -6, @ref), @t0 DATETIME2(7), @n INT;
    PRINT '--- WITHOUT IX_METER_READING_obis_slot ---';
    SET STATISTICS IO ON; SET STATISTICS TIME ON;
    SET @t0 = SYSDATETIME();
    SELECT m.transformer_id, r.obis_code, SUM(ISNULL(r.delta_value, 0)) AS sum_value, COUNT(DISTINCT r.meter_id) AS meter_count
    INTO #a2
    FROM [dbo].[METER_READING] AS r JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
    WHERE r.obis_code IN ('1.8.0', '2.8.0') AND r.reading_timestamp = @ref AND r.status IN ('VALID', 'ESTIMATED', 'EDITED')
    GROUP BY m.transformer_id, r.obis_code
    OPTION (RECOMPILE);
    SET @n = @@ROWCOUNT;
    INSERT INTO #ix VALUES ('2 without index', 'A', DATEDIFF(MICROSECOND, @t0, SYSDATETIME()) / 1000.0, @n);
    SET @t0 = SYSDATETIME();
    SELECT r.reading_timestamp, m.transformer_id, SUM(ISNULL(r.delta_value, 0)) AS kwh, COUNT(DISTINCT r.meter_id) AS meter_count
    INTO #b2
    FROM [dbo].[METER_READING] AS r JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
    WHERE r.obis_code IN ('1.8.0', '2.8.0') AND r.reading_timestamp >= @from AND r.reading_timestamp < @ref AND r.status <> 'SUSPECT'
    GROUP BY r.reading_timestamp, m.transformer_id
    OPTION (RECOMPILE);
    SET @n = @@ROWCOUNT;
    INSERT INTO #ix VALUES ('2 without index', 'B', DATEDIFF(MICROSECOND, @t0, SYSDATETIME()) / 1000.0, @n);
    SET STATISTICS IO OFF; SET STATISTICS TIME OFF;
END
GO
-- step 3: the index is created again (always, so the database is left as indexes.sql defines it)
IF (SELECT run_index_test FROM #cfg) = 1
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_METER_READING_obis_slot' AND object_id = OBJECT_ID(N'dbo.METER_READING'))
    CREATE NONCLUSTERED INDEX [IX_METER_READING_obis_slot]
        ON [dbo].[METER_READING] (obis_code, reading_timestamp)
        INCLUDE (meter_id, delta_value, status);
GO
IF (SELECT run_index_test FROM #cfg) = 1
    SELECT step, query, ms, result_rows FROM #ix ORDER BY query, step;
GO
SET NOEXEC OFF;
GO
PRINT 'perf.sql finished.';
GO
