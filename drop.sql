/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   drop.sql  -  removes every MDMS-Cy object (schema v6, plus older v3/v4 names)
   Safe to re-run: drops all FKs first, then views, then tables.
   ============================================================================ */
SET NOCOUNT ON;
GO

DECLARE @drop_fk NVARCHAR(MAX) = N'';
SELECT @drop_fk += N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) + N'.'
                 + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
                 + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';' + NCHAR(10)
FROM sys.foreign_keys AS fk
WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = N'dbo';
EXEC sys.sp_executesql @drop_fk;
GO

DROP VIEW IF EXISTS dbo.vw_CONSUMER, dbo.vw_TECHNICIAN, dbo.vw_ORGANIZATION_USER, dbo.vw_STAFF,
    dbo.view_CONSUMER, dbo.view_TECHNICIAN, dbo.view_ORGANIZATION_USER, dbo.view_STAFF,
    dbo.view_PREMISE_METER, dbo.view_METER_LOCATION, dbo.view_OPEN_WORK_ORDER, dbo.view_BILL_BALANCE;
GO

-- v5 tables + every table name used by v3/v4, so an old database is cleaned too
DROP TABLE IF EXISTS
    dbo.AUDIT_LOG, dbo.GDPR_REQUEST, dbo.PAYMENT, dbo.BILL, dbo.TARIFF,
    dbo.REMOTE_COMMAND, dbo.WORK_ORDER, dbo.SERVICE_TYPE, dbo.EVENT,
    dbo.TRANSFORMER_CURRENT_STATE, dbo.AGGREGATE, dbo.TRANSFORMER_READING,
    dbo.METER_READING, dbo.TELEMETRY_PACKET, dbo.OBIS_CODE, dbo.DOCUMENT,
    dbo.METER, dbo.METER_TYPE, dbo.PREMISE, dbo.TRANSFORMER,
    dbo.TECHNICIAN_AVAILABILITY, dbo.USER_ACCOUNT, dbo.ORGANIZATION, dbo.ROLE,
    -- v3 / v4 leftovers
    dbo.HISTORICAL_ACCESS, dbo.COMMAND_ATTEMPT, dbo.COMMAND_BATCH, dbo.GEOFENCE_AGGREGATE,
    dbo.METER_AGGREGATE, dbo.VEE_LOG, dbo.VEE_RULE, dbo.GEOFENCE_CURRENT_STATE,
    dbo.CONSUMPTION_ALERT, dbo.METER_INSTALLATION, dbo.APPROVAL_DECISION, dbo.METER_DOCUMENT,
    dbo.WORK_ORDER_EVIDENCE, dbo.WORK_ORDER_NOTIFICATION, dbo.SERVICE_REQUEST,
    dbo.AGGREGATOR_MEMBERSHIP, dbo.AGGREGATOR_USER, dbo.AGGREGATOR, dbo.SUPPLIER_ASSIGNMENT,
    dbo.SUPPLIER_USER, dbo.SUPPLIER, dbo.CONSUMER_PREMISE, dbo.GDPR_REVIEW, dbo.GEOFENCE,
    dbo.RETENTION_POLICY, dbo.COMMUNICATION_TYPE, dbo.PROSUMER_SCHEME, dbo.BANK_ACCOUNT,
    dbo.TECHNICIAN_DOCUMENT, dbo.TECHNICIAN_SPECIALTY, dbo.SPECIALTY, dbo.TECHNICIAN,
    dbo.CONSUMER, dbo.PARISH, dbo.MUNICIPALITY, dbo.DISTRICT, dbo.USER_ROLE;
GO

PRINT 'MDMS-Cy objects dropped.';
GO
