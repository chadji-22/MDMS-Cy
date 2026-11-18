/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_00_internal.sql  -  Build Spec §9.0
   Internal helpers (sp__ prefix, two underscores). PHP never calls them;
   security.sql denies EXECUTE on them to the application role.
   They never open or commit a transaction: they run inside the caller's.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf Κοινές αρχές p.5: identify the user before every protected operation]
CREATE OR ALTER PROCEDURE [dbo].[sp__AssertRole]
    @user_id INT,
    @roles   NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    IF [dbo].[fn_UserHasRole](@user_id, @roles) = 0
        THROW 50002, 'Permission denied: your role or account status does not allow this operation.', 1;
END;
GO

-- [project.pdf Κοινές αρχές p.5: log the user who caused each change]
-- [AR: the web application uses one SQL login, so SELECT USER (lab 10) would always be the same;
--      the actor is kept in SESSION_CONTEXT and the audit triggers read it back]
CREATE OR ALTER PROCEDURE [dbo].[sp__SetActor]
    @user_id   INT,
    @mechanism VARCHAR(60)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @m NVARCHAR(60) = @mechanism;
    EXEC sys.sp_set_session_context @key = N'actor_user_id', @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'mechanism',     @value = @m;
END;
GO

-- [project.pdf Κοινές αρχές p.5: object, user or mechanism, time, old/new state, comment]
-- For log rows that no trigger writes (LOGIN, VEE_RUN, TREE_REFRESH, decision comments ...).
CREATE OR ALTER PROCEDURE [dbo].[sp__Log]
    @action      VARCHAR(50),
    @object_type VARCHAR(30),
    @object_id   VARCHAR(30),
    @old         NVARCHAR(200) = NULL,
    @new         NVARCHAR(200) = NULL,
    @comment     NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @actor INT = TRY_CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);
    DECLARE @mech  VARCHAR(60) = ISNULL(CAST(SESSION_CONTEXT(N'mechanism') AS VARCHAR(60)), 'DIRECT_SQL');

    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    VALUES (CASE WHEN @actor IS NOT NULL THEN 'USER' WHEN @mech = 'DEVICE' THEN 'DEVICE' ELSE 'SYSTEM' END,
            @mech, @action, @object_type, @object_id, @old, @new, @comment, @actor);
END;
GO

-- [project.pdf Κοινές αρχές p.5: unique account per person, password stored hashed; lecture 20-76]
-- Used by every registration procedure.
CREATE OR ALTER PROCEDURE [dbo].[sp__NewUser]
    @email           VARCHAR(255),
    @password        NVARCHAR(128),
    @full_name       NVARCHAR(150),
    @phone           VARCHAR(20),
    @role_code       VARCHAR(20),
    @approval_status VARCHAR(20),
    @organization_id INT           = NULL,
    @birth_date      DATE          = NULL,
    @photo_path      VARCHAR(500)  = NULL,
    @specialty       NVARCHAR(100) = NULL,
    @iban            VARCHAR(34)   = NULL,
    @new_id          INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @email = LOWER(LTRIM(RTRIM(@email)));

    IF @email IS NULL OR @email NOT LIKE '%_@_%._%' OR @email LIKE '% %'
        THROW 50004, 'Invalid input: the email address is not valid.', 1;
    IF @password IS NULL OR LEN(@password) < 8
        THROW 50004, 'Invalid input: the password needs at least 8 characters.', 1;
    IF @full_name IS NULL OR LTRIM(RTRIM(@full_name)) = N''
        THROW 50004, 'Invalid input: the full name is required.', 1;
    IF EXISTS (SELECT 1 FROM [dbo].[USER_ACCOUNT] WHERE email = @email)
        THROW 50005, 'Duplicate: this email is already registered.', 1;

    DECLARE @salt VARBINARY(16) = CRYPT_GEN_RANDOM(16);

    INSERT INTO [dbo].[USER_ACCOUNT]
        (email, password_hash, password_salt, full_name, phone, approval_status,
         iban, birth_date, photo_path, specialty, role_code, organization_id)
    VALUES
        (@email, [dbo].[fn_HashPassword](@password, @salt), @salt, LTRIM(RTRIM(@full_name)), @phone, @approval_status,
         @iban, @birth_date, @photo_path, @specialty, @role_code, @organization_id);

    SET @new_id = SCOPE_IDENTITY();
END;
GO

-- [project.pdf §4.1 p.9: hierarchy of arbitrary depth; lab 10 Hogwarts_Tree (template T4)]
-- #Tree is created by the caller (sp_GetTransformerTree).
CREATE OR ALTER PROCEDURE [dbo].[sp__WalkTransformerTree]
    @parent_id INT,
    @depth     INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT, @name NVARCHAR(100), @level TINYINT;
    DECLARE @next_depth INT = @depth + 1;                   -- EXEC takes variables, not expressions

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR                 -- LOCAL: each recursive call has its own cursor
        SELECT transformer_id, name, [level] FROM [dbo].[TRANSFORMER]
        WHERE parent_transformer_id = @parent_id
        ORDER BY name;
    OPEN c;
    FETCH NEXT FROM c INTO @id, @name, @level;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO #Tree (transformer_id, name, [level], depth, label)
        VALUES (@id, @name, @level, @depth, SPACE(@depth * 2) + CAST(@id AS NVARCHAR(10)) + N' ' + @name);
        EXEC [dbo].[sp__WalkTransformerTree] @id, @next_depth;     -- recursion, as in Hogwarts_Tree
        FETCH NEXT FROM c INTO @id, @name, @level;
    END
    CLOSE c;
    DEALLOCATE c;
END;
GO

-- [project.pdf §4.2 p.10: sums for every level of the hierarchy]
-- Recursive cursor in post-order: children first, then this node = its own meters (#Leaf)
-- plus the rows of its children in #State. Both temp tables are created by the caller.
CREATE OR ALTER PROCEDURE [dbo].[sp__SumSubtree]
    @transformer_id INT,
    @obis           VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @child INT;

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT transformer_id FROM [dbo].[TRANSFORMER] WHERE parent_transformer_id = @transformer_id;
    OPEN c;
    FETCH NEXT FROM c INTO @child;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [dbo].[sp__SumSubtree] @child, @obis;
        FETCH NEXT FROM c INTO @child;
    END
    CLOSE c;
    DEALLOCATE c;

    INSERT INTO #State (transformer_id, obis_code, sum_value, meter_count)
    SELECT @transformer_id, @obis,
           ISNULL((SELECT SUM(l.sum_value) FROM #Leaf AS l
                   WHERE l.transformer_id = @transformer_id AND l.obis_code = @obis), 0)
         + ISNULL((SELECT SUM(s.sum_value) FROM #State AS s
                   JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = s.transformer_id
                   WHERE t.parent_transformer_id = @transformer_id AND s.obis_code = @obis), 0),
           ISNULL((SELECT SUM(l.meter_count) FROM #Leaf AS l
                   WHERE l.transformer_id = @transformer_id AND l.obis_code = @obis), 0)
         + ISNULL((SELECT SUM(s.meter_count) FROM #State AS s
                   JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = s.transformer_id
                   WHERE t.parent_transformer_id = @transformer_id AND s.obis_code = @obis), 0);
END;
GO

-- [project.pdf §3.2 p.9: Estimation - a missing value is estimated from its neighbours (2.0 / ? / 2.2 -> 2.1)]
-- Gap step of Algorithm B. Cursor over the missing 15-min slots of one meter; linear interpolation
-- between the reading before and the reading after, both inside [@from, @to].
-- Slots with no reading on one side are left for a later run.
CREATE OR ALTER PROCEDURE [dbo].[sp__EstimateGaps]
    @meter_id  INT,
    @from      DATETIME2(0),
    @to        DATETIME2(0),
    @estimated INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @estimated = 0;

    DECLARE @first DATETIME2(0) = [dbo].[fn_Floor15](@from);
    IF @first < @from SET @first = DATEADD(MINUTE, 15, @first);
    IF @to < @first RETURN;

    CREATE TABLE #missing (obis_code VARCHAR(20) NOT NULL, slot DATETIME2(0) NOT NULL, PRIMARY KEY (obis_code, slot));

    -- expected slots of the window (tally CTE: works on every SQL Server version) minus the slots that exist
    WITH d AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS v(n)),
    tally AS (
        SELECT TOP (DATEDIFF(MINUTE, @first, @to) / 15 + 1)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM d AS a CROSS JOIN d AS b CROSS JOIN d AS c CROSS JOIN d AS e CROSS JOIN d AS f),
    codes AS (
        SELECT DISTINCT r.obis_code
        FROM [dbo].[METER_READING] AS r
        JOIN [dbo].[OBIS_CODE] AS o ON o.obis_code = r.obis_code AND o.measurement_kind = 'CUMULATIVE'
        WHERE r.meter_id = @meter_id AND r.reading_timestamp BETWEEN @from AND @to)
    INSERT INTO #missing (obis_code, slot)
    SELECT c.obis_code, DATEADD(MINUTE, 15 * t.n, @first)
    FROM codes AS c
    CROSS JOIN tally AS t
    WHERE NOT EXISTS (SELECT 1 FROM [dbo].[METER_READING] AS r
                      WHERE r.meter_id = @meter_id AND r.obis_code = c.obis_code
                        AND r.reading_timestamp = DATEADD(MINUTE, 15 * t.n, @first));

    DECLARE @obis VARCHAR(20), @slot DATETIME2(0);
    DECLARE @ta DATETIME2(0), @ra DECIMAL(18,4), @tb DATETIME2(0), @rb DECIMAL(18,4);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT obis_code, slot FROM #missing ORDER BY obis_code, slot;
    OPEN c;
    FETCH NEXT FROM c INTO @obis, @slot;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @ta = NULL, @ra = NULL, @tb = NULL, @rb = NULL;

        SELECT TOP (1) @ta = reading_timestamp, @ra = [value]
        FROM [dbo].[METER_READING]
        WHERE meter_id = @meter_id AND obis_code = @obis AND status <> 'SUSPECT'
          AND reading_timestamp < @slot AND reading_timestamp >= @from
        ORDER BY reading_timestamp DESC;

        SELECT TOP (1) @tb = reading_timestamp, @rb = [value]
        FROM [dbo].[METER_READING]
        WHERE meter_id = @meter_id AND obis_code = @obis AND status <> 'SUSPECT'
          AND reading_timestamp > @slot AND reading_timestamp <= @to
        ORDER BY reading_timestamp;

        IF @ta IS NOT NULL AND @tb IS NOT NULL
        BEGIN
            INSERT INTO [dbo].[METER_READING]
                (reading_timestamp, [value], status, vee_rule, vee_note, meter_id, obis_code, packet_id)
            VALUES
                (@slot,
                 @ra + (@rb - @ra) * DATEDIFF(MINUTE, @ta, @slot) / CAST(DATEDIFF(MINUTE, @ta, @tb) AS DECIMAL(18,4)),
                 'ESTIMATED', 'LINEAR_INTERPOLATION',
                 N'Estimated between ' + CONVERT(NVARCHAR(19), @ta, 120) + N' and ' + CONVERT(NVARCHAR(19), @tb, 120),
                 @meter_id, @obis, NULL);
            SET @estimated = @estimated + 1;
        END
        FETCH NEXT FROM c INTO @obis, @slot;
    END
    CLOSE c;
    DEALLOCATE c;

    -- recompute the 15-min energy of the estimated slots and of the readings that follow them
    IF @estimated > 0
        UPDATE r
           SET delta_value = r.[value] - p.[value]
        FROM [dbo].[METER_READING] AS r
        JOIN [dbo].[OBIS_CODE] AS o ON o.obis_code = r.obis_code AND o.measurement_kind = 'CUMULATIVE'
        JOIN [dbo].[METER_READING] AS p ON p.meter_id = r.meter_id AND p.obis_code = r.obis_code
                                       AND p.reading_timestamp = DATEADD(MINUTE, -15, r.reading_timestamp)
        WHERE r.meter_id = @meter_id
          AND r.is_final = 0
          AND r.reading_timestamp BETWEEN @from AND @to
          AND (r.delta_value IS NULL OR r.delta_value <> r.[value] - p.[value]);
END;
GO

-- [project.pdf §1.4 p.6-7: detailed readings kept 3 years, or 1 month after a GDPR request; aggregates stay]
-- Deletes the raw readings of one meter that are older than the cut-off, in batches,
-- and only for days that already have a final DAY aggregate (so no consumption is lost).
CREATE OR ALTER PROCEDURE [dbo].[sp__PurgeMeter]
    @meter_id    INT,
    @keep_months TINYINT,
    @deleted     INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cutoff DATETIME2(0) = DATEADD(MONTH, -@keep_months, SYSUTCDATETIME());
    DECLARE @n INT = 1;
    SET @deleted = 0;

    WHILE @n > 0
    BEGIN
        DELETE TOP (5000) r
        FROM [dbo].[METER_READING] AS r
        WHERE r.meter_id = @meter_id
          AND r.reading_timestamp < @cutoff
          AND EXISTS (SELECT 1 FROM [dbo].[AGGREGATE] AS a
                      WHERE a.meter_id = r.meter_id AND a.period_type = 'DAY' AND a.is_final = 1
                        AND a.period_start = CAST(CAST(r.reading_timestamp AS DATE) AS DATETIME2(0)));
        SET @n = @@ROWCOUNT;
        SET @deleted = @deleted + @n;
    END
END;
GO

PRINT 'procedures_00_internal.sql: 8 internal helpers created.';
GO
