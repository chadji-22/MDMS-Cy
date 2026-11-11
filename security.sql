/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   security.sql  -  Build Spec §11
   Run after every procedure file. Re-runnable.
   If the course server does not let students run a statement here, the script prints why
   and goes on; the script then documents the production setting.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------------
   1. The application can only execute procedures  [project.pdf §IV p.13: unauthorised access; rule R1]
      The PHP SQL user is a member of mdms_app. It has EXECUTE on the schema and is DENIED direct
      SELECT / INSERT / UPDATE / DELETE. The procedures still reach the tables through ownership
      chaining (same owner, dbo), so an injected "SELECT * FROM USER_ACCOUNT" fails.
   --------------------------------------------------------------------------- */
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'mdms_app' AND type = 'R')
        CREATE ROLE [mdms_app];

    GRANT EXECUTE ON SCHEMA::[dbo] TO [mdms_app];
    DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::[dbo] TO [mdms_app];

    /* 2. Internal helpers are hidden from the application  [AR: least privilege] */
    DENY EXECUTE ON [dbo].[sp__AssertRole]          TO [mdms_app];
    DENY EXECUTE ON [dbo].[sp__SetActor]            TO [mdms_app];
    DENY EXECUTE ON [dbo].[sp__Log]                 TO [mdms_app];
    DENY EXECUTE ON [dbo].[sp__NewUser]             TO [mdms_app];
    DENY EXECUTE ON [dbo].[sp__WalkTransformerTree] TO [mdms_app];
    DENY EXECUTE ON [dbo].[sp__SumSubtree]          TO [mdms_app];
    DENY EXECUTE ON [dbo].[sp__EstimateGaps]        TO [mdms_app];
    DENY EXECUTE ON [dbo].[sp__PurgeMeter]          TO [mdms_app];

    PRINT 'security.sql: role mdms_app configured.';
END TRY
BEGIN CATCH
    PRINT 'security.sql: the role mdms_app could not be configured here: ' + ERROR_MESSAGE();
END CATCH
GO

/* ---------------------------------------------------------------------------
   3. Add the SQL user of the PHP application to the role.
      The name depends on the server, so it is left as a template:

        ALTER ROLE [mdms_app] ADD MEMBER [<php_sql_user>];
   --------------------------------------------------------------------------- */

/* ---------------------------------------------------------------------------
   4. Snapshot reads  [project.pdf §IV p.13: concurrency; lecture 20-44/45]
      READ COMMITTED stays the isolation level; with READ_COMMITTED_SNAPSHOT readers see the last
      committed version instead of waiting, so dashboards do not block packet ingestion.
      Needs ALTER permission on the database and no other open connection.
   --------------------------------------------------------------------------- */
BEGIN TRY
    IF (SELECT is_read_committed_snapshot_on FROM sys.databases WHERE database_id = DB_ID()) = 0
        ALTER DATABASE CURRENT SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
    PRINT 'security.sql: READ_COMMITTED_SNAPSHOT is ON.';
END TRY
BEGIN CATCH
    PRINT 'security.sql: READ_COMMITTED_SNAPSHOT was not changed (not allowed on this server): ' + ERROR_MESSAGE();
END CATCH
GO

/* ---------------------------------------------------------------------------
   Other measures, implemented in the other files:
   * SQL injection   : static, parameterized SQL in every procedure; no EXEC(@string); PHP uses {call ...} with $params
                       [§IV p.13; lecture 20-12, 20-20]
   * Passwords       : salted SHA2_512 (fn_HashPassword); never returned; one message for every login failure
                       [Κοινές αρχές p.5; lecture 20-76]
   * Row-level rules : every procedure checks role (sp__AssertRole) and ownership
                       (premise owner, assigned technician, own organization)  [§1.4 p.6; §5.1 p.10]
   * Personal data   : user views WITH ENCRYPTION; market data only aggregated, groups of 3 meters or more
                       [§1.4 p.6; lab 10]
   --------------------------------------------------------------------------- */
