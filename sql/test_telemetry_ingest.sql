/* ============================================================================
   test_telemetry_ingest.sql  -  dbo.sp_IngestTelemetryPacket (Algorithm A, Build Spec 9.6)

   Ported to the io implementation. Self-checking: one PASS / FAIL row per test at the end.

   Needs: import.sql, seed_grid.sql, seed_telemetry_demo.sql  (DEMO-NET-001 ACTIVE).
   Re-runnable: the readings of the test day (2025-06-10) are deleted first (they are not final,
   so TR01 allows it). Packets and events of earlier runs stay, as they would in production.

   What changed against the first version of these tests (and why):
     T1  valid packet          unchanged in intent: MATCHED, 2 readings, stored PENDING.
     T1b re-sent packet        was  QUARANTINED / 0 / "Readings already exist for this slot".
                               io:  the packet is MATCHED, 0 readings are inserted, and one
                                    DUPLICATE_READING (INFO) event names the slot and the codes.
     T2  unknown meter         unchanged in intent: UNMATCHED, 0 readings; the WARNING event is
                               written by TR19 as PACKET_UNMATCHED (EVENT has no "result" column).
     T3  wrong unit            was  QUARANTINED / 0 / "Unknown OBIS, wrong unit or invalid value".
                               io:  the packet is MATCHED and the reading IS stored, but as SUSPECT
                                    with vee_rule UNIT_MISMATCH (Build Spec 9.6, Algorithm A) so the
                                    officer decides. QUARANTINED in io means "meter not ACTIVE".
   ============================================================================ */
SET NOCOUNT ON;

DECLARE @m INT;
SELECT @m = meter_id FROM [dbo].[METER] WHERE network_id = 'DEMO-NET-001' AND status = 'ACTIVE';
IF @m IS NULL
    THROW 54000, 'test_telemetry_ingest.sql: DEMO-NET-001 is not ACTIVE - run import.sql, seed_grid.sql, seed_telemetry_demo.sql.', 1;
IF EXISTS (SELECT 1 FROM [dbo].[METER] WHERE network_id = 'DEMO-UNKNOWN-001')
    THROW 54000, 'test_telemetry_ingest.sql: DEMO-UNKNOWN-001 must not exist as a meter.', 1;

IF OBJECT_ID('tempdb..#results') IS NOT NULL DROP TABLE #results;   -- left over from an aborted run in this session
CREATE TABLE #results (seq INT IDENTITY(1,1), test VARCHAR(120), result VARCHAR(4), detail NVARCHAR(400));

DECLARE @d0 DATETIME2(0) = '2025-06-10T00:00:00', @d1 DATETIME2(0) = '2025-06-11T00:00:00';
DECLARE @p NVARCHAR(4000), @pid BIGINT, @pid1 BIGINT, @ms VARCHAR(20), @n INT;

DELETE FROM [dbo].[METER_READING] WHERE meter_id = @m AND reading_timestamp >= @d0 AND reading_timestamp < @d1;

/* ---------------------------------------------------------------------------
   T1: a valid packet (1.8.0 in kWh and 32.7.0 in V), slot 10:15
   --------------------------------------------------------------------------- */
SET @p = N'{
    "Meter_Network_ID": "DEMO-NET-001",
    "Transmission_Timestamp": "2025-06-10T10:15:00Z",
    "Cell_Signal_Strength_dBm": -92,
    "Network_Type": "NB_IOT",
    "Telemetry_Payload": [
        { "obis": "1.8.0",  "value": 1000.5000, "unit": "kWh" },
        { "obis": "32.7.0", "value": 231.0000,  "unit": "V" }
    ]
}';
BEGIN TRY
    EXEC [dbo].[sp_IngestTelemetryPacket] @payload = @p, @silent = 1,
         @packet_id = @pid OUTPUT, @match_status = @ms OUTPUT, @readings_inserted = @n OUTPUT;
    SET @pid1 = @pid;
    INSERT INTO #results (test, result, detail)
    SELECT 'T1 valid packet -> MATCHED, 2 readings stored as PENDING',
           CASE WHEN @ms = 'MATCHED' AND @n = 2
                     AND (SELECT COUNT(*) FROM [dbo].[METER_READING]
                          WHERE packet_id = @pid AND meter_id = @m AND status = 'PENDING' AND is_final = 0
                            AND reading_timestamp = '2025-06-10T10:15:00') = 2
                     AND EXISTS (SELECT 1 FROM [dbo].[TELEMETRY_PACKET]
                                 WHERE packet_id = @pid AND match_status = 'MATCHED' AND meter_id = @m
                                   AND meter_network_id = 'DEMO-NET-001' AND network_type = 'NB_IOT' AND signal_dbm = -92)
                     AND NOT EXISTS (SELECT 1 FROM [dbo].[EVENT] WHERE packet_id = @pid)
                THEN 'PASS' ELSE 'FAIL' END,
           CONCAT(@ms, ' / readings ', @n);
END TRY
BEGIN CATCH INSERT INTO #results (test, result, detail) VALUES ('T1 valid packet', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ---------------------------------------------------------------------------
   T1b: the same packet again -> nothing new is stored, one DUPLICATE_READING event
   --------------------------------------------------------------------------- */
BEGIN TRY
    EXEC [dbo].[sp_IngestTelemetryPacket] @payload = @p, @silent = 1,
         @packet_id = @pid OUTPUT, @match_status = @ms OUTPUT, @readings_inserted = @n OUTPUT;
    INSERT INTO #results (test, result, detail)
    SELECT 'T1b same packet again -> MATCHED, 0 readings, DUPLICATE_READING event, still 2 readings in the slot',
           CASE WHEN @ms = 'MATCHED' AND @n = 0 AND @pid <> @pid1
                     AND EXISTS (SELECT 1 FROM [dbo].[EVENT]
                                 WHERE packet_id = @pid AND event_type = 'DUPLICATE_READING' AND severity = 'INFO' AND meter_id = @m)
                     AND (SELECT COUNT(*) FROM [dbo].[METER_READING]
                          WHERE meter_id = @m AND reading_timestamp = '2025-06-10T10:15:00') = 2
                     AND NOT EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE packet_id = @pid)
                THEN 'PASS' ELSE 'FAIL' END,
           CONCAT(@ms, ' / readings ', @n);
END TRY
BEGIN CATCH INSERT INTO #results (test, result, detail) VALUES ('T1b same packet again', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ---------------------------------------------------------------------------
   T2: unknown meter -> the packet is kept as UNMATCHED, nothing else, TR19 raises a WARNING event
   --------------------------------------------------------------------------- */
SET @p = N'{
    "Meter_Network_ID": "DEMO-UNKNOWN-001",
    "Transmission_Timestamp": "2025-06-10T10:30:00Z",
    "Cell_Signal_Strength_dBm": -92,
    "Network_Type": "NB_IOT",
    "Telemetry_Payload": [ { "obis": "1.8.0", "value": 1001.0000, "unit": "kWh" } ]
}';
BEGIN TRY
    EXEC [dbo].[sp_IngestTelemetryPacket] @payload = @p, @silent = 1,
         @packet_id = @pid OUTPUT, @match_status = @ms OUTPUT, @readings_inserted = @n OUTPUT;
    INSERT INTO #results (test, result, detail)
    SELECT 'T2 unknown meter -> UNMATCHED, 0 readings, PACKET_UNMATCHED WARNING event',
           CASE WHEN @ms = 'UNMATCHED' AND @n = 0
                     AND EXISTS (SELECT 1 FROM [dbo].[TELEMETRY_PACKET]
                                 WHERE packet_id = @pid AND match_status = 'UNMATCHED' AND meter_id IS NULL
                                   AND meter_network_id = 'DEMO-UNKNOWN-001' AND ISJSON(raw_payload) = 1)
                     AND EXISTS (SELECT 1 FROM [dbo].[EVENT]
                                 WHERE packet_id = @pid AND event_type = 'PACKET_UNMATCHED' AND severity = 'WARNING')
                     AND NOT EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE packet_id = @pid)
                THEN 'PASS' ELSE 'FAIL' END,
           CONCAT(@ms, ' / readings ', @n);
END TRY
BEGIN CATCH INSERT INTO #results (test, result, detail) VALUES ('T2 unknown meter', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ---------------------------------------------------------------------------
   T3: wrong unit (32.7.0 is in V, the packet says kWh) -> stored as SUSPECT / UNIT_MISMATCH
   --------------------------------------------------------------------------- */
SET @p = N'{
    "Meter_Network_ID": "DEMO-NET-001",
    "Transmission_Timestamp": "2025-06-10T10:30:00Z",
    "Cell_Signal_Strength_dBm": -92,
    "Network_Type": "NB_IOT",
    "Telemetry_Payload": [ { "obis": "32.7.0", "value": 230.0000, "unit": "kWh" } ]
}';
BEGIN TRY
    EXEC [dbo].[sp_IngestTelemetryPacket] @payload = @p, @silent = 1,
         @packet_id = @pid OUTPUT, @match_status = @ms OUTPUT, @readings_inserted = @n OUTPUT;
    INSERT INTO #results (test, result, detail)
    SELECT 'T3 wrong unit -> MATCHED, 1 reading stored as SUSPECT (UNIT_MISMATCH)',
           CASE WHEN @ms = 'MATCHED' AND @n = 1
                     AND EXISTS (SELECT 1 FROM [dbo].[METER_READING]
                                 WHERE packet_id = @pid AND meter_id = @m AND obis_code = '32.7.0'
                                   AND status = 'SUSPECT' AND vee_rule = 'UNIT_MISMATCH' AND is_final = 0
                                   AND vee_note LIKE N'%kWh%')
                THEN 'PASS' ELSE 'FAIL' END,
           CONCAT(@ms, ' / readings ', @n);
END TRY
BEGIN CATCH INSERT INTO #results (test, result, detail) VALUES ('T3 wrong unit', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ===========================================================================
   SUMMARY
   =========================================================================== */
SELECT seq, result, test, detail FROM #results ORDER BY seq;
SELECT result, COUNT(*) AS tests FROM #results GROUP BY result;

-- what the tests stored (the inspection queries of the first version)
SELECT p.packet_id, p.meter_network_id, p.transmission_timestamp, p.match_status, p.meter_id,
       e.event_type, e.severity
FROM [dbo].[TELEMETRY_PACKET] AS p
LEFT JOIN [dbo].[EVENT] AS e ON e.packet_id = p.packet_id
WHERE p.meter_network_id IN ('DEMO-NET-001', 'DEMO-UNKNOWN-001')
  AND p.transmission_timestamp >= @d0 AND p.transmission_timestamp < @d1
ORDER BY p.packet_id, e.event_id;

SELECT r.reading_id, r.packet_id, r.reading_timestamp, r.obis_code, r.[value], r.status, r.vee_rule, r.is_final
FROM [dbo].[METER_READING] AS r
WHERE r.meter_id = @m AND r.reading_timestamp >= @d0 AND r.reading_timestamp < @d1
ORDER BY r.reading_timestamp, r.obis_code;

DECLARE @fails INT = (SELECT COUNT(*) FROM #results WHERE result <> 'PASS');
DECLARE @total INT = (SELECT COUNT(*) FROM #results);
PRINT 'test_telemetry_ingest.sql: ' + CAST(@total AS VARCHAR(10)) + ' tests, ' + CAST(@fails AS VARCHAR(10)) + ' not passed.';
DROP TABLE #results;
