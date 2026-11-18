/* ============================================================================
   test_telemetry_storage.sql  -  what sp_IngestTelemetryPacket stores (Algorithm A, Build Spec 9.6)

   REWRITTEN. The first version was a stand-alone re-implementation of ingestion (a T-SQL script that
   did its own validation and INSERTs) with rules that io does not have:
        first version                                  io (sp_IngestTelemetryPacket)
        ---------------------------------------------  ---------------------------------------------
        off-slot timestamp  -> THROW 54001, rejected   timestamp is floored with fn_Floor15
        unknown OBIS / unit -> THROW 54004, all lost   unknown OBIS: UNSUPPORTED_OBIS event, others stored;
                                                       wrong unit: stored as SUSPECT / UNIT_MISMATCH
        duplicate OBIS      -> THROW 54005             the first one is kept, the rest are ignored
        existing slot       -> THROW 54007             DUPLICATE_READING event, the packet is still kept
        MATCHED needs ACTIVE + APPROVED meter          MATCHED = ACTIVE meter (there is no approval_status)
        reading.validation_status / value_source       reading.status (PENDING) ; no value_source
        no delta                                       delta_value (15-min energy) is computed at ingest
   So this script now calls the real procedure and checks the rows it leaves behind.

   Needs: import.sql, seed_grid.sql, seed_telemetry_demo.sql.
   Re-runnable: the readings of the test day (2025-06-11) are deleted first.
   ============================================================================ */
SET NOCOUNT ON;

DECLARE @m INT;
SELECT @m = meter_id FROM [dbo].[METER] WHERE network_id = 'DEMO-NET-001' AND status = 'ACTIVE';
IF @m IS NULL
    THROW 54000, 'test_telemetry_storage.sql: DEMO-NET-001 is not ACTIVE - run import.sql, seed_grid.sql, seed_telemetry_demo.sql.', 1;

IF OBJECT_ID('tempdb..#results') IS NOT NULL DROP TABLE #results;   -- left over from an aborted run in this session
CREATE TABLE #results (seq INT IDENTITY(1,1), test VARCHAR(120), result VARCHAR(4), detail NVARCHAR(400));

DECLARE @d0 DATETIME2(0) = '2025-06-11T00:00:00', @d1 DATETIME2(0) = '2025-06-11T23:59:59';
DECLARE @p NVARCHAR(4000), @pid BIGINT, @ms VARCHAR(20), @n INT, @d DECIMAL(18,4), @cnt INT;

DELETE FROM [dbo].[METER_READING] WHERE meter_id = @m AND reading_timestamp >= @d0 AND reading_timestamp <= @d1;

/* S1: three 1.8.0 packets at 09:00, 09:15 and 09:45 (09:30 is missing) */
BEGIN TRY
    SET @p = N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"2025-06-11T09:00:00Z","Cell_Signal_Strength_dBm":-90,"Network_Type":"NB_IOT","Telemetry_Payload":[{"obis":"1.8.0","value":1000.0000,"unit":"kWh"}]}';
    EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1, @pid OUTPUT, @ms OUTPUT, @n OUTPUT;
    INSERT INTO #results (test, result, detail)
    SELECT 'S1a packet row keeps the raw JSON and links the meter',
           CASE WHEN EXISTS (SELECT 1 FROM [dbo].[TELEMETRY_PACKET]
                             WHERE packet_id = @pid AND raw_payload = @p AND match_status = 'MATCHED' AND meter_id = @m
                               AND transmission_timestamp = '2025-06-11T09:00:00' AND signal_dbm = -90)
                THEN 'PASS' ELSE 'FAIL' END, CONCAT(@ms, ' / readings ', @n);

    SET @p = N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"2025-06-11T09:15:00Z","Telemetry_Payload":[{"obis":"1.8.0","value":1000.5000,"unit":"kWh"}]}';
    EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1, @pid OUTPUT, @ms OUTPUT, @n OUTPUT;
    SET @p = N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"2025-06-11T09:45:00Z","Telemetry_Payload":[{"obis":"1.8.0","value":1001.5000,"unit":"kWh"}]}';
    EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1, @pid OUTPUT, @ms OUTPUT, @n OUTPUT;

    INSERT INTO #results (test, result, detail)
    SELECT 'S1b readings are PENDING, not final, with the packet id and no VEE rule yet',
           CASE WHEN COUNT(*) = 3 AND SUM(CASE WHEN status = 'PENDING' AND is_final = 0 AND packet_id IS NOT NULL
                                                    AND vee_rule IS NULL AND original_value IS NULL THEN 1 ELSE 0 END) = 3
                THEN 'PASS' ELSE 'FAIL' END, CONCAT(COUNT(*), ' readings')
    FROM [dbo].[METER_READING] WHERE meter_id = @m AND reading_timestamp >= @d0 AND reading_timestamp <= @d1;

    INSERT INTO #results (test, result, detail)
    SELECT 'S1c delta_value: NULL for the first reading, 0.5 after it, NULL after a missing slot',
           CASE WHEN MAX(CASE WHEN reading_timestamp = '2025-06-11T09:00:00' AND delta_value IS NULL THEN 1 ELSE 0 END) = 1
                 AND MAX(CASE WHEN reading_timestamp = '2025-06-11T09:15:00' AND delta_value = 0.5 THEN 1 ELSE 0 END) = 1
                 AND MAX(CASE WHEN reading_timestamp = '2025-06-11T09:45:00' AND delta_value IS NULL THEN 1 ELSE 0 END) = 1
                THEN 'PASS' ELSE 'FAIL' END, NULL
    FROM [dbo].[METER_READING] WHERE meter_id = @m AND obis_code = '1.8.0' AND reading_timestamp >= @d0 AND reading_timestamp <= @d1;
END TRY
BEGIN CATCH INSERT INTO #results (test, result, detail) VALUES ('S1 storage and delta', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* S2: the late packet of 09:30 arrives -> its own energy, and the energy of the 09:45 reading is recomputed */
BEGIN TRY
    SET @p = N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"2025-06-11T09:30:00Z","Telemetry_Payload":[{"obis":"1.8.0","value":1001.0000,"unit":"kWh"}]}';
    EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1, @pid OUTPUT, @ms OUTPUT, @n OUTPUT;
    INSERT INTO #results (test, result, detail)
    SELECT 'S2 late packet (09:30): delta 0.5, and the already stored 09:45 reading is recomputed to 0.5',
           CASE WHEN @n = 1
                 AND MAX(CASE WHEN reading_timestamp = '2025-06-11T09:30:00' AND delta_value = 0.5 THEN 1 ELSE 0 END) = 1
                 AND MAX(CASE WHEN reading_timestamp = '2025-06-11T09:45:00' AND delta_value = 0.5 THEN 1 ELSE 0 END) = 1
                THEN 'PASS' ELSE 'FAIL' END, NULL
    FROM [dbo].[METER_READING] WHERE meter_id = @m AND obis_code = '1.8.0' AND reading_timestamp >= @d0 AND reading_timestamp <= @d1;
END TRY
BEGIN CATCH INSERT INTO #results (test, result, detail) VALUES ('S2 late packet', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* S3: a timestamp that is not on a 15-minute slot is floored (the first version rejected it) */
BEGIN TRY
    SET @p = N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"2025-06-11T10:07:30Z","Telemetry_Payload":[{"obis":"1.8.0","value":1002.0000,"unit":"kWh"}]}';
    EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1, @pid OUTPUT, @ms OUTPUT, @n OUTPUT;
    INSERT INTO #results (test, result, detail)
    SELECT 'S3 10:07:30 -> reading in the 10:00 slot, the packet keeps the real time',
           CASE WHEN @ms = 'MATCHED' AND @n = 1
                 AND EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE packet_id = @pid AND reading_timestamp = '2025-06-11T10:00:00')
                 AND EXISTS (SELECT 1 FROM [dbo].[TELEMETRY_PACKET] WHERE packet_id = @pid AND transmission_timestamp = '2025-06-11T10:07:30')
                THEN 'PASS' ELSE 'FAIL' END, CONCAT(@ms, ' / readings ', @n);
END TRY
BEGIN CATCH INSERT INTO #results (test, result, detail) VALUES ('S3 off-slot timestamp', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* S4: an OBIS code the system does not know -> one UNSUPPORTED_OBIS event, the known code is still stored */
BEGIN TRY
    SET @p = N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"2025-06-11T10:15:00Z","Telemetry_Payload":[{"obis":"1.8.0","value":1002.5000,"unit":"kWh"},{"obis":"99.9.9","value":5,"unit":"X"}]}';
    EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1, @pid OUTPUT, @ms OUTPUT, @n OUTPUT;
    INSERT INTO #results (test, result, detail)
    SELECT 'S4 unknown OBIS 99.9.9 -> UNSUPPORTED_OBIS event, only 1.8.0 stored',
           CASE WHEN @ms = 'MATCHED' AND @n = 1
                 AND EXISTS (SELECT 1 FROM [dbo].[EVENT] WHERE packet_id = @pid AND event_type = 'UNSUPPORTED_OBIS' AND description LIKE N'%99.9.9%')
                 AND NOT EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE packet_id = @pid AND obis_code = '99.9.9')
                 AND EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE packet_id = @pid AND obis_code = '1.8.0')
                THEN 'PASS' ELSE 'FAIL' END, CONCAT(@ms, ' / readings ', @n);
END TRY
BEGIN CATCH INSERT INTO #results (test, result, detail) VALUES ('S4 unknown OBIS', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* S5: the same OBIS twice in one packet -> one reading (the first version threw an error);
       an INSTANTANEOUS code has no delta_value */
BEGIN TRY
    SET @p = N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"2025-06-11T10:30:00Z","Telemetry_Payload":[{"obis":"32.7.0","value":230.0000,"unit":"V"},{"obis":"32.7.0","value":231.0000,"unit":"V"}]}';
    EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1, @pid OUTPUT, @ms OUTPUT, @n OUTPUT;
    SELECT @cnt = COUNT(*) FROM [dbo].[METER_READING] WHERE packet_id = @pid AND obis_code = '32.7.0';
    INSERT INTO #results (test, result, detail)
    SELECT 'S5 duplicate OBIS inside one packet -> exactly one reading, delta_value NULL for a voltage',
           CASE WHEN @ms = 'MATCHED' AND @n = 1 AND @cnt = 1
                 AND EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE packet_id = @pid AND obis_code = '32.7.0' AND delta_value IS NULL AND status = 'PENDING')
                THEN 'PASS' ELSE 'FAIL' END, CONCAT(@ms, ' / readings ', @n, ' / stored ', @cnt);
END TRY
BEGIN CATCH INSERT INTO #results (test, result, detail) VALUES ('S5 duplicate OBIS', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* S6: a value that is not a number -> the pair is dropped (current io behaviour: no error, no event).
       The first version treated a missing value as an error; the spec only says missing pairs are not errors. */
BEGIN TRY
    SET @p = N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"2025-06-11T10:45:00Z","Telemetry_Payload":[{"obis":"1.8.0","value":"abc","unit":"kWh"}]}';
    EXEC [dbo].[sp_IngestTelemetryPacket] @p, 1, @pid OUTPUT, @ms OUTPUT, @n OUTPUT;
    INSERT INTO #results (test, result, detail)
    SELECT 'S6 non-numeric value -> packet kept as MATCHED, 0 readings (pair dropped)',
           CASE WHEN @ms = 'MATCHED' AND @n = 0
                 AND EXISTS (SELECT 1 FROM [dbo].[TELEMETRY_PACKET] WHERE packet_id = @pid AND match_status = 'MATCHED')
                 AND NOT EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE packet_id = @pid)
                THEN 'PASS' ELSE 'FAIL' END, CONCAT(@ms, ' / readings ', @n);
END TRY
BEGIN CATCH INSERT INTO #results (test, result, detail) VALUES ('S6 non-numeric value', 'FAIL', LEFT(ERROR_MESSAGE(), 400)); END CATCH

/* ===========================================================================
   SUMMARY
   =========================================================================== */
SELECT seq, result, test, detail FROM #results ORDER BY seq;
SELECT result, COUNT(*) AS tests FROM #results GROUP BY result;

SELECT r.reading_timestamp, r.obis_code, r.[value], r.delta_value, r.status, r.vee_rule, r.packet_id
FROM [dbo].[METER_READING] AS r
WHERE r.meter_id = @m AND r.reading_timestamp >= @d0 AND r.reading_timestamp <= @d1
ORDER BY r.reading_timestamp, r.obis_code;

DECLARE @fails INT = (SELECT COUNT(*) FROM #results WHERE result <> 'PASS');
DECLARE @total INT = (SELECT COUNT(*) FROM #results);
PRINT 'test_telemetry_storage.sql: ' + CAST(@total AS VARCHAR(10)) + ' tests, ' + CAST(@fails AS VARCHAR(10)) + ' not passed.';
DROP TABLE #results;
