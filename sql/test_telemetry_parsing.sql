DECLARE @payload NVARCHAR(MAX) = N'{
    "Meter_Network_ID": "DEMO-NET-001",
    "Transmission_Timestamp": "2026-11-06T10:00:00Z",
    "Cell_Signal_Strength_dBm": -92,
    "Network_Type": "NB_IOT",
    "Telemetry_Payload": [
        {"obis": "1.8.0", "value": 1000.0000, "unit": "kWh"},
        {"obis": "32.7.0", "value": 230.0000, "unit": "V"}
    ]
}';

-- 1. Διαβάζουμε τα βασικά στοιχεία του packet.
SELECT
    JSON_VALUE(@payload, '$.Meter_Network_ID')
        AS meter_network_id,
    JSON_VALUE(@payload, '$.Transmission_Timestamp')
        AS transmission_timestamp;

-- 2. Αναζητούμε τον μετρητή στη βάση.
SELECT
    meter_id,
    network_identifier,
    status,
    approval_status
FROM dbo.METER
WHERE network_identifier =
    JSON_VALUE(@payload, '$.Meter_Network_ID');

-- 3. Μετατρέπουμε τη λίστα μετρήσεων σε γραμμές.
SELECT
    obis_code,
    reading_value,
    unit
FROM OPENJSON(@payload, '$.Telemetry_Payload')
WITH (
    obis_code     VARCHAR(20)   '$.obis',
    reading_value DECIMAL(18,4) '$.value',
    unit          VARCHAR(20)   '$.unit'
);
SELECT
    incoming.obis_code,
    incoming.reading_value,
    incoming.unit AS received_unit,
    expected.unit AS expected_unit,
    CASE
        WHEN expected.obis_code IS NULL
            THEN 'UNKNOWN_OBIS'
        WHEN incoming.unit IS NULL
             OR incoming.unit <> expected.unit
            THEN 'WRONG_UNIT'
        WHEN incoming.reading_value IS NULL
            THEN 'MISSING_VALUE'
        ELSE 'OK'
    END AS check_result
FROM OPENJSON(@payload, '$.Telemetry_Payload')
WITH (
    obis_code     VARCHAR(20)   '$.obis',
    reading_value DECIMAL(18,4) '$.value',
    unit          VARCHAR(20)   '$.unit'
) AS incoming
LEFT JOIN dbo.OBIS_CODE AS expected
    ON expected.obis_code = incoming.obis_code;