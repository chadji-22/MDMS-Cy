/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_01_accounts.sql  -  Build Spec §9.1: accounts, login, staff, technicians
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf Κοινές αρχές p.5: the administrator is created by hand]
-- Works only while no SYSTEM_ADMIN exists.
CREATE OR ALTER PROCEDURE [dbo].[sp_BootstrapAdmin]
    @email     VARCHAR(255),
    @password  NVARCHAR(128),
    @full_name NVARCHAR(150)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__SetActor] NULL, 'sp_BootstrapAdmin';
    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF EXISTS (SELECT 1 FROM [dbo].[USER_ACCOUNT] WITH (UPDLOCK, HOLDLOCK) WHERE role_code = 'SYSTEM_ADMIN')
            THROW 50003, 'An administrator already exists.', 1;
        EXEC [dbo].[sp__NewUser] @email, @password, @full_name, NULL, 'SYSTEM_ADMIN', 'APPROVED', @new_id = @new_id OUTPUT;
        COMMIT TRANSACTION;
        SELECT @new_id AS user_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf Κοινές αρχές p.5: login with email and password; §IV p.12]
-- The same error for every failure (50006). The password or its hash is never returned or logged.
CREATE OR ALTER PROCEDURE [dbo].[sp_Login]
    @email    VARCHAR(255),
    @password NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @uid INT, @hash VARBINARY(64), @salt VARBINARY(16), @active BIT, @anon DATETIME2(0);

    SELECT @uid = user_id, @hash = password_hash, @salt = password_salt, @active = is_active, @anon = anonymized_at
    FROM [dbo].[USER_ACCOUNT]
    WHERE email = LOWER(LTRIM(RTRIM(@email)));

    IF @uid IS NOT NULL AND @active = 1 AND @anon IS NULL AND @password IS NOT NULL
       AND @hash = [dbo].[fn_HashPassword](@password, @salt)
    BEGIN
        EXEC [dbo].[sp__SetActor] @uid, 'sp_Login';
        EXEC [dbo].[sp__Log] 'LOGIN_OK', 'USER_ACCOUNT', @uid;
        SELECT user_id, role_code, full_name, approval_status, organization_id
        FROM [dbo].[USER_ACCOUNT] WHERE user_id = @uid;
        RETURN;
    END

    EXEC [dbo].[sp__SetActor] NULL, 'LOGIN';
    EXEC [dbo].[sp__Log] 'LOGIN_FAIL', 'USER_ACCOUNT', '0';      -- the attempted email is not stored
    THROW 50006, 'Login failed.', 1;
END;
GO

-- [project.pdf Κοινές αρχές p.5: password management]
CREATE OR ALTER PROCEDURE [dbo].[sp_ChangePassword]
    @actor_user_id INT,
    @old_password  NVARCHAR(128),
    @new_password  NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN,SYSTEM_OFFICER,CONSUMER,TECHNICIAN_ANY,DSO,TSO,SUPPLIER,AGGREGATOR';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_ChangePassword';

    IF @new_password IS NULL OR LEN(@new_password) < 8
        THROW 50004, 'Invalid input: the password needs at least 8 characters.', 1;

    DECLARE @salt VARBINARY(16) = CRYPT_GEN_RANDOM(16);
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[USER_ACCOUNT]
           SET password_salt = @salt,
               password_hash = [dbo].[fn_HashPassword](@new_password, @salt)
         WHERE user_id = @actor_user_id
           AND @old_password IS NOT NULL
           AND password_hash = [dbo].[fn_HashPassword](@old_password, password_salt);
        IF @@ROWCOUNT = 0
            THROW 50006, 'Login failed.', 1;
        COMMIT TRANSACTION;                              -- TR10 logs PASSWORD_CHANGE (no values)
        SELECT @actor_user_id AS user_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.1 p.5: a consumer registers without pre-approval; UC-01]
CREATE OR ALTER PROCEDURE [dbo].[sp_RegisterConsumer]
    @email        VARCHAR(255),
    @password     NVARCHAR(128),
    @full_name    NVARCHAR(150),
    @phone        VARCHAR(20),
    @iban         VARCHAR(34),
    @notify_email BIT = 1,
    @notify_sms   BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__SetActor] NULL, 'sp_RegisterConsumer';
    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC [dbo].[sp__NewUser] @email, @password, @full_name, @phone, 'CONSUMER', 'APPROVED',
                                 @iban = @iban, @new_id = @new_id OUTPUT;
        UPDATE [dbo].[USER_ACCOUNT]
           SET notify_email = ISNULL(@notify_email, 1), notify_sms = ISNULL(@notify_sms, 0)
         WHERE user_id = @new_id;
        COMMIT TRANSACTION;
        SELECT @new_id AS user_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: this email is already registered.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.1 p.7: a technician registers and waits for approval; UC-09]
CREATE OR ALTER PROCEDURE [dbo].[sp_RegisterTechnician]
    @email      VARCHAR(255),
    @password   NVARCHAR(128),
    @full_name  NVARCHAR(150),
    @phone      VARCHAR(20),
    @birth_date DATE,
    @photo_path VARCHAR(500),
    @specialty  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__SetActor] NULL, 'sp_RegisterTechnician';

    IF @birth_date IS NULL OR @photo_path IS NULL OR @specialty IS NULL
        THROW 50004, 'Invalid input: birth date, photo and specialty are required.', 1;
    IF DATEADD(YEAR, 18, @birth_date) > CAST(SYSUTCDATETIME() AS DATE)
        THROW 50004, 'Invalid input: a technician must be at least 18 years old.', 1;

    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC [dbo].[sp__NewUser] @email, @password, @full_name, @phone, 'TECHNICIAN', 'PENDING',
                                 @birth_date = @birth_date, @photo_path = @photo_path, @specialty = @specialty,
                                 @new_id = @new_id OUTPUT;
        COMMIT TRANSACTION;
        SELECT @new_id AS user_id, 'PENDING' AS approval_status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: this email is already registered.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.1 p.5 account details; §1.2 p.6 notification preferences]
-- IBAN and notification flags apply to consumers only.
CREATE OR ALTER PROCEDURE [dbo].[sp_UpdateMyProfile]
    @actor_user_id INT,
    @full_name     NVARCHAR(150),
    @phone         VARCHAR(20),
    @iban          VARCHAR(34) = NULL,
    @notify_email  BIT = NULL,
    @notify_sms    BIT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN,SYSTEM_OFFICER,CONSUMER,TECHNICIAN_ANY,DSO,TSO,SUPPLIER,AGGREGATOR';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_UpdateMyProfile';

    IF @full_name IS NULL OR LTRIM(RTRIM(@full_name)) = N''
        THROW 50004, 'Invalid input: the full name is required.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[USER_ACCOUNT]
           SET full_name    = LTRIM(RTRIM(@full_name)),
               phone        = @phone,
               iban         = CASE WHEN role_code = 'CONSUMER' THEN @iban ELSE NULL END,
               notify_email = CASE WHEN role_code = 'CONSUMER' THEN ISNULL(@notify_email, notify_email) ELSE notify_email END,
               notify_sms   = CASE WHEN role_code = 'CONSUMER' THEN ISNULL(@notify_sms, notify_sms) ELSE notify_sms END
         WHERE user_id = @actor_user_id;
        IF @@ROWCOUNT = 0
            THROW 50001, 'User not found.', 1;
        COMMIT TRANSACTION;
        SELECT @actor_user_id AS user_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.1 p.5: the user sees their own details] - read through the role's view, no hash or salt
CREATE OR ALTER PROCEDURE [dbo].[sp_GetMyProfile]
    @actor_user_id INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN,SYSTEM_OFFICER,CONSUMER,TECHNICIAN_ANY,DSO,TSO,SUPPLIER,AGGREGATOR';

    DECLARE @role VARCHAR(20);
    SELECT @role = role_code FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;

    IF @role = 'CONSUMER'
        SELECT * FROM [dbo].[view_CONSUMER] WHERE user_id = @actor_user_id;
    ELSE IF @role = 'TECHNICIAN'
        SELECT * FROM [dbo].[view_TECHNICIAN] WHERE user_id = @actor_user_id;
    ELSE IF @role IN ('SUPPLIER', 'AGGREGATOR')
        SELECT * FROM [dbo].[view_ORGANIZATION_USER] WHERE user_id = @actor_user_id;
    ELSE
        SELECT * FROM [dbo].[view_STAFF] WHERE user_id = @actor_user_id;
END;
GO

-- [project.pdf Κοινές αρχές p.5: officers are created by the administrator; UC-20]
CREATE OR ALTER PROCEDURE [dbo].[sp_CreateStaffUser]
    @actor_user_id INT,
    @email         VARCHAR(255),
    @password      NVARCHAR(128),
    @full_name     NVARCHAR(150),
    @phone         VARCHAR(20),
    @role_code     VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_CreateStaffUser';

    IF @role_code IS NULL OR @role_code NOT IN ('SYSTEM_OFFICER', 'DSO', 'TSO')
        THROW 50004, 'Invalid input: the role must be SYSTEM_OFFICER, DSO or TSO.', 1;

    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC [dbo].[sp__NewUser] @email, @password, @full_name, @phone, @role_code, 'APPROVED', @new_id = @new_id OUTPUT;
        COMMIT TRANSACTION;
        SELECT @new_id AS user_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: this email is already registered.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §II.Ε p.3-4 suppliers; §5.1 p.10 aggregators]
CREATE OR ALTER PROCEDURE [dbo].[sp_CreateOrganization]
    @actor_user_id INT,
    @name          NVARCHAR(150),
    @org_type      VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN,SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_CreateOrganization';

    IF @name IS NULL OR LTRIM(RTRIM(@name)) = N'' OR @org_type IS NULL OR @org_type NOT IN ('SUPPLIER', 'AGGREGATOR')
        THROW 50004, 'Invalid input: a name and an org_type of SUPPLIER or AGGREGATOR are required.', 1;
    IF EXISTS (SELECT 1 FROM [dbo].[ORGANIZATION] WHERE name = LTRIM(RTRIM(@name)))
        THROW 50005, 'Duplicate: an organization with this name already exists.', 1;

    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[ORGANIZATION] (name, org_type) VALUES (LTRIM(RTRIM(@name)), @org_type);
        SET @new_id = SCOPE_IDENTITY();
        EXEC [dbo].[sp__Log] 'CREATE', 'ORGANIZATION', @new_id, NULL, @org_type;
        COMMIT TRANSACTION;
        SELECT @new_id AS organization_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: an organization with this name already exists.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §5.1 p.10: users of a supplier or an aggregator]
-- The role of the new user is the type of the organization.
CREATE OR ALTER PROCEDURE [dbo].[sp_CreateOrganizationUser]
    @actor_user_id   INT,
    @organization_id INT,
    @email           VARCHAR(255),
    @password        NVARCHAR(128),
    @full_name       NVARCHAR(150),
    @phone           VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN,SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_CreateOrganizationUser';

    DECLARE @role VARCHAR(20), @new_id INT;
    SELECT @role = org_type FROM [dbo].[ORGANIZATION] WHERE organization_id = @organization_id;
    IF @role IS NULL
        THROW 50001, 'Organization not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC [dbo].[sp__NewUser] @email, @password, @full_name, @phone, @role, 'APPROVED',
                                 @organization_id = @organization_id, @new_id = @new_id OUTPUT;
        COMMIT TRANSACTION;
        SELECT @new_id AS user_id, @role AS role_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: this email is already registered.', 1;
        THROW;
    END CATCH
END;
GO

-- [AR: account management] The last active administrator cannot be deactivated.
CREATE OR ALTER PROCEDURE [dbo].[sp_SetUserActive]
    @actor_user_id INT,
    @user_id       INT,
    @is_active     BIT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_SetUserActive';

    IF @is_active IS NULL
        THROW 50004, 'Invalid input: is_active is required.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @role VARCHAR(20), @anon DATETIME2(0);
        SELECT @role = role_code, @anon = anonymized_at
        FROM [dbo].[USER_ACCOUNT] WITH (UPDLOCK, HOLDLOCK) WHERE user_id = @user_id;

        IF @role IS NULL
            THROW 50001, 'User not found.', 1;
        IF @anon IS NOT NULL AND @is_active = 1
            THROW 50003, 'An anonymized user cannot be activated again.', 1;
        IF @is_active = 0 AND @role = 'SYSTEM_ADMIN'
           AND NOT EXISTS (SELECT 1 FROM [dbo].[USER_ACCOUNT] WITH (UPDLOCK, HOLDLOCK)
                           WHERE role_code = 'SYSTEM_ADMIN' AND is_active = 1 AND user_id <> @user_id)
            THROW 50003, 'The last active administrator cannot be deactivated.', 1;

        UPDATE [dbo].[USER_ACCOUNT] SET is_active = @is_active WHERE user_id = @user_id;
        COMMIT TRANSACTION;
        SELECT @user_id AS user_id, @is_active AS is_active;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf Κοινές αρχές p.5: administration of users] - paged, never returns hash or salt
CREATE OR ALTER PROCEDURE [dbo].[sp_ListUsers]
    @actor_user_id   INT,
    @role_code       VARCHAR(20)   = NULL,
    @approval_status VARCHAR(20)   = NULL,
    @search          NVARCHAR(100) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN,SYSTEM_OFFICER';
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 500 SET @page_size = 50;

    SELECT u.user_id, u.email, u.full_name, u.phone, u.role_code, u.approval_status, u.is_active,
           u.created_at, u.anonymized_at, u.organization_id, o.name AS organization_name
    FROM [dbo].[USER_ACCOUNT] AS u
    LEFT JOIN [dbo].[ORGANIZATION] AS o ON o.organization_id = u.organization_id
    WHERE (@role_code IS NULL OR u.role_code = @role_code)
      AND (@approval_status IS NULL OR u.approval_status = @approval_status)
      AND (@search IS NULL OR u.full_name LIKE N'%' + @search + N'%' OR u.email LIKE N'%' + @search + N'%')
    ORDER BY u.user_id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END;
GO

-- [project.pdf §2.1 p.7: the technician uploads identity, licence and training documents; UC-09]
CREATE OR ALTER PROCEDURE [dbo].[sp_AddTechnicianDocument]
    @actor_user_id INT,
    @doc_type      VARCHAR(40),
    @doc_code      VARCHAR(60),
    @issue_date    DATE,
    @expiry_date   DATE,
    @file_path     VARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN_ANY';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_AddTechnicianDocument';

    IF @doc_type IS NULL OR @doc_type NOT IN ('ID_CARD', 'INSTALLER_LICENSE', 'TRAINING_CERT')
        THROW 50004, 'Invalid input: doc_type must be ID_CARD, INSTALLER_LICENSE or TRAINING_CERT.', 1;
    IF @doc_code IS NULL OR @issue_date IS NULL OR @file_path IS NULL
        THROW 50004, 'Invalid input: code, issue date and file are required.', 1;
    IF @expiry_date IS NOT NULL AND @expiry_date < @issue_date
        THROW 50004, 'Invalid input: the expiry date is before the issue date.', 1;
    IF EXISTS (SELECT 1 FROM [dbo].[DOCUMENT] WHERE doc_type = @doc_type AND doc_code = @doc_code)
        THROW 50005, 'Duplicate: a document of this type with this code already exists.', 1;

    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[DOCUMENT] (doc_type, doc_code, issue_date, expiry_date, file_path, approval_status, user_id)
        VALUES (@doc_type, @doc_code, @issue_date, @expiry_date, @file_path, 'PENDING', @actor_user_id);
        SET @new_id = SCOPE_IDENTITY();
        COMMIT TRANSACTION;
        SELECT @new_id AS document_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: a document of this type with this code already exists.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.1 p.7: a rejected document can be sent again] REJECTED -> PENDING
-- Owner = the technician of the document, or the installer of the meter the certificate belongs to.
CREATE OR ALTER PROCEDURE [dbo].[sp_ResubmitDocument]
    @actor_user_id INT,
    @document_id   INT,
    @file_path     VARCHAR(500),
    @issue_date    DATE,
    @expiry_date   DATE
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN_ANY';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_ResubmitDocument';

    IF @file_path IS NULL OR @issue_date IS NULL OR (@expiry_date IS NOT NULL AND @expiry_date < @issue_date)
        THROW 50004, 'Invalid input: file and issue date are required, and expiry cannot be before issue.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[DOCUMENT] AS d
                   LEFT JOIN [dbo].[METER] AS m ON m.meter_id = d.meter_id
                   WHERE d.document_id = @document_id
                     AND (d.user_id = @actor_user_id OR m.installed_by_user_id = @actor_user_id))
        THROW 50002, 'Permission denied: not your document.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[DOCUMENT]
           SET file_path = @file_path, issue_date = @issue_date, expiry_date = @expiry_date, approval_status = 'PENDING'
         WHERE document_id = @document_id AND approval_status = 'REJECTED';
        IF @@ROWCOUNT = 0
            THROW 50003, 'Only a REJECTED document can be submitted again.', 1;
        COMMIT TRANSACTION;
        SELECT @document_id AS document_id, 'PENDING' AS approval_status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf Κοινές αρχές p.5: the officer checks documents and records the result; UC-09, UC-10]
CREATE OR ALTER PROCEDURE [dbo].[sp_DecideDocument]
    @actor_user_id INT,
    @document_id   INT,
    @decision      VARCHAR(20),
    @comment       NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_DecideDocument';

    IF @decision IS NULL OR @decision NOT IN ('APPROVED', 'REJECTED')
        THROW 50004, 'Invalid input: the decision must be APPROVED or REJECTED.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[DOCUMENT] WHERE document_id = @document_id)
        THROW 50001, 'Document not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[DOCUMENT]
           SET approval_status = @decision
         WHERE document_id = @document_id AND approval_status = 'PENDING';
        IF @@ROWCOUNT = 0
            THROW 50003, 'The document is not PENDING (another officer may have decided it).', 1;
        IF @comment IS NOT NULL
            EXEC [dbo].[sp__Log] 'DECISION_COMMENT', 'DOCUMENT', @document_id, 'PENDING', @decision, @comment;
        COMMIT TRANSACTION;
        SELECT @document_id AS document_id, @decision AS approval_status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.1 p.7: the officer sees the technicians that wait for approval]
CREATE OR ALTER PROCEDURE [dbo].[sp_ListPendingTechnicians]
    @actor_user_id INT,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 500 SET @page_size = 50;

    SELECT t.user_id, t.email, t.full_name, t.phone, t.birth_date, t.photo_path, t.specialty, t.approval_status,
           SUM(CASE WHEN d.approval_status = 'PENDING'  THEN 1 ELSE 0 END) AS documents_pending,
           SUM(CASE WHEN d.approval_status = 'APPROVED' THEN 1 ELSE 0 END) AS documents_approved,
           SUM(CASE WHEN d.approval_status = 'REJECTED' THEN 1 ELSE 0 END) AS documents_rejected
    FROM [dbo].[view_TECHNICIAN] AS t
    LEFT JOIN [dbo].[DOCUMENT] AS d ON d.user_id = t.user_id
    WHERE t.approval_status = 'PENDING'
    GROUP BY t.user_id, t.email, t.full_name, t.phone, t.birth_date, t.photo_path, t.specialty, t.approval_status
    ORDER BY t.user_id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END;
GO

-- [project.pdf §2.1 p.7: the officer approves, rejects or suspends a technician; UC-09]
-- PENDING -> APPROVED | REJECTED;  APPROVED <-> SUSPENDED.  Approval needs the 3 documents approved and not expired.
CREATE OR ALTER PROCEDURE [dbo].[sp_DecideTechnician]
    @actor_user_id      INT,
    @technician_user_id INT,
    @decision           VARCHAR(20),
    @comment            NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_DecideTechnician';

    IF @decision IS NULL OR @decision NOT IN ('APPROVED', 'REJECTED', 'SUSPENDED')
        THROW 50004, 'Invalid input: the decision must be APPROVED, REJECTED or SUSPENDED.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[USER_ACCOUNT] WHERE user_id = @technician_user_id AND role_code = 'TECHNICIAN')
        THROW 50001, 'Technician not found.', 1;
    IF @decision = 'APPROVED'
       AND (SELECT COUNT(DISTINCT d.doc_type) FROM [dbo].[DOCUMENT] AS d
            WHERE d.user_id = @technician_user_id AND d.approval_status = 'APPROVED'
              AND (d.expiry_date IS NULL OR d.expiry_date >= CAST(SYSUTCDATETIME() AS DATE))) < 3
        THROW 50004, 'The technician needs the 3 documents (ID card, installer licence, training certificate) approved and not expired.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[USER_ACCOUNT]
           SET approval_status = @decision
         WHERE user_id = @technician_user_id
           AND role_code = 'TECHNICIAN'
           AND (   (@decision = 'APPROVED'  AND approval_status IN ('PENDING', 'SUSPENDED'))
                OR (@decision = 'REJECTED'  AND approval_status = 'PENDING')
                OR (@decision = 'SUSPENDED' AND approval_status = 'APPROVED'));
        IF @@ROWCOUNT = 0
            THROW 50003, 'This decision is not allowed in the current approval status of the technician.', 1;
        IF @comment IS NOT NULL
            EXEC [dbo].[sp__Log] 'DECISION_COMMENT', 'USER_ACCOUNT', @technician_user_id, NULL, @decision, @comment;
        COMMIT TRANSACTION;
        SELECT @technician_user_id AS user_id, @decision AS approval_status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.1 p.7: a rejected technician can apply again after new documents] REJECTED -> PENDING
CREATE OR ALTER PROCEDURE [dbo].[sp_ResubmitTechnician]
    @actor_user_id INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN_ANY';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_ResubmitTechnician';
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[USER_ACCOUNT]
           SET approval_status = 'PENDING'
         WHERE user_id = @actor_user_id AND approval_status = 'REJECTED';
        IF @@ROWCOUNT = 0
            THROW 50003, 'Only a REJECTED registration can be submitted again.', 1;
        COMMIT TRANSACTION;
        SELECT @actor_user_id AS user_id, 'PENDING' AS approval_status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.1 p.7: daily availability in time and in area]
-- Upsert of one slot (PK user, date, start); no overlap with the other slots of the day.
CREATE OR ALTER PROCEDURE [dbo].[sp_SetAvailability]
    @actor_user_id INT,
    @avail_date    DATE,
    @start_time    TIME(0),
    @end_time      TIME(0),
    @district      NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN_ANY';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_SetAvailability';

    IF @avail_date IS NULL OR @start_time IS NULL OR @end_time IS NULL OR @end_time <= @start_time
        THROW 50004, 'Invalid input: date, start and end are required and the end must be after the start.', 1;
    IF @avail_date < CAST(SYSUTCDATETIME() AS DATE)
        THROW 50004, 'Invalid input: the date cannot be in the past.', 1;
    IF @district IS NULL OR @district NOT IN (N'Λευκωσία', N'Λεμεσός', N'Λάρνακα', N'Πάφος', N'Αμμόχωστος', N'Κερύνεια')
        THROW 50004, 'Invalid input: the district must be one of the 6 districts.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        IF EXISTS (SELECT 1 FROM [dbo].[TECHNICIAN_AVAILABILITY] WITH (UPDLOCK, HOLDLOCK)
                   WHERE user_id = @actor_user_id AND avail_date = @avail_date
                     AND start_time <> @start_time
                     AND start_time < @end_time AND end_time > @start_time)
            THROW 50004, 'Invalid input: the slot overlaps another slot of the same day.', 1;

        UPDATE [dbo].[TECHNICIAN_AVAILABILITY]
           SET end_time = @end_time, district = @district
         WHERE user_id = @actor_user_id AND avail_date = @avail_date AND start_time = @start_time;
        IF @@ROWCOUNT = 0
            INSERT INTO [dbo].[TECHNICIAN_AVAILABILITY] (user_id, avail_date, start_time, end_time, district)
            VALUES (@actor_user_id, @avail_date, @start_time, @end_time, @district);
        COMMIT TRANSACTION;
        SELECT @actor_user_id AS user_id, @avail_date AS avail_date, @start_time AS start_time;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.1 p.7: availability can be withdrawn]
CREATE OR ALTER PROCEDURE [dbo].[sp_DeleteAvailability]
    @actor_user_id INT,
    @avail_date    DATE,
    @start_time    TIME(0)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN_ANY';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_DeleteAvailability';
    BEGIN TRY
        BEGIN TRANSACTION;
        DELETE FROM [dbo].[TECHNICIAN_AVAILABILITY]
         WHERE user_id = @actor_user_id AND avail_date = @avail_date AND start_time = @start_time;
        IF @@ROWCOUNT = 0
            THROW 50001, 'Availability slot not found.', 1;
        COMMIT TRANSACTION;
        SELECT @actor_user_id AS user_id, @avail_date AS avail_date, @start_time AS start_time;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.1 p.7: the technician sees the availability they declared]
CREATE OR ALTER PROCEDURE [dbo].[sp_GetMyAvailability]
    @actor_user_id INT,
    @from          DATE = NULL,
    @to            DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN_ANY';

    SELECT avail_date, start_time, end_time, district
    FROM [dbo].[TECHNICIAN_AVAILABILITY]
    WHERE user_id = @actor_user_id
      AND (@from IS NULL OR avail_date >= @from)
      AND (@to   IS NULL OR avail_date <= @to)
    ORDER BY avail_date, start_time;
END;
GO

-- [project.pdf §1.3 p.6: the request is given to a suitable technician; §2.1 p.7 availability]
-- Approved technicians with a slot that covers the time in that district and no other job at that time.
-- The requested specialty comes first. sp_AssignWorkOrder reads this result set (same columns).
CREATE OR ALTER PROCEDURE [dbo].[sp_FindAvailableTechnicians]
    @actor_user_id INT,
    @date          DATE,
    @start_time    TIME(0),
    @end_time      TIME(0),
    @district      NVARCHAR(30),
    @specialty     NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';

    IF @date IS NULL OR @start_time IS NULL OR @end_time IS NULL OR @end_time <= @start_time
        THROW 50004, 'Invalid input: date, start and end are required and the end must be after the start.', 1;

    DECLARE @start_dt DATETIME2(0) = DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00:00' AS TIME(0)), @start_time), CAST(@date AS DATETIME2(0)));
    DECLARE @end_dt   DATETIME2(0) = DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00:00' AS TIME(0)), @end_time),   CAST(@date AS DATETIME2(0)));

    SELECT t.user_id, t.full_name, t.phone, t.specialty,
           CAST(CASE WHEN @specialty IS NOT NULL AND t.specialty = @specialty THEN 1 ELSE 0 END AS BIT) AS specialty_match,
           a.start_time AS slot_start, a.end_time AS slot_end
    FROM [dbo].[view_TECHNICIAN] AS t
    JOIN [dbo].[TECHNICIAN_AVAILABILITY] AS a ON a.user_id = t.user_id
    WHERE t.approval_status = 'APPROVED'
      AND t.is_active = 1
      AND a.avail_date = @date
      AND a.district = @district
      AND a.start_time <= @start_time
      AND a.end_time >= @end_time
      AND NOT EXISTS (SELECT 1 FROM [dbo].[WORK_ORDER] AS w
                      WHERE w.technician_user_id = t.user_id
                        AND w.status IN ('ASSIGNED', 'ACCEPTED', 'IN_PROGRESS')
                        AND w.scheduled_start < @end_dt
                        AND w.scheduled_end > @start_dt)
    ORDER BY specialty_match DESC, t.full_name;
END;
GO

PRINT 'procedures_01_accounts.sql: 22 procedures created.';
GO
