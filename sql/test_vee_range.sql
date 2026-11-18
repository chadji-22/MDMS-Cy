/* ============================================================================
   test_vee_range.sql  -  VEE range check (sp_RunVEE, Algorithm B step 1: rule RANGE)

   REWRITTEN for io. The first version updated METER_READING directly and logged to VEE_LOG.
   In io:
     * there is no VEE_LOG / VEE_RULE: the outcome sits on the reading (status, vee_rule, vee_note);
       sp_RunVEE writes one summary row per meter to AUDIT_LOG (action VEE_RUN);
     * the check is done by sp_RunVEE (SYSTEM_OFFICER or DSO), never by direct UPDATEs;
     * a value outside OBIS_CODE.valid_min / valid_max becomes SUSPECT with vee_rule = 'RANGE';
     * everything that passes all rules becomes VALID (vee_rule = 'AUTO'), it does NOT stay PENDING;
     * the range of 32.7.0 is 0 - 400 V, the limits themselves are valid.
   The readings are created by the real ingest procedure, so the test also needs no direct INSERTs.

   Needs: import.sql, seed_grid.sql, seed_telemetry_demo.sql.
   Cleans up after itself (see the CLEAN-UP block at the end). Re-runnable: the readings of the test day (2025-06-12) are deleted first.
   ============================================================================ */
SET NOCOUNT ON;

DECLARE @m INT, @officer INT;
SELECT @m = meter_id FROM [dbo].[METER] WHERE network_id = 'DEMO-NET-001' AND status = 'ACTIVE';
SELECT @officer = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'officer1@mdms.cy';
IF @m IS NULL OR @officer IS NULL
    THROW 54000, 'test_vee_range.sql: run import.sql, seed_grid.sql and seed_telemetry_demo.sql first.', 1;

IF OBJECT_ID('tempdb..#results') IS NOT NULL DROP TABLE #results;   -- left over from an aborted run in this session
IF OBJECT_ID('tempdb..#vee') IS NOT NULL DROP TABLE #vee;
CREATE TABLE #results (seq INT IDENTITY(1,1), test VARCHAR(120), result VARCHAR(4), detail NVARCHAR(400));
CREATE TABLE #vee(meters_processed INT, meters_failed INT, readings_valid INT, readings_suspect INT, readings_estimated INT);

DECLARE @d0 DATETIME2(0) = '2025-06-12T10:00:00', @d1 DATETIME2(0) = '2025-06-12T11:00:00';
DECLARE @p NVARCHAR(4000), @pid BIGINT, @ms VARCHAR(20), @n INT;

DELETE FROM [dbo].[METER_READING] WHERE meter_id = @m AND reading_timestamp >= '2025-06-12T00:00:00' AND reading_timestamp < '2025-06-13T00:00:00';

-- five voltages, one per slot 10:00 - 11:00: 230 (ok), 450 (too high), -5 (negative), 400 (the upper limit), 0 (the lower limit)
DECLARE @v TABLE (k INT, val VARCHAR(10));
INSERT INTO @v VALUES (0, '230'), (1, '450'), (2, '-5'), (3, '400'), (4, '0');
DECLARE @k INT = 0, @val VARCHAR(10);
WHILE @k <= 4
BEGIN
    SELECT @val = val FROM @v WHERE k = @k;
    SET @p = CONCAT(N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"',
                    CONVERT(VARCHAR(19), DATEADD(MINUTE, 15 * @k, @d0), 126),
                    N'Z","Telemetry_Payload":[{"obis":"32.7.0","value":', @val, N',"unit":"V"}]}');
    EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1, @pid OUTPUT, @ms OUTPUT, @n OUTPUT;
    SET @k = @k + 1;
END

INSERT INTO #results (test, result, detail)
SELECT 'R0 ingest: 5 voltage readings are PENDING before VEE',
       CASE WHEN COUNT(*) = 5 AND SUM(CASE WHEN status = 'PENDING' THEN 1 ELSE 0 END) = 5 THEN 'PASS' ELSE 'FAIL' END,
       CONCAT(COUNT(*), ' readings')
FROM [dbo].[METER_READING] WHERE meter_id = @m AND obis_code = '32.7.0' AND reading_timestamp >= @d0 AND reading_timestamp <= @d1;

BEGIN TRY
    INSERT INTO #vee EXEC [dbo].[sp_RunVEE] @officer, @d0, @d1, @m;

    INSERT INTO #results (test, result, detail)
    SELECT 'R1 sp_RunVEE summary: 1 meter, 2 suspect, 3 valid, 0 estimated',
           CASE WHEN meters_processed = 1 AND meters_failed = 0 AND readings_suspect = 2
                     AND readings_valid = 3 AND readings_estimated = 0 THEN 'PASS' ELSE 'FAIL' END,
           CONCAT('processed ', meters_processed, ', failed ', meters_failed, ', valid ', readings_valid,
                  ', suspect ', readings_suspect, ', estimated ', readings_estimated)
    FROM #vee;

    INSERT INTO #results (test, result, detail)
    SELECT 'R2 450 V and -5 V -> SUSPECT / RANGE with a note, value untouched',
           CASE WHEN COUNT(*) = 2 AND SUM(CASE WHEN status = 'SUSPECT' AND vee_rule = 'RANGE' AND vee_note IS NOT NULL
                                                    AND original_value IS NULL AND is_final = 0 THEN 1 ELSE 0 END) = 2
                     AND MIN([value]) = -5 AND MAX([value]) = 450 THEN 'PASS' ELSE 'FAIL' END,
           NULL
    FROM [dbo].[METER_READING]
    WHERE meter_id = @m AND obis_code = '32.7.0' AND reading_timestamp >= @d0 AND reading_timestamp <= @d1 AND [value] IN (450, -5);

    INSERT INTO #results (test, result, detail)
    SELECT 'R3 230 V, 400 V (upper limit) and 0 V (lower limit) -> VALID / AUTO, not left PENDING',
           CASE WHEN COUNT(*) = 3 AND SUM(CASE WHEN status = 'VALID' AND vee_rule = 'AUTO' AND is_final = 0 THEN 1 ELSE 0 END) = 3
                THEN 'PASS' ELSE 'FAIL' END, CONCAT(COUNT(*), ' readings')
    FROM [dbo].[METER_READING]
    WHERE meter_id = @m AND obis_code = '32.7.0' AND reading_timestamp >= @d0 AND reading_timestamp <= @d1 AND [value] IN (230, 400, 0);

    -- a second run has nothing PENDING left: the suspect readings are not touched or counted again
    DELETE FROM #vee;
    INSERT INTO #vee EXEC [dbo].[sp_RunVEE] @officer, @d0, @d1, @m;
    INSERT INTO #results (test, result, detail)
    SELECT 'R4 second run -> nothing to do, the SUSPECT readings stay SUSPECT',
           CASE WHEN (SELECT meters_processed FROM #vee) = 0
                     AND (SELECT COUNT(*) FROM [dbo].[METER_READING]
                          WHERE meter_id = @m AND obis_code = '32.7.0' AND reading_timestamp >= @d0 AND reading_timestamp <= @d1
                            AND status = 'SUSPECT') = 2 THEN 'PASS' ELSE 'FAIL' END, NULL;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT INTO #results (test, result, detail) VALUES ('R sp_RunVEE (range)', 'FAIL', LEFT(ERROR_MESSAGE(), 400));
END CATCH

/* ===========================================================================
   SUMMARY
   =========================================================================== */
SELECT seq, result, test, detail FROM #results ORDER BY seq;
SELECT result, COUNT(*) AS tests FROM #results GROUP BY result;

SELECT r.reading_timestamp, r.obis_code, r.[value], r.status, r.vee_rule, r.vee_note
FROM [dbo].[METER_READING] AS r
WHERE r.meter_id = @m AND r.obis_code = '32.7.0' AND r.reading_timestamp >= @d0 AND r.reading_timestamp <= @d1
ORDER BY r.reading_timestamp;

/* ===========================================================================
   CLEAN-UP: remove what this test wrote (events, readings, packets of the test day 2025-06-12).
   The results above were already produced, so nothing is lost. The seeds (DEMO-NET-001 and its
   transformers) stay on purpose so the test can be run again. The audit log is append-only
   (TR03), so its VEE_RUN / status lines stay by design.
   =========================================================================== */
DELETE e FROM [dbo].[EVENT] AS e
JOIN [dbo].[TELEMETRY_PACKET] AS p ON p.packet_id = e.packet_id
WHERE p.meter_network_id LIKE 'DEMO-%' AND p.transmission_timestamp >= '2025-06-12' AND p.transmission_timestamp < '2025-06-13';
DECLARE @clean_events INT = @@ROWCOUNT;
DELETE FROM [dbo].[METER_READING] WHERE meter_id = @m AND reading_timestamp >= '2025-06-12' AND reading_timestamp < '2025-06-13';
DECLARE @clean_readings INT = @@ROWCOUNT;
DELETE FROM [dbo].[TELEMETRY_PACKET]
WHERE meter_network_id LIKE 'DEMO-%' AND transmission_timestamp >= '2025-06-12' AND transmission_timestamp < '2025-06-13';
DECLARE @clean_packets INT = @@ROWCOUNT;
PRINT 'clean-up: ' + CAST(@clean_events AS VARCHAR(10)) + ' events, ' + CAST(@clean_readings AS VARCHAR(10))
      + ' readings, ' + CAST(@clean_packets AS VARCHAR(10)) + ' packets deleted.';

DECLARE @fails INT = (SELECT COUNT(*) FROM #results WHERE result <> 'PASS');
DECLARE @total INT = (SELECT COUNT(*) FROM #results);
PRINT 'test_vee_range.sql: ' + CAST(@total AS VARCHAR(10)) + ' tests, ' + CAST(@fails AS VARCHAR(10)) + ' not passed.';
DROP TABLE #vee;
DROP TABLE #results;
