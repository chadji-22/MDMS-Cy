/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_12_generator.sql  -  Build Spec §12: the large synthetic data set
   [project.pdf §IV p.12: data "of the order of thousands of rows" for the performance tests]

   [AR: this is an administrator load tool, and the ONE place that writes tables directly instead of
        calling the per-row procedures: bulk speed matters, so everything is set-based. The user rows
        follow the logic of sp__NewUser (one random salt per user, fn_HashPassword). The guard triggers
        still fire, so the generated data obeys the same rules as data entered through the procedures.]

   What one call creates (a new batch "SYN<b>" each time, so it can be called again):
     * transformers: 1 per 40 meters at level 1, then levels 2, 3 and one level-4 root
     * @consumers consumers, each with one premise and one ACTIVE meter with 3 approved certificates
       (25 % prosumers, 10 % three-phase)
     * @days days of 15-minute readings up to yesterday: 1.8.0, 1.8.1, 1.8.2, 32.7.0 for every meter,
       2.8.0 for prosumers, 31.7.0 / 51.7.0 / 71.7.0 for three-phase meters; daily load curve with noise
     * every day except the last one is history that already went through VEE: final readings
       (about 0.5 % ESTIMATED, 0.1 % EDITED) with their final DAY (and complete MONTH) aggregates
     * the last day is raw, as if it just came from the meters: PENDING, about 0.5 % of the slots missing
       and 0.1 % spikes, so sp_RunVEE / sp_FinalizeReadings can be shown on a large set
   Readings are written in chunks of 100 meters x 1 day (about 45,000 rows) per transaction (lecture 20-67).
   All synthetic accounts use the password  Synthetic!23
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_GenerateSyntheticData]
    @actor_user_id INT,
    @consumers     INT = 2000,
    @days          INT = 30,
    @seed          INT = 342,
    @chunk_meters  INT = 100        -- meters per transaction (x 1 day x about 4.5 rows per slot); lower it when the log file is small
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'GENERATOR';

    IF @consumers IS NULL OR @consumers NOT BETWEEN 1 AND 100000 OR @days IS NULL OR @days NOT BETWEEN 1 AND 366
        THROW 50004, 'Invalid input: consumers must be 1 - 100000 and days 1 - 366.', 1;
    SET @seed = ISNULL(@seed, 342);
    IF @chunk_meters IS NULL OR @chunk_meters NOT BETWEEN 1 AND 1000 SET @chunk_meters = 100;

    DECLARE @rc INT;
    EXEC @rc = sys.sp_getapplock @Resource = N'GENERATOR', @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 10000;
    IF @rc < 0
        THROW 50007, 'Busy: the generator is already running.', 1;

    DECLARE @t_begin DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @end DATETIME2(0) = CAST(CAST(@now AS DATE) AS DATETIME2(0));        -- today 00:00 UTC, exclusive
    DECLARE @start DATETIME2(0) = DATEADD(DAY, -@days, @end);
    DECLARE @raw_day DATETIME2(0) = DATEADD(DAY, -1, @end);                       -- the last day stays raw
    DECLARE @installed DATETIME2(0) = DATEADD(DAY, -1, @start);
    DECLARE @pw NVARCHAR(128) = N'Synthetic!23';
    DECLARE @batch INT, @prefix NVARCHAR(20), @root INT, @n1 INT, @n2 INT, @n3 INT;
    DECLARE @sup_a INT, @sup_b INT, @agg INT, @type1 INT, @type3 INT;
    DECLARE @day DATETIME2(0), @lo INT, @is_raw BIT, @readings BIGINT = 0, @aggregates BIGINT = 0, @comment NVARCHAR(500);

    BEGIN TRY
        SELECT @batch = COUNT(*) + 1 FROM [dbo].[TRANSFORMER] WHERE name LIKE N'SYN%-L4';
        SET @prefix = N'SYN' + CAST(@batch AS NVARCHAR(10));
        SET @n1 = (@consumers + 39) / 40;
        SET @n2 = (@n1 + 3) / 4;
        SET @n3 = (@n2 + 3) / 4;

        -- numbers 1 .. @consumers, and the 96 slots of a day
        CREATE TABLE #n (n INT NOT NULL PRIMARY KEY);
        WITH d AS (SELECT v FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS x(v))
        INSERT INTO #n (n)
        SELECT TOP (@consumers) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
        FROM d AS a CROSS JOIN d AS b CROSS JOIN d AS c CROSS JOIN d AS e CROSS JOIN d AS f;
        CREATE TABLE #slot (n INT NOT NULL PRIMARY KEY);
        INSERT INTO #slot (n) SELECT n - 1 FROM #n WHERE n <= 96;
        IF @consumers < 96
            INSERT INTO #slot (n)
            SELECT x.n FROM (SELECT TOP (96) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
                             FROM sys.all_columns) AS x
            WHERE NOT EXISTS (SELECT 1 FROM #slot AS s WHERE s.n = x.n);

        /* ---- reference rows the batch needs --------------------------------------------------- */
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM [dbo].[ORGANIZATION] WHERE name = N'SYN Supplier A')
            INSERT INTO [dbo].[ORGANIZATION] (name, org_type) VALUES (N'SYN Supplier A', 'SUPPLIER');
        IF NOT EXISTS (SELECT 1 FROM [dbo].[ORGANIZATION] WHERE name = N'SYN Supplier B')
            INSERT INTO [dbo].[ORGANIZATION] (name, org_type) VALUES (N'SYN Supplier B', 'SUPPLIER');
        IF NOT EXISTS (SELECT 1 FROM [dbo].[ORGANIZATION] WHERE name = N'SYN Aggregator')
            INSERT INTO [dbo].[ORGANIZATION] (name, org_type) VALUES (N'SYN Aggregator', 'AGGREGATOR');
        IF NOT EXISTS (SELECT 1 FROM [dbo].[METER_TYPE] WHERE type_name = 'SYN Single-Phase 1x60A')
            INSERT INTO [dbo].[METER_TYPE] (type_name, connection_phases, max_amps) VALUES ('SYN Single-Phase 1x60A', 1, 60);
        IF NOT EXISTS (SELECT 1 FROM [dbo].[METER_TYPE] WHERE type_name = 'SYN Three-Phase 3x80A')
            INSERT INTO [dbo].[METER_TYPE] (type_name, connection_phases, max_amps) VALUES ('SYN Three-Phase 3x80A', 3, 80);
        SELECT @sup_a = organization_id FROM [dbo].[ORGANIZATION] WHERE name = N'SYN Supplier A';
        SELECT @sup_b = organization_id FROM [dbo].[ORGANIZATION] WHERE name = N'SYN Supplier B';
        SELECT @agg   = organization_id FROM [dbo].[ORGANIZATION] WHERE name = N'SYN Aggregator';
        SELECT @type1 = meter_type_id FROM [dbo].[METER_TYPE] WHERE type_name = 'SYN Single-Phase 1x60A';
        SELECT @type3 = meter_type_id FROM [dbo].[METER_TYPE] WHERE type_name = 'SYN Three-Phase 3x80A';

        /* ---- transformer tree: root (L4) -> L3 -> L2 -> L1 (TR09 checks every row) -------------- */
        INSERT INTO [dbo].[TRANSFORMER] (name, [level], capacity_kva, latitude, longitude)
        VALUES (@prefix + N'-L4', 4, 50000, 35.000, 33.300);
        SET @root = SCOPE_IDENTITY();

        INSERT INTO [dbo].[TRANSFORMER] (name, [level], capacity_kva, latitude, longitude, parent_transformer_id)
        SELECT @prefix + N'-L3-' + RIGHT('0000' + CAST(n AS VARCHAR(10)), 4), 3, 10000,
               34.70 + (n % 50) * 0.010, 32.90 + (n % 90) * 0.010, @root
        FROM #n WHERE n <= @n3;

        INSERT INTO [dbo].[TRANSFORMER] (name, [level], capacity_kva, latitude, longitude, parent_transformer_id)
        SELECT @prefix + N'-L2-' + RIGHT('0000' + CAST(x.n AS VARCHAR(10)), 4), 2, 2500,
               34.70 + (x.n % 50) * 0.010, 32.90 + (x.n % 90) * 0.010, p.transformer_id
        FROM #n AS x
        JOIN [dbo].[TRANSFORMER] AS p ON p.name = @prefix + N'-L3-' + RIGHT('0000' + CAST((x.n - 1) / 4 + 1 AS VARCHAR(10)), 4)
        WHERE x.n <= @n2;

        INSERT INTO [dbo].[TRANSFORMER] (name, [level], capacity_kva, latitude, longitude, parent_transformer_id)
        SELECT @prefix + N'-L1-' + RIGHT('0000' + CAST(x.n AS VARCHAR(10)), 4), 1, 400,
               34.70 + (x.n % 50) * 0.010, 32.90 + (x.n % 90) * 0.010, p.transformer_id
        FROM #n AS x
        JOIN [dbo].[TRANSFORMER] AS p ON p.name = @prefix + N'-L2-' + RIGHT('0000' + CAST((x.n - 1) / 4 + 1 AS VARCHAR(10)), 4)
        WHERE x.n <= @n1;

        /* ---- consumers: the logic of sp__NewUser in set form (salt first, then the hash) -------- */
        CREATE TABLE #u (n INT NOT NULL PRIMARY KEY, email VARCHAR(255) NOT NULL, salt VARBINARY(16) NOT NULL);
        INSERT INTO #u (n, email, salt)
        SELECT n, LOWER(@prefix) + '_' + RIGHT('000000' + CAST(n AS VARCHAR(10)), 6) + '@synthetic.cy', CRYPT_GEN_RANDOM(16)
        FROM #n;

        INSERT INTO [dbo].[USER_ACCOUNT] (email, password_hash, password_salt, full_name, approval_status, role_code)
        SELECT u.email, [dbo].[fn_HashPassword](@pw, u.salt), u.salt,
               N'Synthetic Consumer ' + CAST(@batch AS NVARCHAR(10)) + N'-' + RIGHT('000000' + CAST(u.n AS VARCHAR(10)), 6),
               'APPROVED', 'CONSUMER'
        FROM #u AS u;

        /* ---- premises (TR07) ------------------------------------------------------------------- */
        INSERT INTO [dbo].[PREMISE] (address, latitude, longitude, usage_type, district, municipality, parish, postal_code,
                                     prosumer_scheme, user_id, supplier_org_id, aggregator_org_id)
        SELECT @prefix + N' premise ' + RIGHT('000000' + CAST(u.n AS VARCHAR(10)), 6),
               dd.lat + ((u.n * 37) % 100) * 0.0005, dd.lon + ((u.n * 53) % 100) * 0.0005,
               CASE u.n % 10 WHEN 0 THEN 'COMMERCIAL' WHEN 5 THEN 'INDUSTRIAL' WHEN 7 THEN 'AGRICULTURAL' ELSE 'RESIDENTIAL' END,
               dd.district, dd.district, N'SYN', RIGHT('0000' + CAST(1000 + u.n % 9000 AS VARCHAR(10)), 4),
               CASE WHEN u.n % 8 = 0 THEN 'NET_BILLING' WHEN u.n % 4 = 0 THEN 'NET_METERING' ELSE 'NONE' END,
               a.user_id, CASE WHEN u.n % 2 = 0 THEN @sup_a ELSE @sup_b END, CASE WHEN u.n % 5 = 0 THEN @agg END
        FROM #u AS u
        JOIN [dbo].[USER_ACCOUNT] AS a ON a.email = u.email
        JOIN (VALUES (0, N'Λευκωσία', 35.10, 33.30), (1, N'Λεμεσός', 34.65, 33.00), (2, N'Λάρνακα', 34.90, 33.60),
                     (3, N'Πάφος', 34.75, 32.40), (4, N'Αμμόχωστος', 35.00, 33.90), (5, N'Κερύνεια', 35.30, 33.30)
             ) AS dd(k, district, lat, lon) ON dd.k = u.n % 6;

        /* ---- meters: PENDING, then 3 approved certificates, then ACTIVE (TR04, TR08) ------------ */
        INSERT INTO [dbo].[METER] (serial_number, network_id, firmware_version, communication_type, latitude, longitude,
                                   status, installed_at, meter_type_id, transformer_id, premise_id)
        SELECT @prefix + '-SN-' + RIGHT('000000' + CAST(u.n AS VARCHAR(10)), 6),
               @prefix + '-NET-' + RIGHT('000000' + CAST(u.n AS VARCHAR(10)), 6),
               'FW-1.0.0', CASE u.n % 3 WHEN 0 THEN 'CELLULAR' WHEN 1 THEN 'NB_IOT' ELSE 'PLC' END,
               p.latitude, p.longitude, 'PENDING', @installed,
               CASE WHEN u.n % 10 = 0 THEN @type3 ELSE @type1 END, t.transformer_id, p.premise_id
        FROM #u AS u
        JOIN [dbo].[PREMISE] AS p ON p.address = @prefix + N' premise ' + RIGHT('000000' + CAST(u.n AS VARCHAR(10)), 6)
        JOIN [dbo].[TRANSFORMER] AS t ON t.name = @prefix + N'-L1-' + RIGHT('0000' + CAST((u.n - 1) / 40 + 1 AS VARCHAR(10)), 4);

        CREATE TABLE #m (meter_id INT NOT NULL PRIMARY KEY, n INT NOT NULL, three_phase BIT NOT NULL, prosumer BIT NOT NULL, scale DECIMAL(9,4) NOT NULL);
        INSERT INTO #m (meter_id, n, three_phase, prosumer, scale)
        SELECT m.meter_id, u.n, CASE WHEN u.n % 10 = 0 THEN 1 ELSE 0 END, CASE WHEN u.n % 4 = 0 THEN 1 ELSE 0 END,
               0.60 + ((CHECKSUM(CAST(@seed AS BIGINT) * 7919 + u.n) & 2147483647) % 100) / 100.0
        FROM #u AS u
        JOIN [dbo].[METER] AS m ON m.serial_number = @prefix + '-SN-' + RIGHT('000000' + CAST(u.n AS VARCHAR(10)), 6);
        CREATE INDEX ix_m_n ON #m (n);

        INSERT INTO [dbo].[DOCUMENT] (doc_type, doc_code, issue_date, file_path, approval_status, meter_id)
        SELECT t.doc_type, @prefix + '-' + t.short + '-' + RIGHT('000000' + CAST(m.n AS VARCHAR(10)), 6),
               CAST(@installed AS DATE), '/uploads/synthetic/' + t.short + '.pdf', 'APPROVED', m.meter_id
        FROM #m AS m
        CROSS JOIN (VALUES ('CALIBRATION_CERT', 'CAL'), ('CE_DECLARATION', 'CE'), ('ENCRYPTION_CERT', 'ENC')) AS t(doc_type, short);

        UPDATE me
           SET status = 'ACTIVE', activated_at = @installed
        FROM [dbo].[METER] AS me JOIN #m AS m ON m.meter_id = me.meter_id;
        COMMIT TRANSACTION;

        /* ---- readings: day by day, 100 meters at a time ----------------------------------------- */
        CREATE TABLE #reg (meter_id INT NOT NULL PRIMARY KEY, r180 DECIMAL(18,4) NOT NULL, r181 DECIMAL(18,4) NOT NULL,
                           r182 DECIMAL(18,4) NOT NULL, r280 DECIMAL(18,4) NOT NULL);
        INSERT INTO #reg (meter_id, r180, r181, r182, r280) SELECT meter_id, 1000, 600, 400, 100 FROM #m;

        CREATE TABLE #d (meter_id INT NOT NULL, slot INT NOT NULL, ts DATETIME2(0) NOT NULL, three_phase BIT NOT NULL, prosumer BIT NOT NULL,
                         d180 DECIMAL(18,4) NOT NULL, peak BIT NOT NULL, d280 DECIMAL(18,4) NOT NULL, volt DECIMAL(18,4) NOT NULL,
                         i1 DECIMAL(18,4) NOT NULL, i2 DECIMAL(18,4) NOT NULL, i3 DECIMAL(18,4) NOT NULL,
                         gap BIT NOT NULL, spike BIT NOT NULL, PRIMARY KEY (meter_id, slot));

        SET @day = @start;
        WHILE @day < @end
        BEGIN
            SET @is_raw = CASE WHEN @day = @raw_day THEN 1 ELSE 0 END;
            SET @lo = 1;
            WHILE @lo <= @consumers
            BEGIN
                TRUNCATE TABLE #d;
                -- the 15-min values of this chunk: load curve x size of the customer x noise
                INSERT INTO #d (meter_id, slot, ts, three_phase, prosumer, d180, peak, d280, volt, i1, i2, i3, gap, spike)
                SELECT m.meter_id, s.n, t.ts, m.three_phase, m.prosumer,
                       CAST(c.base * m.scale * (0.85 + 0.30 * r.r1) AS DECIMAL(18,4)),
                       CASE WHEN h.hr BETWEEN 7 AND 22 THEN 1 ELSE 0 END,
                       CAST(CASE WHEN m.prosumer = 1 AND h.hr BETWEEN 9 AND 16 THEN 0.20 * (0.5 + r.r2) ELSE 0 END AS DECIMAL(18,4)),
                       CAST(225 + 10 * r.r3 AS DECIMAL(18,4)),
                       CAST(5 + 10 * r.r1 AS DECIMAL(18,4)), CAST(5 + 10 * r.r2 AS DECIMAL(18,4)), CAST(5 + 10 * r.r3 AS DECIMAL(18,4)),
                       CASE WHEN s.n > 0 AND r.r4 < 0.005 THEN 1 ELSE 0 END,
                       CASE WHEN s.n > 0 AND r.r4 >= 0.999 THEN 1 ELSE 0 END
                FROM #m AS m
                CROSS JOIN #slot AS s
                CROSS APPLY (SELECT DATEADD(MINUTE, 15 * s.n, @day) AS ts) AS t
                CROSS APPLY (SELECT DATEPART(HOUR, t.ts) AS hr, DATEDIFF(MINUTE, '2020-01-01', t.ts) / 15 AS q) AS h
                CROSS APPLY (SELECT CASE WHEN h.hr < 6 THEN 0.08 WHEN h.hr < 9 THEN 0.25 WHEN h.hr < 17 THEN 0.18
                                         WHEN h.hr < 22 THEN 0.40 ELSE 0.15 END AS base) AS c
                -- repeatable pseudo-random numbers in [0, 1) from (seed, meter, slot): a linear step modulo the
                -- prime 1000003, then squared modulo the same prime (CHECKSUM alone gives clustered values)
                CROSS APPLY (SELECT (CAST(@seed AS BIGINT) * 7919 + CAST(m.meter_id AS BIGINT) * 104729) % 1000003 AS k,
                                    CAST(h.q AS BIGINT) AS q) AS key1
                CROSS APPLY (SELECT (key1.k + key1.q * 15485863) % 1000003 AS x1, (key1.k * 3 + key1.q * 32452843) % 1000003 AS x2,
                                    (key1.k * 5 + key1.q * 49979687) % 1000003 AS x3, (key1.k * 7 + key1.q * 67867967) % 1000003 AS x4) AS lin
                CROSS APPLY (SELECT ((lin.x1 * lin.x1 + 11) % 1000003) / 1000003.0 AS r1,
                                    ((lin.x2 * lin.x2 + 23) % 1000003) / 1000003.0 AS r2,
                                    ((lin.x3 * lin.x3 + 37) % 1000003) / 1000003.0 AS r3,
                                    ((lin.x4 * lin.x4 + 41) % 1000003) / 1000003.0 AS r4) AS r
                WHERE m.n BETWEEN @lo AND @lo + @chunk_meters - 1;

                BEGIN TRANSACTION;
                WITH x AS (
                    SELECT d.*,
                           SUM(d.d180) OVER (PARTITION BY d.meter_id ORDER BY d.slot ROWS UNBOUNDED PRECEDING) AS c180,
                           SUM(CASE WHEN d.peak = 1 THEN d.d180 ELSE 0 END) OVER (PARTITION BY d.meter_id ORDER BY d.slot ROWS UNBOUNDED PRECEDING) AS c181,
                           SUM(CASE WHEN d.peak = 0 THEN d.d180 ELSE 0 END) OVER (PARTITION BY d.meter_id ORDER BY d.slot ROWS UNBOUNDED PRECEDING) AS c182,
                           SUM(d.d280) OVER (PARTITION BY d.meter_id ORDER BY d.slot ROWS UNBOUNDED PRECEDING) AS c280,
                           ISNULL(LAG(CAST(d.gap AS INT))   OVER (PARTITION BY d.meter_id ORDER BY d.slot), 0) AS prev_gap,
                           ISNULL(LAG(CAST(d.spike AS INT)) OVER (PARTITION BY d.meter_id ORDER BY d.slot), 0) AS prev_spike
                    FROM #d AS d)
                INSERT INTO [dbo].[METER_READING]
                    (reading_timestamp, [value], delta_value, status, original_value, vee_rule, vee_note,
                     is_final, finalized_at, meter_id, obis_code, packet_id, edited_by_user_id)
                SELECT x.ts,
                       -- raw day: a spike shows as a register value that is 25.4 kWh too high for one slot
                       v.val + CASE WHEN @is_raw = 1 AND v.obis = '1.8.0' AND x.spike = 1 THEN 25.4 ELSE 0 END,
                       CASE WHEN v.cum = 0 THEN NULL
                            WHEN @is_raw = 0 THEN v.delta
                            WHEN x.prev_gap = 1 THEN NULL                                  -- as at ingestion: no previous slot
                            WHEN v.obis = '1.8.0' THEN v.delta + 25.4 * CAST(x.spike AS INT) - 25.4 * x.prev_spike
                            ELSE v.delta END,
                       CASE WHEN @is_raw = 1 THEN 'PENDING'
                            WHEN v.cum = 1 AND x.gap = 1 THEN 'ESTIMATED'
                            WHEN v.obis = '1.8.0' AND x.spike = 1 THEN 'EDITED'
                            ELSE 'VALID' END,
                       CASE WHEN @is_raw = 0 AND v.obis = '1.8.0' AND x.spike = 1 AND x.gap = 0 THEN v.val + 25.4 END,
                       CASE WHEN @is_raw = 1 THEN NULL
                            WHEN v.cum = 1 AND x.gap = 1 THEN 'LINEAR_INTERPOLATION'
                            WHEN v.obis = '1.8.0' AND x.spike = 1 THEN 'MANUAL_EDIT'
                            ELSE 'AUTO' END,
                       CASE WHEN @is_raw = 0 AND (x.gap = 1 OR (v.obis = '1.8.0' AND x.spike = 1)) THEN N'synthetic history' END,
                       CASE WHEN @is_raw = 1 THEN 0 ELSE 1 END,
                       CASE WHEN @is_raw = 1 THEN NULL ELSE @now END,
                       x.meter_id, v.obis, NULL,
                       CASE WHEN @is_raw = 0 AND v.obis = '1.8.0' AND x.spike = 1 AND x.gap = 0 THEN @actor_user_id END
                FROM x
                JOIN #reg AS g ON g.meter_id = x.meter_id
                CROSS APPLY (VALUES
                    ('1.8.0',  g.r180 + x.c180, x.d180, 1, 1),
                    ('1.8.1',  g.r181 + x.c181, CASE WHEN x.peak = 1 THEN x.d180 ELSE 0 END, 1, 1),
                    ('1.8.2',  g.r182 + x.c182, CASE WHEN x.peak = 0 THEN x.d180 ELSE 0 END, 1, 1),
                    ('2.8.0',  g.r280 + x.c280, x.d280, 1, CAST(x.prosumer AS INT)),
                    ('32.7.0', x.volt, NULL, 0, 1),
                    ('31.7.0', x.i1,   NULL, 0, CAST(x.three_phase AS INT)),
                    ('51.7.0', x.i2,   NULL, 0, CAST(x.three_phase AS INT)),
                    ('71.7.0', x.i3,   NULL, 0, CAST(x.three_phase AS INT))
                ) AS v(obis, val, delta, cum, applies)
                WHERE v.applies = 1
                  AND NOT (@is_raw = 1 AND x.gap = 1);                                    -- raw day: the packet never arrived
                SET @readings = @readings + @@ROWCOUNT;

                -- history days: their final DAY aggregates
                IF @is_raw = 0
                BEGIN
                    INSERT INTO [dbo].[AGGREGATE] (period_type, period_start, [value], sample_count, is_final, calculated_at, meter_id, obis_code)
                    SELECT 'DAY', @day, SUM(v.delta), COUNT(*), 1, @now, d.meter_id, v.obis
                    FROM #d AS d
                    CROSS APPLY (VALUES
                        ('1.8.0', d.d180, 1),
                        ('1.8.1', CASE WHEN d.peak = 1 THEN d.d180 ELSE 0 END, 1),
                        ('1.8.2', CASE WHEN d.peak = 0 THEN d.d180 ELSE 0 END, 1),
                        ('2.8.0', d.d280, CAST(d.prosumer AS INT))
                    ) AS v(obis, delta, applies)
                    WHERE v.applies = 1
                    GROUP BY d.meter_id, v.obis;
                    SET @aggregates = @aggregates + @@ROWCOUNT;
                END

                -- the registers at the end of the day
                UPDATE g
                   SET r180 = g.r180 + t.s180, r181 = g.r181 + t.s181, r182 = g.r182 + t.s182, r280 = g.r280 + t.s280
                FROM #reg AS g
                JOIN (SELECT meter_id, SUM(d180) AS s180, SUM(CASE WHEN peak = 1 THEN d180 ELSE 0 END) AS s181,
                             SUM(CASE WHEN peak = 0 THEN d180 ELSE 0 END) AS s182, SUM(d280) AS s280
                      FROM #d GROUP BY meter_id) AS t ON t.meter_id = g.meter_id;
                COMMIT TRANSACTION;

                SET @lo = @lo + @chunk_meters;
            END
            SET @day = DATEADD(DAY, 1, @day);
        END

        /* ---- MONTH aggregates for the months that the history covers completely ------------------- */
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[AGGREGATE] (period_type, period_start, [value], sample_count, is_final, calculated_at, meter_id, obis_code)
        SELECT 'MONTH', mo.month_start, SUM(a.[value]), COUNT(*), 1, @now, a.meter_id, a.obis_code
        FROM [dbo].[AGGREGATE] AS a
        JOIN #m AS m ON m.meter_id = a.meter_id
        CROSS APPLY (SELECT CAST(DATEFROMPARTS(YEAR(a.period_start), MONTH(a.period_start), 1) AS DATETIME2(0)) AS month_start) AS mo
        WHERE a.period_type = 'DAY' AND a.is_final = 1
        GROUP BY a.meter_id, a.obis_code, mo.month_start
        HAVING COUNT(*) = DAY(EOMONTH(mo.month_start));
        SET @aggregates = @aggregates + @@ROWCOUNT;

        SET @comment = @prefix + N': consumers ' + CAST(@consumers AS NVARCHAR(10)) + N', days ' + CAST(@days AS NVARCHAR(10))
                     + N', readings ' + CAST(@readings AS NVARCHAR(20)) + N', aggregates ' + CAST(@aggregates AS NVARCHAR(20));
        EXEC [dbo].[sp__Log] 'GENERATE', 'METER_READING', '0', NULL, NULL, @comment;
        COMMIT TRANSACTION;

        EXEC sys.sp_releaseapplock @Resource = N'GENERATOR', @LockOwner = 'Session';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_releaseapplock @Resource = N'GENERATOR', @LockOwner = 'Session';
        THROW;
    END CATCH

    SELECT @prefix AS batch, @consumers AS consumers, @n1 + @n2 + @n3 + 1 AS transformers, @days AS days,
           @start AS readings_from, @end AS readings_to, @raw_day AS raw_day_for_vee,
           @readings AS readings, @aggregates AS aggregates,
           DATEDIFF(SECOND, @t_begin, SYSUTCDATETIME()) AS seconds;
END;
GO

PRINT 'procedures_12_generator.sql: 1 procedure created.';
GO
