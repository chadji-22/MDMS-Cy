-- Demo ελέγχου ορίων για τον DEMO-NET-001.
-- Καταγράφει τον έλεγχο στο VEE_LOG.
-- Οι εκτός ορίων μετρήσεις γίνονται SUSPECT.
-- Δεν οριστικοποιεί μετρήσεις.

SET XACT_ABORT ON;

DECLARE @checks TABLE (
    reading_id BIGINT PRIMARY KEY,
    original_value DECIMAL(18,4),
    old_status VARCHAR(20),
    new_status VARCHAR(20),
    reason NVARCHAR(300)
);

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO @checks (
        reading_id,
        original_value,
        old_status,
        new_status,
        reason
    )
    SELECT
        r.reading_id,
        r.[value],
        r.validation_status,
        CASE
            WHEN r.[value] < o.valid_min
              OR r.[value] > o.valid_max
                THEN 'SUSPECT'
            ELSE 'PENDING'
        END,
        CASE
            WHEN r.[value] < o.valid_min
              OR r.[value] > o.valid_max
                THEN N'Value is outside the configured OBIS range.'
            WHEN o.valid_min IS NULL AND o.valid_max IS NULL
                THEN N'No range configured; further validation required.'
            ELSE N'Configured range check passed; further validation required.'
        END
    FROM dbo.METER_READING AS r WITH (UPDLOCK, HOLDLOCK)
    JOIN dbo.OBIS_CODE AS o
        ON o.obis_code = r.obis_code
    JOIN dbo.METER AS m
        ON m.meter_id = r.meter_id
    WHERE m.network_identifier = 'DEMO-NET-001'
      AND r.is_final = 0
      AND r.validation_status = 'PENDING'
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.VEE_LOG AS v
          WHERE v.reading_id = r.reading_id
            AND v.rule_code = 'VAL_RANGE'
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
        old_status,
        new_status,
        original_value,
        NULL,
        reason,
        'AUTOMATIC',
        reading_id,
        'VAL_RANGE'
    FROM @checks;

    UPDATE r
    SET validation_status = c.new_status
    FROM dbo.METER_READING AS r
    JOIN @checks AS c
        ON c.reading_id = r.reading_id
    WHERE c.new_status = 'SUSPECT';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

SELECT
    v.reading_id,
    v.rule_code,
    v.original_value,
    v.old_status,
    v.new_status,
    v.reason
FROM dbo.VEE_LOG AS v
JOIN dbo.METER_READING AS r
    ON r.reading_id = v.reading_id
JOIN dbo.METER AS m
    ON m.meter_id = r.meter_id
WHERE m.network_identifier = 'DEMO-NET-001'
  AND v.rule_code = 'VAL_RANGE'
ORDER BY v.reading_id;