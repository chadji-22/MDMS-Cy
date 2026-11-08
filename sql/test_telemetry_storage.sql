USE [egeorg28];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- 1. Demo δεδομένα από τον μετρητή
DECLARE @payload NVARCHAR(MAX) = N'{
    "Meter_Network_ID": "DEMO-NET-001",
    "Transmission_Timestamp": "2026-11-06T10:00:00Z",
    "Cell_Signal_Strength_dBm": -92,
    "Network_Type": "NB_IOT",
    "Telemetry_Payload": [
        {
            "obis": "1.8.0",
            "value": 1000.0000,
            "unit": "kWh"
        },
        {
            "obis": "32.7.0",
            "value": 230.0000,
            "unit": "V"
        }
    ]
}';

DECLARE @meter_id INT;
DECLARE @packet_id BIGINT;

-- 2. Έλεγχος JSON και μεγέθους
IF ISJSON(@payload) <> 1
BEGIN
    THROW 54000, 'Invalid JSON payload.', 1;
END;

-- Το raw_payload του υπάρχοντος schema είναι NVARCHAR(4000).
IF DATALENGTH(@payload) > 8000
BEGIN
    THROW 54002, 'Payload exceeds the current storage limit.', 1;
END;

-- 3. Μετατροπή timestamp σε UTC
DECLARE @timestamp_with_zone DATETIMEOFFSET(7) =
    TRY_CONVERT(
        DATETIMEOFFSET(7),
        JSON_VALUE(@payload, '$.Transmission_Timestamp')
    );

DECLARE @reading_time DATETIME2(7) =
    CAST(
        SWITCHOFFSET(@timestamp_with_zone, '+00:00')
        AS DATETIME2(7)
    );

-- Οι μετρήσεις πρέπει να αντιστοιχούν σε διάστημα 15 λεπτών.
IF @reading_time IS NULL
   OR DATEPART(MINUTE, @reading_time) % 15 <> 0
   OR DATEPART(SECOND, @reading_time) <> 0
   OR DATEPART(NANOSECOND, @reading_time) <> 0
BEGIN
    THROW 54001, 'Invalid timestamp or non-15-minute slot.', 1;
END;

-- 4. Μετατροπή των μετρήσεων JSON σε γραμμές
DECLARE @readings TABLE (
    obis_code VARCHAR(20),
    reading_value DECIMAL(18,4),
    unit VARCHAR(20)
);

INSERT INTO @readings (
    obis_code,
    reading_value,
    unit
)
SELECT
    obis_code,
    reading_value,
    unit
FROM OPENJSON(@payload, '$.Telemetry_Payload')
WITH (
    obis_code VARCHAR(20) '$.obis',
    reading_value DECIMAL(18,4) '$.value',
    unit VARCHAR(20) '$.unit'
);

-- 5. Έλεγχος ότι υπάρχουν μετρήσεις
IF NOT EXISTS (
    SELECT 1
    FROM @readings
)
BEGIN
    THROW 54003, 'Packet contains no readings.', 1;
END;

-- 6. Έλεγχος OBIS, μονάδας και τιμής
IF EXISTS (
    SELECT 1
    FROM @readings AS incoming
    LEFT JOIN dbo.OBIS_CODE AS expected
        ON expected.obis_code = incoming.obis_code
    WHERE expected.obis_code IS NULL
       OR incoming.unit IS NULL
       OR incoming.unit <> expected.unit
       OR incoming.reading_value IS NULL
)
BEGIN
    THROW 54004, 'Unknown OBIS, wrong unit or missing value.', 1;
END;

-- 7. Έλεγχος για επαναλαμβανόμενο OBIS μέσα στο ίδιο packet
IF EXISTS (
    SELECT obis_code
    FROM @readings
    GROUP BY obis_code
    HAVING COUNT(*) > 1
)
BEGIN
    THROW 54005, 'Duplicate OBIS code inside the packet.', 1;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    -- 8. Εντοπισμός ενεργού και εγκεκριμένου μετρητή
    SELECT @meter_id = meter_id
    FROM dbo.METER WITH (UPDLOCK, HOLDLOCK)
    WHERE network_identifier =
        JSON_VALUE(@payload, '$.Meter_Network_ID')
      AND status = 'ACTIVE'
      AND approval_status = 'APPROVED';

    IF @meter_id IS NULL
    BEGIN
        THROW 54006, 'No active and approved meter found.', 1;
    END;

    -- 9. Αποτροπή αποθήκευσης των ίδιων μετρήσεων δεύτερη φορά
    IF EXISTS (
        SELECT 1
        FROM dbo.METER_READING AS existing
        JOIN @readings AS incoming
            ON incoming.obis_code = existing.obis_code
        WHERE existing.meter_id = @meter_id
          AND existing.reading_timestamp = @reading_time
    )
    BEGIN
        THROW 54007, 'Readings already exist for this slot.', 1;
    END;

    -- 10. Αποθήκευση του αρχικού packet
    INSERT INTO dbo.TELEMETRY_PACKET (
        meter_network_id,
        transmission_timestamp,
        network_type,
        signal_strength_dbm,
        raw_payload,
        match_status,
        processed_at,
        meter_id
    )
    VALUES (
        JSON_VALUE(@payload, '$.Meter_Network_ID'),
        @reading_time,
        JSON_VALUE(@payload, '$.Network_Type'),
        TRY_CONVERT(
            SMALLINT,
            JSON_VALUE(@payload, '$.Cell_Signal_Strength_dBm')
        ),
        @payload,
        'MATCHED',
        SYSUTCDATETIME(),
        @meter_id
    );

    SET @packet_id = CONVERT(BIGINT, SCOPE_IDENTITY());

    -- 11. Αποθήκευση μετρήσεων που περιμένουν VEE
    INSERT INTO dbo.METER_READING (
        reading_timestamp,
        [value],
        validation_status,
        value_source,
        is_final,
        packet_id,
        meter_id,
        obis_code
    )
    SELECT
        @reading_time,
        reading_value,
        'PENDING',
        'TELEMETRY',
        0,
        @packet_id,
        @meter_id,
        obis_code
    FROM @readings;

    COMMIT TRANSACTION;

    -- 12. Εμφάνιση του packet που αποθηκεύτηκε
    SELECT
        packet_id,
        meter_network_id,
        transmission_timestamp,
        match_status,
        meter_id
    FROM dbo.TELEMETRY_PACKET
    WHERE packet_id = @packet_id;

    -- 13. Εμφάνιση των δύο μετρήσεων
    SELECT
        reading_id,
        packet_id,
        meter_id,
        reading_timestamp,
        obis_code,
        [value],
        validation_status,
        value_source,
        is_final
    FROM dbo.METER_READING
    WHERE packet_id = @packet_id
    ORDER BY obis_code;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;