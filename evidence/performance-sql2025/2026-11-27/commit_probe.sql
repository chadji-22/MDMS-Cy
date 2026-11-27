-- Cost of one COMMIT (log flush) on SQL2025: 100 single-row inserts in autocommit vs. inside one transaction, 3 rounds.
-- Creates and drops dbo.zz_perf_commit_probe (refuses to run if that name exists).
SET NOCOUNT ON;
IF OBJECT_ID('dbo.zz_perf_commit_probe') IS NOT NULL THROW 50000, 'dbo.zz_perf_commit_probe already exists: not touching it', 1;
CREATE TABLE dbo.zz_perf_commit_probe (i INT NOT NULL);
DECLARE @r TABLE (rnd INT, mode VARCHAR(20), ms DECIMAL(12,2));
DECLARE @rnd INT = 1, @i INT, @t DATETIME2(7);
BEGIN TRY
    WHILE @rnd <= 3
    BEGIN
        SELECT @i = 0, @t = SYSDATETIME();
        WHILE @i < 100 BEGIN INSERT dbo.zz_perf_commit_probe VALUES (@i); SET @i += 1; END
        INSERT @r VALUES (@rnd, '100 commits', DATEDIFF_BIG(MICROSECOND, @t, SYSDATETIME()) / 1000.0);
        SELECT @i = 0, @t = SYSDATETIME();
        BEGIN TRANSACTION;
        WHILE @i < 100 BEGIN INSERT dbo.zz_perf_commit_probe VALUES (@i); SET @i += 1; END
        COMMIT;
        INSERT @r VALUES (@rnd, '1 commit', DATEDIFF_BIG(MICROSECOND, @t, SYSDATETIME()) / 1000.0);
        SET @rnd += 1;
    END
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    PRINT CONCAT('probe error ', ERROR_NUMBER(), ': ', ERROR_MESSAGE());
END CATCH
DROP TABLE dbo.zz_perf_commit_probe;
SELECT CONCAT('PROBE|', rnd, '|', mode, '|', ms) AS r FROM @r ORDER BY rnd, mode;
SELECT CONCAT('PROBE|per-commit ms|', CAST((SUM(CASE WHEN mode = '100 commits' THEN ms END) - SUM(CASE WHEN mode = '1 commit' THEN ms END)) / 300.0 AS DECIMAL(9,3))) FROM @r;
SELECT CONCAT('PROBE|table gone|', CASE WHEN OBJECT_ID('dbo.zz_perf_commit_probe') IS NULL THEN 'yes' ELSE 'NO' END);
