/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   bulk_import.sql  -  Build Spec §12: reload of the .dat files   [project.pdf §V p.14]

   EXPORT (once, from a database that holds the data; bcp is part of the Microsoft "mssql-tools"):
       for each table T of the list below, in a terminal:
        bcp <database>.dbo.T out data/T.dat -w -k -E -S <server> -U <user>
     -w = UTF-16 (keeps the Greek text), -k = keep NULLs, -E = keep the identity values.

   IMPORT (this script):
     1. run create.sql and the code files first (empty tables, triggers in place);
     2. set the folder below - it must be a path that the SQL SERVER machine can read;
   3. run in SQLCMD mode:   sqlcmd ... -b -v DataPath="C:\mdms\data" -i bulk_import.sql
      On Linux, use an absolute server-side directory such as /var/opt/mssql/import.
   The tables are loaded in foreign-key order. Triggers do not fire on BULK INSERT (no FIRE_TRIGGERS):
   the files hold data that already passed them, and the audit rows are loaded from AUDIT_LOG.dat itself.
   CHECK and FOREIGN KEY constraints ARE checked (CHECK_CONSTRAINTS).

   [AR: the only dynamic SQL of the project (rule R6). BULK INSERT does not take a variable for the file,
        so the statement is built here; the table names come from a fixed list in this script, never from
        input, the folder is validated (no quote, no semicolon, no comment marks) and the name is passed
        through QUOTENAME.]

   Verified locally on SQL Server 2022 with the synthetic import dataset.
   On the course server, the student login lacks the bulk-load permission and access to server-side files.
   ============================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @path NVARCHAR(260) = N'$(DataPath)';
IF @path LIKE N'%''%' OR @path LIKE N'%;%' OR @path LIKE N'%--%' OR @path LIKE N'%/*%' OR LEN(@path) = 0
    THROW 54090, 'bulk_import.sql: the data path is not valid.', 1;
IF EXISTS (SELECT 1 FROM [dbo].[USER_ACCOUNT])
    THROW 54091, 'bulk_import.sql: the tables are not empty. Run create.sql first.', 1;

DECLARE @separator NCHAR(1) = CASE WHEN LEFT(@path, 1) = N'/' THEN N'/' ELSE N'\' END;
IF RIGHT(@path, 1) <> @separator SET @path += @separator;

-- foreign-key order; ROLE, OBIS_CODE and SERVICE_TYPE already hold the reference rows of create.sql
DECLARE @tables TABLE (seq INT IDENTITY(1,1), name SYSNAME, has_reference_rows BIT);
INSERT INTO @tables (name, has_reference_rows) VALUES
 (N'ROLE', 1), (N'ORGANIZATION', 0), (N'USER_ACCOUNT', 0), (N'TECHNICIAN_AVAILABILITY', 0), (N'TRANSFORMER', 0),
 (N'PREMISE', 0), (N'METER_TYPE', 0), (N'METER', 0), (N'DOCUMENT', 0), (N'OBIS_CODE', 1), (N'TELEMETRY_PACKET', 0),
 (N'METER_READING', 0), (N'TRANSFORMER_READING', 0), (N'AGGREGATE', 0), (N'TRANSFORMER_CURRENT_STATE', 0),
 (N'EVENT', 0), (N'SERVICE_TYPE', 1), (N'WORK_ORDER', 0), (N'REMOTE_COMMAND', 0), (N'TARIFF', 0), (N'BILL', 0),
 (N'PAYMENT', 0), (N'GDPR_REQUEST', 0), (N'AUDIT_LOG', 0);

-- Import each file in one statement. TRANSFORMER references itself, so its parents and children
-- are present together when the foreign key is checked.
DECLARE @name SYSNAME, @ref BIT, @sql NVARCHAR(MAX), @rows INT;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT name, has_reference_rows FROM @tables ORDER BY seq;
BEGIN TRY
    BEGIN TRANSACTION;
    OPEN c;
    FETCH NEXT FROM c INTO @name, @ref;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @ref = 1
        BEGIN
            -- the reference rows are in the file too: empty the table first (nothing points to it yet)
            SET @sql = N'DELETE FROM [dbo].' + QUOTENAME(@name) + N';';
            EXEC sys.sp_executesql @sql;
        END;
        SET @sql = N'BULK INSERT [dbo].' + QUOTENAME(@name) + N' FROM ''' + @path + @name + N'.dat'' '
                 + N'WITH (DATAFILETYPE = ''widechar'', KEEPIDENTITY, KEEPNULLS, CHECK_CONSTRAINTS, TABLOCK);'
                 + N' SET @loaded = @@ROWCOUNT;';
        EXEC sys.sp_executesql @sql, N'@loaded INT OUTPUT', @loaded = @rows OUTPUT;
        PRINT 'loaded ' + @name + ': ' + CAST(@rows AS VARCHAR(12)) + ' rows';
        FETCH NEXT FROM c INTO @name, @ref;
    END
    CLOSE c;
    DEALLOCATE c;
    COMMIT TRANSACTION;
    PRINT 'bulk_import.sql finished.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
