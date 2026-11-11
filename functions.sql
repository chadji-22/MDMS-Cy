/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   functions.sql  -  Build Spec §6 (run after create.sql)
   Re-runnable: CREATE OR ALTER.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;      -- needed by the filtered indexes of create.sql (sqlcmd defaults to OFF)
GO

-- [project.pdf Κοινές αρχές p.5: passwords never in plaintext; lecture 20-76 HASHBYTES]
-- [AR: per-user salt, so equal passwords do not give equal hashes]
CREATE OR ALTER FUNCTION [dbo].[fn_HashPassword] (@password NVARCHAR(128), @salt VARBINARY(16))
RETURNS VARBINARY(64)
AS
BEGIN
    RETURN HASHBYTES('SHA2_512', @salt + CAST(@password AS VARBINARY(256)));
END;
GO

-- [project.pdf §3.1 p.8: every reading belongs to its 15-minute slot]
CREATE OR ALTER FUNCTION [dbo].[fn_Floor15] (@ts DATETIME2(0))
RETURNS DATETIME2(0)
AS
BEGIN
    RETURN DATEADD(MINUTE, (DATEDIFF(MINUTE, '2000-01-01', @ts) / 15) * 15, CAST('2000-01-01' AS DATETIME2(0)));
END;
GO

-- [project.pdf Κοινές αρχές p.5: the user is identified before every protected operation]
-- @roles is a CSV list. The pseudo-role TECHNICIAN_ANY matches a technician in any approval status.
CREATE OR ALTER FUNCTION [dbo].[fn_UserHasRole] (@user_id INT, @roles NVARCHAR(200))
RETURNS BIT
AS
BEGIN
    DECLARE @r BIT = 0;
    IF EXISTS (
        SELECT 1
        FROM [dbo].[USER_ACCOUNT] AS u
        WHERE u.user_id = @user_id
          AND u.is_active = 1
          AND u.anonymized_at IS NULL
          AND (   (u.approval_status = 'APPROVED'
                   AND u.role_code IN (SELECT LTRIM(RTRIM(s.[value])) FROM STRING_SPLIT(@roles, ',') AS s))
               OR (u.role_code = 'TECHNICIAN'
                   AND EXISTS (SELECT 1 FROM STRING_SPLIT(@roles, ',') AS s WHERE LTRIM(RTRIM(s.[value])) = 'TECHNICIAN_ANY'))))
        SET @r = 1;
    RETURN @r;
END;
GO

-- [project.pdf §4.1-4.2 p.9-10: all transformers directly or indirectly under a node, whatever the depth]
-- Breadth-first with a WHILE loop: no recursion, so no 32-level limit.
CREATE OR ALTER FUNCTION [dbo].[fn_TransformerSubtree] (@root_id INT)
RETURNS @records TABLE (transformer_id INT PRIMARY KEY, [level] TINYINT, depth INT)
AS
BEGIN
    DECLARE @depth INT = 0, @added INT;

    INSERT INTO @records (transformer_id, [level], depth)
    SELECT transformer_id, [level], 0 FROM [dbo].[TRANSFORMER] WHERE transformer_id = @root_id;
    SET @added = @@ROWCOUNT;

    WHILE @added > 0
    BEGIN
        INSERT INTO @records (transformer_id, [level], depth)
        SELECT t.transformer_id, t.[level], @depth + 1
        FROM [dbo].[TRANSFORMER] AS t
        JOIN @records AS r ON r.transformer_id = t.parent_transformer_id
        WHERE r.depth = @depth
          AND NOT EXISTS (SELECT 1 FROM @records AS x WHERE x.transformer_id = t.transformer_id);
        SET @added = @@ROWCOUNT;
        SET @depth = @depth + 1;
    END
    RETURN;
END;
GO

-- [project.pdf §4.2 p.10: a reading affects its L1 geofence and all its ancestors]
-- Returns the node itself (distance 0) and then every ancestor up to the root.
-- [AR: the node itself is included so "the ancestor at level 1" of a level-1 transformer is itself]
CREATE OR ALTER FUNCTION [dbo].[fn_TransformerAncestors] (@transformer_id INT)
RETURNS @records TABLE (transformer_id INT, [level] TINYINT, distance INT)
AS
BEGIN
    DECLARE @cur INT = @transformer_id, @lvl TINYINT, @parent INT, @distance INT = 0;

    WHILE @cur IS NOT NULL AND @distance < 50          -- 50 steps = cycle guard
    BEGIN
        SET @lvl = NULL;
        SELECT @lvl = [level], @parent = parent_transformer_id
        FROM [dbo].[TRANSFORMER] WHERE transformer_id = @cur;
        IF @lvl IS NULL BREAK;                          -- no such transformer

        INSERT INTO @records (transformer_id, [level], distance) VALUES (@cur, @lvl, @distance);
        SET @cur = @parent;
        SET @distance = @distance + 1;
    END
    RETURN;
END;
GO

-- [project.pdf §4.1 p.9: from a meter's coordinates find the Geofence it falls in]
-- The level-1 transformer whose rectangle holds the point; the smallest rectangle wins.
CREATE OR ALTER FUNCTION [dbo].[fn_FindGeofence] (@lat DECIMAL(9,6), @lon DECIMAL(9,6))
RETURNS INT
AS
BEGIN
    DECLARE @id INT = NULL;
    SELECT TOP (1) @id = t.transformer_id
    FROM [dbo].[TRANSFORMER] AS t
    WHERE t.[level] = 1
      AND t.min_lat IS NOT NULL
      AND @lat BETWEEN t.min_lat AND t.max_lat
      AND @lon BETWEEN t.min_lon AND t.max_lon
    ORDER BY (t.max_lat - t.min_lat) * (t.max_lon - t.min_lon), t.transformer_id;
    RETURN @id;
END;
GO

-- [project.pdf §1.2 p.6: current month free, earlier months paid, never beyond the retention period]
-- The window is [@from, @to). 1 = the user may see the readings of this meter in the window.
CREATE OR ALTER FUNCTION [dbo].[fn_CanViewReadings] (@user_id INT, @meter_id INT, @from DATETIME2(0), @to DATETIME2(0))
RETURNS BIT
AS
BEGIN
    DECLARE @retention TINYINT = NULL;

    -- (a) the meter is on a premise of the user
    SELECT @retention = m.retention_months
    FROM [dbo].[METER] AS m
    JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
    WHERE m.meter_id = @meter_id AND p.user_id = @user_id;
    IF @retention IS NULL RETURN 0;
    IF @from IS NULL OR @to IS NULL OR @to < @from RETURN 0;

    DECLARE @today       DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @month_start DATE = DATEFROMPARTS(YEAR(@today), MONTH(@today), 1);
    DECLARE @day         DATE = CAST(@from AS DATE);
    DECLARE @last        DATE = CAST(@to AS DATE);

    -- @to is exclusive: a window that ends at midnight does not touch that day
    IF @to > @from AND CAST(@to AS TIME(0)) = '00:00:00' SET @last = DATEADD(DAY, -1, @last);

    -- (c) not older than the retention period
    IF @day < DATEADD(MONTH, -@retention, @today) RETURN 0;

    -- (b) every day before the current month must be covered by a completed HISTORICAL_ACCESS payment
    IF @last >= @month_start SET @last = DATEADD(DAY, -1, @month_start);
    WHILE @day <= @last
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM [dbo].[PAYMENT] AS pay
            JOIN [dbo].[SERVICE_TYPE] AS s ON s.service_type_id = pay.service_type_id
            WHERE pay.user_id = @user_id
              AND pay.access_meter_id = @meter_id
              AND pay.status = 'COMPLETED'
              AND s.service_name = N'HISTORICAL_ACCESS'
              AND @day BETWEEN pay.access_from AND pay.access_to)
            RETURN 0;
        SET @day = DATEADD(DAY, 1, @day);
    END
    RETURN 1;
END;
GO

-- [project.pdf §1.3 p.6: the tariff in force on a day]
CREATE OR ALTER FUNCTION [dbo].[fn_ActiveTariff] (@day DATE)
RETURNS INT
AS
BEGIN
    DECLARE @id INT = NULL;
    SELECT TOP (1) @id = tariff_id
    FROM [dbo].[TARIFF]
    WHERE valid_from <= @day AND (valid_to IS NULL OR valid_to >= @day)
    ORDER BY valid_from DESC, tariff_id DESC;
    RETURN @id;
END;
GO

-- [project.pdf §1.3 p.6: a bill can be paid with several payments]
CREATE OR ALTER FUNCTION [dbo].[fn_BillPaid] (@bill_id INT)
RETURNS DECIMAL(12,2)
AS
BEGIN
    DECLARE @paid DECIMAL(12,2);
    SELECT @paid = SUM(amount) FROM [dbo].[PAYMENT] WHERE bill_id = @bill_id AND status = 'COMPLETED';
    RETURN ISNULL(@paid, 0);
END;
GO

-- [Lab 10 exercise, reused: dd/mm/yyyy for display in PHP]
CREATE OR ALTER FUNCTION [dbo].[fn_DATE_ONLY] (@d DATETIME2)
RETURNS CHAR(10)
AS
BEGIN
    RETURN CONVERT(CHAR(10), @d, 103);
END;
GO

PRINT 'functions.sql: 10 functions created.';
GO
