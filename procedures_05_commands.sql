/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_05_commands.sql  -  Build Spec §9.5: remote commands
   REMOTE_COMMAND.status (§4.2): PENDING_APPROVAL -> APPROVED | REJECTED;
   APPROVED -> SENT (attempt 1); SENT -> SENT (attempt n); SENT -> ACKNOWLEDGED | FAILED.
   TR16 allows commands only for ACTIVE meters; TR15 logs every status change and attempt.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf §2.4 p.8: remote disconnect / reconnect / firmware upgrade, with approval where needed; UC-12]
-- Technician -> PENDING_APPROVAL. DSO, TSO, officer -> APPROVED at once.
CREATE OR ALTER PROCEDURE [dbo].[sp_RequestRemoteCommand]
    @actor_user_id INT,
    @meter_id      INT,
    @command_type  VARCHAR(20),
    @parameters    NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN,DSO,TSO,SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_RequestRemoteCommand';

    IF @command_type IS NULL OR @command_type NOT IN ('DISCONNECT', 'RECONNECT', 'FIRMWARE_UPGRADE')
        THROW 50004, 'Invalid input: unknown command type.', 1;
    IF @command_type = 'FIRMWARE_UPGRADE' AND (@parameters IS NULL OR LTRIM(RTRIM(@parameters)) = N'')
        THROW 50004, 'Invalid input: FIRMWARE_UPGRADE needs the target version in the parameters.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[METER] WHERE meter_id = @meter_id)
        THROW 50001, 'Meter not found.', 1;

    DECLARE @role VARCHAR(20), @status VARCHAR(20), @new_id INT;
    SELECT @role = role_code FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;
    SET @status = CASE WHEN @role = 'TECHNICIAN' THEN 'PENDING_APPROVAL' ELSE 'APPROVED' END;

    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[REMOTE_COMMAND] (command_type, parameters, status, meter_id, requested_by_user_id)
        VALUES (@command_type, @parameters, @status, @meter_id, @actor_user_id);
        SET @new_id = SCOPE_IDENTITY();
        COMMIT TRANSACTION;
        SELECT @new_id AS command_id, @status AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.4 p.8: commands that need approval are approved by an officer; UC-12]
CREATE OR ALTER PROCEDURE [dbo].[sp_DecideRemoteCommand]
    @actor_user_id INT,
    @command_id    INT,
    @decision      VARCHAR(20),
    @comment       NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_DecideRemoteCommand';

    IF @decision IS NULL OR @decision NOT IN ('APPROVED', 'REJECTED')
        THROW 50004, 'Invalid input: the decision must be APPROVED or REJECTED.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[REMOTE_COMMAND] WHERE command_id = @command_id)
        THROW 50001, 'Command not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[REMOTE_COMMAND]
           SET status = @decision,
               result = CASE WHEN @decision = 'REJECTED' THEN LEFT(ISNULL(@comment, N'Rejected'), 300) ELSE result END
         WHERE command_id = @command_id AND status = 'PENDING_APPROVAL';
        IF @@ROWCOUNT = 0
            THROW 50003, 'The command is not waiting for approval.', 1;
        IF @comment IS NOT NULL
            EXEC [dbo].[sp__Log] 'DECISION_COMMENT', 'REMOTE_COMMAND', @command_id, 'PENDING_APPROVAL', @decision, @comment;
        COMMIT TRANSACTION;
        SELECT @command_id AS command_id, @decision AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.4 p.8: successive attempts until the meter answers with ACK; UC-12] (template T3)
-- Cursor over APPROVED / SENT commands, one short transaction per command.
-- No ACK after @max_attempts -> FAILED and an EVENT COMMAND_FAILED.
-- In the demo the device answers through sp_AcknowledgeCommand.
CREATE OR ALTER PROCEDURE [dbo].[sp_DispatchCommands]
    @actor_user_id INT,
    @max_attempts  SMALLINT = 3
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO,TSO,SYSTEM_ADMIN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_DispatchCommands';

    IF @max_attempts IS NULL OR @max_attempts < 1 SET @max_attempts = 3;

    DECLARE @command_id INT, @attempts SMALLINT, @meter_id INT;
    DECLARE @sent INT = 0, @failed INT = 0, @errors INT = 0, @now DATETIME2(0);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT command_id, attempt_count, meter_id FROM [dbo].[REMOTE_COMMAND]
        WHERE status IN ('APPROVED', 'SENT')
        ORDER BY requested_at, command_id;
    OPEN c;
    FETCH NEXT FROM c INTO @command_id, @attempts, @meter_id;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SET @now = SYSUTCDATETIME();
            BEGIN TRANSACTION;          -- one short transaction per command, not one for the whole loop
            IF @attempts >= @max_attempts
            BEGIN
                UPDATE [dbo].[REMOTE_COMMAND]
                   SET status = 'FAILED',
                       result = N'No ACK after ' + CAST(attempt_count AS NVARCHAR(10)) + N' attempts'
                 WHERE command_id = @command_id AND status = 'SENT' AND attempt_count = @attempts;
                IF @@ROWCOUNT = 1
                BEGIN
                    INSERT INTO [dbo].[EVENT] (event_timestamp, event_type, severity, description, meter_id)
                    VALUES (@now, 'COMMAND_FAILED', 'WARNING',
                            N'Remote command ' + CAST(@command_id AS NVARCHAR(10)) + N' got no ACK after '
                            + CAST(@attempts AS NVARCHAR(10)) + N' attempts.', @meter_id);
                    SET @failed = @failed + 1;
                END
            END
            ELSE
            BEGIN
                UPDATE [dbo].[REMOTE_COMMAND]
                   SET status = 'SENT', attempt_count = attempt_count + 1, last_attempt_at = @now,
                       executed_by_user_id = @actor_user_id
                 WHERE command_id = @command_id AND status IN ('APPROVED', 'SENT') AND attempt_count = @attempts;
                SET @sent = @sent + @@ROWCOUNT;   -- 0 when the device acknowledged in the meantime
            END
            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            SET @errors = @errors + 1;
            -- log the failure and continue with the next command
            EXEC [dbo].[sp__Log] 'DISPATCH_ERROR', 'REMOTE_COMMAND', @command_id;
        END CATCH
        FETCH NEXT FROM c INTO @command_id, @attempts, @meter_id;
    END
    CLOSE c;
    DEALLOCATE c;

    SELECT @sent AS attempts_sent, @failed AS commands_failed, @errors AS errors;
END;
GO

-- [project.pdf §2.4 p.8: the meter confirms the command with an ACK]
-- Called for the device (no user; mechanism DEVICE). A firmware upgrade also updates the meter (TR13 logs it).
CREATE OR ALTER PROCEDURE [dbo].[sp_AcknowledgeCommand]
    @network_id VARCHAR(60),
    @command_id INT,
    @result     NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__SetActor] NULL, 'DEVICE';

    DECLARE @meter_id INT, @type VARCHAR(20), @parameters NVARCHAR(500);
    SELECT @meter_id = c.meter_id, @type = c.command_type, @parameters = c.parameters
    FROM [dbo].[REMOTE_COMMAND] AS c
    JOIN [dbo].[METER] AS m ON m.meter_id = c.meter_id
    WHERE c.command_id = @command_id AND m.network_id = @network_id;
    IF @meter_id IS NULL
        THROW 50001, 'Command not found for this meter.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[REMOTE_COMMAND]
           SET status = 'ACKNOWLEDGED', ack_at = SYSUTCDATETIME(), result = ISNULL(@result, N'ACK')
         WHERE command_id = @command_id AND status = 'SENT';
        IF @@ROWCOUNT = 0
            THROW 50003, 'The command is not in SENT state.', 1;

        IF @type = 'FIRMWARE_UPGRADE'
            UPDATE [dbo].[METER]
               SET firmware_version = LEFT(LTRIM(RTRIM(@parameters)), 30)
             WHERE meter_id = @meter_id AND status <> 'REMOVED';
        COMMIT TRANSACTION;
        SELECT @command_id AS command_id, 'ACKNOWLEDGED' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §II.Δ p.3: remote shedding on all the meters of a transformer; UC-13]
-- Cursor over the ACTIVE meters under the subtree of the transformer: one APPROVED command per meter,
-- all in one transaction (all or nothing). sp_DispatchCommands then sends them.
CREATE OR ALTER PROCEDURE [dbo].[sp_ShedTransformerLoad]
    @actor_user_id  INT,
    @transformer_id INT,
    @command_type   VARCHAR(20),
    @reason         NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_ShedTransformerLoad';

    IF @command_type IS NULL OR @command_type NOT IN ('DISCONNECT', 'RECONNECT')
        THROW 50004, 'Invalid input: shedding uses DISCONNECT or RECONNECT.', 1;
    IF @reason IS NULL OR LTRIM(RTRIM(@reason)) = N''
        THROW 50004, 'Invalid input: a reason is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE transformer_id = @transformer_id)
        THROW 50001, 'Transformer not found.', 1;

    DECLARE @meter_id INT, @count INT = 0;
    DECLARE @parameters NVARCHAR(500) = N'SHED transformer ' + CAST(@transformer_id AS NVARCHAR(10)) + N': ' + @reason;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT m.meter_id
            FROM [dbo].[METER] AS m
            JOIN [dbo].[fn_TransformerSubtree](@transformer_id) AS s ON s.transformer_id = m.transformer_id
            WHERE m.status = 'ACTIVE';
        OPEN c;
        FETCH NEXT FROM c INTO @meter_id;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            INSERT INTO [dbo].[REMOTE_COMMAND] (command_type, parameters, status, meter_id, requested_by_user_id)
            VALUES (@command_type, @parameters, 'APPROVED', @meter_id, @actor_user_id);
            SET @count = @count + 1;
            FETCH NEXT FROM c INTO @meter_id;
        END
        CLOSE c;
        DEALLOCATE c;

        EXEC [dbo].[sp__Log] 'SHED_LOAD', 'TRANSFORMER', @transformer_id, NULL, @command_type, @parameters;
        COMMIT TRANSACTION;
        SELECT @transformer_id AS transformer_id, @command_type AS command_type, @count AS commands_created;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'c') >= 0 CLOSE c;
        IF CURSOR_STATUS('local', 'c') >= -1 DEALLOCATE c;
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.4 p.8: commands and the trail of their attempts]
CREATE OR ALTER PROCEDURE [dbo].[sp_ListCommands]
    @actor_user_id INT,
    @status        VARCHAR(20) = NULL,
    @meter_id      INT = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN,SYSTEM_OFFICER,DSO,TSO';
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 500 SET @page_size = 50;

    SELECT c.command_id, c.command_type, c.parameters, c.status, c.requested_at, c.attempt_count,
           c.last_attempt_at, c.ack_at, c.result, c.meter_id, m.serial_number,
           c.requested_by_user_id, c.executed_by_user_id,
           (SELECT STRING_AGG(CAST(CONVERT(NVARCHAR(19), l.logged_at, 120) + N' ' + l.action
                              + ISNULL(N' ' + l.old_state, N'') + ISNULL(N' -> ' + l.new_state, N'') AS NVARCHAR(MAX)), N'; ')
                   WITHIN GROUP (ORDER BY l.log_id)
            FROM [dbo].[AUDIT_LOG] AS l
            WHERE l.object_type = 'REMOTE_COMMAND' AND l.object_id = CAST(c.command_id AS VARCHAR(30))) AS history
    FROM [dbo].[REMOTE_COMMAND] AS c
    JOIN [dbo].[METER] AS m ON m.meter_id = c.meter_id
    WHERE (@status IS NULL OR c.status = @status)
      AND (@meter_id IS NULL OR c.meter_id = @meter_id)
    ORDER BY c.requested_at DESC, c.command_id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END;
GO

PRINT 'procedures_05_commands.sql: 6 procedures created.';
GO
