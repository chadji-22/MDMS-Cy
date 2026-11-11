/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_03_workorders.sql  -  Build Spec §9.3: requests and work orders
   State machine (§4.2): SUBMITTED -> ASSIGNED -> ACCEPTED -> IN_PROGRESS -> COMPLETED;
   ASSIGNED -> SUBMITTED (declined); SUBMITTED | ASSIGNED | ACCEPTED -> CANCELLED.
   Every change is a guarded UPDATE (the expected state is in the WHERE) -> 50003.
   TR05 checks the technician, TR14 writes the history.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf §1.3 p.6: the consumer asks for a technical check or reports a fault; UC-05]
CREATE OR ALTER PROCEDURE [dbo].[sp_SubmitServiceRequest]
    @actor_user_id INT,
    @premise_id    INT,
    @meter_id      INT = NULL,
    @work_type     VARCHAR(20),
    @description   NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_SubmitServiceRequest';

    IF @work_type IS NULL OR @work_type NOT IN ('TECHNICAL_CHECK', 'FAULT_REPAIR')
        THROW 50004, 'Invalid input: a consumer can ask for TECHNICAL_CHECK or FAULT_REPAIR.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[PREMISE] WHERE premise_id = @premise_id)
        THROW 50001, 'Premise not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[PREMISE] WHERE premise_id = @premise_id AND user_id = @actor_user_id)
        THROW 50002, 'Permission denied: not your premise.', 1;
    IF @meter_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM [dbo].[METER] WHERE meter_id = @meter_id AND premise_id = @premise_id)
        THROW 50004, 'Invalid input: the meter is not on this premise.', 1;

    IF @meter_id IS NULL
        SELECT @meter_id = meter_id FROM [dbo].[METER] WHERE premise_id = @premise_id AND removed_at IS NULL;

    DECLARE @service_id INT = NULL, @new_id INT;
    IF @work_type = 'TECHNICAL_CHECK'
        SELECT @service_id = service_type_id FROM [dbo].[SERVICE_TYPE] WHERE service_name = N'METER_CHECK';

    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[WORK_ORDER] (work_type, origin, description, status, requested_by_user_id,
                                        premise_id, meter_id, service_type_id)
        VALUES (@work_type, 'CONSUMER_REQUEST', @description, 'SUBMITTED', @actor_user_id,
                @premise_id, @meter_id, @service_id);
        SET @new_id = SCOPE_IDENTITY();
        COMMIT TRANSACTION;
        SELECT @new_id AS work_order_id, 'SUBMITTED' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.2 p.7: officers create field jobs; UC-10, UC-14]
-- origin = OFFICER, or EVENT when @event_id is given.
CREATE OR ALTER PROCEDURE [dbo].[sp_CreateWorkOrder]
    @actor_user_id   INT,
    @work_type       VARCHAR(20),
    @premise_id      INT,
    @meter_id        INT = NULL,
    @event_id        BIGINT = NULL,
    @description     NVARCHAR(1000) = NULL,
    @scheduled_start DATETIME2(0) = NULL,
    @scheduled_end   DATETIME2(0) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_CreateWorkOrder';

    IF @work_type IS NULL OR @work_type NOT IN ('INSTALLATION', 'REPLACEMENT', 'TECHNICAL_CHECK', 'FAULT_REPAIR', 'ANTI_TAMPER')
        THROW 50004, 'Invalid input: unknown work type.', 1;
    IF @meter_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [dbo].[METER] WHERE meter_id = @meter_id)
        THROW 50001, 'Meter not found.', 1;
    IF @premise_id IS NULL AND @meter_id IS NOT NULL
        SELECT @premise_id = premise_id FROM [dbo].[METER] WHERE meter_id = @meter_id;
    IF @premise_id IS NULL
        THROW 50004, 'Invalid input: a premise or a meter is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[PREMISE] WHERE premise_id = @premise_id)
        THROW 50001, 'Premise not found.', 1;
    IF @meter_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [dbo].[METER] WHERE meter_id = @meter_id AND premise_id = @premise_id)
        THROW 50004, 'Invalid input: the meter is not on this premise.', 1;
    IF @work_type IN ('REPLACEMENT', 'ANTI_TAMPER') AND @meter_id IS NULL
        THROW 50004, 'Invalid input: REPLACEMENT and ANTI_TAMPER need a meter.', 1;
    IF @work_type = 'INSTALLATION'
       AND EXISTS (SELECT 1 FROM [dbo].[METER] WHERE premise_id = @premise_id AND removed_at IS NULL)
        THROW 50003, 'The premise already has a meter in service; use REPLACEMENT.', 1;
    IF @event_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [dbo].[EVENT] WHERE event_id = @event_id)
        THROW 50001, 'Event not found.', 1;
    IF @scheduled_start IS NOT NULL AND @scheduled_end IS NOT NULL AND @scheduled_end < @scheduled_start
        THROW 50004, 'Invalid input: the schedule ends before it starts.', 1;

    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[WORK_ORDER] (work_type, origin, description, status, scheduled_start, scheduled_end,
                                        requested_by_user_id, premise_id, meter_id, event_id)
        VALUES (@work_type, CASE WHEN @event_id IS NULL THEN 'OFFICER' ELSE 'EVENT' END, @description, 'SUBMITTED',
                @scheduled_start, @scheduled_end, @actor_user_id, @premise_id, @meter_id, @event_id);
        SET @new_id = SCOPE_IDENTITY();
        COMMIT TRANSACTION;
        SELECT @new_id AS work_order_id, 'SUBMITTED' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.3 p.6, §2.2 p.7: the officer gives the job to a suitable technician; UC-05]
-- The technician must be returned by sp_FindAvailableTechnicians for that time and the district of the premise.
CREATE OR ALTER PROCEDURE [dbo].[sp_AssignWorkOrder]
    @actor_user_id      INT,
    @work_order_id      INT,
    @technician_user_id INT,
    @scheduled_start    DATETIME2(0),
    @scheduled_end      DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_AssignWorkOrder';

    IF @scheduled_start IS NULL OR @scheduled_end IS NULL OR @scheduled_end <= @scheduled_start
       OR CAST(@scheduled_start AS DATE) <> CAST(@scheduled_end AS DATE)
        THROW 50004, 'Invalid input: the visit needs a start and a later end on the same day.', 1;

    DECLARE @district NVARCHAR(30), @found INT;
    SELECT @found = w.work_order_id, @district = p.district
    FROM [dbo].[WORK_ORDER] AS w
    LEFT JOIN [dbo].[METER] AS m ON m.meter_id = w.meter_id
    LEFT JOIN [dbo].[PREMISE] AS p ON p.premise_id = COALESCE(w.premise_id, m.premise_id)
    WHERE w.work_order_id = @work_order_id;
    IF @found IS NULL
        THROW 50001, 'Work order not found.', 1;

    DECLARE @date DATE = CAST(@scheduled_start AS DATE);
    DECLARE @start_time TIME(0) = CAST(@scheduled_start AS TIME(0)), @end_time TIME(0) = CAST(@scheduled_end AS TIME(0));

    CREATE TABLE #available (user_id INT, full_name NVARCHAR(150), phone VARCHAR(20), specialty NVARCHAR(100),
                             specialty_match BIT, slot_start TIME(0), slot_end TIME(0));
    INSERT INTO #available
        EXEC [dbo].[sp_FindAvailableTechnicians] @actor_user_id, @date, @start_time, @end_time, @district, NULL;

    IF NOT EXISTS (SELECT 1 FROM #available WHERE user_id = @technician_user_id)
        THROW 50004, 'The technician is not available at that time in the district of the premise.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[WORK_ORDER]
           SET status = 'ASSIGNED', technician_user_id = @technician_user_id,
               scheduled_start = @scheduled_start, scheduled_end = @scheduled_end
         WHERE work_order_id = @work_order_id AND status = 'SUBMITTED';
        IF @@ROWCOUNT = 0
            THROW 50003, 'The work order is not in SUBMITTED state (another officer may have assigned it).', 1;
        COMMIT TRANSACTION;
        SELECT @work_order_id AS work_order_id, 'ASSIGNED' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.2 p.7: the technician accepts a job assigned to them] (template T2)
CREATE OR ALTER PROCEDURE [dbo].[sp_AcceptWorkOrder]
    @actor_user_id INT,
    @work_order_id INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_AcceptWorkOrder';
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[WORK_ORDER]
           SET status = 'ACCEPTED', accepted_at = SYSUTCDATETIME()
         WHERE work_order_id = @work_order_id
           AND technician_user_id = @actor_user_id
           AND status = 'ASSIGNED';                  -- the state check is part of the WHERE
        IF @@ROWCOUNT = 0
            THROW 50003, 'Work order is not assigned to you, or is not in ASSIGNED state.', 1;
        COMMIT TRANSACTION;
        SELECT @work_order_id AS work_order_id, 'ACCEPTED' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.2 p.7: the technician may decline] ASSIGNED -> SUBMITTED, technician cleared, reason logged
CREATE OR ALTER PROCEDURE [dbo].[sp_DeclineWorkOrder]
    @actor_user_id INT,
    @work_order_id INT,
    @reason        NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_DeclineWorkOrder';

    IF @reason IS NULL OR LTRIM(RTRIM(@reason)) = N''
        THROW 50004, 'Invalid input: a reason is required.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[WORK_ORDER]
           SET status = 'SUBMITTED', technician_user_id = NULL, scheduled_start = NULL, scheduled_end = NULL
         WHERE work_order_id = @work_order_id
           AND technician_user_id = @actor_user_id
           AND status = 'ASSIGNED';
        IF @@ROWCOUNT = 0
            THROW 50003, 'Work order is not assigned to you, or is not in ASSIGNED state.', 1;
        EXEC [dbo].[sp__Log] 'DECLINE', 'WORK_ORDER', @work_order_id, 'ASSIGNED', 'SUBMITTED', @reason;
        COMMIT TRANSACTION;
        SELECT @work_order_id AS work_order_id, 'SUBMITTED' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.2 p.7: the technician starts the visit] ACCEPTED -> IN_PROGRESS
CREATE OR ALTER PROCEDURE [dbo].[sp_StartWorkOrder]
    @actor_user_id INT,
    @work_order_id INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_StartWorkOrder';
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[WORK_ORDER]
           SET status = 'IN_PROGRESS'
         WHERE work_order_id = @work_order_id
           AND technician_user_id = @actor_user_id
           AND status = 'ACCEPTED';
        IF @@ROWCOUNT = 0
            THROW 50003, 'Work order is not assigned to you, or is not in ACCEPTED state.', 1;
        COMMIT TRANSACTION;
        SELECT @work_order_id AS work_order_id, 'IN_PROGRESS' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.2 p.7: findings and evidence; §2.4 p.8: persons to notify after an anti-tamper check; UC-05, UC-14]
CREATE OR ALTER PROCEDURE [dbo].[sp_CompleteWorkOrder]
    @actor_user_id     INT,
    @work_order_id     INT,
    @findings          NVARCHAR(2000),
    @evidence_path     VARCHAR(500) = NULL,
    @persons_to_notify NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_CompleteWorkOrder';

    DECLARE @work_type VARCHAR(20);
    SELECT @work_type = work_type FROM [dbo].[WORK_ORDER] WHERE work_order_id = @work_order_id;
    IF @work_type IS NULL
        THROW 50001, 'Work order not found.', 1;
    IF @findings IS NULL OR LTRIM(RTRIM(@findings)) = N''
        THROW 50004, 'Invalid input: the findings are required.', 1;
    IF @work_type = 'ANTI_TAMPER' AND (@persons_to_notify IS NULL OR LTRIM(RTRIM(@persons_to_notify)) = N'')
        THROW 50004, 'Invalid input: an anti-tamper job needs the persons to notify.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[WORK_ORDER]
           SET status = 'COMPLETED', completed_at = SYSUTCDATETIME(), findings = @findings,
               evidence_path = @evidence_path, persons_to_notify = @persons_to_notify
         WHERE work_order_id = @work_order_id
           AND technician_user_id = @actor_user_id
           AND status = 'IN_PROGRESS';
        IF @@ROWCOUNT = 0
            THROW 50003, 'Work order is not assigned to you, or is not in IN_PROGRESS state.', 1;
        COMMIT TRANSACTION;
        SELECT @work_order_id AS work_order_id, 'COMPLETED' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.3 p.6: a request can be withdrawn]
-- Consumer: own request while still SUBMITTED. Officer: SUBMITTED, ASSIGNED or ACCEPTED.
CREATE OR ALTER PROCEDURE [dbo].[sp_CancelWorkOrder]
    @actor_user_id INT,
    @work_order_id INT,
    @reason        NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER,SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_CancelWorkOrder';

    DECLARE @role VARCHAR(20), @requester INT, @old VARCHAR(20);
    SELECT @role = role_code FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;
    SELECT @requester = requested_by_user_id, @old = status FROM [dbo].[WORK_ORDER] WHERE work_order_id = @work_order_id;
    IF @requester IS NULL
        THROW 50001, 'Work order not found.', 1;
    IF @role = 'CONSUMER' AND @requester <> @actor_user_id
        THROW 50002, 'Permission denied: not your request.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[WORK_ORDER]
           SET status = 'CANCELLED'
         WHERE work_order_id = @work_order_id
           AND (   (@role = 'CONSUMER' AND status = 'SUBMITTED' AND requested_by_user_id = @actor_user_id)
                OR (@role = 'SYSTEM_OFFICER' AND status IN ('SUBMITTED', 'ASSIGNED', 'ACCEPTED')));
        IF @@ROWCOUNT = 0
            THROW 50003, 'The work order cannot be cancelled in its current state.', 1;
        IF @reason IS NOT NULL
            EXEC [dbo].[sp__Log] 'CANCEL_REASON', 'WORK_ORDER', @work_order_id, @old, 'CANCELLED', @reason;
        COMMIT TRANSACTION;
        SELECT @work_order_id AS work_order_id, 'CANCELLED' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.2 p.7: the technician sees the jobs and their geographic position; §1.3 p.6 the consumer sees requests]
-- Technician: own open jobs from view_OPEN_WORK_ORDER (with coordinates). Consumer: own requests, any status.
CREATE OR ALTER PROCEDURE [dbo].[sp_ListMyWorkOrders]
    @actor_user_id INT,
    @status        VARCHAR(20) = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN,CONSUMER';
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 500 SET @page_size = 50;

    DECLARE @role VARCHAR(20);
    SELECT @role = role_code FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;

    IF @role = 'TECHNICIAN'
        SELECT v.work_order_id, v.work_type, v.origin, v.description, v.status, v.created_at,
               v.scheduled_start, v.scheduled_end, v.accepted_at, v.premise_id, v.premise_address, v.district,
               v.premise_latitude, v.premise_longitude, v.meter_id, v.meter_latitude, v.meter_longitude
        FROM [dbo].[view_OPEN_WORK_ORDER] AS v
        WHERE v.technician_user_id = @actor_user_id
          AND (@status IS NULL OR v.status = @status)
        ORDER BY v.scheduled_start, v.work_order_id
        OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
    ELSE
        SELECT w.work_order_id, w.work_type, w.origin, w.description, w.status, w.created_at,
               w.scheduled_start, w.scheduled_end, w.accepted_at, w.completed_at, w.findings,
               w.premise_id, p.address AS premise_address, w.meter_id, tech.full_name AS technician_name,
               s.service_name, s.fee
        FROM [dbo].[WORK_ORDER] AS w
        LEFT JOIN [dbo].[PREMISE] AS p ON p.premise_id = w.premise_id
        LEFT JOIN [dbo].[USER_ACCOUNT] AS tech ON tech.user_id = w.technician_user_id
        LEFT JOIN [dbo].[SERVICE_TYPE] AS s ON s.service_type_id = w.service_type_id
        WHERE w.requested_by_user_id = @actor_user_id
          AND (@status IS NULL OR w.status = @status)
        ORDER BY w.created_at DESC, w.work_order_id DESC
        OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END;
GO

-- [project.pdf §2.2 p.7: the officer follows all the jobs]
CREATE OR ALTER PROCEDURE [dbo].[sp_ListWorkOrders]
    @actor_user_id INT,
    @status        VARCHAR(20)  = NULL,
    @work_type     VARCHAR(20)  = NULL,
    @district      NVARCHAR(30) = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO,SYSTEM_ADMIN';
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 500 SET @page_size = 50;

    SELECT w.work_order_id, w.work_type, w.origin, w.description, w.status, w.created_at,
           w.scheduled_start, w.scheduled_end, w.accepted_at, w.completed_at,
           w.requested_by_user_id, w.technician_user_id, tech.full_name AS technician_name,
           p.premise_id, p.address AS premise_address, p.district, w.meter_id, w.event_id
    FROM [dbo].[WORK_ORDER] AS w
    LEFT JOIN [dbo].[METER] AS m ON m.meter_id = w.meter_id
    LEFT JOIN [dbo].[PREMISE] AS p ON p.premise_id = COALESCE(w.premise_id, m.premise_id)
    LEFT JOIN [dbo].[USER_ACCOUNT] AS tech ON tech.user_id = w.technician_user_id
    WHERE (@status IS NULL OR w.status = @status)
      AND (@work_type IS NULL OR w.work_type = @work_type)
      AND (@district IS NULL OR p.district = @district)
    ORDER BY w.created_at DESC, w.work_order_id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END;
GO

-- [project.pdf §1.3 p.6: every request has a status and a history]
-- The work order with its AUDIT_LOG rows in time order (one row per history entry).
CREATE OR ALTER PROCEDURE [dbo].[sp_GetWorkOrderHistory]
    @actor_user_id INT,
    @work_order_id INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER,TECHNICIAN,SYSTEM_OFFICER';

    DECLARE @role VARCHAR(20), @requester INT, @technician INT, @owner INT;
    SELECT @role = role_code FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;
    SELECT @requester = w.requested_by_user_id, @technician = w.technician_user_id, @owner = p.user_id
    FROM [dbo].[WORK_ORDER] AS w
    LEFT JOIN [dbo].[METER] AS m ON m.meter_id = w.meter_id
    LEFT JOIN [dbo].[PREMISE] AS p ON p.premise_id = COALESCE(w.premise_id, m.premise_id)
    WHERE w.work_order_id = @work_order_id;

    IF @requester IS NULL
        THROW 50001, 'Work order not found.', 1;
    IF (@role = 'CONSUMER' AND @actor_user_id NOT IN (@requester, ISNULL(@owner, 0)))
       OR (@role = 'TECHNICIAN' AND ISNULL(@technician, 0) <> @actor_user_id)
        THROW 50002, 'Permission denied: not your work order.', 1;

    SELECT w.work_order_id, w.work_type, w.origin, w.status AS current_status, w.description, w.findings,
           w.scheduled_start, w.scheduled_end, w.completed_at,
           l.logged_at, l.action, l.old_state, l.new_state, l.comment, l.actor_type, l.mechanism,
           l.user_id AS actor_user_id, u.full_name AS actor_name
    FROM [dbo].[WORK_ORDER] AS w
    LEFT JOIN [dbo].[AUDIT_LOG] AS l ON l.object_type = 'WORK_ORDER' AND l.object_id = CAST(w.work_order_id AS VARCHAR(30))
    LEFT JOIN [dbo].[USER_ACCOUNT] AS u ON u.user_id = l.user_id
    WHERE w.work_order_id = @work_order_id
    ORDER BY l.logged_at, l.log_id;
END;
GO

PRINT 'procedures_03_workorders.sql: 11 procedures created.';
GO
