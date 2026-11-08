IF NOT EXISTS (
    SELECT 1
    FROM dbo.METER_TYPE
    WHERE type_name = 'DEMO_SINGLE_PHASE'
)
BEGIN
    INSERT INTO dbo.METER_TYPE (
        type_name,
        connection_phases,
        max_amps
    )
    VALUES (
        'DEMO_SINGLE_PHASE',
        1,
        60
    );
END;

SELECT
    meter_type_id,
    type_name,
    connection_phases,
    max_amps
FROM dbo.METER_TYPE
WHERE type_name = 'DEMO_SINGLE_PHASE';
DECLARE @meter_type_id INT = (
    SELECT meter_type_id
    FROM dbo.METER_TYPE
    WHERE type_name = 'DEMO_SINGLE_PHASE'
);

DECLARE @transformer_id INT = (
    SELECT transformer_id
    FROM dbo.TRANSFORMER
    WHERE name = N'DEMO_TRANSFORMER_1'
);

DECLARE @retention_policy_id INT = (
    SELECT retention_policy_id
    FROM dbo.RETENTION_POLICY
    WHERE policy_name = 'STANDARD_3Y'
);

IF @meter_type_id IS NULL
   OR @transformer_id IS NULL
   OR @retention_policy_id IS NULL
BEGIN
    THROW 54000, 'Missing required demo data.', 1;
END;

IF NOT EXISTS (
    SELECT 1
    FROM dbo.METER
    WHERE network_identifier = 'DEMO-NET-001'
)
BEGIN
    INSERT INTO dbo.METER (
        serial_number,
        network_identifier,
        firmware_version,
        communication_type,
        latitude,
        longitude,
        status,
        approval_status,
        activated_at,
        meter_type_id,
        transformer_id,
        retention_policy_id
    )
    VALUES (
        'DEMO-SERIAL-001',
        'DEMO-NET-001',
        '1.0',
        'NB_IOT',
        35.16,
        33.37,
        'ACTIVE',
        'APPROVED',
        SYSUTCDATETIME(),
        @meter_type_id,
        @transformer_id,
        @retention_policy_id
    );
END;

SELECT
    meter_id,
    serial_number,
    network_identifier,
    status,
    approval_status,
    transformer_id
FROM dbo.METER
WHERE network_identifier = 'DEMO-NET-001';