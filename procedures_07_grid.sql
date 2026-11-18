/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_07_grid.sql  -  Build Spec §9.7: transformer tree, current state, TSO / DSO analytics
   Algorithm E = sp_RefreshTransformerState.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf §4.1 p.9: transformers / geofences in a hierarchy of any depth]
-- Insert (@transformer_id NULL) or update. TR09 checks levels and cycles.
-- The rectangle of a child must lie inside the rectangle of its parent when both exist.
CREATE OR ALTER PROCEDURE [dbo].[sp_UpsertTransformer]
    @actor_user_id         INT,
    @transformer_id        INT = NULL,
    @name                  NVARCHAR(100),
    @level                 TINYINT,
    @capacity_kva          DECIMAL(10,2),
    @latitude              DECIMAL(9,6),
    @longitude             DECIMAL(9,6),
    @min_lat               DECIMAL(9,6) = NULL,
    @min_lon               DECIMAL(9,6) = NULL,
    @max_lat               DECIMAL(9,6) = NULL,
    @max_lon               DECIMAL(9,6) = NULL,
    @parent_transformer_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_UpsertTransformer';

    IF @name IS NULL OR LTRIM(RTRIM(@name)) = N'' OR @level IS NULL OR @level < 1 OR @capacity_kva IS NULL OR @capacity_kva <= 0
        THROW 50004, 'Invalid input: name, level >= 1 and capacity > 0 are required.', 1;
    IF @latitude IS NULL OR @longitude IS NULL OR @latitude NOT BETWEEN -90 AND 90 OR @longitude NOT BETWEEN -180 AND 180
        THROW 50004, 'Invalid input: the coordinates are not valid.', 1;
    IF NOT (   (@min_lat IS NULL AND @min_lon IS NULL AND @max_lat IS NULL AND @max_lon IS NULL)
            OR (@min_lat IS NOT NULL AND @min_lon IS NOT NULL AND @max_lat IS NOT NULL AND @max_lon IS NOT NULL
                AND @min_lat <= @max_lat AND @min_lon <= @max_lon))
        THROW 50004, 'Invalid input: give all four corners of the rectangle (min <= max) or none.', 1;
    IF @transformer_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE transformer_id = @transformer_id)
        THROW 50001, 'Transformer not found.', 1;
    IF @parent_transformer_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE transformer_id = @parent_transformer_id)
        THROW 50001, 'Parent transformer not found.', 1;
    IF EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE name = LTRIM(RTRIM(@name)) AND transformer_id <> ISNULL(@transformer_id, 0))
        THROW 50005, 'Duplicate: a transformer with this name already exists.', 1;
    IF @min_lat IS NOT NULL AND EXISTS (
        SELECT 1 FROM [dbo].[TRANSFORMER] AS p
        WHERE p.transformer_id = @parent_transformer_id AND p.min_lat IS NOT NULL
          AND (@min_lat < p.min_lat OR @max_lat > p.max_lat OR @min_lon < p.min_lon OR @max_lon > p.max_lon))
        THROW 50004, 'Invalid input: the rectangle must lie inside the rectangle of the parent.', 1;
    IF @transformer_id IS NOT NULL AND @min_lat IS NOT NULL AND EXISTS (
        SELECT 1 FROM [dbo].[TRANSFORMER] AS ch
        WHERE ch.parent_transformer_id = @transformer_id AND ch.min_lat IS NOT NULL
          AND (ch.min_lat < @min_lat OR ch.max_lat > @max_lat OR ch.min_lon < @min_lon OR ch.max_lon > @max_lon))
        THROW 50004, 'Invalid input: the rectangles of the children would fall outside the new rectangle.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        IF @transformer_id IS NULL
        BEGIN
            INSERT INTO [dbo].[TRANSFORMER] (name, [level], capacity_kva, latitude, longitude,
                                             min_lat, min_lon, max_lat, max_lon, parent_transformer_id)
            VALUES (LTRIM(RTRIM(@name)), @level, @capacity_kva, @latitude, @longitude,
                    @min_lat, @min_lon, @max_lat, @max_lon, @parent_transformer_id);
            SET @transformer_id = SCOPE_IDENTITY();
            EXEC [dbo].[sp__Log] 'CREATE', 'TRANSFORMER', @transformer_id, NULL, @level, @name;
        END
        ELSE
        BEGIN
            UPDATE [dbo].[TRANSFORMER]
               SET name = LTRIM(RTRIM(@name)), [level] = @level, capacity_kva = @capacity_kva,
                   latitude = @latitude, longitude = @longitude,
                   min_lat = @min_lat, min_lon = @min_lon, max_lat = @max_lat, max_lon = @max_lon,
                   parent_transformer_id = @parent_transformer_id
             WHERE transformer_id = @transformer_id;
            EXEC [dbo].[sp__Log] 'UPDATE', 'TRANSFORMER', @transformer_id, NULL, @level, @name;
        END
        COMMIT TRANSACTION;
        SELECT @transformer_id AS transformer_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: a transformer with this name already exists.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §4.1 p.9: the hierarchy, whatever its depth; lab 10 Hogwarts_Tree; UC-17]
-- Creates #Tree, puts the root at depth 0 and lets sp__WalkTransformerTree (recursive cursor) fill the rest.
-- @root_id NULL = every root of the forest.
CREATE OR ALTER PROCEDURE [dbo].[sp_GetTransformerTree]
    @actor_user_id INT,
    @root_id       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TSO,DSO,SYSTEM_OFFICER,SYSTEM_ADMIN';

    IF @root_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE transformer_id = @root_id)
        THROW 50001, 'Transformer not found.', 1;

    CREATE TABLE #Tree (seq INT IDENTITY(1,1) PRIMARY KEY, transformer_id INT NOT NULL, name NVARCHAR(100) NOT NULL,
                        [level] TINYINT NOT NULL, depth INT NOT NULL, label NVARCHAR(200) NOT NULL);

    DECLARE @id INT, @name NVARCHAR(100), @level TINYINT;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT transformer_id, name, [level] FROM [dbo].[TRANSFORMER]
        WHERE (@root_id IS NOT NULL AND transformer_id = @root_id)
           OR (@root_id IS NULL AND parent_transformer_id IS NULL)
        ORDER BY name;
    OPEN c;
    FETCH NEXT FROM c INTO @id, @name, @level;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO #Tree (transformer_id, name, [level], depth, label)
        VALUES (@id, @name, @level, 0, CAST(@id AS NVARCHAR(10)) + N' ' + @name);
        EXEC [dbo].[sp__WalkTransformerTree] @id, 1;
        FETCH NEXT FROM c INTO @id, @name, @level;
    END
    CLOSE c;
    DEALLOCATE c;

    SELECT tr.seq, tr.transformer_id, tr.name, tr.[level], tr.depth, tr.label,
           t.parent_transformer_id, t.capacity_kva, t.latitude, t.longitude,
           t.min_lat, t.min_lon, t.max_lat, t.max_lon,
           imp.reference_15_min, imp.sum_value AS import_kwh, ex.sum_value AS export_kwh,
           imp.meter_count AS meters_reporting,
           (SELECT COUNT(*) FROM [dbo].[METER] AS m
            WHERE m.transformer_id = tr.transformer_id AND m.removed_at IS NULL) AS meters_connected
    FROM #Tree AS tr
    JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = tr.transformer_id
    LEFT JOIN [dbo].[TRANSFORMER_CURRENT_STATE] AS imp ON imp.transformer_id = tr.transformer_id AND imp.obis_code = '1.8.0'
    LEFT JOIN [dbo].[TRANSFORMER_CURRENT_STATE] AS ex  ON ex.transformer_id  = tr.transformer_id AND ex.obis_code  = '2.8.0'
    ORDER BY tr.seq;
END;
GO

-- [project.pdf §4.1 p.9: from coordinates to the geofence, and to the geofences above it]
CREATE OR ALTER PROCEDURE [dbo].[sp_FindGeofenceForPoint]
    @actor_user_id INT,
    @latitude      DECIMAL(9,6),
    @longitude     DECIMAL(9,6)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN,SYSTEM_OFFICER,DSO,TSO,TECHNICIAN';

    DECLARE @l1 INT = [dbo].[fn_FindGeofence](@latitude, @longitude);

    SELECT a.distance, t.transformer_id, t.name, t.[level], t.min_lat, t.min_lon, t.max_lat, t.max_lon
    FROM [dbo].[fn_TransformerAncestors](@l1) AS a
    JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = a.transformer_id
    ORDER BY a.distance;                 -- no rows = the point is in no geofence
END;
GO

-- [project.pdf §4.2 p.10: the current state of the whole hierarchy, refreshed by an authorized user; UC-17]
-- Algorithm E: #Leaf set-based outside any transaction, sp__SumSubtree (recursive cursor, post-order)
-- for every level, then one short MERGE.
-- [AR: session-scope app lock, because the heavy part runs outside the transaction (second contention point, §10)]
CREATE OR ALTER PROCEDURE [dbo].[sp_RefreshTransformerState]
    @actor_user_id   INT,
    @reference_15_min DATETIME2(0) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TSO,DSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'TREE_REFRESH';

    DECLARE @rc INT, @ref DATETIME2(0), @root INT, @rows INT = 0, @comment NVARCHAR(500);
    EXEC @rc = sys.sp_getapplock @Resource = N'TREE_REFRESH', @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 10000;
    IF @rc < 0
        THROW 50007, 'Busy: the tree refresh is already running.', 1;

    BEGIN TRY
        -- 1. the reference slot: the given one, or the latest slot with VEE-verified readings
        SET @ref = [dbo].[fn_Floor15](@reference_15_min);
        IF @ref IS NULL
            SELECT @ref = MAX(reading_timestamp)
            FROM [dbo].[METER_READING]
            WHERE obis_code IN ('1.8.0', '2.8.0') AND status IN ('VALID', 'ESTIMATED', 'EDITED');
        IF @ref IS NULL
            THROW 50001, 'There are no VEE-verified readings yet.', 1;

        -- 2. the meters of every level-1 transformer at that slot (missing readings are simply not there)
        CREATE TABLE #Leaf (transformer_id INT NOT NULL, obis_code VARCHAR(20) NOT NULL,
                            sum_value DECIMAL(20,4) NOT NULL, meter_count INT NOT NULL,
                            PRIMARY KEY (transformer_id, obis_code));
        CREATE TABLE #State (transformer_id INT NOT NULL, obis_code VARCHAR(20) NOT NULL,
                             sum_value DECIMAL(20,4) NOT NULL, meter_count INT NOT NULL,
                             PRIMARY KEY (transformer_id, obis_code));

        INSERT INTO #Leaf (transformer_id, obis_code, sum_value, meter_count)
        SELECT m.transformer_id, r.obis_code, SUM(ISNULL(r.delta_value, 0)), COUNT(DISTINCT r.meter_id)
        FROM [dbo].[METER_READING] AS r
        JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
        WHERE r.obis_code IN ('1.8.0', '2.8.0')
          AND r.reading_timestamp = @ref
          AND r.status IN ('VALID', 'ESTIMATED', 'EDITED')
        GROUP BY m.transformer_id, r.obis_code;

        -- 3. every level, from the leaves up
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT transformer_id FROM [dbo].[TRANSFORMER] WHERE parent_transformer_id IS NULL;
        OPEN c;
        FETCH NEXT FROM c INTO @root;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC [dbo].[sp__SumSubtree] @root, '1.8.0';
            EXEC [dbo].[sp__SumSubtree] @root, '2.8.0';
            FETCH NEXT FROM c INTO @root;
        END
        CLOSE c;
        DEALLOCATE c;

        -- 4. one short write
        BEGIN TRANSACTION;
        MERGE [dbo].[TRANSFORMER_CURRENT_STATE] AS tgt
        USING #State AS src
           ON tgt.transformer_id = src.transformer_id AND tgt.obis_code = src.obis_code
        WHEN MATCHED THEN
            UPDATE SET reference_15_min = @ref, sum_value = src.sum_value,
                       meter_count = src.meter_count, computed_at = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (reference_15_min, sum_value, meter_count, transformer_id, obis_code)
            VALUES (@ref, src.sum_value, src.meter_count, src.transformer_id, src.obis_code);
        SET @rows = @@ROWCOUNT;

        SET @comment = N'rows ' + CAST(@rows AS NVARCHAR(10));
        EXEC [dbo].[sp__Log] 'TREE_REFRESH', 'TRANSFORMER_CURRENT_STATE', '0', NULL, @ref, @comment;
        COMMIT TRANSACTION;

        EXEC sys.sp_releaseapplock @Resource = N'TREE_REFRESH', @LockOwner = 'Session';
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'c') >= 0 CLOSE c;
        IF CURSOR_STATUS('local', 'c') >= -1 DEALLOCATE c;
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_releaseapplock @Resource = N'TREE_REFRESH', @LockOwner = 'Session';
        THROW;
    END CATCH

    SELECT @ref AS reference_15_min, @rows AS rows_written;
END;
GO

-- [project.pdf §4.2 p.10: a reading affects an L1 geofence and its ancestors]
-- Recomputes one level-1 node from its meters, then walks up: each parent = the sum of its children's rows.
CREATE OR ALTER PROCEDURE [dbo].[sp_RefreshTransformerAncestors]
    @actor_user_id    INT,
    @transformer_id   INT,
    @reference_15_min DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TSO,DSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'TREE_REFRESH';

    DECLARE @ref DATETIME2(0) = [dbo].[fn_Floor15](@reference_15_min);
    DECLARE @cur INT, @rc INT, @steps INT = 0, @nodes INT = 0;

    IF @ref IS NULL
        THROW 50004, 'Invalid input: the reference slot is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE transformer_id = @transformer_id AND [level] = 1)
        THROW 50001, 'Level-1 transformer not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC @rc = sys.sp_getapplock @Resource = N'TREE_REFRESH', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @rc < 0
            THROW 50007, 'Busy: the tree refresh is already running.', 1;

        -- the level-1 node from its own meters
        MERGE [dbo].[TRANSFORMER_CURRENT_STATE] AS tgt
        USING (SELECT o.obis_code,
                      ISNULL(SUM(r.delta_value), 0) AS sum_value, COUNT(DISTINCT r.meter_id) AS meter_count
               FROM (VALUES ('1.8.0'), ('2.8.0')) AS o(obis_code)
               LEFT JOIN ([dbo].[METER_READING] AS r
                          JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id AND m.transformer_id = @transformer_id)
                      ON r.obis_code = o.obis_code AND r.reading_timestamp = @ref
                     AND r.status IN ('VALID', 'ESTIMATED', 'EDITED')
               GROUP BY o.obis_code) AS src
           ON tgt.transformer_id = @transformer_id AND tgt.obis_code = src.obis_code
        WHEN MATCHED THEN
            UPDATE SET reference_15_min = @ref, sum_value = src.sum_value, meter_count = src.meter_count, computed_at = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (reference_15_min, sum_value, meter_count, transformer_id, obis_code)
            VALUES (@ref, src.sum_value, src.meter_count, @transformer_id, src.obis_code);
        SET @nodes = 1;

        -- the ancestors, one level at a time
        SELECT @cur = parent_transformer_id FROM [dbo].[TRANSFORMER] WHERE transformer_id = @transformer_id;
        WHILE @cur IS NOT NULL AND @steps < 50
        BEGIN
            MERGE [dbo].[TRANSFORMER_CURRENT_STATE] AS tgt
            USING (SELECT o.obis_code, ISNULL(SUM(s.sum_value), 0) AS sum_value, ISNULL(SUM(s.meter_count), 0) AS meter_count
                   FROM (VALUES ('1.8.0'), ('2.8.0')) AS o(obis_code)
                   LEFT JOIN ([dbo].[TRANSFORMER_CURRENT_STATE] AS s
                              JOIN [dbo].[TRANSFORMER] AS ch ON ch.transformer_id = s.transformer_id AND ch.parent_transformer_id = @cur)
                          ON s.obis_code = o.obis_code
                   GROUP BY o.obis_code) AS src
               ON tgt.transformer_id = @cur AND tgt.obis_code = src.obis_code
            WHEN MATCHED THEN
                UPDATE SET reference_15_min = @ref, sum_value = src.sum_value, meter_count = src.meter_count, computed_at = SYSUTCDATETIME()
            WHEN NOT MATCHED BY TARGET THEN
                INSERT (reference_15_min, sum_value, meter_count, transformer_id, obis_code)
                VALUES (@ref, src.sum_value, src.meter_count, @cur, src.obis_code);

            SET @nodes = @nodes + 1;
            SET @steps = @steps + 1;
            SELECT @cur = parent_transformer_id FROM [dbo].[TRANSFORMER] WHERE transformer_id = @cur;
        END

        EXEC [dbo].[sp__Log] 'TREE_REFRESH_PATH', 'TRANSFORMER', @transformer_id, NULL, @ref;
        COMMIT TRANSACTION;
        SELECT @transformer_id AS transformer_id, @ref AS reference_15_min, @nodes AS nodes_updated;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §II.Δ p.3; §4.2 p.10: the current load of every transformer; UC-17]
-- load % = (kWh of the 15-min slot x 4 = average kW) / capacity (kVA) x 100.
CREATE OR ALTER PROCEDURE [dbo].[sp_GetTransformerState]
    @actor_user_id INT,
    @root_id       INT = NULL,
    @level         TINYINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TSO,DSO';

    DECLARE @scope TABLE (transformer_id INT PRIMARY KEY);
    IF @root_id IS NULL
        INSERT INTO @scope SELECT transformer_id FROM [dbo].[TRANSFORMER];
    ELSE
        INSERT INTO @scope SELECT transformer_id FROM [dbo].[fn_TransformerSubtree](@root_id);

    SELECT t.transformer_id, t.name, t.[level], t.parent_transformer_id, t.capacity_kva,
           imp.reference_15_min, imp.sum_value AS import_kwh, ex.sum_value AS export_kwh,
           imp.meter_count, imp.computed_at,
           CAST(imp.sum_value * 4 / t.capacity_kva * 100 AS DECIMAL(9,2)) AS load_pct,
           f.[value] AS frequency_hz, f.reading_timestamp AS frequency_at
    FROM @scope AS s
    JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = s.transformer_id
    LEFT JOIN [dbo].[TRANSFORMER_CURRENT_STATE] AS imp ON imp.transformer_id = t.transformer_id AND imp.obis_code = '1.8.0'
    LEFT JOIN [dbo].[TRANSFORMER_CURRENT_STATE] AS ex  ON ex.transformer_id  = t.transformer_id AND ex.obis_code  = '2.8.0'
    OUTER APPLY (SELECT TOP (1) tr.[value], tr.reading_timestamp
                 FROM [dbo].[TRANSFORMER_READING] AS tr
                 WHERE tr.transformer_id = t.transformer_id AND tr.obis_code = '14.7.0'
                 ORDER BY tr.reading_timestamp DESC) AS f
    WHERE (@level IS NULL OR t.[level] = @level)
    ORDER BY t.[level] DESC, t.name;
END;
GO

-- [project.pdf §II.Δ p.3: measurements of the grid equipment; §1.4 p.7: kept for ever]
-- Grid equipment (no @actor_user_id, mechanism DEVICE) or DSO. For 1.8.0 / 2.8.0 the value is the
-- energy of the 15-min slot. Frequency more than 0.2 Hz away from 50 Hz -> EVENT FREQUENCY_DEVIATION.
CREATE OR ALTER PROCEDURE [dbo].[sp_RecordTransformerReading]
    @actor_user_id     INT = NULL,
    @transformer_id    INT,
    @reading_timestamp DATETIME2(0),
    @obis_code         VARCHAR(20),
    @value             DECIMAL(18,4)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @actor_user_id IS NOT NULL
    BEGIN
        EXEC [dbo].[sp__AssertRole] @actor_user_id, N'DSO';
        EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_RecordTransformerReading';
    END
    ELSE
        EXEC [dbo].[sp__SetActor] NULL, 'DEVICE';

    IF NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE transformer_id = @transformer_id)
        THROW 50001, 'Transformer not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[OBIS_CODE] WHERE obis_code = @obis_code)
        THROW 50004, 'Invalid input: unknown OBIS code.', 1;
    IF @reading_timestamp IS NULL OR @value IS NULL
        THROW 50004, 'Invalid input: timestamp and value are required.', 1;

    DECLARE @slot DATETIME2(0) = [dbo].[fn_Floor15](@reading_timestamp), @new_id BIGINT;
    IF EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER_READING]
               WHERE transformer_id = @transformer_id AND obis_code = @obis_code AND reading_timestamp = @slot)
        THROW 50005, 'Duplicate: this transformer already has a reading of this code in this slot.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[TRANSFORMER_READING] (reading_timestamp, [value], transformer_id, obis_code)
        VALUES (@slot, @value, @transformer_id, @obis_code);
        SET @new_id = SCOPE_IDENTITY();

        IF @obis_code = '14.7.0' AND ABS(@value - 50) > 0.2
            INSERT INTO [dbo].[EVENT] (event_timestamp, event_type, severity, description, transformer_id)
            VALUES (@reading_timestamp, 'FREQUENCY_DEVIATION', 'CRITICAL',
                    N'Frequency ' + CAST(@value AS NVARCHAR(30)) + N' Hz (nominal 50 Hz, allowed +/- 0.2 Hz).', @transformer_id);
        COMMIT TRANSACTION;
        SELECT @new_id AS transformer_reading_id, @slot AS reading_timestamp;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: this transformer already has a reading of this code in this slot.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §II.Γ p.3: voltage sags and swells for the DSO; UC-19]
-- Per meter under the transformer: readings outside 207 - 253 V and the events raised at ingestion.
CREATE OR ALTER PROCEDURE [dbo].[sp_ReportVoltageEvents]
    @actor_user_id       INT,
    @root_transformer_id INT,
    @from                DATETIME2(0),
    @to                  DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'DSO';

    IF NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE transformer_id = @root_transformer_id)
        THROW 50001, 'Transformer not found.', 1;
    IF @from IS NULL OR @to IS NULL OR @to <= @from
        THROW 50004, 'Invalid input: the window must have from < to.', 1;

    SELECT t.transformer_id, t.name AS transformer_name, m.meter_id, m.serial_number,
           ISNULL(v.sag_readings, 0)   AS sag_readings,
           ISNULL(v.swell_readings, 0) AS swell_readings,
           v.min_voltage, v.max_voltage,
           ISNULL(e.sag_events, 0)   AS sag_events,
           ISNULL(e.swell_events, 0) AS swell_events
    FROM [dbo].[fn_TransformerSubtree](@root_transformer_id) AS s
    JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = s.transformer_id
    JOIN [dbo].[METER] AS m ON m.transformer_id = t.transformer_id
    OUTER APPLY (SELECT SUM(CASE WHEN r.[value] < 207 THEN 1 ELSE 0 END) AS sag_readings,
                        SUM(CASE WHEN r.[value] > 253 THEN 1 ELSE 0 END) AS swell_readings,
                        MIN(r.[value]) AS min_voltage, MAX(r.[value]) AS max_voltage
                 FROM [dbo].[METER_READING] AS r
                 WHERE r.meter_id = m.meter_id AND r.obis_code IN ('32.7.0', '52.7.0', '72.7.0')
                   AND r.reading_timestamp >= @from AND r.reading_timestamp < @to) AS v
    OUTER APPLY (SELECT SUM(CASE WHEN ev.event_type = 'VOLTAGE_SAG' THEN 1 ELSE 0 END) AS sag_events,
                        SUM(CASE WHEN ev.event_type = 'VOLTAGE_SWELL' THEN 1 ELSE 0 END) AS swell_events
                 FROM [dbo].[EVENT] AS ev
                 WHERE ev.meter_id = m.meter_id AND ev.event_type IN ('VOLTAGE_SAG', 'VOLTAGE_SWELL')
                   AND ev.event_timestamp >= @from AND ev.event_timestamp < @to) AS e
    WHERE ISNULL(v.sag_readings, 0) + ISNULL(v.swell_readings, 0) + ISNULL(e.sag_events, 0) + ISNULL(e.swell_events, 0) > 0
    ORDER BY t.name, m.meter_id;
END;
GO

-- [project.pdf §II.Γ p.3: phase unbalance; Appendix p.15: the three phase currents; UC-19]
-- Three-phase meters: per slot, unbalance % = (max - min) / average x 100 of 31.7.0 / 51.7.0 / 71.7.0.
-- @raise_events = 1 also writes one PHASE_UNBALANCE event per meter (its worst slot).
CREATE OR ALTER PROCEDURE [dbo].[sp_ReportPhaseUnbalance]
    @actor_user_id       INT,
    @root_transformer_id INT,
    @from                DATETIME2(0),
    @to                  DATETIME2(0),
    @threshold_pct       DECIMAL(6,2) = 20,
    @raise_events        BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'DSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_ReportPhaseUnbalance';

    IF NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE transformer_id = @root_transformer_id)
        THROW 50001, 'Transformer not found.', 1;
    IF @from IS NULL OR @to IS NULL OR @to <= @from
        THROW 50004, 'Invalid input: the window must have from < to.', 1;
    SET @threshold_pct = ISNULL(@threshold_pct, 20);

    SELECT x.transformer_id, x.meter_id, x.reading_timestamp, x.l1, x.l2, x.l3,
           CAST((mx.hi - mx.lo) / ((x.l1 + x.l2 + x.l3) / 3) * 100 AS DECIMAL(9,2)) AS unbalance_pct
    INTO #Unbalance
    FROM (SELECT m.transformer_id, r.meter_id, r.reading_timestamp,
                 MAX(CASE WHEN r.obis_code = '31.7.0' THEN r.[value] END) AS l1,
                 MAX(CASE WHEN r.obis_code = '51.7.0' THEN r.[value] END) AS l2,
                 MAX(CASE WHEN r.obis_code = '71.7.0' THEN r.[value] END) AS l3
          FROM [dbo].[fn_TransformerSubtree](@root_transformer_id) AS s
          JOIN [dbo].[METER] AS m ON m.transformer_id = s.transformer_id
          JOIN [dbo].[METER_TYPE] AS mt ON mt.meter_type_id = m.meter_type_id AND mt.connection_phases = 3
          JOIN [dbo].[METER_READING] AS r ON r.meter_id = m.meter_id
          WHERE r.obis_code IN ('31.7.0', '51.7.0', '71.7.0')
            AND r.reading_timestamp >= @from AND r.reading_timestamp < @to
            AND r.status <> 'SUSPECT'
          GROUP BY m.transformer_id, r.meter_id, r.reading_timestamp) AS x
    CROSS APPLY (SELECT MAX(v.a) AS hi, MIN(v.a) AS lo FROM (VALUES (x.l1), (x.l2), (x.l3)) AS v(a)) AS mx
    WHERE x.l1 IS NOT NULL AND x.l2 IS NOT NULL AND x.l3 IS NOT NULL
      AND x.l1 + x.l2 + x.l3 > 0
      AND (mx.hi - mx.lo) / ((x.l1 + x.l2 + x.l3) / 3) * 100 > @threshold_pct;

    IF @raise_events = 1
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            INSERT INTO [dbo].[EVENT] (event_timestamp, event_type, severity, description, meter_id)
            SELECT w.reading_timestamp, 'PHASE_UNBALANCE', 'WARNING',
                   N'Phase unbalance ' + CAST(w.unbalance_pct AS NVARCHAR(20)) + N' % (threshold '
                   + CAST(@threshold_pct AS NVARCHAR(20)) + N' %).', w.meter_id
            FROM (SELECT u.*, ROW_NUMBER() OVER (PARTITION BY u.meter_id ORDER BY u.unbalance_pct DESC, u.reading_timestamp) AS rn
                  FROM #Unbalance AS u) AS w
            WHERE w.rn = 1
              AND NOT EXISTS (SELECT 1 FROM [dbo].[EVENT] AS e
                              WHERE e.meter_id = w.meter_id AND e.event_type = 'PHASE_UNBALANCE'
                                AND e.event_timestamp = w.reading_timestamp);
            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH
    END

    SELECT u.transformer_id, t.name AS transformer_name, u.meter_id, u.reading_timestamp,
           u.l1 AS current_l1, u.l2 AS current_l2, u.l3 AS current_l3, u.unbalance_pct
    FROM #Unbalance AS u
    JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = u.transformer_id
    ORDER BY u.unbalance_pct DESC, u.reading_timestamp;
END;
GO

-- [project.pdf §II.Γ p.3: technical losses, and losses that point to electricity theft; UC-19]
-- Input = what the transformer measured. Delivered = what its meters measured (import - export).
-- Loss above 8 % is flagged as a possible non-technical loss, next to the tamper alerts under the transformer.
CREATE OR ALTER PROCEDURE [dbo].[sp_ReportTechnicalLosses]
    @actor_user_id  INT,
    @transformer_id INT,
    @from           DATETIME2(0),
    @to             DATETIME2(0),
    @raise_events   BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'DSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_ReportTechnicalLosses';

    IF NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE transformer_id = @transformer_id AND [level] = 1)
        THROW 50001, 'Level-1 transformer not found.', 1;
    IF @from IS NULL OR @to IS NULL OR @to <= @from
        THROW 50004, 'Invalid input: the window must have from < to.', 1;

    DECLARE @input DECIMAL(20,4), @import DECIMAL(20,4), @export DECIMAL(20,4), @tamper INT;

    SELECT @input = ISNULL(SUM([value]), 0)
    FROM [dbo].[TRANSFORMER_READING]
    WHERE transformer_id = @transformer_id AND obis_code = '1.8.0'
      AND reading_timestamp >= @from AND reading_timestamp < @to;

    SELECT @import = ISNULL(SUM(CASE WHEN r.obis_code = '1.8.0' THEN r.delta_value END), 0),
           @export = ISNULL(SUM(CASE WHEN r.obis_code = '2.8.0' THEN r.delta_value END), 0)
    FROM [dbo].[METER] AS m
    JOIN [dbo].[METER_READING] AS r ON r.meter_id = m.meter_id
    WHERE m.transformer_id = @transformer_id AND r.obis_code IN ('1.8.0', '2.8.0')
      AND r.status <> 'SUSPECT'
      AND r.reading_timestamp >= @from AND r.reading_timestamp < @to;

    SELECT @tamper = COUNT(*)
    FROM [dbo].[EVENT] AS e
    JOIN [dbo].[METER] AS m ON m.meter_id = e.meter_id
    WHERE m.transformer_id = @transformer_id AND e.event_type = 'TAMPER_ALERT'
      AND e.event_timestamp >= @from AND e.event_timestamp < @to;

    DECLARE @delivered DECIMAL(20,4) = @import - @export;
    DECLARE @loss DECIMAL(20,4) = @input - @delivered;
    DECLARE @loss_pct DECIMAL(9,2) = CASE WHEN @input > 0 THEN @loss / @input * 100 END;

    IF @raise_events = 1 AND @loss_pct > 8
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            INSERT INTO [dbo].[EVENT] (event_timestamp, event_type, severity, description, transformer_id)
            VALUES (SYSUTCDATETIME(), 'TECHNICAL_LOSS_HIGH', 'WARNING',
                    N'Loss ' + CAST(@loss_pct AS NVARCHAR(20)) + N' % between ' + CONVERT(NVARCHAR(19), @from, 120)
                    + N' and ' + CONVERT(NVARCHAR(19), @to, 120) + N' (possible non-technical loss).', @transformer_id);
            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH
    END

    SELECT @transformer_id AS transformer_id, @from AS [from], @to AS [to],
           @input AS input_kwh, @import AS meters_import_kwh, @export AS meters_export_kwh,
           @delivered AS delivered_kwh, @loss AS loss_kwh, @loss_pct AS loss_pct,
           CAST(CASE WHEN @loss_pct > 8 THEN 1 ELSE 0 END AS BIT) AS possible_theft,
           @tamper AS tamper_alerts;
END;
GO

-- [project.pdf §II.Δ p.3: every 15 minutes the TSO sees an overall picture of the grid]
-- One row per transformer: current sums, load %, overload flag, latest frequency, recent critical events.
-- [AR: EVENT has no "closed" state, so "open" critical events = the critical events of the last 24 hours]
CREATE OR ALTER PROCEDURE [dbo].[sp_GetGridOverview]
    @actor_user_id    INT,
    @reference_15_min DATETIME2(0) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TSO';

    DECLARE @ref DATETIME2(0) = [dbo].[fn_Floor15](@reference_15_min);
    IF @ref IS NULL
        SELECT @ref = MAX(reference_15_min) FROM [dbo].[TRANSFORMER_CURRENT_STATE];
    DECLARE @since DATETIME2(0) = DATEADD(HOUR, -24, ISNULL(@ref, SYSUTCDATETIME()));

    SELECT t.transformer_id, t.name, t.[level], t.parent_transformer_id, t.capacity_kva,
           t.latitude, t.longitude,
           imp.reference_15_min, imp.sum_value AS import_kwh, ex.sum_value AS export_kwh, imp.meter_count,
           CAST(imp.sum_value * 4 / t.capacity_kva * 100 AS DECIMAL(9,2)) AS load_pct,
           CAST(CASE WHEN imp.sum_value * 4 > t.capacity_kva THEN 1 ELSE 0 END AS BIT) AS overloaded,
           f.[value] AS frequency_hz,
           (SELECT COUNT(*) FROM [dbo].[EVENT] AS e
            WHERE e.severity = 'CRITICAL' AND e.event_timestamp >= @since
              AND (e.transformer_id = t.transformer_id
                   OR e.meter_id IN (SELECT m.meter_id FROM [dbo].[METER] AS m WHERE m.transformer_id = t.transformer_id))) AS critical_events_24h
    FROM [dbo].[TRANSFORMER] AS t
    LEFT JOIN [dbo].[TRANSFORMER_CURRENT_STATE] AS imp
           ON imp.transformer_id = t.transformer_id AND imp.obis_code = '1.8.0' AND imp.reference_15_min = @ref
    LEFT JOIN [dbo].[TRANSFORMER_CURRENT_STATE] AS ex
           ON ex.transformer_id = t.transformer_id AND ex.obis_code = '2.8.0' AND ex.reference_15_min = @ref
    OUTER APPLY (SELECT TOP (1) tr.[value]
                 FROM [dbo].[TRANSFORMER_READING] AS tr
                 WHERE tr.transformer_id = t.transformer_id AND tr.obis_code = '14.7.0'
                 ORDER BY tr.reading_timestamp DESC) AS f
    ORDER BY t.[level] DESC, t.name;
END;
GO

PRINT 'procedures_07_grid.sql: 11 procedures created.';
GO
