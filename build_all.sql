/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   build_all.sql  -  Build Spec §13: builds the whole database in order.

   Run from a terminal in this folder (go-sqlcmd or sqlcmd):
        sqlcmd -S "<server>" -U <user> -d <database> -C -I -b -i build_all.sql
   or in SSMS with SQLCMD mode on (Query > SQLCMD Mode). The :r paths are relative to the folder
   the tool was started in.

   WARNING: create.sql drops and recreates every MDMS-Cy table (all project data is lost).
   The script can run any number of times in a row.

   Not included on purpose (run them by hand, after this script):
        select.sql        one demo per use case
        tests.sql         every block must print PASS
        perf.sql          performance run on the large data set (see its header)
        bulk_import.sql   reload from .dat files (needs bulkadmin and bcp, see its header)
        EXEC dbo.sp_GenerateSyntheticData @actor_user_id = <admin>, @consumers = ..., @days = ...;
   ============================================================================ */
:on error exit

PRINT '--- create.sql ---';
:r create.sql
PRINT '--- functions.sql ---';
:r functions.sql
PRINT '--- views.sql ---';
:r views.sql
PRINT '--- procedures_00_internal.sql ---';
:r procedures_00_internal.sql
PRINT '--- triggers.sql ---';
:r triggers.sql
PRINT '--- procedures_01_accounts.sql ---';
:r procedures_01_accounts.sql
PRINT '--- procedures_02_consumer.sql ---';
:r procedures_02_consumer.sql
PRINT '--- procedures_03_workorders.sql ---';
:r procedures_03_workorders.sql
PRINT '--- procedures_04_meters.sql ---';
:r procedures_04_meters.sql
PRINT '--- procedures_05_commands.sql ---';
:r procedures_05_commands.sql
PRINT '--- procedures_06_telemetry.sql ---';
:r procedures_06_telemetry.sql
PRINT '--- procedures_07_grid.sql ---';
:r procedures_07_grid.sql
PRINT '--- procedures_08_billing.sql ---';
:r procedures_08_billing.sql
PRINT '--- procedures_09_gdpr.sql ---';
:r procedures_09_gdpr.sql
PRINT '--- procedures_10_market.sql ---';
:r procedures_10_market.sql
PRINT '--- procedures_11_admin.sql ---';
:r procedures_11_admin.sql
PRINT '--- procedures_12_generator.sql ---';
:r procedures_12_generator.sql
PRINT '--- indexes.sql ---';
:r indexes.sql
PRINT '--- security.sql ---';
:r security.sql
PRINT '--- import.sql ---';
:r import.sql
GO

-- what was built
SELECT x.object_kind, COUNT(*) AS objects
FROM (SELECT CASE o.type WHEN 'U' THEN '1 tables' WHEN 'V' THEN '2 views' WHEN 'FN' THEN '3 scalar functions'
                         WHEN 'TF' THEN '4 table functions' WHEN 'TR' THEN '5 triggers' WHEN 'P' THEN '6 procedures' END AS object_kind
      FROM sys.objects AS o
      WHERE o.schema_id = SCHEMA_ID(N'dbo') AND o.type IN ('U', 'V', 'P', 'TR', 'FN', 'TF') AND o.is_ms_shipped = 0
        AND (o.type <> 'U' OR o.name IN ('ROLE','ORGANIZATION','USER_ACCOUNT','TECHNICIAN_AVAILABILITY','TRANSFORMER','PREMISE',
             'METER_TYPE','METER','DOCUMENT','OBIS_CODE','TELEMETRY_PACKET','METER_READING','TRANSFORMER_READING','AGGREGATE',
             'TRANSFORMER_CURRENT_STATE','EVENT','SERVICE_TYPE','WORK_ORDER','REMOTE_COMMAND','TARIFF','BILL','PAYMENT',
             'GDPR_REQUEST','AUDIT_LOG'))
        AND (o.type NOT IN ('P', 'FN') OR o.name LIKE 'sp[_]%' AND o.name NOT LIKE '%diagram%' OR o.name LIKE 'fn[_]%' AND o.name NOT LIKE '%diagram%')
     ) AS x
GROUP BY x.object_kind
UNION ALL
SELECT '7 indexes (non-key, of indexes.sql)', COUNT(*)
FROM sys.indexes AS i
WHERE i.object_id IN (SELECT object_id FROM sys.tables WHERE schema_id = SCHEMA_ID(N'dbo'))
  AND i.is_primary_key = 0 AND i.is_unique_constraint = 0
  AND (i.name LIKE 'IX[_]%' OR i.name = 'UQ_BILL_premise_period')
ORDER BY 1;
-- expected: 24 tables, 8 views, 8 scalar functions, 2 table functions, 23 triggers, 110 procedures, 14 indexes
PRINT 'build_all.sql finished.';
GO
