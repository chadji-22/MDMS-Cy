/* ============================================================================
   seed_grid.sql  -  demo transformers for the telemetry tests

   Ported to the io schema (v6):
     * there is no GEOFENCE table; a geofence IS a TRANSFORMER row
       ([level], parent_transformer_id and an optional WGS84 rectangle);
     * level 1 = low-voltage transformer that meters hang on, level n = ancestor
       (TR09 checks that a parent is exactly one level above its child);
     * the rows are created through sp_UpsertTransformer, which needs a TSO.

   The first version built its own DEMO_L3 > DEMO_L2 > DEMO_L1 chain with no parent. In io that would be
   a SECOND ROOT next to "TX-L4 Cyprus" (import.sql), and tests.sql H4 requires every root to be at the
   top level. So the demo chain hangs under the existing "TX-L3 Nicosia" instead:

        TX-L3 Nicosia (import.sql)
          +-- DEMO_TX_L2   level 2, 2000 kVA, 35.12-35.22 / 33.32-33.45   (was DEMO_L2)
                +-- DEMO_TX_L1   level 1, 500 kVA, 35.14-35.18 / 33.34-33.40   (was DEMO_L1 + DEMO_TRANSFORMER_1)

   Needs: import.sql (tso@mdms.cy and TX-L3 Nicosia). Re-runnable: a transformer that exists is not created again.
   ============================================================================ */
SET NOCOUNT ON;

DECLARE @tso INT, @l3 INT, @l2 INT;
SELECT @tso = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'tso@mdms.cy';
SELECT @l3  = transformer_id FROM [dbo].[TRANSFORMER] WHERE name = N'TX-L3 Nicosia' AND [level] = 3;
IF @tso IS NULL OR @l3 IS NULL
    THROW 54000, 'seed_grid.sql: run import.sql first (tso@mdms.cy or the transformer TX-L3 Nicosia is missing).', 1;

-- level 2 (the rectangle of a child must lie inside the rectangle of its parent: TX-L3 Nicosia is 35.05-35.25 / 33.20-33.50)
IF NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE name = N'DEMO_TX_L2')
    EXEC [dbo].[sp_UpsertTransformer] @actor_user_id = @tso, @transformer_id = NULL, @name = N'DEMO_TX_L2',
         @level = 2, @capacity_kva = 2000, @latitude = 35.170, @longitude = 33.385,
         @min_lat = 35.12, @min_lon = 33.32, @max_lat = 35.22, @max_lon = 33.45, @parent_transformer_id = @l3;
SELECT @l2 = transformer_id FROM [dbo].[TRANSFORMER] WHERE name = N'DEMO_TX_L2';

-- level 1: the low-voltage transformer of the demo meter (was DEMO_TRANSFORMER_1, 500 kVA)
IF NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE name = N'DEMO_TX_L1')
    EXEC [dbo].[sp_UpsertTransformer] @actor_user_id = @tso, @transformer_id = NULL, @name = N'DEMO_TX_L1',
         @level = 1, @capacity_kva = 500, @latitude = 35.160, @longitude = 33.370,
         @min_lat = 35.14, @min_lon = 33.34, @max_lat = 35.18, @max_lon = 33.40, @parent_transformer_id = @l2;

SELECT t.transformer_id, t.name, t.[level], t.capacity_kva, p.name AS parent_name,
       t.min_lat, t.min_lon, t.max_lat, t.max_lon
FROM [dbo].[TRANSFORMER] AS t
LEFT JOIN [dbo].[TRANSFORMER] AS p ON p.transformer_id = t.parent_transformer_id
WHERE t.name IN (N'DEMO_TX_L1', N'DEMO_TX_L2')
ORDER BY t.[level] DESC;
