/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   indexes.sql  -  Build Spec §10
   Re-runnable: DROP INDEX IF EXISTS, then CREATE.
   The PDF asks for the three most important indexes, documented (which, why, how) and one
   measured before / after case [§IV p.12]. IX1 - IX3 are those three; perf.sql measures IX1.
   The unique and filtered unique indexes of the keys are in create.sql.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------------
   IX1  [project.pdf §4.2 p.10; §5.2 p.11]
   WHICH : METER_READING (obis_code, reading_timestamp) INCLUDE (meter_id, delta_value, status)
   WHY   : the tree refresh (Algorithm E) and the transformer aggregates (Algorithm D) read EVERY meter
           at ONE slot for 1.8.0 / 2.8.0; the intraday market data reads every meter over a few hours.
           The clustered key is reading_id and the unique key starts with meter_id, so without this
           index those queries scan the whole table.
   HOW   : non-clustered, covering (the INCLUDE columns answer the query without a key lookup).
   --------------------------------------------------------------------------- */
DROP INDEX IF EXISTS [IX_METER_READING_obis_slot] ON [dbo].[METER_READING];
CREATE NONCLUSTERED INDEX [IX_METER_READING_obis_slot]
    ON [dbo].[METER_READING] (obis_code, reading_timestamp)
    INCLUDE (meter_id, delta_value, status);
GO

/* ---------------------------------------------------------------------------
   IX2  [project.pdf §3.2 p.8-9]
   WHICH : METER_READING (meter_id, reading_timestamp) INCLUDE (obis_code, value, delta_value, status)
           WHERE is_final = 0
   WHY   : VEE and finalization touch only readings that are not final yet. After finalization a row
           leaves the index, so the index stays small (days of data) while the table keeps years.
   HOW   : filtered non-clustered index.
   --------------------------------------------------------------------------- */
DROP INDEX IF EXISTS [IX_METER_READING_not_final] ON [dbo].[METER_READING];
CREATE NONCLUSTERED INDEX [IX_METER_READING_not_final]
    ON [dbo].[METER_READING] (meter_id, reading_timestamp)
    INCLUDE (obis_code, [value], delta_value, status)
    WHERE is_final = 0;
GO

/* ---------------------------------------------------------------------------
   IX3  [project.pdf §5.1 p.10; §1.3 p.6]
   WHICH : PREMISE (supplier_org_id) INCLUDE (prosumer_scheme)  and  PREMISE (aggregator_org_id) INCLUDE (prosumer_scheme)
   WHY   : the market procedures and the bill run start from "all the premises of my organization".
   HOW   : two non-clustered indexes on the foreign keys (SQL Server does not index foreign keys by itself).
   --------------------------------------------------------------------------- */
DROP INDEX IF EXISTS [IX_PREMISE_supplier] ON [dbo].[PREMISE];
CREATE NONCLUSTERED INDEX [IX_PREMISE_supplier]
    ON [dbo].[PREMISE] (supplier_org_id) INCLUDE (prosumer_scheme);

DROP INDEX IF EXISTS [IX_PREMISE_aggregator] ON [dbo].[PREMISE];
CREATE NONCLUSTERED INDEX [IX_PREMISE_aggregator]
    ON [dbo].[PREMISE] (aggregator_org_id) INCLUDE (prosumer_scheme);
GO

-- 4. [§II.Δ p.3] shedding and tree sums: the meters of a transformer
DROP INDEX IF EXISTS [IX_METER_transformer] ON [dbo].[METER];
CREATE NONCLUSTERED INDEX [IX_METER_transformer]
    ON [dbo].[METER] (transformer_id) INCLUDE (status, premise_id);

-- 5. [§1.2 p.5-6] consumer screens: the meters of a premise (also the removed ones)
DROP INDEX IF EXISTS [IX_METER_premise] ON [dbo].[METER];
CREATE NONCLUSTERED INDEX [IX_METER_premise]
    ON [dbo].[METER] (premise_id) INCLUDE (status, removed_at);
GO

-- 6. [§2.2 p.7] the job list of a technician and the overlap check when assigning
DROP INDEX IF EXISTS [IX_WORK_ORDER_open] ON [dbo].[WORK_ORDER];
CREATE NONCLUSTERED INDEX [IX_WORK_ORDER_open]
    ON [dbo].[WORK_ORDER] (technician_user_id, status)
    INCLUDE (scheduled_start, scheduled_end)
    WHERE status IN ('ASSIGNED', 'ACCEPTED', 'IN_PROGRESS');
GO

-- 7. [Κοινές αρχές p.5] history of a work order, a command, a GDPR request
DROP INDEX IF EXISTS [IX_AUDIT_LOG_object] ON [dbo].[AUDIT_LOG];
CREATE NONCLUSTERED INDEX [IX_AUDIT_LOG_object]
    ON [dbo].[AUDIT_LOG] (object_type, object_id, logged_at);

-- 8. [§1.2 p.5; §II.Γ p.3] events of a meter: consumer screen, threshold check, theft report
DROP INDEX IF EXISTS [IX_EVENT_meter_time] ON [dbo].[EVENT];
CREATE NONCLUSTERED INDEX [IX_EVENT_meter_time]
    ON [dbo].[EVENT] (meter_id, event_timestamp) INCLUDE (event_type, severity);

-- 9. [§3.1 p.8] looking into the packets of a network id that did not match
DROP INDEX IF EXISTS [IX_TELEMETRY_PACKET_network] ON [dbo].[TELEMETRY_PACKET];
CREATE NONCLUSTERED INDEX [IX_TELEMETRY_PACKET_network]
    ON [dbo].[TELEMETRY_PACKET] (meter_network_id, received_at);

-- 10. [§4.1 p.9] every walk of the tree asks for "the children of this transformer"
DROP INDEX IF EXISTS [IX_TRANSFORMER_parent] ON [dbo].[TRANSFORMER];
CREATE NONCLUSTERED INDEX [IX_TRANSFORMER_parent]
    ON [dbo].[TRANSFORMER] (parent_transformer_id);
GO

-- 11. [§IV p.13 concurrency] one bill per premise and month, even when two bill runs race
DROP INDEX IF EXISTS [UQ_BILL_premise_period] ON [dbo].[BILL];
CREATE UNIQUE NONCLUSTERED INDEX [UQ_BILL_premise_period]
    ON [dbo].[BILL] (premise_id, period_start)
    WHERE status <> 'CANCELLED';

-- 12. [§1.3 p.6] fn_BillPaid and TR06: the payments of a bill
DROP INDEX IF EXISTS [IX_PAYMENT_bill] ON [dbo].[PAYMENT];
CREATE NONCLUSTERED INDEX [IX_PAYMENT_bill]
    ON [dbo].[PAYMENT] (bill_id) INCLUDE (amount, status)
    WHERE bill_id IS NOT NULL;
GO

-- [AR: added to the catalog] the purge of old packets and the delete check of the FK need the packet of a reading
DROP INDEX IF EXISTS [IX_METER_READING_packet] ON [dbo].[METER_READING];
CREATE NONCLUSTERED INDEX [IX_METER_READING_packet]
    ON [dbo].[METER_READING] (packet_id)
    WHERE packet_id IS NOT NULL;
GO

/* ---------------------------------------------------------------------------
   Contention point 1  [project.pdf §IV p.12]
   METER_READING, TELEMETRY_PACKET and AUDIT_LOG are clustered on an IDENTITY key, so every insert
   goes to the last page (last-page insert contention when many packets arrive together).
   OPTIMIZE_FOR_SEQUENTIAL_KEY (SQL Server 2019+) keeps the throughput under that pressure.
   Contention point 2 is TRANSFORMER_CURRENT_STATE: see sp_RefreshTransformerState (Algorithm E).
   --------------------------------------------------------------------------- */
BEGIN TRY
    ALTER INDEX [PK_METER_READING]    ON [dbo].[METER_READING]    SET (OPTIMIZE_FOR_SEQUENTIAL_KEY = ON);
    ALTER INDEX [PK_TELEMETRY_PACKET] ON [dbo].[TELEMETRY_PACKET] SET (OPTIMIZE_FOR_SEQUENTIAL_KEY = ON);
    ALTER INDEX [PK_AUDIT_LOG]        ON [dbo].[AUDIT_LOG]        SET (OPTIMIZE_FOR_SEQUENTIAL_KEY = ON);
END TRY
BEGIN CATCH
    PRINT 'OPTIMIZE_FOR_SEQUENTIAL_KEY was not applied: ' + ERROR_MESSAGE();
END CATCH
GO

PRINT 'indexes.sql: indexes created.';
GO
