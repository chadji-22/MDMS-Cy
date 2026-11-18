/* ============================================================================
   test_telemetry_parsing.sql  -  how the JSON packet is read (read-only demo, writes nothing)

   Mirrors the parsing of sp_IngestTelemetryPacket (Algorithm A). Changes against the first version:
     * METER.network_identifier is now METER.network_id; there is no approval_status
       (MATCHED = the meter exists and its status is ACTIVE; exists but not ACTIVE = QUARANTINED;
       missing = UNMATCHED);
     * the value is read as text and converted with TRY_CONVERT (a value that is not a number is
       dropped, it is not an error);
     * the timestamp is converted to UTC and floored to its 15-minute slot with fn_Floor15;
     * the labels of the last query say what io does with each pair:
         unknown code  -> UNSUPPORTED_OBIS event, the pair is not stored   (was UNKNOWN_OBIS)
         wrong unit    -> stored as SUSPECT / UNIT_MISMATCH                (was WRONG_UNIT = rejected)
         no unit       -> stored (the unit is only compared when it is given)
         bad value     -> dropped without an event
   Needs: create.sql (the OBIS_CODE rows) and functions.sql (fn_Floor15); DEMO-NET-001 from the seeds for query 2.
   ============================================================================ */
SET NOCOUNT ON;

DECLARE @payload NVARCHAR(4000) = N'{
    "Meter_Network_ID": "DEMO-NET-001",
    "Transmission_Timestamp": "2025-06-10T10:07:30Z",
    "Cell_Signal_Strength_dBm": -92,
    "Network_Type": "NB_IOT",
    "Telemetry_Payload": [
        {"obis": "1.8.0",  "value": 1000.0000, "unit": "kWh"},
        {"obis": "32.7.0", "value": 230.0000,  "unit": "V"},
        {"obis": "32.7.0", "value": 230.0000,  "unit": "kWh"},
        {"obis": "99.9.9", "value": 5,         "unit": "X"},
        {"obis": "31.7.0", "value": 4.2},
        {"obis": "52.7.0", "value": "abc",     "unit": "V"}
    ]
}';

-- 1. The packet header (ISJSON must be 1, otherwise io stores the text as a COMM_ERROR packet).
SELECT ISJSON(@payload) AS is_json,
       JSON_VALUE(@payload, '$.Meter_Network_ID')                    AS meter_network_id,
       JSON_VALUE(@payload, '$.Transmission_Timestamp')              AS transmission_timestamp_text,
       CAST(SWITCHOFFSET(TRY_CONVERT(DATETIMEOFFSET, JSON_VALUE(@payload, '$.Transmission_Timestamp')), '+00:00')
            AS DATETIME2(0))                                         AS transmission_utc,
       [dbo].[fn_Floor15](CAST(SWITCHOFFSET(TRY_CONVERT(DATETIMEOFFSET, JSON_VALUE(@payload, '$.Transmission_Timestamp')), '+00:00')
            AS DATETIME2(0)))                                        AS reading_slot,
       JSON_VALUE(@payload, '$.Network_Type')                        AS network_type,
       TRY_CONVERT(SMALLINT, JSON_VALUE(@payload, '$.Cell_Signal_Strength_dBm')) AS signal_dbm;

-- 2. The meter lookup and the match status the packet would get.
SELECT JSON_VALUE(@payload, '$.Meter_Network_ID') AS meter_network_id,
       m.meter_id, m.network_id, m.status AS meter_status,
       CASE WHEN m.meter_id IS NULL THEN 'UNMATCHED'
            WHEN m.status = 'ACTIVE' THEN 'MATCHED'
            ELSE 'QUARANTINED' END AS match_status
FROM (SELECT 1 AS one) AS x
LEFT JOIN [dbo].[METER] AS m ON m.network_id = JSON_VALUE(@payload, '$.Meter_Network_ID');

-- 3. The list of readings as rows (value read as text, then converted).
SELECT j.obis, j.val AS value_text, TRY_CONVERT(DECIMAL(18,4), j.val) AS reading_value, j.unit
FROM OPENJSON(@payload, '$.Telemetry_Payload')
     WITH (obis VARCHAR(20) '$.obis', val NVARCHAR(50) '$.value', unit VARCHAR(10) '$.unit') AS j;

-- 4. What io does with each pair. Expected:
--    1.8.0 kWh -> OK | 32.7.0 V -> OK | 32.7.0 kWh -> same code twice: only the first one is kept |
--    99.9.9 -> UNSUPPORTED_OBIS | 31.7.0 without unit -> OK (stored) | 52.7.0 "abc" -> DROPPED_BAD_VALUE
SELECT incoming.obis,
       incoming.reading_value,
       incoming.unit AS received_unit,
       expected.unit AS expected_unit,
       CASE WHEN incoming.reading_value IS NULL                                  THEN 'DROPPED_BAD_VALUE'
            WHEN incoming.rn > 1                                                 THEN 'IGNORED_DUPLICATE_IN_PACKET'
            WHEN expected.obis_code IS NULL                                      THEN 'UNSUPPORTED_OBIS (event, not stored)'
            WHEN incoming.unit IS NOT NULL AND incoming.unit <> expected.unit    THEN 'UNIT_MISMATCH (stored as SUSPECT)'
            ELSE 'OK (stored as PENDING)' END AS io_result
FROM (SELECT j.obis, TRY_CONVERT(DECIMAL(18,4), j.val) AS reading_value, j.unit,
             ROW_NUMBER() OVER (PARTITION BY j.obis ORDER BY (SELECT NULL)) AS rn
      FROM OPENJSON(@payload, '$.Telemetry_Payload')
           WITH (obis VARCHAR(20) '$.obis', val NVARCHAR(50) '$.value', unit VARCHAR(10) '$.unit') AS j
      WHERE j.obis IS NOT NULL) AS incoming
LEFT JOIN [dbo].[OBIS_CODE] AS expected ON expected.obis_code = incoming.obis
ORDER BY incoming.obis, incoming.rn;
