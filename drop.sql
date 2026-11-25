/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   drop.sql  -  removes every MDMS-Cy object (schema v6, plus older v3/v4 names)
   Safe to re-run: drops the FKs that touch MDMS-Cy tables, then views, then the MDMS-Cy tables (other tables stay).
   ============================================================================ */
SET NOCOUNT ON;
GO

-- The MDMS-Cy tables (v6 plus the names used by v3/v4, so an old database is cleaned too). Only these tables and
-- the foreign keys that touch them are dropped: other tables of the database (e.g. lab exercises) keep theirs.
DECLARE @mdms TABLE (name SYSNAME PRIMARY KEY);
INSERT INTO @mdms (name) VALUES
    (N'NOTIFICATION'),
    (N'AUDIT_LOG'),
    (N'GDPR_REQUEST'),
    (N'PAYMENT'),
    (N'BILL'),
    (N'TARIFF'),
    (N'REMOTE_COMMAND'),
    (N'WORK_ORDER'),
    (N'SERVICE_TYPE'),
    (N'EVENT'),
    (N'TRANSFORMER_CURRENT_STATE'),
    (N'AGGREGATE'),
    (N'TRANSFORMER_READING'),
    (N'METER_READING'),
    (N'TELEMETRY_PACKET'),
    (N'OBIS_CODE'),
    (N'DOCUMENT'),
    (N'METER'),
    (N'METER_TYPE'),
    (N'PREMISE'),
    (N'TRANSFORMER'),
    (N'TECHNICIAN_AVAILABILITY'),
    (N'USER_ACCOUNT'),
    (N'ORGANIZATION'),
    (N'ROLE'),
    (N'HISTORICAL_ACCESS'),
    (N'COMMAND_ATTEMPT'),
    (N'COMMAND_BATCH'),
    (N'GEOFENCE_AGGREGATE'),
    (N'METER_AGGREGATE'),
    (N'VEE_LOG'),
    (N'VEE_RULE'),
    (N'GEOFENCE_CURRENT_STATE'),
    (N'CONSUMPTION_ALERT'),
    (N'METER_INSTALLATION'),
    (N'APPROVAL_DECISION'),
    (N'METER_DOCUMENT'),
    (N'WORK_ORDER_EVIDENCE'),
    (N'WORK_ORDER_NOTIFICATION'),
    (N'SERVICE_REQUEST'),
    (N'AGGREGATOR_MEMBERSHIP'),
    (N'AGGREGATOR_USER'),
    (N'AGGREGATOR'),
    (N'SUPPLIER_ASSIGNMENT'),
    (N'SUPPLIER_USER'),
    (N'SUPPLIER'),
    (N'CONSUMER_PREMISE'),
    (N'GDPR_REVIEW'),
    (N'GEOFENCE'),
    (N'RETENTION_POLICY'),
    (N'COMMUNICATION_TYPE'),
    (N'PROSUMER_SCHEME'),
    (N'BANK_ACCOUNT'),
    (N'TECHNICIAN_DOCUMENT'),
    (N'TECHNICIAN_SPECIALTY'),
    (N'SPECIALTY'),
    (N'TECHNICIAN'),
    (N'CONSUMER'),
    (N'PARISH'),
    (N'MUNICIPALITY'),
    (N'DISTRICT'),
    (N'USER_ROLE');

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) + N'.'
             + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
             + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';' + NCHAR(10)
FROM sys.foreign_keys AS fk
WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = N'dbo'
  AND (OBJECT_NAME(fk.parent_object_id) IN (SELECT name FROM @mdms)
       OR OBJECT_NAME(fk.referenced_object_id) IN (SELECT name FROM @mdms));
EXEC sys.sp_executesql @sql;

DROP VIEW IF EXISTS dbo.vw_CONSUMER, dbo.vw_TECHNICIAN, dbo.vw_ORGANIZATION_USER, dbo.vw_STAFF,
    dbo.view_CONSUMER, dbo.view_TECHNICIAN, dbo.view_ORGANIZATION_USER, dbo.view_STAFF,
    dbo.view_PREMISE_METER, dbo.view_METER_LOCATION, dbo.view_OPEN_WORK_ORDER, dbo.view_BILL_BALANCE;

-- one table per statement: small transactions for the capped log of the course databases
DECLARE @name SYSNAME;
DECLARE drop_cur CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM @mdms;
OPEN drop_cur;
FETCH NEXT FROM drop_cur INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'DROP TABLE IF EXISTS [dbo].' + QUOTENAME(@name) + N';';
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM drop_cur INTO @name;
END
CLOSE drop_cur;
DEALLOCATE drop_cur;
GO

PRINT 'MDMS-Cy objects dropped.';
GO
