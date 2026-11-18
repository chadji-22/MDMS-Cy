/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_10_market.sql  -  Build Spec §9.10: market data for suppliers and aggregators
   The organization of the actor comes from USER_ACCOUNT.organization_id, never from a parameter.
   A supplier sees only premises with supplier_org_id = its organization; an aggregator only those
   with aggregator_org_id = its organization. No raw rows of single meters are returned.
   [AR: groups with fewer than 3 meters are suppressed, so no single household can be singled out;
        supports §1.4 p.6 "aggregated data is preferred"]
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf §5.1 p.10-11; §5.2 p.11 Day-Ahead: validated data in daily form; UC-18]
-- From the final DAY aggregates of the organization's meters, per day and per transformer at @group_level.
CREATE OR ALTER PROCEDURE [dbo].[sp_GetDayAheadAggregates]
    @actor_user_id       INT,
    @from                DATE,
    @to                  DATE,
    @group_level         TINYINT = 1,
    @root_transformer_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SUPPLIER,AGGREGATOR';

    IF @from IS NULL OR @to IS NULL OR @to < @from
        THROW 50004, 'Invalid input: the period must have from <= to.', 1;
    SET @group_level = ISNULL(@group_level, 1);

    DECLARE @role VARCHAR(20), @org INT;
    SELECT @role = role_code, @org = organization_id FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;

    -- the meters of my organization
    SELECT m.meter_id, m.transformer_id
    INTO #Mine
    FROM [dbo].[PREMISE] AS p
    JOIN [dbo].[METER] AS m ON m.premise_id = p.premise_id
    WHERE (@role = 'SUPPLIER' AND p.supplier_org_id = @org)
       OR (@role = 'AGGREGATOR' AND p.aggregator_org_id = @org);

    -- each level-1 transformer -> its ancestor at the requested level
    SELECT t.transformer_id AS l1_id, g.transformer_id AS group_id
    INTO #Map
    FROM (SELECT DISTINCT transformer_id FROM #Mine) AS t
    CROSS APPLY [dbo].[fn_TransformerAncestors](t.transformer_id) AS g
    WHERE g.[level] = @group_level
      AND (@root_transformer_id IS NULL
           OR t.transformer_id IN (SELECT s.transformer_id FROM [dbo].[fn_TransformerSubtree](@root_transformer_id) AS s));

    SELECT CAST(a.period_start AS DATE) AS [day], x.group_id AS transformer_id, tr.name AS transformer_name,
           SUM(CASE WHEN a.obis_code = '1.8.0' THEN a.[value] ELSE 0 END) AS import_kwh,
           SUM(CASE WHEN a.obis_code = '2.8.0' THEN a.[value] ELSE 0 END) AS export_kwh,
           SUM(CASE WHEN a.obis_code = '1.8.0' THEN a.[value] ELSE -a.[value] END) AS net_kwh,
           COUNT(DISTINCT a.meter_id) AS meter_count
    FROM #Mine AS me
    JOIN #Map AS x ON x.l1_id = me.transformer_id
    JOIN [dbo].[TRANSFORMER] AS tr ON tr.transformer_id = x.group_id
    JOIN [dbo].[AGGREGATE] AS a ON a.meter_id = me.meter_id
    WHERE a.period_type = 'DAY' AND a.is_final = 1
      AND a.obis_code IN ('1.8.0', '2.8.0')
      AND a.period_start >= CAST(@from AS DATETIME2(0))
      AND a.period_start < DATEADD(DAY, 1, CAST(@to AS DATETIME2(0)))
    GROUP BY CAST(a.period_start AS DATE), x.group_id, tr.name
    HAVING COUNT(DISTINCT a.meter_id) >= 3
    ORDER BY [day], tr.name;
END;
GO

-- [project.pdf §5.2 p.11 Intraday: data before VEE is complete, marked as provisional; UC-18]
-- Straight from METER_READING (any status except SUSPECT), per 15-min slot and transformer. Window <= 24 h.
CREATE OR ALTER PROCEDURE [dbo].[sp_GetIntradayProvisional]
    @actor_user_id INT,
    @from          DATETIME2(0),
    @to            DATETIME2(0),
    @group_level   TINYINT = 1
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SUPPLIER,AGGREGATOR';

    IF @from IS NULL OR @to IS NULL OR @to <= @from OR DATEDIFF(MINUTE, @from, @to) > 1440
        THROW 50004, 'Invalid input: the window must have from < to and at most 24 hours.', 1;
    SET @group_level = ISNULL(@group_level, 1);

    DECLARE @role VARCHAR(20), @org INT;
    SELECT @role = role_code, @org = organization_id FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;

    SELECT m.meter_id, m.transformer_id
    INTO #Mine
    FROM [dbo].[PREMISE] AS p
    JOIN [dbo].[METER] AS m ON m.premise_id = p.premise_id
    WHERE (@role = 'SUPPLIER' AND p.supplier_org_id = @org)
       OR (@role = 'AGGREGATOR' AND p.aggregator_org_id = @org);

    SELECT t.transformer_id AS l1_id, g.transformer_id AS group_id
    INTO #Map
    FROM (SELECT DISTINCT transformer_id FROM #Mine) AS t
    CROSS APPLY [dbo].[fn_TransformerAncestors](t.transformer_id) AS g
    WHERE g.[level] = @group_level;

    SELECT r.reading_timestamp AS slot, x.group_id AS transformer_id, tr.name AS transformer_name,
           SUM(CASE WHEN r.obis_code = '1.8.0' THEN ISNULL(r.delta_value, 0) ELSE 0 END) AS import_kwh,
           SUM(CASE WHEN r.obis_code = '2.8.0' THEN ISNULL(r.delta_value, 0) ELSE 0 END) AS export_kwh,
           SUM(CASE WHEN r.obis_code = '1.8.0' THEN ISNULL(r.delta_value, 0) ELSE -ISNULL(r.delta_value, 0) END) AS net_kwh,
           COUNT(DISTINCT r.meter_id) AS meter_count,
           CAST(1 AS BIT) AS is_provisional
    FROM [dbo].[METER_READING] AS r
    JOIN #Mine AS me ON me.meter_id = r.meter_id
    JOIN #Map AS x ON x.l1_id = me.transformer_id
    JOIN [dbo].[TRANSFORMER] AS tr ON tr.transformer_id = x.group_id
    WHERE r.obis_code IN ('1.8.0', '2.8.0')
      AND r.reading_timestamp >= @from AND r.reading_timestamp < @to
      AND r.status <> 'SUSPECT'
    GROUP BY r.reading_timestamp, x.group_id, tr.name
    HAVING COUNT(DISTINCT r.meter_id) >= 3
    ORDER BY slot, tr.name;
END;
GO

-- [project.pdf §5.1 p.10: the portfolio of an aggregator / the customers of a supplier]
CREATE OR ALTER PROCEDURE [dbo].[sp_GetPortfolioSummary]
    @actor_user_id INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'AGGREGATOR,SUPPLIER';

    DECLARE @role VARCHAR(20), @org INT;
    SELECT @role = role_code, @org = organization_id FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;

    SELECT p.district,
           COUNT(DISTINCT p.user_id) AS customers,
           COUNT(*) AS premises,
           SUM(CASE WHEN p.prosumer_scheme <> 'NONE' THEN 1 ELSE 0 END) AS prosumers,
           SUM(CASE WHEN p.prosumer_scheme = 'NET_METERING' THEN 1 ELSE 0 END) AS net_metering,
           SUM(CASE WHEN p.prosumer_scheme = 'NET_BILLING' THEN 1 ELSE 0 END) AS net_billing,
           SUM(CASE WHEN m.meter_id IS NOT NULL THEN 1 ELSE 0 END) AS meters_installed,
           SUM(CASE WHEN m.status = 'ACTIVE' THEN 1 ELSE 0 END) AS meters_active
    FROM [dbo].[PREMISE] AS p
    LEFT JOIN [dbo].[METER] AS m ON m.premise_id = p.premise_id AND m.removed_at IS NULL
    WHERE (@role = 'SUPPLIER' AND p.supplier_org_id = @org)
       OR (@role = 'AGGREGATOR' AND p.aggregator_org_id = @org)
    GROUP BY p.district
    ORDER BY p.district;
END;
GO

PRINT 'procedures_10_market.sql: 3 procedures created.';
GO
