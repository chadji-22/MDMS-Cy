-- Run after the io database build, seed_grid.sql and seed_telemetry_demo.sql.
-- In a new query session, ingest 450 V, flag it, then correct it to 230 V.
-- The transaction rolls back fixture readings, packets, events and audit rows.
SET NOCOUNT ON;

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR ('Run the edit test without an open transaction.', 16, 1);
    RETURN;
END;
SET XACT_ABORT ON;

DECLARE @meter INT, @officer INT, @reading BIGINT;
DECLARE @slot DATETIME2(0) = '2026-11-06T10:30:00';
DECLARE @packet BIGINT, @inserted INT;
DECLARE @note NVARCHAR(300) = N'Demo correction to a synthetic reference value of 230 V.';

SELECT @meter = meter_id FROM dbo.METER WHERE network_id = 'DEMO-NET-001' AND status = 'ACTIVE';
SELECT @officer = user_id FROM dbo.USER_ACCOUNT WHERE email = 'officer1@mdms.cy';
IF @meter IS NULL OR @officer IS NULL
    THROW 54062, 'Run the io database build and telemetry seeds first.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    IF EXISTS (SELECT 1 FROM dbo.METER_READING WHERE meter_id = @meter AND reading_timestamp = @slot)
        THROW 54063, 'The edit fixture slot already contains readings.', 1;

    EXEC dbo.sp_IngestTelemetryPacket
        @payload = N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"2026-11-06T10:30:00Z","Telemetry_Payload":[{"obis":"32.7.0","value":450,"unit":"V"}]}',
        @silent = 1, @packet_id = @packet OUTPUT, @readings_inserted = @inserted OUTPUT;

    IF @inserted <> 1
        THROW 54064, 'The edit fixture did not ingest exactly one reading.', 1;

    EXEC dbo.sp_RunVEE @officer, @slot, @slot, @meter;

    SELECT @reading = reading_id
    FROM dbo.METER_READING
    WHERE packet_id = @packet AND [value] = 450 AND status = 'SUSPECT' AND vee_rule = 'RANGE';

    IF @reading IS NULL
        THROW 54065, 'VEE did not flag the fixture as a range violation.', 1;

    EXEC dbo.sp_EditReading @officer, @reading, 230, @note;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.METER_READING
        WHERE reading_id = @reading AND [value] = 230 AND original_value = 450
          AND status = 'EDITED' AND is_final = 0 AND edited_by_user_id = @officer
          AND vee_rule = 'MANUAL_EDIT' AND vee_note = @note AND delta_value IS NULL
    )
        THROW 54066, 'The edit did not preserve the expected value, status and actor.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.AUDIT_LOG
        WHERE object_type = 'METER_READING' AND object_id = CAST(@reading AS VARCHAR(30))
          AND action = 'VEE_EDIT' AND user_id = @officer AND mechanism = 'sp_EditReading'
          AND old_state = N'SUSPECT 450.0000' AND new_state = N'EDITED 230.0000'
    )
        THROW 54067, 'The expected manual edit audit row was not written.', 1;

    ROLLBACK TRANSACTION;
    PRINT 'PASS: manual edit, original reading and audit entry verified.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
