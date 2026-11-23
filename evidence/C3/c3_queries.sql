/* C3 [project.pdf §IV p.12: at least one case where an index lowers the cost] - the two queries of perf.sql PART 3.
   Run: sqlcmd ... -y 0 -v STATE=with -i c3_queries.sql ; DROP INDEX IX_METER_READING_obis_slot ;
        sqlcmd ... -y 0 -v STATE=without -i c3_queries.sql ; create the index again exactly as in indexes.sql (IX1).
   (-y 0: no truncation of the plan XML; each <ShowPlanXML ...> line of the output is saved as a .sqlplan file.)
   Query A = leaf query of the tree refresh (Algorithm E, §4.2 p.10): every meter at ONE 15-minute slot.
   Query B = core of sp_GetIntradayProvisional (§5.2 p.11): every meter over 6 hours.
   Each query runs once to warm the cache, then once measured (STATISTICS IO + TIME + actual plan XML). */
SET NOCOUNT ON;
DECLARE @ix INT = (SELECT COUNT(*) FROM sys.indexes WHERE name = N'IX_METER_READING_obis_slot'),
        @rows INT = (SELECT COUNT(*) FROM [dbo].[METER_READING]), @na INT, @nb INT;
PRINT '=== state: $(STATE) IX_METER_READING_obis_slot; index present = ' + CAST(@ix AS VARCHAR(1));
DECLARE @ref DATETIME2(0) = (SELECT MAX(reading_timestamp) FROM [dbo].[METER_READING] WHERE obis_code = '1.8.0' AND status IN ('VALID', 'ESTIMATED', 'EDITED'));
DECLARE @from DATETIME2(0) = DATEADD(HOUR, -6, @ref);
PRINT 'reference slot ' + CONVERT(VARCHAR(19), @ref, 120) + '; METER_READING rows = ' + CAST(@rows AS VARCHAR(12));

-- warm-up (not measured)
SELECT m.transformer_id, r.obis_code, SUM(ISNULL(r.delta_value, 0)) AS s INTO #w1
FROM [dbo].[METER_READING] AS r JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
WHERE r.obis_code IN ('1.8.0', '2.8.0') AND r.reading_timestamp = @ref GROUP BY m.transformer_id, r.obis_code OPTION (RECOMPILE);
SELECT r.reading_timestamp, SUM(ISNULL(r.delta_value, 0)) AS s INTO #w2
FROM [dbo].[METER_READING] AS r WHERE r.obis_code IN ('1.8.0', '2.8.0') AND r.reading_timestamp >= @from AND r.reading_timestamp < @ref
GROUP BY r.reading_timestamp OPTION (RECOMPILE);

PRINT '--- Query A ($(STATE) index) ---';
SET STATISTICS IO ON; SET STATISTICS TIME ON; SET STATISTICS XML ON;
SELECT m.transformer_id, r.obis_code, SUM(ISNULL(r.delta_value, 0)) AS sum_value, COUNT(DISTINCT r.meter_id) AS meter_count
INTO #a
FROM [dbo].[METER_READING] AS r JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
WHERE r.obis_code IN ('1.8.0', '2.8.0') AND r.reading_timestamp = @ref AND r.status IN ('VALID', 'ESTIMATED', 'EDITED')
GROUP BY m.transformer_id, r.obis_code
OPTION (RECOMPILE);
SET STATISTICS XML OFF; SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

PRINT '--- Query B ($(STATE) index) ---';
SET STATISTICS IO ON; SET STATISTICS TIME ON; SET STATISTICS XML ON;
SELECT r.reading_timestamp, m.transformer_id, SUM(ISNULL(r.delta_value, 0)) AS kwh, COUNT(DISTINCT r.meter_id) AS meter_count
INTO #b
FROM [dbo].[METER_READING] AS r JOIN [dbo].[METER] AS m ON m.meter_id = r.meter_id
WHERE r.obis_code IN ('1.8.0', '2.8.0') AND r.reading_timestamp >= @from AND r.reading_timestamp < @ref AND r.status <> 'SUSPECT'
GROUP BY r.reading_timestamp, m.transformer_id
OPTION (RECOMPILE);
SET STATISTICS XML OFF; SET STATISTICS IO OFF; SET STATISTICS TIME OFF;
SELECT @na = COUNT(*) FROM #a; SELECT @nb = COUNT(*) FROM #b;
PRINT 'rows: A = ' + CAST(@na AS VARCHAR(10)) + ', B = ' + CAST(@nb AS VARCHAR(10));
