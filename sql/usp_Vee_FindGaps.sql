CREATE OR ALTER PROCEDURE dbo.usp_Vee_FindGaps
    @meter_network_id VARCHAR(60),
    @obis_code VARCHAR(20),
    @from_time DATETIME2(0),
    @to_time DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @meter_id INT;

    SELECT @meter_id = meter_id
    FROM dbo.METER
    WHERE network_id = @meter_network_id;

    IF @meter_id IS NULL
    BEGIN
        THROW 54030, 'Meter not found.', 1;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.OBIS_CODE
        WHERE obis_code = @obis_code
    )
    BEGIN
        THROW 54031, 'Unknown OBIS code.', 1;
    END;

    IF @from_time IS NULL
       OR @to_time IS NULL
       OR @from_time > @to_time
    BEGIN
        THROW 54032, 'Invalid time interval.', 1;
    END;

    IF DATEPART(MINUTE, @from_time) % 15 <> 0
       OR DATEPART(SECOND, @from_time) <> 0
       OR DATEPART(MINUTE, @to_time) % 15 <> 0
       OR DATEPART(SECOND, @to_time) <> 0
    BEGIN
        THROW 54033, 'Interval boundaries must align to 15-minute slots.', 1;
    END;

    IF DATEDIFF_BIG(MINUTE, @from_time, @to_time) > 31 * 24 * 60
    BEGIN
        THROW 54034, 'Use an interval of at most 31 days.', 1;
    END;

    DECLARE @slot_count INT =
        DATEDIFF(MINUTE, @from_time, @to_time) / 15;

    ;WITH slot_numbers AS (
        SELECT 0 AS slot_number

        UNION ALL

        SELECT slot_number + 1
        FROM slot_numbers
        WHERE slot_number < @slot_count
    ),
    expected_slots AS (
        SELECT
            DATEADD(MINUTE, slot_number * 15, @from_time)
                AS expected_timestamp
        FROM slot_numbers
    )
    SELECT
        @meter_network_id AS meter_network_id,
        @obis_code AS obis_code,
        s.expected_timestamp AS missing_timestamp
    FROM expected_slots AS s
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.METER_READING AS r
        WHERE r.meter_id = @meter_id
          AND r.obis_code = @obis_code
          AND r.reading_timestamp = s.expected_timestamp
    )
    ORDER BY s.expected_timestamp
    OPTION (MAXRECURSION 3000);
END;
GO
