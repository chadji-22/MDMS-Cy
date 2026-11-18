/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_09_gdpr.sql  -  Build Spec §9.9: GDPR requests (Algorithm F)
   GDPR_REQUEST.status (§4.2): SUBMITTED -> UNDER_REVIEW -> PRE_APPROVED -> APPROVED -> EXECUTED;
   SUBMITTED | UNDER_REVIEW | PRE_APPROVED -> REJECTED.
   TR17 writes one AUDIT_LOG row per stage: these rows are the review history.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf §1.4 p.6-7: right to be forgotten, or retention reduced to one month; UC-07, UC-08]
CREATE OR ALTER PROCEDURE [dbo].[sp_SubmitGdprRequest]
    @actor_user_id INT,
    @request_type  VARCHAR(30),
    @meter_id      INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_SubmitGdprRequest';

    IF @request_type IS NULL OR @request_type NOT IN ('RIGHT_TO_BE_FORGOTTEN', 'RETENTION_REDUCTION')
        THROW 50004, 'Invalid input: unknown request type.', 1;
    IF @request_type = 'RIGHT_TO_BE_FORGOTTEN' SET @meter_id = NULL;
    IF @request_type = 'RETENTION_REDUCTION' AND @meter_id IS NULL
        THROW 50004, 'Invalid input: a retention reduction is asked for one meter.', 1;
    IF @meter_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM [dbo].[METER] AS m JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
                       WHERE m.meter_id = @meter_id AND p.user_id = @actor_user_id)
        THROW 50002, 'Permission denied: not your meter.', 1;

    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF EXISTS (SELECT 1 FROM [dbo].[GDPR_REQUEST] WITH (UPDLOCK, HOLDLOCK)
                   WHERE user_id = @actor_user_id AND request_type = @request_type
                     AND status NOT IN ('REJECTED', 'EXECUTED')
                     AND (@meter_id IS NULL OR meter_id = @meter_id))
            THROW 50005, 'Duplicate: you already have an open request of this type.', 1;

        INSERT INTO [dbo].[GDPR_REQUEST] (request_type, status, user_id, meter_id)
        VALUES (@request_type, 'SUBMITTED', @actor_user_id, @meter_id);
        SET @new_id = SCOPE_IDENTITY();
        COMMIT TRANSACTION;
        SELECT @new_id AS gdpr_request_id, 'SUBMITTED' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.4 p.6: stages of submission, review, pre-approval and final approval, each one logged; UC-07]
-- [AR: two-person rule - the officer who gives the final approval is not the one who pre-approved]
CREATE OR ALTER PROCEDURE [dbo].[sp_AdvanceGdprRequest]
    @actor_user_id   INT,
    @gdpr_request_id INT,
    @new_status      VARCHAR(20),
    @comment         NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_AdvanceGdprRequest';

    IF @new_status IS NULL OR @new_status NOT IN ('UNDER_REVIEW', 'PRE_APPROVED', 'APPROVED', 'REJECTED')
        THROW 50004, 'Invalid input: the new status must be UNDER_REVIEW, PRE_APPROVED, APPROVED or REJECTED.', 1;

    DECLARE @old VARCHAR(20), @pre_approver INT;
    SELECT @old = status FROM [dbo].[GDPR_REQUEST] WHERE gdpr_request_id = @gdpr_request_id;
    IF @old IS NULL
        THROW 50001, 'GDPR request not found.', 1;

    IF @new_status = 'APPROVED'
    BEGIN
        SELECT TOP (1) @pre_approver = l.user_id
        FROM [dbo].[AUDIT_LOG] AS l
        WHERE l.object_type = 'GDPR_REQUEST' AND l.object_id = CAST(@gdpr_request_id AS VARCHAR(30))
          AND l.action = 'STATUS_CHANGE' AND l.new_state = N'PRE_APPROVED'
        ORDER BY l.log_id DESC;
        IF @pre_approver = @actor_user_id
            THROW 50002, 'Permission denied: the final approval must come from a different officer than the pre-approval.', 1;
    END

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[GDPR_REQUEST]
           SET status = @new_status,
               decided_at = CASE WHEN @new_status IN ('APPROVED', 'REJECTED') THEN SYSUTCDATETIME() ELSE decided_at END
         WHERE gdpr_request_id = @gdpr_request_id
           AND status = @old
           AND (   (@new_status = 'UNDER_REVIEW' AND status = 'SUBMITTED')
                OR (@new_status = 'PRE_APPROVED' AND status = 'UNDER_REVIEW')
                OR (@new_status = 'APPROVED'     AND status = 'PRE_APPROVED')
                OR (@new_status = 'REJECTED'     AND status IN ('SUBMITTED', 'UNDER_REVIEW', 'PRE_APPROVED')));
        IF @@ROWCOUNT = 0
            THROW 50003, 'This step is not allowed from the current stage of the request.', 1;
        IF @comment IS NOT NULL
            EXEC [dbo].[sp__Log] 'STAGE_COMMENT', 'GDPR_REQUEST', @gdpr_request_id, @old, @new_status, @comment;
        COMMIT TRANSACTION;
        SELECT @gdpr_request_id AS gdpr_request_id, @new_status AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.4 p.6-7: an approved request is carried out; UC-07, UC-08]  Algorithm F, one transaction
-- RETENTION_REDUCTION : the meter keeps 1 month of detailed readings; older ones are purged; aggregates stay.
-- RIGHT_TO_BE_FORGOTTEN: the account is anonymized and can no longer log in; the detailed readings of the
--   user's meters are cut to 1 month. Kept on purpose: bills, payments, aggregates, events, audit log,
--   and the premise row (it now points to an anonymous user).
CREATE OR ALTER PROCEDURE [dbo].[sp_ExecuteGdprRequest]
    @actor_user_id   INT,
    @gdpr_request_id INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_ExecuteGdprRequest';

    DECLARE @type VARCHAR(30), @user_id INT, @meter_id INT, @m INT, @n INT, @deleted INT = 0;
    SELECT @type = request_type, @user_id = user_id, @meter_id = meter_id
    FROM [dbo].[GDPR_REQUEST] WHERE gdpr_request_id = @gdpr_request_id;
    IF @type IS NULL
        THROW 50001, 'GDPR request not found.', 1;

    DECLARE @salt VARBINARY(16) = CRYPT_GEN_RANDOM(16);
    DECLARE @random_password NVARCHAR(128) = CONVERT(NVARCHAR(128), CRYPT_GEN_RANDOM(32), 2);   -- nobody knows it
    DECLARE @comment NVARCHAR(500);

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[GDPR_REQUEST]
           SET status = 'EXECUTED'
         WHERE gdpr_request_id = @gdpr_request_id AND status = 'APPROVED';
        IF @@ROWCOUNT = 0
            THROW 50003, 'Only an APPROVED request can be executed.', 1;

        IF @type = 'RETENTION_REDUCTION'
        BEGIN
            UPDATE [dbo].[METER] SET retention_months = 1 WHERE meter_id = @meter_id AND retention_months <> 1;   -- TR13 logs it
            EXEC [dbo].[sp__PurgeMeter] @meter_id, 1, @n OUTPUT;
            SET @deleted = @n;
        END
        ELSE
        BEGIN
            -- 1. anonymize the account (TR10 logs ANONYMIZE; no personal value is written to the log)
            UPDATE [dbo].[USER_ACCOUNT]
               SET email = 'forgotten_' + CAST(user_id AS VARCHAR(12)) + '@anon.invalid',
                   full_name = N'FORGOTTEN USER',
                   phone = NULL, iban = NULL,
                   password_salt = @salt,
                   password_hash = [dbo].[fn_HashPassword](@random_password, @salt),
                   notify_email = 0, notify_sms = 0,
                   is_active = 0,
                   anonymized_at = SYSUTCDATETIME()
             WHERE user_id = @user_id AND anonymized_at IS NULL;

            -- 2. the detailed 15-min data shows activity patterns: cut it to 1 month for every meter of the user
            DECLARE c CURSOR LOCAL FAST_FORWARD FOR
                SELECT m.meter_id
                FROM [dbo].[METER] AS m JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
                WHERE p.user_id = @user_id;
            OPEN c;
            FETCH NEXT FROM c INTO @m;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                UPDATE [dbo].[METER] SET retention_months = 1 WHERE meter_id = @m AND retention_months <> 1;
                EXEC [dbo].[sp__PurgeMeter] @m, 1, @n OUTPUT;
                SET @deleted = @deleted + @n;
                FETCH NEXT FROM c INTO @m;
            END
            CLOSE c;
            DEALLOCATE c;

            -- 3. no more alerts for this user
            UPDATE [dbo].[PREMISE] SET monthly_threshold_kwh = NULL
             WHERE user_id = @user_id AND monthly_threshold_kwh IS NOT NULL;
        END

        SET @comment = @type + N': readings deleted ' + CAST(@deleted AS NVARCHAR(12));
        EXEC [dbo].[sp__Log] 'GDPR_EXECUTE', 'GDPR_REQUEST', @gdpr_request_id, 'APPROVED', 'EXECUTED', @comment;
        COMMIT TRANSACTION;
        SELECT @gdpr_request_id AS gdpr_request_id, 'EXECUTED' AS status, @deleted AS readings_deleted;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'c') >= 0 CLOSE c;
        IF CURSOR_STATUS('local', 'c') >= -1 DEALLOCATE c;
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.4 p.6: requests with the history of their stages]
-- Officer: all requests. Consumer: own requests.
CREATE OR ALTER PROCEDURE [dbo].[sp_ListGdprRequests]
    @actor_user_id INT,
    @status        VARCHAR(20) = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,CONSUMER';
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 500 SET @page_size = 50;

    DECLARE @role VARCHAR(20);
    SELECT @role = role_code FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;

    SELECT g.gdpr_request_id, g.request_type, g.status, g.submitted_at, g.decided_at, g.user_id, g.meter_id,
           (SELECT STRING_AGG(CAST(CONVERT(NVARCHAR(19), l.logged_at, 120) + N' ' + l.action
                                   + ISNULL(N' ' + l.old_state, N'') + ISNULL(N' -> ' + l.new_state, N'')
                                   + ISNULL(N' by user ' + CAST(l.user_id AS NVARCHAR(12)), N'') AS NVARCHAR(MAX)), N'; ')
                   WITHIN GROUP (ORDER BY l.log_id)
            FROM [dbo].[AUDIT_LOG] AS l
            WHERE l.object_type = 'GDPR_REQUEST' AND l.object_id = CAST(g.gdpr_request_id AS VARCHAR(30))) AS history
    FROM [dbo].[GDPR_REQUEST] AS g
    WHERE (@role = 'SYSTEM_OFFICER' OR g.user_id = @actor_user_id)
      AND (@status IS NULL OR g.status = @status)
    ORDER BY g.submitted_at DESC, g.gdpr_request_id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END;
GO

PRINT 'procedures_09_gdpr.sql: 4 procedures created.';
GO
