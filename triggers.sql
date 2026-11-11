/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   triggers.sql  -  Build Spec §8 (TR01 - TR22)
   Guard triggers  : RAISERROR('[51xxx] ...', 16, 1); ROLLBACK TRANSACTION; RETURN;   (lecture 18)
   Audit triggers  : INSERT INTO AUDIT_LOG ... FROM inserted / deleted                (lab 10)
   The actor comes from SESSION_CONTEXT (set by sp__SetActor).
   Every trigger works on inserted / deleted as sets; only TR09 uses a cursor.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------------
   GUARD TRIGGERS
   --------------------------------------------------------------------------- */

-- TR01 [project.pdf §3.2 p.9: after VEE the readings cannot change]
-- DELETE stays allowed: the retention purge removes old raw readings [§1.4 p.6-7].
CREATE OR ALTER TRIGGER [dbo].[tr_METER_READING_immutable]
ON [dbo].[METER_READING]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted WHERE is_final = 1)
    BEGIN
        RAISERROR('[51001] A finalized reading cannot be changed.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- TR02 [project.pdf §3.2 p.9, §4.2 p.10: historical aggregates are immutable]
CREATE OR ALTER TRIGGER [dbo].[tr_AGGREGATE_immutable]
ON [dbo].[AGGREGATE]
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted WHERE is_final = 1)
    BEGIN
        RAISERROR('[51002] A final aggregate cannot be changed or deleted.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- TR03 [project.pdf Κοινές αρχές p.5: the trail of every critical change must stay]
CREATE OR ALTER TRIGGER [dbo].[tr_AUDIT_LOG_append_only]
ON [dbo].[AUDIT_LOG]
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted)
    BEGIN
        RAISERROR('[51003] The audit log is append-only.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- TR04 [project.pdf §2.3 p.8: a meter becomes active only after the officer confirms its documents]
CREATE OR ALTER TRIGGER [dbo].[tr_METER_activation_guard]
ON [dbo].[METER]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 FROM inserted AS i
        WHERE i.status = 'ACTIVE'
          AND (SELECT COUNT(DISTINCT d.doc_type) FROM [dbo].[DOCUMENT] AS d
               WHERE d.meter_id = i.meter_id AND d.approval_status = 'APPROVED') < 3)
    BEGIN
        RAISERROR('[51004] A meter can become ACTIVE only with its 3 certificates approved.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- TR05 [project.pdf §2.1 p.7: a technician cannot do jobs before being approved]
-- Checked when a technician is put on a job (not on later updates of the same job).
CREATE OR ALTER TRIGGER [dbo].[tr_WORK_ORDER_technician_guard]
ON [dbo].[WORK_ORDER]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        LEFT JOIN deleted AS d ON d.work_order_id = i.work_order_id
        LEFT JOIN [dbo].[USER_ACCOUNT] AS u ON u.user_id = i.technician_user_id
        WHERE i.technician_user_id IS NOT NULL
          AND (d.work_order_id IS NULL OR d.technician_user_id IS NULL OR d.technician_user_id <> i.technician_user_id)
          AND (u.user_id IS NULL OR u.role_code <> 'TECHNICIAN' OR u.approval_status <> 'APPROVED' OR u.is_active = 0))
    BEGIN
        RAISERROR('[51005] A work order can be given only to an active, approved technician.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- TR06 [project.pdf §1.3 p.6: several payments per bill] - lab 10 tr_ORDER_TOTAL pattern:
-- the bill status is derived from its payments whenever they change.
CREATE OR ALTER TRIGGER [dbo].[tr_PAYMENT_bill_status]
ON [dbo].[PAYMENT]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @bills TABLE (bill_id INT PRIMARY KEY, amount DECIMAL(12,2), paid DECIMAL(12,2), old_status VARCHAR(20));

    INSERT INTO @bills (bill_id, amount, paid, old_status)
    SELECT b.bill_id, b.amount, [dbo].[fn_BillPaid](b.bill_id), b.status
    FROM [dbo].[BILL] AS b
    WHERE b.bill_id IN (SELECT bill_id FROM inserted WHERE bill_id IS NOT NULL
                        UNION
                        SELECT bill_id FROM deleted  WHERE bill_id IS NOT NULL);
    IF NOT EXISTS (SELECT 1 FROM @bills) RETURN;

    IF EXISTS (SELECT 1 FROM @bills WHERE paid > amount)
    BEGIN
        RAISERROR('[51006] The payments of a bill cannot be more than its amount.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    DECLARE @actor INT = TRY_CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);
    DECLARE @mech  VARCHAR(60) = ISNULL(CAST(SESSION_CONTEXT(N'mechanism') AS VARCHAR(60)), 'DIRECT_SQL');

    -- new status: PAID when fully paid; PARTIALLY_PAID from ISSUED; an OVERDUE bill changes only when fully paid
    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    SELECT CASE WHEN @actor IS NOT NULL THEN 'USER' WHEN @mech = 'DEVICE' THEN 'DEVICE' ELSE 'SYSTEM' END,
           @mech, 'STATUS_CHANGE', 'BILL', CAST(x.bill_id AS VARCHAR(30)), x.old_status,
           CASE WHEN x.paid = x.amount THEN 'PAID' ELSE 'PARTIALLY_PAID' END,
           N'paid ' + CAST(x.paid AS NVARCHAR(20)) + N' of ' + CAST(x.amount AS NVARCHAR(20)), @actor
    FROM @bills AS x
    WHERE (x.paid = x.amount AND x.amount > 0 AND x.old_status IN ('ISSUED', 'PARTIALLY_PAID', 'OVERDUE'))
       OR (x.paid > 0 AND x.paid < x.amount AND x.old_status = 'ISSUED');

    UPDATE b
       SET status = CASE WHEN x.paid = x.amount THEN 'PAID' ELSE 'PARTIALLY_PAID' END
    FROM [dbo].[BILL] AS b
    JOIN @bills AS x ON x.bill_id = b.bill_id
    WHERE (x.paid = x.amount AND x.amount > 0 AND x.old_status IN ('ISSUED', 'PARTIALLY_PAID', 'OVERDUE'))
       OR (x.paid > 0 AND x.paid < x.amount AND x.old_status = 'ISSUED');
END;
GO

-- TR07 [project.pdf §1.1 p.5: a premise belongs to a consumer; §II.Ε p.4: supplier / aggregator]
CREATE OR ALTER TRIGGER [dbo].[tr_PREMISE_guard]
ON [dbo].[PREMISE]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN [dbo].[USER_ACCOUNT] AS u ON u.user_id = i.user_id
        LEFT JOIN [dbo].[ORGANIZATION] AS s ON s.organization_id = i.supplier_org_id
        LEFT JOIN [dbo].[ORGANIZATION] AS a ON a.organization_id = i.aggregator_org_id
        WHERE u.role_code <> 'CONSUMER'
           OR (i.supplier_org_id   IS NOT NULL AND s.org_type <> 'SUPPLIER')
           OR (i.aggregator_org_id IS NOT NULL AND a.org_type <> 'AGGREGATOR'))
    BEGIN
        RAISERROR('[51007] A premise needs a CONSUMER owner, a SUPPLIER organization and an AGGREGATOR organization of the right type.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- TR08 [project.pdf §4.1 p.9: a meter is connected to a low-voltage transformer]
CREATE OR ALTER TRIGGER [dbo].[tr_METER_transformer_guard]
ON [dbo].[METER]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 FROM inserted AS i
        JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = i.transformer_id
        WHERE t.[level] <> 1)
    BEGIN
        RAISERROR('[51008] A meter must be connected to a level-1 (low-voltage) transformer.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- TR09 [project.pdf §4.1 p.9: the transformers form a tree]
-- Cursor over inserted: (a) parent.level = level + 1, (b) walk up the parent chain to find a cycle.
-- Then, set-based: children must stay one level below, and a transformer with meters must stay level 1.
CREATE OR ALTER TRIGGER [dbo].[tr_TRANSFORMER_tree_guard]
ON [dbo].[TRANSFORMER]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT, @lvl TINYINT, @parent INT, @plevel TINYINT, @cur INT, @steps INT;
    DECLARE @bad VARCHAR(200) = NULL;

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT transformer_id, [level], parent_transformer_id FROM inserted;
    OPEN c;
    FETCH NEXT FROM c INTO @id, @lvl, @parent;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @parent IS NOT NULL
        BEGIN
            SELECT @plevel = [level] FROM [dbo].[TRANSFORMER] WHERE transformer_id = @parent;
            IF @plevel <> @lvl + 1
                SET @bad = '[51009] The parent of a transformer must be exactly one level above it.';

            SET @cur = @parent;
            SET @steps = 0;
            WHILE @cur IS NOT NULL AND @bad IS NULL
            BEGIN
                IF @cur = @id OR @steps >= 50
                    SET @bad = '[51009] The transformer hierarchy cannot contain a cycle.';
                SELECT @cur = parent_transformer_id FROM [dbo].[TRANSFORMER] WHERE transformer_id = @cur;
                SET @steps = @steps + 1;
            END
        END
        IF @bad IS NOT NULL BREAK;
        FETCH NEXT FROM c INTO @id, @lvl, @parent;
    END
    CLOSE c;
    DEALLOCATE c;

    IF @bad IS NULL AND EXISTS (
        SELECT 1 FROM inserted AS i
        JOIN [dbo].[TRANSFORMER] AS ch ON ch.parent_transformer_id = i.transformer_id
        WHERE ch.[level] + 1 <> i.[level])
        SET @bad = '[51009] The level cannot change: the children of this transformer must stay one level below it.';

    IF @bad IS NULL AND EXISTS (
        SELECT 1 FROM inserted AS i
        WHERE i.[level] <> 1
          AND EXISTS (SELECT 1 FROM [dbo].[METER] AS m WHERE m.transformer_id = i.transformer_id))
        SET @bad = '[51009] The level cannot change: this transformer has meters, so it must stay level 1.';

    IF @bad IS NOT NULL
    BEGIN
        RAISERROR(@bad, 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- TR11 [project.pdf §1.4 p.6: bills and payments keep their user, so users are anonymized, never deleted]
CREATE OR ALTER TRIGGER [dbo].[tr_USER_ACCOUNT_no_delete]
ON [dbo].[USER_ACCOUNT]
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted)
    BEGIN
        RAISERROR('[51010] Users are never deleted; they are anonymized.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- TR16 [project.pdf §2.4 p.8: remote commands go to meters in operation]
CREATE OR ALTER TRIGGER [dbo].[tr_REMOTE_COMMAND_guard]
ON [dbo].[REMOTE_COMMAND]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 FROM inserted AS i
        JOIN [dbo].[METER] AS m ON m.meter_id = i.meter_id
        WHERE m.status <> 'ACTIVE')
    BEGIN
        RAISERROR('[51011] A remote command can target only an ACTIVE meter.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- TR22a [project.pdf §1.4 p.6: accounting data is kept]
CREATE OR ALTER TRIGGER [dbo].[tr_BILL_no_delete]
ON [dbo].[BILL]
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted)
    BEGIN
        RAISERROR('[51012] Bills are never deleted.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- TR22b [project.pdf §1.4 p.6: accounting data is kept]
CREATE OR ALTER TRIGGER [dbo].[tr_PAYMENT_no_delete]
ON [dbo].[PAYMENT]
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted)
    BEGIN
        RAISERROR('[51012] Payments are never deleted.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

/* ---------------------------------------------------------------------------
   AUDIT TRIGGERS  (template T6)
   --------------------------------------------------------------------------- */

-- TR10 [project.pdf §2.1 p.7: status changes are recorded; §1.4 p.6 anonymization]
-- Passwords, IBANs and other personal values are never written: only the column name.
CREATE OR ALTER TRIGGER [dbo].[tr_USER_ACCOUNT_audit]
ON [dbo].[USER_ACCOUNT]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @actor INT = TRY_CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);
    DECLARE @mech  VARCHAR(60) = ISNULL(CAST(SESSION_CONTEXT(N'mechanism') AS VARCHAR(60)), 'DIRECT_SQL');
    DECLARE @atype VARCHAR(10) = CASE WHEN @actor IS NOT NULL THEN 'USER' WHEN @mech = 'DEVICE' THEN 'DEVICE' ELSE 'SYSTEM' END;

    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    SELECT @atype, @mech, x.action, 'USER_ACCOUNT', CAST(x.user_id AS VARCHAR(30)), x.old_state, x.new_state, x.comment, @actor
    FROM (
        SELECT i.user_id, 'REGISTER' AS action, CAST(NULL AS NVARCHAR(200)) AS old_state,
               CAST(i.approval_status AS NVARCHAR(200)) AS new_state, CAST(N'role ' + i.role_code AS NVARCHAR(500)) AS comment
        FROM inserted AS i LEFT JOIN deleted AS d ON d.user_id = i.user_id
        WHERE d.user_id IS NULL
        UNION ALL
        SELECT i.user_id, 'STATUS_CHANGE', d.approval_status, i.approval_status, N'approval_status'
        FROM inserted AS i JOIN deleted AS d ON d.user_id = i.user_id
        WHERE d.approval_status <> i.approval_status
        UNION ALL
        SELECT i.user_id, CASE WHEN i.is_active = 1 THEN 'ACTIVATE' ELSE 'DEACTIVATE' END,
               CAST(d.is_active AS NVARCHAR(1)), CAST(i.is_active AS NVARCHAR(1)), N'is_active'
        FROM inserted AS i JOIN deleted AS d ON d.user_id = i.user_id
        WHERE d.is_active <> i.is_active
        UNION ALL
        SELECT i.user_id, 'ROLE_CHANGE', d.role_code, i.role_code, N'role_code'
        FROM inserted AS i JOIN deleted AS d ON d.user_id = i.user_id
        WHERE d.role_code <> i.role_code
        UNION ALL
        SELECT i.user_id, 'ANONYMIZE', NULL, N'ANONYMIZED', N'right to be forgotten executed'
        FROM inserted AS i JOIN deleted AS d ON d.user_id = i.user_id
        WHERE d.anonymized_at IS NULL AND i.anonymized_at IS NOT NULL
        UNION ALL
        SELECT i.user_id, 'PASSWORD_CHANGE', NULL, NULL, N'password changed'
        FROM inserted AS i JOIN deleted AS d ON d.user_id = i.user_id
        WHERE d.password_hash <> i.password_hash AND i.anonymized_at IS NULL
        UNION ALL
        SELECT i.user_id, 'PROFILE_CHANGE', NULL, NULL,
               STUFF(CASE WHEN d.email <> i.email THEN N', email changed' ELSE N'' END
                   + CASE WHEN d.full_name <> i.full_name THEN N', full_name changed' ELSE N'' END
                   + CASE WHEN ISNULL(d.phone, '') <> ISNULL(i.phone, '') THEN N', phone changed' ELSE N'' END
                   + CASE WHEN ISNULL(d.iban, '') <> ISNULL(i.iban, '') THEN N', iban changed' ELSE N'' END
                   + CASE WHEN d.notify_email <> i.notify_email OR d.notify_sms <> i.notify_sms THEN N', notification preferences changed' ELSE N'' END,
                     1, 2, N'')
        FROM inserted AS i JOIN deleted AS d ON d.user_id = i.user_id
        WHERE i.anonymized_at IS NULL
          AND (d.email <> i.email OR d.full_name <> i.full_name
               OR ISNULL(d.phone, '') <> ISNULL(i.phone, '') OR ISNULL(d.iban, '') <> ISNULL(i.iban, '')
               OR d.notify_email <> i.notify_email OR d.notify_sms <> i.notify_sms)
    ) AS x;
END;
GO

-- TR12 [project.pdf Κοινές αρχές p.5: officers record the result of their document checks]
CREATE OR ALTER TRIGGER [dbo].[tr_DOCUMENT_audit]
ON [dbo].[DOCUMENT]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @actor INT = TRY_CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);
    DECLARE @mech  VARCHAR(60) = ISNULL(CAST(SESSION_CONTEXT(N'mechanism') AS VARCHAR(60)), 'DIRECT_SQL');

    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    SELECT CASE WHEN @actor IS NOT NULL THEN 'USER' WHEN @mech = 'DEVICE' THEN 'DEVICE' ELSE 'SYSTEM' END,
           @mech,
           CASE WHEN d.document_id IS NULL THEN 'UPLOAD' ELSE 'STATUS_CHANGE' END,
           'DOCUMENT', CAST(i.document_id AS VARCHAR(30)),
           d.approval_status, i.approval_status, i.doc_type, @actor
    FROM inserted AS i
    LEFT JOIN deleted AS d ON d.document_id = i.document_id
    WHERE d.document_id IS NULL OR d.approval_status <> i.approval_status;
END;
GO

-- TR13 [project.pdf Κοινές αρχές p.5: changes of status and of technical data are traceable]
-- One row per changed technical column (old -> new).
CREATE OR ALTER TRIGGER [dbo].[tr_METER_audit]
ON [dbo].[METER]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @actor INT = TRY_CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);
    DECLARE @mech  VARCHAR(60) = ISNULL(CAST(SESSION_CONTEXT(N'mechanism') AS VARCHAR(60)), 'DIRECT_SQL');
    DECLARE @atype VARCHAR(10) = CASE WHEN @actor IS NOT NULL THEN 'USER' WHEN @mech = 'DEVICE' THEN 'DEVICE' ELSE 'SYSTEM' END;

    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    SELECT @atype, @mech, x.action, 'METER', CAST(x.meter_id AS VARCHAR(30)), x.old_state, x.new_state, x.comment, @actor
    FROM (
        SELECT i.meter_id, 'INSTALL' AS action, CAST(NULL AS NVARCHAR(200)) AS old_state,
               CAST(i.status AS NVARCHAR(200)) AS new_state, CAST(N'serial ' + i.serial_number AS NVARCHAR(500)) AS comment
        FROM inserted AS i LEFT JOIN deleted AS d ON d.meter_id = i.meter_id
        WHERE d.meter_id IS NULL
        UNION ALL
        SELECT i.meter_id, 'STATUS_CHANGE', d.status, i.status, N'status'
        FROM inserted AS i JOIN deleted AS d ON d.meter_id = i.meter_id
        WHERE d.status <> i.status
        UNION ALL
        SELECT i.meter_id, 'TECHNICAL_CHANGE', d.firmware_version, i.firmware_version, N'firmware_version'
        FROM inserted AS i JOIN deleted AS d ON d.meter_id = i.meter_id
        WHERE d.firmware_version <> i.firmware_version
        UNION ALL
        SELECT i.meter_id, 'TECHNICAL_CHANGE', d.communication_type, i.communication_type, N'communication_type'
        FROM inserted AS i JOIN deleted AS d ON d.meter_id = i.meter_id
        WHERE d.communication_type <> i.communication_type
        UNION ALL
        SELECT i.meter_id, 'TECHNICAL_CHANGE', CAST(d.meter_type_id AS NVARCHAR(20)), CAST(i.meter_type_id AS NVARCHAR(20)), N'meter_type_id'
        FROM inserted AS i JOIN deleted AS d ON d.meter_id = i.meter_id
        WHERE d.meter_type_id <> i.meter_type_id
        UNION ALL
        SELECT i.meter_id, 'TECHNICAL_CHANGE', CAST(d.transformer_id AS NVARCHAR(20)), CAST(i.transformer_id AS NVARCHAR(20)), N'transformer_id'
        FROM inserted AS i JOIN deleted AS d ON d.meter_id = i.meter_id
        WHERE d.transformer_id <> i.transformer_id
        UNION ALL
        SELECT i.meter_id, 'TECHNICAL_CHANGE', CAST(d.retention_months AS NVARCHAR(20)), CAST(i.retention_months AS NVARCHAR(20)), N'retention_months'
        FROM inserted AS i JOIN deleted AS d ON d.meter_id = i.meter_id
        WHERE d.retention_months <> i.retention_months
    ) AS x;
END;
GO

-- TR14 [project.pdf §1.3 p.6: a request has a status and a history; §2.2 p.7]
CREATE OR ALTER TRIGGER [dbo].[tr_WORK_ORDER_audit]
ON [dbo].[WORK_ORDER]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @actor INT = TRY_CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);
    DECLARE @mech  VARCHAR(60) = ISNULL(CAST(SESSION_CONTEXT(N'mechanism') AS VARCHAR(60)), 'DIRECT_SQL');
    DECLARE @atype VARCHAR(10) = CASE WHEN @actor IS NOT NULL THEN 'USER' WHEN @mech = 'DEVICE' THEN 'DEVICE' ELSE 'SYSTEM' END;

    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    SELECT @atype, @mech,
           CASE WHEN d.work_order_id IS NULL THEN 'CREATE' ELSE 'STATUS_CHANGE' END,
           'WORK_ORDER', CAST(i.work_order_id AS VARCHAR(30)),
           d.status, i.status,
           CASE WHEN d.work_order_id IS NULL THEN i.work_type + N' / ' + i.origin END, @actor
    FROM inserted AS i
    LEFT JOIN deleted AS d ON d.work_order_id = i.work_order_id
    WHERE d.work_order_id IS NULL OR d.status <> i.status;

    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    SELECT @atype, @mech,
           CASE WHEN i.technician_user_id IS NULL THEN 'UNASSIGN' ELSE 'ASSIGN' END,
           'WORK_ORDER', CAST(i.work_order_id AS VARCHAR(30)),
           CAST(d.technician_user_id AS NVARCHAR(20)), CAST(i.technician_user_id AS NVARCHAR(20)),
           N'technician_user_id', @actor
    FROM inserted AS i
    JOIN deleted AS d ON d.work_order_id = i.work_order_id
    WHERE ISNULL(d.technician_user_id, 0) <> ISNULL(i.technician_user_id, 0);
END;
GO

-- TR15 [project.pdf §2.4 p.8: successive attempts until ACK, all recorded]
CREATE OR ALTER TRIGGER [dbo].[tr_REMOTE_COMMAND_audit]
ON [dbo].[REMOTE_COMMAND]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @actor INT = TRY_CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);
    DECLARE @mech  VARCHAR(60) = ISNULL(CAST(SESSION_CONTEXT(N'mechanism') AS VARCHAR(60)), 'DIRECT_SQL');
    DECLARE @atype VARCHAR(10) = CASE WHEN @actor IS NOT NULL THEN 'USER' WHEN @mech = 'DEVICE' THEN 'DEVICE' ELSE 'SYSTEM' END;

    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    SELECT @atype, @mech,
           CASE WHEN d.command_id IS NULL THEN 'CREATE' ELSE 'STATUS_CHANGE' END,
           'REMOTE_COMMAND', CAST(i.command_id AS VARCHAR(30)),
           d.status, i.status,
           CASE WHEN d.command_id IS NULL THEN i.command_type + N' for meter ' + CAST(i.meter_id AS NVARCHAR(20)) ELSE i.result END,
           @actor
    FROM inserted AS i
    LEFT JOIN deleted AS d ON d.command_id = i.command_id
    WHERE d.command_id IS NULL OR d.status <> i.status;

    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    SELECT @atype, @mech, 'COMMAND_ATTEMPT', 'REMOTE_COMMAND', CAST(i.command_id AS VARCHAR(30)),
           CAST(d.attempt_count AS NVARCHAR(10)), CAST(i.attempt_count AS NVARCHAR(10)),
           N'attempt ' + CAST(i.attempt_count AS NVARCHAR(10)), @actor
    FROM inserted AS i
    JOIN deleted AS d ON d.command_id = i.command_id
    WHERE i.attempt_count > d.attempt_count;
END;
GO

-- TR17 [project.pdf §1.4 p.6: a log entry at every stage of a GDPR request]
CREATE OR ALTER TRIGGER [dbo].[tr_GDPR_REQUEST_audit]
ON [dbo].[GDPR_REQUEST]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @actor INT = TRY_CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);
    DECLARE @mech  VARCHAR(60) = ISNULL(CAST(SESSION_CONTEXT(N'mechanism') AS VARCHAR(60)), 'DIRECT_SQL');

    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    SELECT CASE WHEN @actor IS NOT NULL THEN 'USER' WHEN @mech = 'DEVICE' THEN 'DEVICE' ELSE 'SYSTEM' END,
           @mech,
           CASE WHEN d.gdpr_request_id IS NULL THEN 'SUBMIT' ELSE 'STATUS_CHANGE' END,
           'GDPR_REQUEST', CAST(i.gdpr_request_id AS VARCHAR(30)),
           d.status, i.status, i.request_type, @actor
    FROM inserted AS i
    LEFT JOIN deleted AS d ON d.gdpr_request_id = i.gdpr_request_id
    WHERE d.gdpr_request_id IS NULL OR d.status <> i.status;
END;
GO

-- TR18 [project.pdf §3.2 p.9: original value, corrected value and origin of every Editing]
-- Only officer decisions are logged row by row (a reading became EDITED, or left SUSPECT).
-- Automatic VALID results stay on the reading row; sp_RunVEE writes one summary row per meter.
CREATE OR ALTER TRIGGER [dbo].[tr_METER_READING_edit_audit]
ON [dbo].[METER_READING]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT (UPDATE(status) OR UPDATE([value])) RETURN;

    DECLARE @actor INT = TRY_CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);
    DECLARE @mech  VARCHAR(60) = ISNULL(CAST(SESSION_CONTEXT(N'mechanism') AS VARCHAR(60)), 'DIRECT_SQL');

    INSERT INTO [dbo].[AUDIT_LOG] (actor_type, mechanism, action, object_type, object_id, old_state, new_state, comment, user_id)
    SELECT CASE WHEN COALESCE(i.edited_by_user_id, @actor) IS NOT NULL THEN 'USER' WHEN @mech = 'DEVICE' THEN 'DEVICE' ELSE 'SYSTEM' END,
           @mech,
           CASE WHEN i.status = 'EDITED' THEN 'VEE_EDIT' ELSE 'VEE_ACCEPT' END,
           'METER_READING', CAST(i.reading_id AS VARCHAR(30)),
           d.status + N' ' + CAST(d.[value] AS NVARCHAR(30)),
           i.status + N' ' + CAST(i.[value] AS NVARCHAR(30)),
           LEFT(ISNULL(i.vee_rule, '') + N': ' + ISNULL(i.vee_note, N''), 500),
           COALESCE(i.edited_by_user_id, @actor)
    FROM inserted AS i
    JOIN deleted AS d ON d.reading_id = i.reading_id
    WHERE (i.status = 'EDITED' AND (d.status <> 'EDITED' OR d.[value] <> i.[value]))
       OR (d.status = 'SUSPECT' AND i.status <> 'SUSPECT');
END;
GO

/* ---------------------------------------------------------------------------
   DERIVED-ROW TRIGGERS
   --------------------------------------------------------------------------- */

-- TR19 [project.pdf §3.1 p.8: packets that cannot be matched must not be lost silently]
CREATE OR ALTER TRIGGER [dbo].[tr_TELEMETRY_PACKET_failure_event]
ON [dbo].[TELEMETRY_PACKET]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[EVENT] (event_timestamp, event_type, severity, description, meter_id, packet_id)
    SELECT i.received_at, 'PACKET_' + i.match_status, 'WARNING',
           N'Packet from network id ' + i.meter_network_id + N' was not matched (' + i.match_status + N').',
           i.meter_id, i.packet_id
    FROM inserted AS i
    WHERE i.match_status <> 'MATCHED';
END;
GO

-- TR20 [project.pdf §2.4 p.8: tamper alerts lead to a new field job]
CREATE OR ALTER TRIGGER [dbo].[tr_EVENT_work_order]
ON [dbo].[EVENT]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted WHERE event_type = 'TAMPER_ALERT' AND severity = 'CRITICAL' AND meter_id IS NOT NULL)
        RETURN;

    -- the session actor, or the first administrator when a device raised the event
    DECLARE @requester INT = TRY_CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);
    IF @requester IS NULL
        SELECT @requester = MIN(user_id) FROM [dbo].[USER_ACCOUNT] WHERE role_code = 'SYSTEM_ADMIN';
    IF @requester IS NULL RETURN;

    INSERT INTO [dbo].[WORK_ORDER] (work_type, origin, description, status, requested_by_user_id, premise_id, meter_id, event_id)
    SELECT 'ANTI_TAMPER', 'EVENT',
           N'Anti-tamper check: ' + ISNULL(i.description, N'tamper alert'),
           'SUBMITTED', @requester, m.premise_id, i.meter_id, i.event_id
    FROM inserted AS i
    JOIN [dbo].[METER] AS m ON m.meter_id = i.meter_id
    WHERE i.event_type = 'TAMPER_ALERT' AND i.severity = 'CRITICAL';
END;
GO

-- TR21 [project.pdf §1.2 p.6: the consumer is told when consumption passes the threshold they set]
-- Fires when final DAY aggregates of 1.8.0 are inserted: month-to-date against the premise threshold,
-- one THRESHOLD_EXCEEDED event per meter per month. PHP sends the email / SMS (notify_email / notify_sms).
CREATE OR ALTER TRIGGER [dbo].[tr_AGGREGATE_threshold_alert]
ON [dbo].[AGGREGATE]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted WHERE period_type = 'DAY' AND obis_code = '1.8.0' AND meter_id IS NOT NULL)
        RETURN;

    WITH months AS (
        SELECT DISTINCT i.meter_id,
               CAST(DATEFROMPARTS(YEAR(i.period_start), MONTH(i.period_start), 1) AS DATETIME2(0)) AS month_start
        FROM inserted AS i
        WHERE i.period_type = 'DAY' AND i.obis_code = '1.8.0' AND i.meter_id IS NOT NULL)
    INSERT INTO [dbo].[EVENT] (event_timestamp, event_type, severity, description, meter_id)
    SELECT t.last_day, 'THRESHOLD_EXCEEDED', 'INFO',
           N'Month-to-date consumption ' + CAST(t.total AS NVARCHAR(30)) + N' kWh is above the threshold of '
           + CAST(p.monthly_threshold_kwh AS NVARCHAR(30)) + N' kWh.',
           x.meter_id
    FROM months AS x
    JOIN [dbo].[METER] AS m ON m.meter_id = x.meter_id
    JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
    CROSS APPLY (SELECT SUM(a.[value]) AS total, MAX(a.period_start) AS last_day
                 FROM [dbo].[AGGREGATE] AS a
                 WHERE a.meter_id = x.meter_id AND a.period_type = 'DAY' AND a.obis_code = '1.8.0'
                   AND a.period_start >= x.month_start AND a.period_start < DATEADD(MONTH, 1, x.month_start)) AS t
    WHERE p.monthly_threshold_kwh IS NOT NULL
      AND t.total > p.monthly_threshold_kwh
      AND NOT EXISTS (SELECT 1 FROM [dbo].[EVENT] AS e
                      WHERE e.meter_id = x.meter_id AND e.event_type = 'THRESHOLD_EXCEEDED'
                        AND e.event_timestamp >= x.month_start AND e.event_timestamp < DATEADD(MONTH, 1, x.month_start));
END;
GO

PRINT 'triggers.sql: TR01 - TR22 created (23 triggers; TR22 is one on BILL and one on PAYMENT).';
GO
