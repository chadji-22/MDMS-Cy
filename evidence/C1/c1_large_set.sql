/* ============================================================================
   C1 - large data set + the normal pipeline on it   [project.pdf §IV p.12: "of the order of thousands of rows"]
   Run on the course database ichara09 (decision of Ioannis, 22/11/2026). Its caps are data 27 MB / log 12 MB, so the
   size was chosen by measurement (trial 2 consumers x 2 days = 1,532 readings, about 370 bytes each with indexes):
   8 consumers x 2 days, chunks of 2 meters per transaction (small log use), leaving >= 3 MB free for the team.
   On a local server the same script scales: change @consumers / @days.

   Steps (each timed): generate -> sp_RunVEE on the raw day -> sp_FinalizeReadings (meter DAY/MONTH aggregates)
   -> sp_BuildTransformerAggregates -> sp_RefreshTransformerState. Row counts before and after.
   ============================================================================ */
SET NOCOUNT ON;
DECLARE @consumers INT = 8, @days INT = 2, @chunk INT = 2;          -- <== size

DECLARE @admin INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'admin@mdms.cy');
DECLARE @dso   INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'dso@mdms.cy');
DECLARE @tso   INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'tso@mdms.cy');
DECLARE @raw_day DATE = DATEADD(DAY, -1, CAST(SYSUTCDATETIME() AS DATE));   -- the generator leaves yesterday raw
DECLARE @t0 DATETIME2(3);

CREATE TABLE #counts (stage VARCHAR(10), tbl VARCHAR(40), n BIGINT);
CREATE TABLE #steps (step VARCHAR(60), ms INT);

INSERT INTO #counts SELECT 'before', t.name, SUM(p.rows) FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id < 2
WHERE t.schema_id = SCHEMA_ID('dbo') GROUP BY t.name;

SET @t0 = SYSDATETIME();
EXEC dbo.sp_GenerateSyntheticData @actor_user_id = @admin, @consumers = @consumers, @days = @days, @seed = 342, @chunk_meters = @chunk;
INSERT INTO #steps VALUES ('sp_GenerateSyntheticData', DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));
CHECKPOINT;

DECLARE @from DATETIME2(0) = CAST(@raw_day AS DATETIME2(0)), @to DATETIME2(0) = DATEADD(DAY, 1, CAST(@raw_day AS DATETIME2(0)));
SELECT status, COUNT(*) AS readings_on_raw_day_before_vee FROM dbo.METER_READING
WHERE reading_timestamp >= @from AND reading_timestamp < @to GROUP BY status;

SET @t0 = SYSDATETIME();
EXEC dbo.sp_RunVEE @dso, @from, @to;
INSERT INTO #steps VALUES ('sp_RunVEE (raw day)', DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));
CHECKPOINT;

SELECT status, COUNT(*) AS readings_on_raw_day_after_vee FROM dbo.METER_READING
WHERE reading_timestamp >= @from AND reading_timestamp < @to GROUP BY status;

SET @t0 = SYSDATETIME();
EXEC dbo.sp_FinalizeReadings @dso, @raw_day;
INSERT INTO #steps VALUES ('sp_FinalizeReadings (raw day)', DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));
CHECKPOINT;

SET @t0 = SYSDATETIME();
EXEC dbo.sp_BuildTransformerAggregates @dso, @raw_day;
INSERT INTO #steps VALUES ('sp_BuildTransformerAggregates (raw day)', DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));

SET @t0 = SYSDATETIME();
EXEC dbo.sp_RefreshTransformerState @tso, NULL;
INSERT INTO #steps VALUES ('sp_RefreshTransformerState (whole tree)', DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));
CHECKPOINT;

SELECT is_final, status, COUNT(*) AS readings_on_raw_day_after_finalize FROM dbo.METER_READING
WHERE reading_timestamp >= @from AND reading_timestamp < @to GROUP BY is_final, status;

INSERT INTO #counts SELECT 'after', t.name, SUM(p.rows) FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id < 2
WHERE t.schema_id = SCHEMA_ID('dbo') GROUP BY t.name;

SELECT step, ms FROM #steps;
SELECT a.tbl AS [table], b.n AS rows_before, a.n AS rows_after, a.n - ISNULL(b.n, 0) AS added
FROM #counts AS a LEFT JOIN #counts AS b ON b.tbl = a.tbl AND b.stage = 'before'
WHERE a.stage = 'after' ORDER BY a.n DESC;
SELECT name, CAST(FILEPROPERTY(name, 'SpaceUsed') * 8 / 1024.0 AS DECIMAL(6,2)) AS used_mb, CAST(max_size * 8 / 1024.0 AS DECIMAL(6,2)) AS max_mb
FROM sys.database_files;
