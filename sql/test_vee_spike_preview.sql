-- Run after the io database build, seed_grid.sql and seed_telemetry_demo.sql.
-- In a new query session, preview the Algorithm B spike predicate for a
-- synthetic series, then compare the prediction with sp_RunVEE.
-- The transaction rolls back fixture readings, packets, events and audit rows.
SET NOCOUNT ON;

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR ('Run the spike test without an open transaction.', 16, 1);
    RETURN;
END;
SET XACT_ABORT ON;

DECLARE @meter INT, @officer INT, @inserted INT;
DECLARE @first DATETIME2(0) = '2026-11-06T12:00:00';
DECLARE @last DATETIME2(0) = DATEADD(MINUTE, 75, @first);
DECLARE @index INT = 0, @slot DATETIME2(0), @payload NVARCHAR(4000);
DECLARE @value DECIMAL(18,4);

SELECT @meter = meter_id FROM dbo.METER WHERE network_id = 'DEMO-NET-001' AND status = 'ACTIVE';
SELECT @officer = user_id FROM dbo.USER_ACCOUNT WHERE email = 'officer1@mdms.cy';
IF @meter IS NULL OR @officer IS NULL
    THROW 54041, 'Run the io database build and telemetry seeds first.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    IF EXISTS (
        SELECT 1 FROM dbo.METER_READING
        WHERE meter_id = @meter AND reading_timestamp BETWEEN @first AND @last
    )
        THROW 54042, 'The spike fixture window already contains readings.', 1;

    WHILE @index <= 5
    BEGIN
        SET @slot = DATEADD(MINUTE, 15 * @index, @first);
        SET @value = 1002 + 0.5 * @index + CASE WHEN @index = 5 THEN 4.5 ELSE 0 END;
        SET @payload = CONCAT(
            N'{"Meter_Network_ID":"DEMO-NET-001","Transmission_Timestamp":"',
            CONVERT(VARCHAR(19), @slot, 126),
            N'Z","Telemetry_Payload":[{"obis":"1.8.0","value":', @value, N',"unit":"kWh"}]}'
        );
        EXEC dbo.sp_IngestTelemetryPacket
            @payload = @payload, @silent = 1, @readings_inserted = @inserted OUTPUT;
        IF @inserted <> 1
            THROW 54043, 'A spike fixture packet did not ingest exactly one reading.', 1;
        SET @index += 1;
    END;

    DECLARE @delta DECIMAL(18,4), @average DECIMAL(38,6), @sample_count INT;

    SELECT @delta = delta_value
    FROM dbo.METER_READING
    WHERE meter_id = @meter AND obis_code = '1.8.0' AND reading_timestamp = @last AND status = 'PENDING';

    SELECT @average = AVG(delta_value), @sample_count = COUNT(*)
    FROM (
        SELECT TOP (4) delta_value
        FROM dbo.METER_READING
        WHERE meter_id = @meter AND obis_code = '1.8.0' AND reading_timestamp < @last
          AND status <> 'SUSPECT' AND delta_value IS NOT NULL
        ORDER BY reading_timestamp DESC
    ) AS history;

    DECLARE @possible_spike BIT =
        CASE WHEN @delta > 1 AND @sample_count >= 3 AND @delta > 5 * @average THEN 1 ELSE 0 END;

    SELECT @last AS reading_timestamp, @delta AS delta_value, @sample_count AS previous_intervals,
           @average AS average_delta, @possible_spike AS possible_spike;

    IF @possible_spike = 0 OR @sample_count <> 4 OR @average <> 0.5 OR @delta <> 5
        THROW 54044, 'The spike fixture did not produce the expected preview.', 1;

    EXEC dbo.sp_RunVEE @officer, @first, @last, @meter;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.METER_READING
        WHERE meter_id = @meter AND obis_code = '1.8.0' AND reading_timestamp = @last
          AND status = 'SUSPECT' AND vee_rule = 'SPIKE' AND [value] = 1009 AND delta_value = 5 AND is_final = 0
    )
        THROW 54045, 'VEE did not flag the predicted spike.', 1;

    ROLLBACK TRANSACTION;
    PRINT 'PASS: the spike preview agrees with sp_RunVEE.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
