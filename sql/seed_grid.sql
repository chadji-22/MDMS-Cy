IF NOT EXISTS (
    SELECT 1
    FROM dbo.GEOFENCE
    WHERE name = N'DEMO_L3'
)
BEGIN
    INSERT INTO dbo.GEOFENCE (
        name,
        [level],
        boundary,
        parent_geofence_id
    )
    VALUES (
        N'DEMO_L3',
        3,
        geography::STGeomFromText(
            'POLYGON((
                33.30 35.10,
                33.50 35.10,
                33.50 35.25,
                33.30 35.25,
                33.30 35.10
            ))',
            4326
        ),
        NULL
    );
END;

SELECT
    geofence_id,
    name,
    [level],
    parent_geofence_id
FROM dbo.GEOFENCE;
IF NOT EXISTS (
    SELECT 1
    FROM dbo.GEOFENCE
    WHERE name = N'DEMO_L2'
)
BEGIN
    INSERT INTO dbo.GEOFENCE (
        name,
        [level],
        boundary,
        parent_geofence_id
    )
    SELECT
        N'DEMO_L2',
        2,
        geography::STGeomFromText(
            'POLYGON((
                33.32 35.12,
                33.45 35.12,
                33.45 35.22,
                33.32 35.22,
                33.32 35.12
            ))',
            4326
        ),
        geofence_id
    FROM dbo.GEOFENCE
    WHERE name = N'DEMO_L3';
END;

SELECT
    geofence_id,
    name,
    [level],
    parent_geofence_id
FROM dbo.GEOFENCE;
IF NOT EXISTS (
    SELECT 1
    FROM dbo.GEOFENCE
    WHERE name = N'DEMO_L1'
)
BEGIN
    INSERT INTO dbo.GEOFENCE (
        name,
        [level],
        boundary,
        parent_geofence_id
    )
    SELECT
        N'DEMO_L1',
        1,
        geography::STGeomFromText(
            'POLYGON((
                33.34 35.14,
                33.40 35.14,
                33.40 35.18,
                33.34 35.18,
                33.34 35.14
            ))',
            4326
        ),
        geofence_id
    FROM dbo.GEOFENCE
    WHERE name = N'DEMO_L2';
END;

SELECT
    geofence_id,
    name,
    [level],
    parent_geofence_id
FROM dbo.GEOFENCE
ORDER BY [level] DESC;
IF NOT EXISTS (
    SELECT 1
    FROM dbo.TRANSFORMER
    WHERE name = N'DEMO_TRANSFORMER_1'
)
BEGIN
    INSERT INTO dbo.TRANSFORMER (
        name,
        capacity_kva,
        latitude,
        longitude,
        geofence_id
    )
    SELECT
        N'DEMO_TRANSFORMER_1',
        500,
        35.16,
        33.37,
        geofence_id
    FROM dbo.GEOFENCE
    WHERE name = N'DEMO_L1';
END;

SELECT
    t.transformer_id,
    t.name AS transformer_name,
    t.capacity_kva,
    g.name AS geofence_name,
    g.[level]
FROM dbo.TRANSFORMER AS t
JOIN dbo.GEOFENCE AS g
    ON g.geofence_id = t.geofence_id;