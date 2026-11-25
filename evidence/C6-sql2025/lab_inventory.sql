/* C6 (SQL2025): read-only inventory of the tables that are NOT MDMS-Cy tables (lab exercises), to compare before and
   after a rebuild. Lists every non-MDMS table with its row count, and every foreign key with its columns. */
SET NOCOUNT ON;
DECLARE @mdms TABLE (name SYSNAME PRIMARY KEY);
INSERT INTO @mdms VALUES (N'NOTIFICATION'),(N'AUDIT_LOG'),(N'GDPR_REQUEST'),(N'PAYMENT'),(N'BILL'),(N'TARIFF'),(N'REMOTE_COMMAND'),
 (N'WORK_ORDER'),(N'SERVICE_TYPE'),(N'EVENT'),(N'TRANSFORMER_CURRENT_STATE'),(N'AGGREGATE'),(N'TRANSFORMER_READING'),(N'METER_READING'),
 (N'TELEMETRY_PACKET'),(N'OBIS_CODE'),(N'DOCUMENT'),(N'METER'),(N'METER_TYPE'),(N'PREMISE'),(N'TRANSFORMER'),(N'TECHNICIAN_AVAILABILITY'),
 (N'USER_ACCOUNT'),(N'ORGANIZATION'),(N'ROLE');
SELECT 'TABLE|' + t.name + '|' + CAST(SUM(p.rows) AS varchar(20)) + '|cols=' + CAST((SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = t.object_id) AS varchar(5))
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE t.name NOT IN (SELECT name FROM @mdms) GROUP BY t.name, t.object_id ORDER BY t.name;
SELECT 'FK|' + fk.name + '|' + OBJECT_NAME(fk.parent_object_id) + '(' + STRING_AGG(pc.name, ',') WITHIN GROUP (ORDER BY fkc.constraint_column_id)
     + ') -> ' + OBJECT_NAME(fk.referenced_object_id) + '(' + STRING_AGG(rc.name, ',') WITHIN GROUP (ORDER BY fkc.constraint_column_id) + ')'
FROM sys.foreign_keys fk JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns pc ON pc.object_id = fkc.parent_object_id AND pc.column_id = fkc.parent_column_id
JOIN sys.columns rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id
WHERE OBJECT_NAME(fk.parent_object_id) NOT IN (SELECT name FROM @mdms)
GROUP BY fk.name, fk.parent_object_id, fk.referenced_object_id ORDER BY fk.name;
