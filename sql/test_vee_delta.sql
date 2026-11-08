-- Demo προσωρινού υπολογισμού κατανάλωσης 15 λεπτών.
-- Αφορά μόνο σωρευτικές μετρήσεις του DEMO-NET-001.
-- Δεν οριστικοποιεί μετρήσεις.
-- Η τελική υλοποίηση χρειάζεται επανέλεγχο όταν αλλάζουν
-- προηγούμενες τιμές ή φτάνουν καθυστερημένες μετρήσεις.

SET XACT_ABORT ON;

DECLARE @delta_checks TABLE (
    reading_id BIGINT PRIMARY KEY,
    original_value DECIMAL(18,4),
    calculated_delta DECIMAL(18,4),
    new_status VARCHAR(20),
    reason NVARCHAR(300)
);

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.VEE_RULE WITH (UPDLOCK, HOLDLOCK)
        WHERE rule_code = 'VAL_CUMULATIVE_DELTA'
    )
    BEGIN
        INSERT INTO dbo.VEE_RULE (
            rule_code,
            stage,
            description,
            parameters,
            is_active
        )
        VALUES (
            'VAL_CUMULATIVE_DELTA',
            'VALIDATION',
            N'Check consecutive cumulative readings and calculate a provisional 15-minute delta.',
            NULL,
            1
        );
    END;

    INSERT INTO @delta_checks (
        reading_id,
        original_value,
        calculated_delta,
        new_status,
        reason
    )
    SELECT
        current_reading.reading_id,
        current_reading.[value],
        CASE
            WHEN previous_reading.reading_id IS NULL THEN NULL
            WHEN previous_reading.validation_status = 'SUSPECT' THEN NULL
            WHEN current_reading.[value] < previous_reading.[value] THEN NULL
            ELSE current_reading.[value] - previous_reading.[value]
        END,
        CASE
            WHEN previous_reading.reading_id IS NOT NULL
             AND previous_reading.validation_status <> 'SUSPECT'
             AND current_reading.[value] < previous_reading.[value]
                THEN 'SUSPECT'
            ELSE 'PENDING'
        END,
        CASE
            WHEN previous_reading.reading_id IS NULL
                THEN N'Previous 15-minute reading missing; delta remains NULL.'
            WHEN previous_reading.validation_status = 'SUSPECT'
                THEN N'Previous reading is suspect; delta remains NULL.'
            WHEN current_reading.[value] < previous_reading.[value]
                THEN N'Cumulative register decreased; investigation required.'
            ELSE N'Provisional delta calculated; full VEE validation still required.'
        END
    FROM dbo.METER_READING AS current_reading
        WITH (UPDLOCK, HOLDLOCK)
    JOIN dbo.METER AS m
        ON m.meter_id = current_reading.meter_id
    JOIN dbo.OBIS_CODE AS o
        ON o.obis_code = current_reading.obis_code
    LEFT JOIN dbo.METER_READING AS previous_reading
        WITH (UPDLOCK, HOLDLOCK)
        ON previous_reading.meter_id = current_reading.meter_id
       AND previous_reading.obis_code = current_reading.obis_code
       AND previous_reading.reading_timestamp =
           DATEADD(MINUTE, -15, current_reading.reading_timestamp)
    WHERE m.network_identifier = 'DEMO-NET-001'
      AND o.measurement_kind = 'CUMULATIVE'
      AND current_reading.is_final = 0
      AND current_reading.validation_status = 'PENDING'
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.VEE_LOG AS v
          WHERE v.reading_id = current_reading.reading_id
            AND v.rule_code = 'VAL_CUMULATIVE_DELTA'
      );

    INSERT INTO dbo.VEE_LOG (
        old_status,
        new_status,
        original_value,
        corrected_value,
        reason,
        origin,
        reading_id,
        rule_code
    )
    SELECT
        'PENDING',
        new_status,
        original_value,
        NULL,
        reason,
        'AUTOMATIC',
        reading_id,
        'VAL_CUMULATIVE_DELTA'
    FROM @delta_checks;

    UPDATE r
    SET
        delta_value = c.calculated_delta,
        validation_status = c.new_status
    FROM dbo.METER_READING AS r
    JOIN @delta_checks AS c
        ON c.reading_id = r.reading_id;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

SELECT
    r.reading_timestamp,
    r.obis_code,
    r.[value],
    r.delta_value,
    r.validation_status,
    r.is_final
FROM dbo.METER_READING AS r
JOIN dbo.METER AS m
    ON m.meter_id = r.meter_id
WHERE m.network_identifier = 'DEMO-NET-001'
ORDER BY r.reading_timestamp, r.obis_code;