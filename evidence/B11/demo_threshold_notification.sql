/* B11 demo [project.pdf §1.2 p.6]: a consumer threshold is passed -> THRESHOLD_EXCEEDED event -> TR23 records one
   SIMULATED notification per chosen channel -> the consumer sees them (sp_ListMyNotifications, events.php).
   Every call runs as mdms_php, the EXECUTE-only user of the web application. Re-runnable: one event per meter per month,
   so a second run raises nothing new and lists the same notifications. Uses consumer8 (premise 10). */
SET NOCOUNT ON;
DECLARE @c8 INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'consumer8@example.cy');
DECLARE @off1 INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'officer1@mdms.cy');
DECLARE @p10 INT = (SELECT premise_id FROM dbo.PREMISE WHERE user_id = @c8);
DECLARE @last_month_end DATE = EOMONTH(CAST(SYSUTCDATETIME() AS DATE), -1);
EXECUTE AS USER = 'mdms_php';
PRINT '1. consumer8 sets a monthly threshold of 5 kWh on premise ' + CAST(@p10 AS VARCHAR(10));
EXEC dbo.sp_SetPremiseThreshold @c8, @p10, 5.0;
PRINT '2. the officer runs the threshold job for the last day of the previous month';
EXEC dbo.sp_CheckConsumptionThresholds @off1, @last_month_end;
PRINT '3. consumer8 lists the notifications of the premise';
EXEC dbo.sp_ListMyNotifications @c8, @p10;
PRINT '4. the events of the premise';
EXEC dbo.sp_GetPremiseEvents @c8, @p10, NULL, NULL;
REVERT;
