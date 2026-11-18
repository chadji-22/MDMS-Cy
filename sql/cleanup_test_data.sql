/* ============================================================================
   cleanup_test_data.sql  -  removes ALL telemetry test data of the four test files

   Each test already cleans up after itself. Run this one only if a test was aborted half way
   (the readings, packets and events of the test days 2025-06-10 .. 2025-06-13 are left behind).

   Deleted:  events and packets of the DEMO-* network ids and the readings of DEMO-NET-001
             on 2025-06-10 .. 2025-06-13 (the days the tests use).
   Kept:     the seeds (DEMO-NET-001, DEMO_TX_L1, DEMO_TX_L2) and the audit log (append-only, TR03).
   ============================================================================ */
SET NOCOUNT ON;
DECLARE @m INT = (SELECT meter_id FROM [dbo].[METER] WHERE network_id = 'DEMO-NET-001');

DELETE e FROM [dbo].[EVENT] AS e
JOIN [dbo].[TELEMETRY_PACKET] AS p ON p.packet_id = e.packet_id
WHERE p.meter_network_id LIKE 'DEMO-%' AND p.transmission_timestamp >= '2025-06-10' AND p.transmission_timestamp < '2025-06-14';
DECLARE @e INT = @@ROWCOUNT;
DELETE FROM [dbo].[METER_READING] WHERE meter_id = @m AND reading_timestamp >= '2025-06-10' AND reading_timestamp < '2025-06-14';
DECLARE @r INT = @@ROWCOUNT;
DELETE FROM [dbo].[TELEMETRY_PACKET]
WHERE meter_network_id LIKE 'DEMO-%' AND transmission_timestamp >= '2025-06-10' AND transmission_timestamp < '2025-06-14';
DECLARE @p INT = @@ROWCOUNT;
PRINT 'cleanup_test_data.sql: ' + CAST(@e AS VARCHAR(10)) + ' events, ' + CAST(@r AS VARCHAR(10))
      + ' readings, ' + CAST(@p AS VARCHAR(10)) + ' packets deleted.';
