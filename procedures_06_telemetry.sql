/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_06_telemetry.sql  -  Build Spec §9.6: ingestion, VEE, aggregates, purge
   Algorithms A (ingest), B (VEE), C (finalize), D (transformer aggregates).
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf §3.1 p.8; Appendix p.15: one telemetry packet in JSON; UC-15]  Algorithm A
-- No user: the meter or the head-end sends it (mechanism INGESTION).
-- Every packet is stored, matched or not (TR19 raises the event for the ones that are not).
-- @silent / the OUTPUT parameters are for sp_IngestTelemetryBatch only; PHP reads the result set.
CREATE OR ALTER PROCEDURE [dbo].[sp_IngestTelemetryPacket]
    @payload           NVARCHAR(4000),
    @silent            BIT = 0,
    @packet_id         BIGINT = NULL OUTPUT,
    @match_status      VARCHAR(20) = NULL OUTPUT,
    @readings_inserted INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__SetActor] NULL, 'INGESTION';

    DECLARE @net VARCHAR(60) = NULL, @ts DATETIME2(0) = NULL, @network_type VARCHAR(30) = NULL, @signal SMALLINT = NULL;
    DECLARE @is_json BIT = CASE WHEN ISJSON(@payload) = 1 THEN 1 ELSE 0 END;
    SELECT @packet_id = NULL, @match_status = NULL, @readings_inserted = 0;

    IF @is_json = 1
    BEGIN
        SET @net = LEFT(JSON_VALUE(@payload, '$.Meter_Network_ID'), 60);
        SET @ts  = CAST(SWITCHOFFSET(TRY_CONVERT(DATETIMEOFFSET, JSON_VALUE(@payload, '$.Transmission_Timestamp')), '+00:00') AS DATETIME2(0));
        SET @network_type = LEFT(JSON_VALUE(@payload, '$.Network_Type'), 30);
        SET @signal = TRY_CONVERT(SMALLINT, JSON_VALUE(@payload, '$.Cell_Signal_Strength_dBm'));
    END

    -- step 2: malformed packet -> COMM_ERROR, raw text kept (wrapped as JSON so the CHECK passes)
    IF @is_json = 0 OR @net IS NULL OR @ts IS NULL
    BEGIN
        DECLARE @raw NVARCHAR(4000) = CASE WHEN @is_json = 1 THEN @payload
                                           ELSE ISNULL((SELECT LEFT(@payload, 1800) AS [raw] FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), N'{}') END;
        INSERT INTO [dbo].[TELEMETRY_PACKET] (meter_network_id, transmission_timestamp, network_type, signal_dbm, raw_payload, match_status)
        VALUES (ISNULL(@net, 'UNKNOWN'), SYSUTCDATETIME(), @network_type, @signal, @raw, 'COMM_ERROR');
        SET @packet_id = SCOPE_IDENTITY();
        SET @match_status = 'COMM_ERROR';
        IF @silent = 0
            SELECT @packet_id AS packet_id, @match_status AS match_status, @readings_inserted AS readings_inserted;
        RETURN;
    END

    -- step 4: match the network id with a meter
    DECLARE @meter_id INT = NULL, @meter_status VARCHAR(20) = NULL;
    SELECT @meter_id = meter_id, @meter_status = status FROM [dbo].[METER] WHERE network_id = @net;
    SET @match_status = CASE WHEN @meter_id IS NULL THEN 'UNMATCHED'
                             WHEN @meter_status = 'ACTIVE' THEN 'MATCHED'
                             ELSE 'QUARANTINED' END;

    DECLARE @pairs TABLE (obis VARCHAR(20) NOT NULL PRIMARY KEY, val DECIMAL(18,4) NOT NULL, unit VARCHAR(10) NULL);
    DECLARE @slot DATETIME2(0) = [dbo].[fn_Floor15](@ts);
    DECLARE @list NVARCHAR(400);

    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[TELEMETRY_PACKET] (meter_network_id, transmission_timestamp, network_type, signal_dbm, raw_payload, match_status, meter_id)
        VALUES (@net, @ts, @network_type, @signal, @payload, @match_status, @meter_id);
        SET @packet_id = SCOPE_IDENTITY();

        IF @match_status = 'MATCHED'
        BEGIN
            -- the OBIS / value pairs (a packet does not have to carry every code)
            INSERT INTO @pairs (obis, val, unit)
            SELECT x.obis, x.val, x.unit
            FROM (SELECT j.obis, TRY_CONVERT(DECIMAL(18,4), j.val) AS val, j.unit,
                         ROW_NUMBER() OVER (PARTITION BY j.obis ORDER BY (SELECT NULL)) AS rn
                  FROM OPENJSON(@payload, '$.Telemetry_Payload')
                       WITH (obis VARCHAR(20) '$.obis', val NVARCHAR(50) '$.value', unit VARCHAR(10) '$.unit') AS j
                  WHERE j.obis IS NOT NULL) AS x
            WHERE x.rn = 1 AND x.val IS NOT NULL;

            -- codes that the system does not know: one event, not stored
            SELECT @list = LEFT(STRING_AGG(CAST(p.obis AS NVARCHAR(MAX)), N', '), 400)
            FROM @pairs AS p
            WHERE NOT EXISTS (SELECT 1 FROM [dbo].[OBIS_CODE] AS o WHERE o.obis_code = p.obis);
            IF @list IS NOT NULL
            BEGIN
                INSERT INTO [dbo].[EVENT] (event_timestamp, event_type, severity, description, meter_id, packet_id)
                VALUES (@ts, 'UNSUPPORTED_OBIS', 'INFO', N'Unsupported OBIS codes: ' + @list, @meter_id, @packet_id);
                DELETE p FROM @pairs AS p
                WHERE NOT EXISTS (SELECT 1 FROM [dbo].[OBIS_CODE] AS o WHERE o.obis_code = p.obis);
            END

            -- a reading for this meter / code / slot already exists: one event, skipped
            SET @list = NULL;
            SELECT @list = LEFT(STRING_AGG(CAST(p.obis AS NVARCHAR(MAX)), N', '), 400)
            FROM @pairs AS p
            WHERE EXISTS (SELECT 1 FROM [dbo].[METER_READING] AS r
                          WHERE r.meter_id = @meter_id AND r.obis_code = p.obis AND r.reading_timestamp = @slot);
            IF @list IS NOT NULL
            BEGIN
                INSERT INTO [dbo].[EVENT] (event_timestamp, event_type, severity, description, meter_id, packet_id)
                VALUES (@ts, 'DUPLICATE_READING', 'INFO',
                        N'Slot ' + CONVERT(NVARCHAR(19), @slot, 120) + N' already has: ' + @list, @meter_id, @packet_id);
                DELETE p FROM @pairs AS p
                WHERE EXISTS (SELECT 1 FROM [dbo].[METER_READING] AS r
                              WHERE r.meter_id = @meter_id AND r.obis_code = p.obis AND r.reading_timestamp = @slot);
            END

            -- the readings: PENDING (or SUSPECT on a unit mismatch); 15-min energy for cumulative registers
            INSERT INTO [dbo].[METER_READING] (reading_timestamp, [value], delta_value, status, vee_rule, vee_note, meter_id, obis_code, packet_id)
            SELECT @slot, p.val,
                   CASE WHEN o.measurement_kind = 'CUMULATIVE' THEN p.val - prev.[value] END,
                   CASE WHEN p.unit IS NOT NULL AND p.unit <> o.unit THEN 'SUSPECT' ELSE 'PENDING' END,
                   CASE WHEN p.unit IS NOT NULL AND p.unit <> o.unit THEN 'UNIT_MISMATCH' END,
                   CASE WHEN p.unit IS NOT NULL AND p.unit <> o.unit THEN N'Unit ' + p.unit + N' instead of ' + o.unit END,
                   @meter_id, p.obis, @packet_id
            FROM @pairs AS p
            JOIN [dbo].[OBIS_CODE] AS o ON o.obis_code = p.obis
            LEFT JOIN [dbo].[METER_READING] AS prev
                   ON prev.meter_id = @meter_id AND prev.obis_code = p.obis
                  AND prev.reading_timestamp = DATEADD(MINUTE, -15, @slot);
            SET @readings_inserted = @@ROWCOUNT;

            -- a late packet: the next slot is already there, so its energy changes too
            UPDATE nxt
               SET delta_value = nxt.[value] - p.val
            FROM [dbo].[METER_READING] AS nxt
            JOIN @pairs AS p ON p.obis = nxt.obis_code
            JOIN [dbo].[OBIS_CODE] AS o ON o.obis_code = p.obis AND o.measurement_kind = 'CUMULATIVE'
            WHERE nxt.meter_id = @meter_id
              AND nxt.reading_timestamp = DATEADD(MINUTE, 15, @slot)
              AND nxt.is_final = 0;

            -- voltage quality: 230 V +/- 10 %  [§1.2 p.5; §II.Γ p.3]
            INSERT INTO [dbo].[EVENT] (event_timestamp, event_type, severity, description, meter_id, packet_id)
            SELECT @ts, CASE WHEN p.val < 207 THEN 'VOLTAGE_SAG' ELSE 'VOLTAGE_SWELL' END, 'WARNING',
                   N'Voltage ' + CAST(p.val AS NVARCHAR(30)) + N' V on ' + p.obis + N' (allowed 207 - 253 V).',
                   @meter_id, @packet_id
            FROM @pairs AS p
            WHERE p.obis IN ('32.7.0', '52.7.0', '72.7.0') AND (p.val < 207 OR p.val > 253);
        END
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    IF @silent = 0
        SELECT @packet_id AS packet_id, @match_status AS match_status, @readings_inserted AS readings_inserted;
END;
GO

-- [project.pdf §3.1 p.8: packets arrive in volume]
-- Cursor over the elements of a JSON array; each packet goes through sp_IngestTelemetryPacket
-- in its own transaction, so one bad packet does not stop the others.
CREATE OR ALTER PROCEDURE [dbo].[sp_IngestTelemetryBatch]
    @actor_user_id INT,
    @payload_array NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO';

    IF ISJSON(@payload_array) = 0 OR LEFT(LTRIM(@payload_array), 1) <> N'['
        THROW 50004, 'Invalid input: a JSON array of packets is required.', 1;

    DECLARE @element NVARCHAR(MAX), @one NVARCHAR(4000), @pid BIGINT, @status VARCHAR(20), @n INT;
    DECLARE @total INT = 0, @matched INT = 0, @unmatched INT = 0, @quarantined INT = 0,
            @comm_error INT = 0, @errors INT = 0, @readings INT = 0;

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT [value] FROM OPENJSON(@payload_array);
    OPEN c;
    FETCH NEXT FROM c INTO @element;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @total = @total + 1;
        BEGIN TRY
            -- a packet longer than the 4000 characters of raw_payload is cut and so becomes a COMM_ERROR
            SET @one = LEFT(@element, 4000);
            EXEC [dbo].[sp_IngestTelemetryPacket] @one, 1, @pid OUTPUT, @status OUTPUT, @n OUTPUT;
            IF @status = 'MATCHED'          SET @matched = @matched + 1;
            ELSE IF @status = 'UNMATCHED'   SET @unmatched = @unmatched + 1;
            ELSE IF @status = 'QUARANTINED' SET @quarantined = @quarantined + 1;
            ELSE                            SET @comm_error = @comm_error + 1;
            SET @readings = @readings + ISNULL(@n, 0);
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            SET @errors = @errors + 1;
        END CATCH
        FETCH NEXT FROM c INTO @element;
    END
    CLOSE c;
    DEALLOCATE c;

    -- the packet procedure set the session to INGESTION; the summary row belongs to the officer
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_IngestTelemetryBatch';
    DECLARE @summary NVARCHAR(500) = N'packets ' + CAST(@total AS NVARCHAR(10)) + N', matched ' + CAST(@matched AS NVARCHAR(10))
        + N', unmatched ' + CAST(@unmatched AS NVARCHAR(10)) + N', quarantined ' + CAST(@quarantined AS NVARCHAR(10))
        + N', comm_error ' + CAST(@comm_error AS NVARCHAR(10)) + N', errors ' + CAST(@errors AS NVARCHAR(10))
        + N', readings ' + CAST(@readings AS NVARCHAR(10));
    EXEC [dbo].[sp__Log] 'INGEST_BATCH', 'TELEMETRY_PACKET', '0', NULL, NULL, @summary;

    SELECT @total AS packets, @matched AS matched, @unmatched AS unmatched, @quarantined AS quarantined,
           @comm_error AS comm_error, @errors AS errors, @readings AS readings_inserted;
END;
GO

-- [project.pdf §2.4 p.8: tamper alerts are recorded and lead to a field job; UC-14]
-- Device (no @actor_user_id, mechanism DEVICE) or DSO. TR20 creates the ANTI_TAMPER work order.
CREATE OR ALTER PROCEDURE [dbo].[sp_RaiseTamperEvent]
    @actor_user_id INT = NULL,
    @network_id    VARCHAR(60),
    @description   NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @actor_user_id IS NOT NULL
    BEGIN
        EXEC [dbo].[sp__AssertRole] @actor_user_id, N'DSO';
        EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_RaiseTamperEvent';
    END
    ELSE
        EXEC [dbo].[sp__SetActor] NULL, 'DEVICE';

    DECLARE @meter_id INT, @event_id BIGINT;
    SELECT @meter_id = meter_id FROM [dbo].[METER] WHERE network_id = @network_id;
    IF @meter_id IS NULL
        THROW 50001, 'Meter not found for this network id.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[EVENT] (event_timestamp, event_type, severity, description, meter_id)
        VALUES (SYSUTCDATETIME(), 'TAMPER_ALERT', 'CRITICAL', ISNULL(@description, N'Tamper alert from the meter'), @meter_id);
        SET @event_id = SCOPE_IDENTITY();
        COMMIT TRANSACTION;
        SELECT @event_id AS event_id,
               (SELECT MAX(work_order_id) FROM [dbo].[WORK_ORDER] WHERE event_id = @event_id) AS work_order_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §3.2 p.8-9: Validation, Estimation (Editing is manual); UC-16]  Algorithm B
-- Cursor over the meters with PENDING readings in [@from, @to]; per meter an app lock and one short
-- transaction: RANGE, NEGATIVE_DELTA, SPIKE, OVER_CAPACITY -> SUSPECT; gaps -> ESTIMATED; the rest -> VALID.
CREATE OR ALTER PROCEDURE [dbo].[sp_RunVEE]
    @actor_user_id INT,
    @from          DATETIME2(0),
    @to            DATETIME2(0),
    @meter_id      INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'VEE_JOB';

    IF @from IS NULL OR @to IS NULL OR @to < @from
        THROW 50004, 'Invalid input: the window must have from <= to.', 1;

    DECLARE @m INT, @rc INT, @resource NVARCHAR(100), @comment NVARCHAR(500);
    DECLARE @suspect INT, @estimated INT, @valid INT;
    DECLARE @meters INT = 0, @failed INT = 0, @t_valid INT = 0, @t_suspect INT = 0, @t_estimated INT = 0;

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT r.meter_id
        FROM [dbo].[METER_READING] AS r
        WHERE r.status = 'PENDING' AND r.is_final = 0
          AND r.reading_timestamp BETWEEN @from AND @to
          AND (@meter_id IS NULL OR r.meter_id = @meter_id);
    OPEN c;
    FETCH NEXT FROM c INTO @m;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SELECT @suspect = 0, @estimated = 0, @valid = 0;
            SET @resource = N'VEE_' + CAST(@m AS NVARCHAR(12));

            BEGIN TRANSACTION;
            EXEC @rc = sys.sp_getapplock @Resource = @resource, @LockMode = 'Exclusive',
                                         @LockOwner = 'Transaction', @LockTimeout = 10000;
            IF @rc < 0
                THROW 50007, 'Busy: VEE is already running for this meter.', 1;

            -- 1. Range: outside the valid_min / valid_max of the OBIS code
            UPDATE r
               SET status = 'SUSPECT', vee_rule = 'RANGE',
                   vee_note = N'Value outside the allowed range of the code'
            FROM [dbo].[METER_READING] AS r
            JOIN [dbo].[OBIS_CODE] AS o ON o.obis_code = r.obis_code
            WHERE r.meter_id = @m AND r.status = 'PENDING' AND r.reading_timestamp BETWEEN @from AND @to
              AND (r.[value] < o.valid_min OR r.[value] > o.valid_max);
            SET @suspect = @suspect + @@ROWCOUNT;

            -- 2. Negative delta: a cumulative register went down
            UPDATE r
               SET status = 'SUSPECT', vee_rule = 'NEGATIVE_DELTA',
                   vee_note = N'Cumulative register is lower than in the previous slot'
            FROM [dbo].[METER_READING] AS r
            JOIN [dbo].[OBIS_CODE] AS o ON o.obis_code = r.obis_code AND o.measurement_kind = 'CUMULATIVE'
            WHERE r.meter_id = @m AND r.status = 'PENDING' AND r.reading_timestamp BETWEEN @from AND @to
              AND r.delta_value < 0;
            SET @suspect = @suspect + @@ROWCOUNT;

            -- 3. Spike: more than 5 x the average of the previous 4 non-suspect deltas, and more than 1 kWh
            --    (the example of the spec: 1.8, 2.0, 1.9, 25.4 -> 25.4 is flagged)
            UPDATE r
               SET status = 'SUSPECT', vee_rule = 'SPIKE',
                   vee_note = N'Energy ' + CAST(r.delta_value AS NVARCHAR(30)) + N' against a recent average of '
                              + CAST(CAST(h.avg_delta AS DECIMAL(18,4)) AS NVARCHAR(30))
            FROM [dbo].[METER_READING] AS r
            JOIN [dbo].[OBIS_CODE] AS o ON o.obis_code = r.obis_code AND o.measurement_kind = 'CUMULATIVE'
            CROSS APPLY (SELECT AVG(x.delta_value) AS avg_delta, COUNT(*) AS n
                         FROM (SELECT TOP (4) p.delta_value
                               FROM [dbo].[METER_READING] AS p
                               WHERE p.meter_id = r.meter_id AND p.obis_code = r.obis_code
                                 AND p.reading_timestamp < r.reading_timestamp
                                 AND p.status <> 'SUSPECT' AND p.delta_value IS NOT NULL
                               ORDER BY p.reading_timestamp DESC) AS x) AS h
            WHERE r.meter_id = @m AND r.status = 'PENDING' AND r.reading_timestamp BETWEEN @from AND @to
              AND r.delta_value > 1
              AND h.n >= 3
              AND r.delta_value > 5 * h.avg_delta;
            SET @suspect = @suspect + @@ROWCOUNT;

            -- 4. Over capacity: more energy in 15 minutes than the meter type can carry
            UPDATE r
               SET status = 'SUSPECT', vee_rule = 'OVER_CAPACITY',
                   vee_note = N'More than the meter type allows in 15 minutes'
            FROM [dbo].[METER_READING] AS r
            JOIN [dbo].[METER] AS me ON me.meter_id = r.meter_id
            JOIN [dbo].[METER_TYPE] AS mt ON mt.meter_type_id = me.meter_type_id
            WHERE r.meter_id = @m AND r.status = 'PENDING' AND r.reading_timestamp BETWEEN @from AND @to
              AND r.obis_code = '1.8.0'
              AND r.delta_value > mt.max_amps * 230 * mt.connection_phases * 0.25 / 1000;
            SET @suspect = @suspect + @@ROWCOUNT;

            -- 5. Gaps: linear interpolation (cursor over the missing slots)
            EXEC [dbo].[sp__EstimateGaps] @m, @from, @to, @estimated OUTPUT;

            -- 6. Everything else passed validation
            UPDATE [dbo].[METER_READING]
               SET status = 'VALID', vee_rule = 'AUTO'
             WHERE meter_id = @m AND status = 'PENDING' AND reading_timestamp BETWEEN @from AND @to;
            SET @valid = @@ROWCOUNT;

            -- 7. One summary row per meter
            SET @comment = N'valid ' + CAST(@valid AS NVARCHAR(10)) + N', suspect ' + CAST(@suspect AS NVARCHAR(10))
                         + N', estimated ' + CAST(@estimated AS NVARCHAR(10)) + N'; window '
                         + CONVERT(NVARCHAR(19), @from, 120) + N' - ' + CONVERT(NVARCHAR(19), @to, 120);
            EXEC [dbo].[sp__Log] 'VEE_RUN', 'METER', @m, NULL, NULL, @comment;
            COMMIT TRANSACTION;

            SELECT @meters = @meters + 1, @t_valid = @t_valid + @valid,
                   @t_suspect = @t_suspect + @suspect, @t_estimated = @t_estimated + @estimated;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            SET @failed = @failed + 1;
            SET @comment = LEFT(ERROR_MESSAGE(), 500);
            EXEC [dbo].[sp__Log] 'VEE_RUN_FAILED', 'METER', @m, NULL, NULL, @comment;
        END CATCH
        FETCH NEXT FROM c INTO @m;
    END
    CLOSE c;
    DEALLOCATE c;

    SELECT @meters AS meters_processed, @failed AS meters_failed, @t_valid AS readings_valid,
           @t_suspect AS readings_suspect, @t_estimated AS readings_estimated;
END;
GO

-- [project.pdf §3.2 p.8-9: suspect values are shown to the officer for a decision]
-- With the value before and the value after, for context.
CREATE OR ALTER PROCEDURE [dbo].[sp_ListSuspectReadings]
    @actor_user_id INT,
    @from          DATETIME2(0) = NULL,
    @to            DATETIME2(0) = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO';
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 500 SET @page_size = 50;

    SELECT r.reading_id, r.meter_id, m.serial_number, r.obis_code, r.reading_timestamp, r.[value], r.delta_value,
           r.vee_rule, r.vee_note, pv.[value] AS previous_value, nx.[value] AS next_value
    FROM [dbo].[METER_READING] AS r
    JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
    OUTER APPLY (SELECT TOP (1) p.[value] FROM [dbo].[METER_READING] AS p
                 WHERE p.meter_id = r.meter_id AND p.obis_code = r.obis_code AND p.reading_timestamp < r.reading_timestamp
                 ORDER BY p.reading_timestamp DESC) AS pv
    OUTER APPLY (SELECT TOP (1) n.[value] FROM [dbo].[METER_READING] AS n
                 WHERE n.meter_id = r.meter_id AND n.obis_code = r.obis_code AND n.reading_timestamp > r.reading_timestamp
                 ORDER BY n.reading_timestamp) AS nx
    WHERE r.status = 'SUSPECT' AND r.is_final = 0
      AND (@from IS NULL OR r.reading_timestamp >= @from)
      AND (@to   IS NULL OR r.reading_timestamp <= @to)
    ORDER BY r.reading_timestamp, r.meter_id, r.obis_code
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END;
GO

-- [project.pdf §3.2 p.9: the officer accepts a suspect value as it is] SUSPECT -> VALID (TR18 logs it)
CREATE OR ALTER PROCEDURE [dbo].[sp_AcceptSuspectReading]
    @actor_user_id INT,
    @reading_id    BIGINT,
    @note          NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_AcceptSuspectReading';

    IF NOT EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE reading_id = @reading_id)
        THROW 50001, 'Reading not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[METER_READING]
           SET status = 'VALID', vee_note = ISNULL(@note, vee_note), edited_by_user_id = @actor_user_id
         WHERE reading_id = @reading_id AND status = 'SUSPECT' AND is_final = 0;
        IF @@ROWCOUNT = 0
            THROW 50003, 'The reading is not SUSPECT, or it is already final.', 1;
        COMMIT TRANSACTION;
        SELECT @reading_id AS reading_id, 'VALID' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §3.2 p.9: Editing keeps the original value, the corrected value and who changed it; UC-16]
-- SUSPECT | ESTIMATED | EDITED -> EDITED, not final. The energy of this slot and of the next one is recomputed.
CREATE OR ALTER PROCEDURE [dbo].[sp_EditReading]
    @actor_user_id INT,
    @reading_id    BIGINT,
    @new_value     DECIMAL(18,4),
    @note          NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_EditReading';

    DECLARE @meter_id INT, @obis VARCHAR(20), @slot DATETIME2(0), @kind VARCHAR(15);
    SELECT @meter_id = r.meter_id, @obis = r.obis_code, @slot = r.reading_timestamp, @kind = o.measurement_kind
    FROM [dbo].[METER_READING] AS r
    JOIN [dbo].[OBIS_CODE] AS o ON o.obis_code = r.obis_code
    WHERE r.reading_id = @reading_id;

    IF @meter_id IS NULL
        THROW 50001, 'Reading not found.', 1;
    IF @new_value IS NULL
        THROW 50004, 'Invalid input: the new value is required.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE r
           SET original_value    = ISNULL(r.original_value, r.[value]),
               [value]           = @new_value,
               status            = 'EDITED',
               vee_rule          = 'MANUAL_EDIT',
               vee_note          = ISNULL(@note, r.vee_note),
               edited_by_user_id = @actor_user_id,
               delta_value       = CASE WHEN @kind = 'CUMULATIVE'
                                        THEN @new_value - (SELECT p.[value] FROM [dbo].[METER_READING] AS p
                                                           WHERE p.meter_id = @meter_id AND p.obis_code = @obis
                                                             AND p.reading_timestamp = DATEADD(MINUTE, -15, @slot))
                                        ELSE r.delta_value END
        FROM [dbo].[METER_READING] AS r
        WHERE r.reading_id = @reading_id
          AND r.status IN ('SUSPECT', 'ESTIMATED', 'EDITED')
          AND r.is_final = 0;
        IF @@ROWCOUNT = 0
            THROW 50003, 'Only a SUSPECT, ESTIMATED or EDITED reading that is not final can be edited.', 1;

        IF @kind = 'CUMULATIVE'
            UPDATE [dbo].[METER_READING]
               SET delta_value = [value] - @new_value
             WHERE meter_id = @meter_id AND obis_code = @obis
               AND reading_timestamp = DATEADD(MINUTE, 15, @slot)
               AND is_final = 0;
        COMMIT TRANSACTION;
        SELECT @reading_id AS reading_id, 'EDITED' AS status, @new_value AS [value];
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §3.2 p.9: after VEE the readings are immutable and the aggregates are produced; UC-16]  Algorithm C
-- A meter-day is finalized when it has no PENDING / SUSPECT reading and 96 slots of 1.8.0.
-- One transaction per meter-day: is_final = 1, then the final DAY aggregates (TR21 checks thresholds),
-- then MONTH (and YEAR) when the month is complete for that meter.
-- [AR: "complete" = every full day the meter was in service in that month. The day of installation and
--      the day of removal cannot have 96 slots, so they are not required; without this a meter that was
--      installed or replaced in the middle of a month would never get a MONTH aggregate and never a bill.]
CREATE OR ALTER PROCEDURE [dbo].[sp_FinalizeReadings]
    @actor_user_id INT,
    @day           DATE,
    @meter_id      INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_FinalizeReadings';

    IF @day IS NULL OR @day >= CAST(SYSUTCDATETIME() AS DATE)
        THROW 50004, 'Invalid input: only a day that has ended can be finalized.', 1;

    DECLARE @d0 DATETIME2(0) = CAST(@day AS DATETIME2(0));
    DECLARE @d1 DATETIME2(0) = DATEADD(DAY, 1, @d0);
    DECLARE @month_start DATE = DATEFROMPARTS(YEAR(@day), MONTH(@day), 1);
    DECLARE @month_end   DATE = EOMONTH(@day);
    DECLARE @ms DATETIME2(0) = CAST(@month_start AS DATETIME2(0));
    DECLARE @year_start DATETIME2(0) = CAST(DATEFROMPARTS(YEAR(@day), 1, 1) AS DATETIME2(0));
    DECLARE @now DATETIME2(0);
    DECLARE @m INT, @first DATE, @last DATE, @reason NVARCHAR(200);

    CREATE TABLE #result (meter_id INT NOT NULL, outcome VARCHAR(10) NOT NULL, reason NVARCHAR(500) NULL);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT r.meter_id
        FROM [dbo].[METER_READING] AS r
        WHERE r.reading_timestamp >= @d0 AND r.reading_timestamp < @d1 AND r.is_final = 0
          AND (@meter_id IS NULL OR r.meter_id = @meter_id);
    OPEN c;
    FETCH NEXT FROM c INTO @m;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SET @reason = NULL;
            IF EXISTS (SELECT 1 FROM [dbo].[METER_READING]
                       WHERE meter_id = @m AND reading_timestamp >= @d0 AND reading_timestamp < @d1
                         AND status IN ('PENDING', 'SUSPECT'))
                SET @reason = N'PENDING or SUSPECT readings: run VEE and decide the suspect ones first';
            ELSE IF (SELECT COUNT(*) FROM [dbo].[METER_READING]
                     WHERE meter_id = @m AND obis_code = '1.8.0'
                       AND reading_timestamp >= @d0 AND reading_timestamp < @d1) < 96
                SET @reason = N'fewer than 96 slots of 1.8.0 for the day';

            IF @reason IS NOT NULL
                INSERT INTO #result (meter_id, outcome, reason) VALUES (@m, 'SKIPPED', @reason);
            ELSE
            BEGIN
                SET @now = SYSUTCDATETIME();
                BEGIN TRANSACTION;

                UPDATE [dbo].[METER_READING]
                   SET is_final = 1, finalized_at = @now
                 WHERE meter_id = @m AND reading_timestamp >= @d0 AND reading_timestamp < @d1
                   AND is_final = 0 AND status IN ('VALID', 'ESTIMATED', 'EDITED');

                -- final DAY aggregate per cumulative code: energy of the day = sum of the 15-min energies
                INSERT INTO [dbo].[AGGREGATE] (period_type, period_start, [value], sample_count, is_final, calculated_at, meter_id, obis_code)
                SELECT 'DAY', @d0, SUM(ISNULL(r.delta_value, 0)), COUNT(*), 1, @now, @m, r.obis_code
                FROM [dbo].[METER_READING] AS r
                JOIN [dbo].[OBIS_CODE] AS o ON o.obis_code = r.obis_code AND o.measurement_kind = 'CUMULATIVE'
                WHERE r.meter_id = @m AND r.reading_timestamp >= @d0 AND r.reading_timestamp < @d1 AND r.is_final = 1
                  AND NOT EXISTS (SELECT 1 FROM [dbo].[AGGREGATE] AS a
                                  WHERE a.meter_id = @m AND a.obis_code = r.obis_code
                                    AND a.period_type = 'DAY' AND a.period_start = @d0)
                GROUP BY r.obis_code;

                -- MONTH: every full day in service of the month is final
                -- first required day = the day after activation, or the first finalized day of the meter if that
                -- is earlier (data loaded for days before the activation, as in import.sql); never before the month
                SELECT @first = DATEADD(DAY, 1, CAST(COALESCE(activated_at, installed_at) AS DATE)),
                       @last  = CASE WHEN removed_at IS NOT NULL AND DATEADD(DAY, -1, CAST(removed_at AS DATE)) < @month_end
                                     THEN DATEADD(DAY, -1, CAST(removed_at AS DATE)) ELSE @month_end END
                FROM [dbo].[METER] WHERE meter_id = @m;

                SELECT @first = CASE WHEN CAST(MIN(period_start) AS DATE) < @first THEN CAST(MIN(period_start) AS DATE) ELSE @first END
                FROM [dbo].[AGGREGATE]
                WHERE meter_id = @m AND obis_code = '1.8.0' AND period_type = 'DAY' AND is_final = 1;
                IF @first < @month_start SET @first = @month_start;

                IF @first <= @last AND @last <= @day
                   AND (SELECT COUNT(*) FROM [dbo].[AGGREGATE]
                        WHERE meter_id = @m AND obis_code = '1.8.0' AND period_type = 'DAY' AND is_final = 1
                          AND period_start >= CAST(@first AS DATETIME2(0)) AND period_start <= CAST(@last AS DATETIME2(0)))
                       = DATEDIFF(DAY, @first, @last) + 1
                BEGIN
                    INSERT INTO [dbo].[AGGREGATE] (period_type, period_start, [value], sample_count, is_final, calculated_at, meter_id, obis_code)
                    SELECT 'MONTH', @ms, SUM(a.[value]), COUNT(*), 1, @now, @m, a.obis_code
                    FROM [dbo].[AGGREGATE] AS a
                    WHERE a.meter_id = @m AND a.period_type = 'DAY' AND a.is_final = 1
                      AND a.period_start >= @ms AND a.period_start < DATEADD(MONTH, 1, @ms)
                      AND NOT EXISTS (SELECT 1 FROM [dbo].[AGGREGATE] AS x
                                      WHERE x.meter_id = @m AND x.obis_code = a.obis_code
                                        AND x.period_type = 'MONTH' AND x.period_start = @ms)
                    GROUP BY a.obis_code;

                    -- YEAR: when December is complete
                    IF MONTH(@day) = 12
                        INSERT INTO [dbo].[AGGREGATE] (period_type, period_start, [value], sample_count, is_final, calculated_at, meter_id, obis_code)
                        SELECT 'YEAR', @year_start, SUM(a.[value]), COUNT(*), 1, @now, @m, a.obis_code
                        FROM [dbo].[AGGREGATE] AS a
                        WHERE a.meter_id = @m AND a.period_type = 'MONTH' AND a.is_final = 1
                          AND a.period_start >= @year_start AND a.period_start < DATEADD(YEAR, 1, @year_start)
                          AND NOT EXISTS (SELECT 1 FROM [dbo].[AGGREGATE] AS x
                                          WHERE x.meter_id = @m AND x.obis_code = a.obis_code
                                            AND x.period_type = 'YEAR' AND x.period_start = @year_start)
                        GROUP BY a.obis_code;
                END

                EXEC [dbo].[sp__Log] 'FINALIZE', 'METER', @m, NULL, NULL, @day;
                COMMIT TRANSACTION;
                INSERT INTO #result (meter_id, outcome, reason) VALUES (@m, 'FINALIZED', NULL);
            END
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            INSERT INTO #result (meter_id, outcome, reason) VALUES (@m, 'ERROR', LEFT(ERROR_MESSAGE(), 500));
        END CATCH
        FETCH NEXT FROM c INTO @m;
    END
    CLOSE c;
    DEALLOCATE c;

    SELECT @day AS [day], meter_id, outcome, reason FROM #result ORDER BY outcome, meter_id;
END;
GO

-- [project.pdf §4.2 p.10: historical aggregates per transformer, immutable; UC-17]  Algorithm D
-- Computed in #temp tables first, then written in one short transaction (lecture 20-67).
CREATE OR ALTER PROCEDURE [dbo].[sp_BuildTransformerAggregates]
    @actor_user_id INT,
    @day           DATE,
    @force         BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO,TSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_BuildTransformerAggregates';

    IF @day IS NULL OR @day >= CAST(SYSUTCDATETIME() AS DATE)
        THROW 50004, 'Invalid input: only a day that has ended can be aggregated.', 1;

    DECLARE @d0 DATETIME2(0) = CAST(@day AS DATETIME2(0));
    DECLARE @d1 DATETIME2(0) = DATEADD(DAY, 1, @d0);
    DECLARE @ms DATETIME2(0) = CAST(DATEFROMPARTS(YEAR(@day), MONTH(@day), 1) AS DATETIME2(0));
    DECLARE @year_start DATETIME2(0) = CAST(DATEFROMPARTS(YEAR(@day), 1, 1) AS DATETIME2(0));
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @quarter_rows INT = 0, @day_rows INT = 0, @month_rows INT = 0, @year_rows INT = 0;

    -- 1. every active meter must be finalized for the day (unless forced)
    IF ISNULL(@force, 0) = 0 AND EXISTS (
        SELECT 1 FROM [dbo].[METER_READING] AS r
        JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
        WHERE m.status = 'ACTIVE' AND r.is_final = 0
          AND r.reading_timestamp >= @d0 AND r.reading_timestamp < @d1)
        THROW 50003, 'Some active meters still have readings that are not final for this day; finalize them or use @force = 1.', 1;

    -- 2. level-1 sums from the final readings: per slot, and for the whole day
    SELECT m.transformer_id, r.obis_code, r.reading_timestamp AS slot,
           SUM(ISNULL(r.delta_value, 0)) AS sum_value, COUNT(DISTINCT r.meter_id) AS meters
    INTO #L1Slot
    FROM [dbo].[METER_READING] AS r
    JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
    WHERE r.obis_code IN ('1.8.0', '2.8.0') AND r.is_final = 1
      AND r.reading_timestamp >= @d0 AND r.reading_timestamp < @d1
    GROUP BY m.transformer_id, r.obis_code, r.reading_timestamp;

    SELECT m.transformer_id, r.obis_code,
           SUM(ISNULL(r.delta_value, 0)) AS sum_value, COUNT(DISTINCT r.meter_id) AS meters
    INTO #L1Day
    FROM [dbo].[METER_READING] AS r
    JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
    WHERE r.obis_code IN ('1.8.0', '2.8.0') AND r.is_final = 1
      AND r.reading_timestamp >= @d0 AND r.reading_timestamp < @d1
    GROUP BY m.transformer_id, r.obis_code;

    -- 3. roll up to every ancestor (the function returns the node itself and all its ancestors)
    SELECT t.transformer_id AS l1_id, a.transformer_id AS node_id
    INTO #Up
    FROM [dbo].[TRANSFORMER] AS t
    CROSS APPLY [dbo].[fn_TransformerAncestors](t.transformer_id) AS a
    WHERE t.[level] = 1;

    SELECT u.node_id, s.obis_code, s.slot, SUM(s.sum_value) AS sum_value, SUM(s.meters) AS meters
    INTO #Quarter
    FROM #L1Slot AS s JOIN #Up AS u ON u.l1_id = s.transformer_id
    GROUP BY u.node_id, s.obis_code, s.slot;

    SELECT u.node_id, d.obis_code, SUM(d.sum_value) AS sum_value, SUM(d.meters) AS meters
    INTO #Day
    FROM #L1Day AS d JOIN #Up AS u ON u.l1_id = d.transformer_id
    GROUP BY u.node_id, d.obis_code;

    -- 4. one short transaction: the aggregates are final and immutable from now on (TR02)
    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO [dbo].[AGGREGATE] (period_type, period_start, [value], sample_count, is_final, calculated_at, transformer_id, obis_code)
        SELECT 'QUARTER_HOUR', q.slot, q.sum_value, q.meters, 1, @now, q.node_id, q.obis_code
        FROM #Quarter AS q
        WHERE NOT EXISTS (SELECT 1 FROM [dbo].[AGGREGATE] AS a
                          WHERE a.transformer_id = q.node_id AND a.obis_code = q.obis_code
                            AND a.period_type = 'QUARTER_HOUR' AND a.period_start = q.slot);
        SET @quarter_rows = @@ROWCOUNT;

        INSERT INTO [dbo].[AGGREGATE] (period_type, period_start, [value], sample_count, is_final, calculated_at, transformer_id, obis_code)
        SELECT 'DAY', @d0, d.sum_value, d.meters, 1, @now, d.node_id, d.obis_code
        FROM #Day AS d
        WHERE NOT EXISTS (SELECT 1 FROM [dbo].[AGGREGATE] AS a
                          WHERE a.transformer_id = d.node_id AND a.obis_code = d.obis_code
                            AND a.period_type = 'DAY' AND a.period_start = @d0);
        SET @day_rows = @@ROWCOUNT;

        -- MONTH on the last day of the month, when every day of the month has its DAY row
        IF @day = EOMONTH(@day)
        BEGIN
            INSERT INTO [dbo].[AGGREGATE] (period_type, period_start, [value], sample_count, is_final, calculated_at, transformer_id, obis_code)
            SELECT 'MONTH', @ms, SUM(a.[value]), MAX(a.sample_count), 1, @now, a.transformer_id, a.obis_code
            FROM [dbo].[AGGREGATE] AS a
            WHERE a.transformer_id IS NOT NULL AND a.period_type = 'DAY' AND a.is_final = 1
              AND a.period_start >= @ms AND a.period_start < DATEADD(MONTH, 1, @ms)
              AND NOT EXISTS (SELECT 1 FROM [dbo].[AGGREGATE] AS x
                              WHERE x.transformer_id = a.transformer_id AND x.obis_code = a.obis_code
                                AND x.period_type = 'MONTH' AND x.period_start = @ms)
            GROUP BY a.transformer_id, a.obis_code
            HAVING COUNT(*) = DAY(EOMONTH(@day));
            SET @month_rows = @@ROWCOUNT;

            -- YEAR on 31 December, when the 12 MONTH rows exist
            IF MONTH(@day) = 12
            BEGIN
                INSERT INTO [dbo].[AGGREGATE] (period_type, period_start, [value], sample_count, is_final, calculated_at, transformer_id, obis_code)
                SELECT 'YEAR', @year_start, SUM(a.[value]), MAX(a.sample_count), 1, @now, a.transformer_id, a.obis_code
                FROM [dbo].[AGGREGATE] AS a
                WHERE a.transformer_id IS NOT NULL AND a.period_type = 'MONTH' AND a.is_final = 1
                  AND a.period_start >= @year_start AND a.period_start < DATEADD(YEAR, 1, @year_start)
                  AND NOT EXISTS (SELECT 1 FROM [dbo].[AGGREGATE] AS x
                                  WHERE x.transformer_id = a.transformer_id AND x.obis_code = a.obis_code
                                    AND x.period_type = 'YEAR' AND x.period_start = @year_start)
                GROUP BY a.transformer_id, a.obis_code
                HAVING COUNT(*) = 12;
                SET @year_rows = @@ROWCOUNT;
            END
        END

        EXEC [dbo].[sp__Log] 'TRANSFORMER_AGGREGATES', 'AGGREGATE', '0', NULL, NULL, @day;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @day AS [day], @quarter_rows AS quarter_hour_rows, @day_rows AS day_rows,
           @month_rows AS month_rows, @year_rows AS year_rows;
END;
GO

-- [project.pdf §1.4 p.6-7: detailed readings are kept 3 years, or 1 month after a GDPR request;
--  aggregates stay; transformer measurements are kept for ever; UC-08]
-- Cursor over the meters (each has its own retention). Then the matched packets that nothing points to any more.
-- [AR: the app lock has session scope, because each meter is purged in its own short transaction]
CREATE OR ALTER PROCEDURE [dbo].[sp_PurgeExpiredReadings]
    @actor_user_id INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'PURGE_JOB';

    DECLARE @rc INT;
    EXEC @rc = sys.sp_getapplock @Resource = N'PURGE', @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 10000;
    IF @rc < 0
        THROW 50007, 'Busy: the purge job is already running.', 1;

    DECLARE @m INT, @keep TINYINT, @n INT, @readings INT = 0, @packets INT = 0, @errors INT = 0;
    DECLARE @comment NVARCHAR(500);

    BEGIN TRY
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT meter_id, retention_months FROM [dbo].[METER] ORDER BY retention_months, meter_id;
        OPEN c;
        FETCH NEXT FROM c INTO @m, @keep;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                BEGIN TRANSACTION;
                EXEC [dbo].[sp__PurgeMeter] @m, @keep, @n OUTPUT;
                IF @n > 0
                BEGIN
                    SET @comment = N'readings deleted ' + CAST(@n AS NVARCHAR(12)) + N'; kept months ' + CAST(@keep AS NVARCHAR(3));
                    EXEC [dbo].[sp__Log] 'PURGE', 'METER', @m, NULL, NULL, @comment;
                END
                COMMIT TRANSACTION;
                SET @readings = @readings + @n;
            END TRY
            BEGIN CATCH
                IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                SET @errors = @errors + 1;
            END CATCH
            FETCH NEXT FROM c INTO @m, @keep;
        END
        CLOSE c;
        DEALLOCATE c;

        -- matched packets older than the retention of their meter that no reading or event uses any more
        SET @n = 1;
        WHILE @n > 0
        BEGIN
            DELETE TOP (5000) p
            FROM [dbo].[TELEMETRY_PACKET] AS p
            JOIN [dbo].[METER] AS m ON m.meter_id = p.meter_id
            WHERE p.match_status = 'MATCHED'
              AND p.transmission_timestamp < DATEADD(MONTH, -m.retention_months, SYSUTCDATETIME())
              AND NOT EXISTS (SELECT 1 FROM [dbo].[METER_READING] AS r WHERE r.packet_id = p.packet_id)
              AND NOT EXISTS (SELECT 1 FROM [dbo].[EVENT] AS e WHERE e.packet_id = p.packet_id);
            SET @n = @@ROWCOUNT;
            SET @packets = @packets + @n;
        END

        SET @comment = N'readings ' + CAST(@readings AS NVARCHAR(12)) + N', packets ' + CAST(@packets AS NVARCHAR(12))
                     + N', meters with errors ' + CAST(@errors AS NVARCHAR(12));
        EXEC [dbo].[sp__Log] 'PURGE_RUN', 'METER_READING', '0', NULL, NULL, @comment;
        EXEC sys.sp_releaseapplock @Resource = N'PURGE', @LockOwner = 'Session';
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'c') >= 0 CLOSE c;
        IF CURSOR_STATUS('local', 'c') >= -1 DEALLOCATE c;
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_releaseapplock @Resource = N'PURGE', @LockOwner = 'Session';
        THROW;
    END CATCH

    SELECT @readings AS readings_deleted, @packets AS packets_deleted, @errors AS meters_with_errors;
END;
GO

PRINT 'procedures_06_telemetry.sql: 10 procedures created.';
GO
