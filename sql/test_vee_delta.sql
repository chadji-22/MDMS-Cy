/* ============================================================================
   test_vee_delta.sql  -  15-minute energy of cumulative registers (ingest + sp_RunVEE steps 2 and 5)

   REWRITTEN for io. The first version had its own VAL_CUMULATIVE_DELTA rule, VEE_RULE / VEE_LOG
   tables and direct UPDATEs. In io the work is split like this:
     * delta_value is computed by sp_IngestTelemetryPacket (value - the value of the previous
       15-minute slot; NULL when that slot has no reading);
     * sp_RunVEE step 2 marks a negative delta SUSPECT / NEGATIVE_DELTA. The negative delta is KEPT
       on the reading (the first version set it to NULL);
     * the reading after a suspect one still gets delta = value - previous value (the first version
       left it NULL because the previous reading was suspect);
     * everything that passes becomes VALID (not left PENDING);
     * a missing slot is filled by sp__EstimateGaps (ESTIMATED / LINEAR_INTERPOLATION, packet_id NULL)
       and the deltas of the estimated slot and of the reading after it are recomputed.
   Nothing here finalizes a reading (sp_FinalizeReadings is covered by tests.sql).

   Data (1.8.0, kWh), slots 08:00 .. 09:15:
        08:00 1000.0   08:15 1000.5   08:30 1001.0   08:45 1001.4   09:00 1000.9 (register went down)   09:15 1001.5
   Data (2.8.0, kWh):   08:00 10.0     08:15 10.2     08:30 missing  08:45 10.6

   Needs: import.sql, seed_grid.sql, seed_telemetry_demo.sql.
   Re-runnable: the readings of the test day (2025-06-13) are deleted first.
   ============================================================================ */
SET NOCOUNT ON;

DECLARE @m INT, @officer INT;
SELECT @m = meter_id FROM [dbo].[METER] WHERE network_id = 'DEMO-NET-001' AND status = 'ACTIVE';
SELECT @officer = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'officer1@mdms.cy';
IF @m IS NULL OR @officer IS NULL
    THROW 54000, 'test_vee_delta.sql: run import.sql, seed_grid.sql and seed_telemetry_demo.sql first.', 1;

IF OBJECT_ID('tempdb..#results') IS NOT NULL DROP TABLE #results;   -- left over from an aborted run in this session
IF OBJECT_ID('tempdb..#vee') IS NOT NULL DROP TABLE #vee;
CREATE TABLE #results (seq INT IDENTITY(1,1), test VARCHAR(120), result VARCHAR(4), detail NVARCHAR(400));
CREATE TABLE #vee(meters_processed INT, meters_failed INT, readings_valid INT, readings_suspect INT, readings_estimated INT);

DECLARE @d0 DATETIME2(0) = '2025-06-13T08:00:00', @d1 DATETIME2(0) = '2025-06-13T09:15:00';
DECLARE @p NVARCHAR(4000), @pid BIGINT, @ms VARCHAR(20), @n INT;

DELETE FROM [dbo].[METER_READING] WHERE meter_id = @m AND reading_timestamp >= '2025-06-13T00:00:00' AND reading_timestamp < '2025-06-14T00:00:00';

DECLARE @reg TABLE (k INT, obis VARCHAR(10), val VARCHAR(12));
INSERT INTO @reg VALUES
    (0, '1.8.0', '1000.0'), (1, '1.8.0', '1000.5'), (2, '1.8.0', '1001.0'), (3, '1.8.0', '1001.4'), (4, '1.8.0', '1000.9'), (5, '1.8.0', '1001.5'),
    (0, '2.8.0', '10.0'),   (1, '2.8.0', '10.2'),                                                    (3, '2.8.0', '10.6');
DECLARE @k INT, @obis VARCHAR(10), @val VARCHAR(12);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT k, obis, val FROM @reg ORDER BY k, obis;
OPEN c;
FETCH NEXT FROM c INTO @k, @obis, @val;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @p = CONCAT(N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"',
                    CONVERT(VARCHAR(19), DATEADD(MINUTE, 15 * @k, @d0), 126),
                    N'Z","Telemetry_Payload":[{"obis":"', @obis, N'","value":', @val, N',"unit":"kWh"}]}');
    EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1, @pid OUTPUT, @ms OUTPUT, @n OUTPUT;
    FETCH NEXT FROM c INTO @k, @obis, @val;
END
CLOSE c; DEALLOCATE c;

/* D0: what ingest computed, before VEE */
INSERT INTO #results (test, result, detail)
SELECT 'D0 ingest: 1.8.0 energies NULL / 0.5 / 0.5 / 0.4 / -0.5 / 0.6, all PENDING',
       CASE WHEN COUNT(*) = 6 AND SUM(CASE WHEN status = 'PENDING' THEN 1 ELSE 0 END) = 6
                 AND MAX(CASE WHEN reading_timestamp = '2025-06-13T08:00:00' AND delta_value IS NULL THEN 1 ELSE 0 END) = 1
                 AND MAX(CASE WHEN reading_timestamp = '2025-06-13T08:15:00' AND delta_value = 0.5  THEN 1 ELSE 0 END) = 1
                 AND MAX(CASE WHEN reading_timestamp = '2025-06-13T08:30:00' AND delta_value = 0.5  THEN 1 ELSE 0 END) = 1
                 AND MAX(CASE WHEN reading_timestamp = '2025-06-13T08:45:00' AND delta_value = 0.4  THEN 1 ELSE 0 END) = 1
                 AND MAX(CASE WHEN reading_timestamp = '2025-06-13T09:00:00' AND delta_value = -0.5 THEN 1 ELSE 0 END) = 1
                 AND MAX(CASE WHEN reading_timestamp = '2025-06-13T09:15:00' AND delta_value = 0.6  THEN 1 ELSE 0 END) = 1
            THEN 'PASS' ELSE 'FAIL' END, CONCAT(COUNT(*), ' readings')
FROM [dbo].[METER_READING] WHERE meter_id = @m AND obis_code = '1.8.0' AND reading_timestamp >= @d0 AND reading_timestamp <= @d1;

INSERT INTO #results (test, result, detail)
SELECT 'D0b ingest: 2.8.0 08:45 has no energy yet because 08:30 is missing',
       CASE WHEN COUNT(*) = 3 AND MAX(CASE WHEN reading_timestamp = '2025-06-13T08:45:00' AND delta_value IS NULL THEN 1 ELSE 0 END) = 1
            THEN 'PASS' ELSE 'FAIL' END, CONCAT(COUNT(*), ' readings')
FROM [dbo].[METER_READING] WHERE meter_id = @m AND obis_code = '2.8.0' AND reading_timestamp >= @d0 AND reading_timestamp <= @d1;

BEGIN TRY
    INSERT INTO #vee EXEC [dbo].[sp_RunVEE] @officer, @d0, @d1, @m;

    INSERT INTO #results (test, result, detail)
    SELECT 'D1 sp_RunVEE summary: 8 valid, 1 suspect, 1 estimated',
           CASE WHEN meters_processed = 1 AND meters_failed = 0 AND readings_valid = 8
                     AND readings_suspect = 1 AND readings_estimated = 1 THEN 'PASS' ELSE 'FAIL' END,
           CONCAT('processed ', meters_processed, ', failed ', meters_failed, ', valid ', readings_valid,
                  ', suspect ', readings_suspect, ', estimated ', readings_estimated)
    FROM #vee;

    INSERT INTO #results (test, result, detail)
    SELECT 'D2 register went down (09:00) -> SUSPECT / NEGATIVE_DELTA, negative energy kept',
           CASE WHEN status = 'SUSPECT' AND vee_rule = 'NEGATIVE_DELTA' AND delta_value = -0.5 AND [value] = 1000.9 AND is_final = 0
                THEN 'PASS' ELSE 'FAIL' END, CONCAT(status, ' / ', ISNULL(vee_rule, '-'), ' / ', delta_value)
    FROM [dbo].[METER_READING] WHERE meter_id = @m AND obis_code = '1.8.0' AND reading_timestamp = '2025-06-13T09:00:00';

    INSERT INTO #results (test, result, detail)
    SELECT 'D3 reading after the suspect one (09:15) -> VALID, energy 0.6 against the previous stored value',
           CASE WHEN status = 'VALID' AND vee_rule = 'AUTO' AND delta_value = 0.6 THEN 'PASS' ELSE 'FAIL' END,
           CONCAT(status, ' / ', ISNULL(vee_rule, '-'), ' / ', delta_value)
    FROM [dbo].[METER_READING] WHERE meter_id = @m AND obis_code = '1.8.0' AND reading_timestamp = '2025-06-13T09:15:00';

    INSERT INTO #results (test, result, detail)
    SELECT 'D4 first reading and the normal ones are VALID (08:00 .. 08:45), energies unchanged',
           CASE WHEN COUNT(*) = 4 AND SUM(CASE WHEN status = 'VALID' AND vee_rule = 'AUTO' THEN 1 ELSE 0 END) = 4
                     AND MAX(CASE WHEN reading_timestamp = '2025-06-13T08:00:00' AND delta_value IS NULL THEN 1 ELSE 0 END) = 1
                     AND SUM(ISNULL(delta_value, 0)) = 1.4 THEN 'PASS' ELSE 'FAIL' END, NULL
    FROM [dbo].[METER_READING] WHERE meter_id = @m AND obis_code = '1.8.0'
      AND reading_timestamp >= '2025-06-13T08:00:00' AND reading_timestamp <= '2025-06-13T08:45:00';

    INSERT INTO #results (test, result, detail)
    SELECT 'D5 2.8.0 gap 08:30 -> ESTIMATED 10.4 (LINEAR_INTERPOLATION, no packet), energy 0.2',
           CASE WHEN status = 'ESTIMATED' AND vee_rule = 'LINEAR_INTERPOLATION' AND [value] = 10.4
                     AND packet_id IS NULL AND delta_value = 0.2 THEN 'PASS' ELSE 'FAIL' END,
           CONCAT(status, ' / ', [value], ' / ', delta_value)
    FROM [dbo].[METER_READING] WHERE meter_id = @m AND obis_code = '2.8.0' AND reading_timestamp = '2025-06-13T08:30:00';

    INSERT INTO #results (test, result, detail)
    SELECT 'D6 2.8.0 08:45 (the reading after the estimated one) -> energy recomputed to 0.2, VALID',
           CASE WHEN status = 'VALID' AND delta_value = 0.2 THEN 'PASS' ELSE 'FAIL' END, CONCAT(status, ' / ', delta_value)
    FROM [dbo].[METER_READING] WHERE meter_id = @m AND obis_code = '2.8.0' AND reading_timestamp = '2025-06-13T08:45:00';

    INSERT INTO #results (test, result, detail)
    SELECT 'D7 nothing was finalized (sp_FinalizeReadings was not called)',
           CASE WHEN NOT EXISTS (SELECT 1 FROM [dbo].[METER_READING]
                                 WHERE meter_id = @m AND reading_timestamp >= @d0 AND reading_timestamp <= @d1 AND is_final = 1)
                THEN 'PASS' ELSE 'FAIL' END, NULL;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT INTO #results (test, result, detail) VALUES ('D sp_RunVEE (delta)', 'FAIL', LEFT(ERROR_MESSAGE(), 400));
END CATCH

/* ===========================================================================
   SUMMARY
   =========================================================================== */
SELECT seq, result, test, detail FROM #results ORDER BY seq;
SELECT result, COUNT(*) AS tests FROM #results GROUP BY result;

SELECT r.reading_timestamp, r.obis_code, r.[value], r.delta_value, r.status, r.vee_rule, r.is_final
FROM [dbo].[METER_READING] AS r
WHERE r.meter_id = @m AND r.reading_timestamp >= @d0 AND r.reading_timestamp <= @d1
ORDER BY r.obis_code, r.reading_timestamp;

DECLARE @fails INT = (SELECT COUNT(*) FROM #results WHERE result <> 'PASS');
DECLARE @total INT = (SELECT COUNT(*) FROM #results);
PRINT 'test_vee_delta.sql: ' + CAST(@total AS VARCHAR(10)) + ' tests, ' + CAST(@fails AS VARCHAR(10)) + ' not passed.';
DROP TABLE #vee;
DROP TABLE #results;
