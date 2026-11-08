/*
    Demo tests για dbo.usp_Telemetry_Ingest.

    Εκτέλεση στη δική σου βάση δεδομένων.

    Προϋποθέσεις:
    - Έχει δημιουργηθεί η usp_Telemetry_Ingest.
    - Υπάρχει ο DEMO-NET-001 ως ACTIVE / APPROVED.
    - Υπάρχουν τα OBIS 1.8.0 και 32.7.0.
    - Ο DEMO-UNKNOWN-001 δεν υπάρχει στον πίνακα METER.

    Οι δοκιμές αποθηκεύουν πραγματικά demo δεδομένα.

    Αν η δοκιμή 1 έχει ήδη εκτελεστεί:
    αναμένεται QUARANTINED / 0 / Readings already exist for this slot.
    Κάθε επανάληψη διατηρεί νέο packet, χωρίς διπλές μετρήσεις.
*/

-- TEST 1: Έγκυρο packet.
-- Πρώτη εκτέλεση για αυτό το slot:
-- MATCHED / inserted_readings = 2 / reason = NULL.

EXEC dbo.usp_Telemetry_Ingest
    @payload = N'{
        "Meter_Network_ID": "DEMO-NET-001",
        "Transmission_Timestamp": "2026-11-06T10:15:00Z",
        "Cell_Signal_Strength_dBm": -92,
        "Network_Type": "NB_IOT",
        "Telemetry_Payload": [
            {
                "obis": "1.8.0",
                "value": 1000.5000,
                "unit": "kWh"
            },
            {
                "obis": "32.7.0",
                "value": 231.0000,
                "unit": "V"
            }
        ]
    }';
GO

-- TEST 2: Άγνωστος μετρητής.
-- Αναμένεται:
-- UNMATCHED / inserted_readings = 0.
-- reason = Unknown meter network ID.
-- Καταγραφή συμβάντος WARNING.

EXEC dbo.usp_Telemetry_Ingest
    @payload = N'{
        "Meter_Network_ID": "DEMO-UNKNOWN-001",
        "Transmission_Timestamp": "2026-11-06T10:30:00Z",
        "Cell_Signal_Strength_dBm": -92,
        "Network_Type": "NB_IOT",
        "Telemetry_Payload": [
            {
                "obis": "1.8.0",
                "value": 1001.0000,
                "unit": "kWh"
            }
        ]
    }';
GO

-- TEST 3: Λάθος μονάδα.
-- Το OBIS 32.7.0 απαιτεί V, όχι kWh.
-- Αναμένεται:
-- QUARANTINED / inserted_readings = 0.
-- reason = Unknown OBIS, wrong unit or invalid reading value.

EXEC dbo.usp_Telemetry_Ingest
    @payload = N'{
        "Meter_Network_ID": "DEMO-NET-001",
        "Transmission_Timestamp": "2026-11-06T10:30:00Z",
        "Cell_Signal_Strength_dBm": -92,
        "Network_Type": "NB_IOT",
        "Telemetry_Payload": [
            {
                "obis": "32.7.0",
                "value": 230.0000,
                "unit": "kWh"
            }
        ]
    }';
GO

-- Έλεγχος αποθηκευμένων demo packets και συμβάντων.

SELECT
    p.packet_id,
    p.meter_network_id,
    p.transmission_timestamp,
    p.match_status,
    p.meter_id,
    e.event_type,
    e.result,
    e.severity
FROM dbo.TELEMETRY_PACKET AS p
LEFT JOIN dbo.EVENT AS e
    ON e.packet_id = p.packet_id
WHERE p.meter_network_id IN (
    'DEMO-NET-001',
    'DEMO-UNKNOWN-001'
)
ORDER BY p.packet_id;
GO

-- Έλεγχος μετρήσεων του έγκυρου packet.
-- Αναμένονται 2 γραμμές, ακόμη και μετά από επανάληψη του TEST 1.

SELECT
    r.reading_id,
    r.packet_id,
    r.obis_code,
    r.[value],
    r.validation_status,
    r.is_final
FROM dbo.METER_READING AS r
JOIN dbo.METER AS m
    ON m.meter_id = r.meter_id
WHERE m.network_identifier = 'DEMO-NET-001'
  AND r.reading_timestamp = '2026-11-06T10:15:00'
ORDER BY r.obis_code;
GO