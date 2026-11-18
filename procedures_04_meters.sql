/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_04_meters.sql  -  Build Spec §9.4: meters
   METER.status (§4.2): PENDING -> ACTIVE | INACTIVE; ACTIVE <-> INACTIVE;
   ACTIVE -> FAULTY -> ACTIVE; any -> REMOVED (final).
   TR04 (3 certificates), TR08 (level-1 transformer), TR13 (audit) back these procedures.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf §2.3 p.7: the technician registers the meter they installed; §4.1 p.9 geofence; UC-10]
CREATE OR ALTER PROCEDURE [dbo].[sp_InstallMeter]
    @actor_user_id      INT,
    @work_order_id      INT,
    @serial_number      VARCHAR(50),
    @network_id         VARCHAR(60),
    @firmware_version   VARCHAR(30),
    @communication_type VARCHAR(20),
    @latitude           DECIMAL(9,6),
    @longitude          DECIMAL(9,6),
    @meter_type_id      INT,
    @installation_photo VARCHAR(500) = NULL,
    @transformer_id     INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_InstallMeter';

    DECLARE @premise_id INT, @wo_type VARCHAR(20), @wo_status VARCHAR(20), @wo_tech INT;
    SELECT @premise_id = premise_id, @wo_type = work_type, @wo_status = status, @wo_tech = technician_user_id
    FROM [dbo].[WORK_ORDER] WHERE work_order_id = @work_order_id;

    IF @wo_type IS NULL
        THROW 50001, 'Work order not found.', 1;
    IF ISNULL(@wo_tech, 0) <> @actor_user_id
        THROW 50002, 'Permission denied: the work order is not assigned to you.', 1;
    IF @wo_type <> 'INSTALLATION' OR @wo_status NOT IN ('ACCEPTED', 'IN_PROGRESS') OR @premise_id IS NULL
        THROW 50003, 'The work order must be an INSTALLATION for a premise, in ACCEPTED or IN_PROGRESS state.', 1;
    IF @serial_number IS NULL OR @network_id IS NULL OR @firmware_version IS NULL
        THROW 50004, 'Invalid input: serial number, network id and firmware version are required.', 1;
    IF @communication_type IS NULL OR @communication_type NOT IN ('CELLULAR', 'NB_IOT', 'PLC')
        THROW 50004, 'Invalid input: unknown communication type.', 1;
    IF @latitude IS NULL OR @longitude IS NULL OR @latitude NOT BETWEEN -90 AND 90 OR @longitude NOT BETWEEN -180 AND 180
        THROW 50004, 'Invalid input: the coordinates are not valid.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[METER_TYPE] WHERE meter_type_id = @meter_type_id)
        THROW 50004, 'Invalid input: unknown meter type.', 1;
    IF EXISTS (SELECT 1 FROM [dbo].[METER] WHERE serial_number = @serial_number OR network_id = @network_id)
        THROW 50005, 'Duplicate: a meter with this serial number or network id already exists.', 1;
    IF EXISTS (SELECT 1 FROM [dbo].[METER] WHERE premise_id = @premise_id AND removed_at IS NULL)
        THROW 50003, 'The premise already has a meter in service.', 1;

    SET @transformer_id = ISNULL(@transformer_id, [dbo].[fn_FindGeofence](@latitude, @longitude));
    IF @transformer_id IS NULL
        THROW 50004, 'No geofence holds these coordinates; give the transformer explicitly.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[TRANSFORMER] WHERE transformer_id = @transformer_id AND [level] = 1)
        THROW 50004, 'Invalid input: the transformer must be an existing level-1 transformer.', 1;

    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[METER] (serial_number, network_id, firmware_version, communication_type, latitude, longitude,
                                   status, installed_at, installation_photo, meter_type_id, transformer_id,
                                   premise_id, installed_by_user_id)
        VALUES (@serial_number, @network_id, @firmware_version, @communication_type, @latitude, @longitude,
                'PENDING', SYSUTCDATETIME(), @installation_photo, @meter_type_id, @transformer_id,
                @premise_id, @actor_user_id);
        SET @new_id = SCOPE_IDENTITY();

        UPDATE [dbo].[WORK_ORDER]
           SET meter_id = @new_id
         WHERE work_order_id = @work_order_id
           AND technician_user_id = @actor_user_id
           AND status IN ('ACCEPTED', 'IN_PROGRESS');
        IF @@ROWCOUNT = 0
            THROW 50003, 'The work order changed state while the meter was being registered.', 1;
        COMMIT TRANSACTION;
        SELECT @new_id AS meter_id, 'PENDING' AS status, @transformer_id AS transformer_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: serial number, network id, or a meter already in service on this premise.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.3 p.7: calibration certificate, CE declaration, encryption certificate; UC-10]
CREATE OR ALTER PROCEDURE [dbo].[sp_AddMeterDocument]
    @actor_user_id INT,
    @meter_id      INT,
    @doc_type      VARCHAR(40),
    @doc_code      VARCHAR(60),
    @issue_date    DATE,
    @expiry_date   DATE,
    @file_path     VARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_AddMeterDocument';

    IF NOT EXISTS (SELECT 1 FROM [dbo].[METER] WHERE meter_id = @meter_id)
        THROW 50001, 'Meter not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[METER] WHERE meter_id = @meter_id AND installed_by_user_id = @actor_user_id)
        THROW 50002, 'Permission denied: you did not install this meter.', 1;
    IF @doc_type IS NULL OR @doc_type NOT IN ('CALIBRATION_CERT', 'CE_DECLARATION', 'ENCRYPTION_CERT')
        THROW 50004, 'Invalid input: doc_type must be CALIBRATION_CERT, CE_DECLARATION or ENCRYPTION_CERT.', 1;
    IF @doc_code IS NULL OR @issue_date IS NULL OR @file_path IS NULL
        THROW 50004, 'Invalid input: code, issue date and file are required.', 1;
    IF @expiry_date IS NOT NULL AND @expiry_date < @issue_date
        THROW 50004, 'Invalid input: the expiry date is before the issue date.', 1;
    IF EXISTS (SELECT 1 FROM [dbo].[DOCUMENT] WHERE doc_type = @doc_type AND doc_code = @doc_code)
        THROW 50005, 'Duplicate: a document of this type with this code already exists.', 1;

    DECLARE @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[DOCUMENT] (doc_type, doc_code, issue_date, expiry_date, file_path, approval_status, meter_id)
        VALUES (@doc_type, @doc_code, @issue_date, @expiry_date, @file_path, 'PENDING', @meter_id);
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

-- [project.pdf §2.3 p.8: the officer confirms the installation; only then is the meter active; UC-10]
-- APPROVE: PENDING -> ACTIVE (TR04 checks the 3 certificates). REJECT: PENDING -> INACTIVE.
CREATE OR ALTER PROCEDURE [dbo].[sp_ConfirmMeter]
    @actor_user_id INT,
    @meter_id      INT,
    @decision      VARCHAR(10),
    @comment       NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_ConfirmMeter';

    IF @decision IS NULL OR @decision NOT IN ('APPROVE', 'REJECT')
        THROW 50004, 'Invalid input: the decision must be APPROVE or REJECT.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[METER] WHERE meter_id = @meter_id)
        THROW 50001, 'Meter not found.', 1;

    DECLARE @new_status VARCHAR(20) = CASE WHEN @decision = 'APPROVE' THEN 'ACTIVE' ELSE 'INACTIVE' END;
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[METER]
           SET status = @new_status,
               activated_at = CASE WHEN @decision = 'APPROVE' THEN SYSUTCDATETIME() ELSE activated_at END
         WHERE meter_id = @meter_id AND status = 'PENDING';
        IF @@ROWCOUNT = 0
            THROW 50003, 'The meter is not in PENDING state.', 1;
        IF @comment IS NOT NULL
            EXEC [dbo].[sp__Log] 'DECISION_COMMENT', 'METER', @meter_id, 'PENDING', @new_status, @comment;
        COMMIT TRANSACTION;
        SELECT @meter_id AS meter_id, @new_status AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.3 p.8: a meter is replaced and the history of the premise is kept; UC-11]
-- One transaction: the old meter becomes REMOVED first (one meter in service per premise), then the
-- new meter is inserted PENDING on the same premise and transformer. The old readings stay.
CREATE OR ALTER PROCEDURE [dbo].[sp_ReplaceMeter]
    @actor_user_id      INT,
    @work_order_id      INT,
    @old_meter_id       INT,
    @serial_number      VARCHAR(50),
    @network_id         VARCHAR(60),
    @firmware_version   VARCHAR(30),
    @communication_type VARCHAR(20),
    @latitude           DECIMAL(9,6),
    @longitude          DECIMAL(9,6),
    @meter_type_id      INT,
    @installation_photo VARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_ReplaceMeter';

    DECLARE @wo_type VARCHAR(20), @wo_status VARCHAR(20), @wo_tech INT, @wo_meter INT;
    SELECT @wo_type = work_type, @wo_status = status, @wo_tech = technician_user_id, @wo_meter = meter_id
    FROM [dbo].[WORK_ORDER] WHERE work_order_id = @work_order_id;

    DECLARE @premise_id INT, @transformer_id INT;
    SELECT @premise_id = premise_id, @transformer_id = transformer_id
    FROM [dbo].[METER] WHERE meter_id = @old_meter_id;

    IF @wo_type IS NULL
        THROW 50001, 'Work order not found.', 1;
    IF @premise_id IS NULL
        THROW 50001, 'Old meter not found.', 1;
    IF ISNULL(@wo_tech, 0) <> @actor_user_id
        THROW 50002, 'Permission denied: the work order is not assigned to you.', 1;
    IF @wo_type <> 'REPLACEMENT' OR @wo_status NOT IN ('ACCEPTED', 'IN_PROGRESS') OR ISNULL(@wo_meter, 0) <> @old_meter_id
        THROW 50003, 'The work order must be a REPLACEMENT of this meter, in ACCEPTED or IN_PROGRESS state.', 1;
    IF @serial_number IS NULL OR @network_id IS NULL OR @firmware_version IS NULL
        THROW 50004, 'Invalid input: serial number, network id and firmware version are required.', 1;
    IF @communication_type IS NULL OR @communication_type NOT IN ('CELLULAR', 'NB_IOT', 'PLC')
        THROW 50004, 'Invalid input: unknown communication type.', 1;
    IF @latitude IS NULL OR @longitude IS NULL OR @latitude NOT BETWEEN -90 AND 90 OR @longitude NOT BETWEEN -180 AND 180
        THROW 50004, 'Invalid input: the coordinates are not valid.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[METER_TYPE] WHERE meter_type_id = @meter_type_id)
        THROW 50004, 'Invalid input: unknown meter type.', 1;
    IF EXISTS (SELECT 1 FROM [dbo].[METER] WHERE serial_number = @serial_number OR network_id = @network_id)
        THROW 50005, 'Duplicate: a meter with this serial number or network id already exists.', 1;

    DECLARE @new_id INT, @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[METER]
           SET status = 'REMOVED', removed_at = @now
         WHERE meter_id = @old_meter_id AND status <> 'REMOVED';
        IF @@ROWCOUNT = 0
            THROW 50003, 'The old meter is already REMOVED.', 1;

        INSERT INTO [dbo].[METER] (serial_number, network_id, firmware_version, communication_type, latitude, longitude,
                                   status, installed_at, installation_photo, meter_type_id, transformer_id,
                                   premise_id, installed_by_user_id)
        VALUES (@serial_number, @network_id, @firmware_version, @communication_type, @latitude, @longitude,
                'PENDING', @now, @installation_photo, @meter_type_id, @transformer_id,
                @premise_id, @actor_user_id);
        SET @new_id = SCOPE_IDENTITY();

        EXEC [dbo].[sp__Log] 'REPLACE', 'METER', @new_id, @old_meter_id, @new_id, N'new meter replaces the old one (old_state = old meter id)';
        COMMIT TRANSACTION;
        SELECT @new_id AS meter_id, 'PENDING' AS status, @old_meter_id AS replaced_meter_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: serial number or network id.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.3 p.8: the state of a meter is managed by authorized staff]
-- ACTIVE <-> INACTIVE, ACTIVE -> FAULTY -> ACTIVE.
CREATE OR ALTER PROCEDURE [dbo].[sp_SetMeterStatus]
    @actor_user_id INT,
    @meter_id      INT,
    @status        VARCHAR(20),
    @comment       NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER,DSO';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_SetMeterStatus';

    IF @status IS NULL OR @status NOT IN ('ACTIVE', 'INACTIVE', 'FAULTY')
        THROW 50004, 'Invalid input: the status must be ACTIVE, INACTIVE or FAULTY.', 1;

    DECLARE @old VARCHAR(20);
    SELECT @old = status FROM [dbo].[METER] WHERE meter_id = @meter_id;
    IF @old IS NULL
        THROW 50001, 'Meter not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[METER]
           SET status = @status,
               activated_at = CASE WHEN @status = 'ACTIVE' THEN ISNULL(activated_at, SYSUTCDATETIME()) ELSE activated_at END
         WHERE meter_id = @meter_id
           AND status = @old
           AND (   (@status = 'ACTIVE'   AND status IN ('INACTIVE', 'FAULTY'))
                OR (@status = 'INACTIVE' AND status = 'ACTIVE')
                OR (@status = 'FAULTY'   AND status = 'ACTIVE'));
        IF @@ROWCOUNT = 0
            THROW 50003, 'This status change is not allowed from the current state of the meter.', 1;
        IF @comment IS NOT NULL
            EXEC [dbo].[sp__Log] 'STATUS_COMMENT', 'METER', @meter_id, @old, @status, @comment;
        COMMIT TRANSACTION;
        SELECT @meter_id AS meter_id, @status AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf Κοινές αρχές p.5: changes of technical data are logged; §II.Β p.3]
-- NULL = keep the current value. TR13 writes one audit row per changed column.
CREATE OR ALTER PROCEDURE [dbo].[sp_UpdateMeterTechnicalData]
    @actor_user_id      INT,
    @meter_id           INT,
    @firmware_version   VARCHAR(30) = NULL,
    @communication_type VARCHAR(20) = NULL,
    @meter_type_id      INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'TECHNICIAN,SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_UpdateMeterTechnicalData';

    DECLARE @role VARCHAR(20);
    SELECT @role = role_code FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;

    IF NOT EXISTS (SELECT 1 FROM [dbo].[METER] WHERE meter_id = @meter_id)
        THROW 50001, 'Meter not found.', 1;
    IF @role = 'TECHNICIAN'
       AND NOT EXISTS (SELECT 1 FROM [dbo].[WORK_ORDER]
                       WHERE meter_id = @meter_id AND technician_user_id = @actor_user_id
                         AND status IN ('ACCEPTED', 'IN_PROGRESS'))
        THROW 50002, 'Permission denied: you have no open job on this meter.', 1;
    IF @communication_type IS NOT NULL AND @communication_type NOT IN ('CELLULAR', 'NB_IOT', 'PLC')
        THROW 50004, 'Invalid input: unknown communication type.', 1;
    IF @meter_type_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [dbo].[METER_TYPE] WHERE meter_type_id = @meter_type_id)
        THROW 50004, 'Invalid input: unknown meter type.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE [dbo].[METER]
           SET firmware_version   = ISNULL(@firmware_version, firmware_version),
               communication_type = ISNULL(@communication_type, communication_type),
               meter_type_id      = ISNULL(@meter_type_id, meter_type_id)
         WHERE meter_id = @meter_id AND status <> 'REMOVED';
        IF @@ROWCOUNT = 0
            THROW 50003, 'A REMOVED meter cannot be changed.', 1;
        COMMIT TRANSACTION;
        SELECT @meter_id AS meter_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §2.3 p.7-8: a meter with its type, documents, transformer and premise]
-- One row per document (one row with NULL document columns when there is none).
-- Consumer: own meters. Technician: meters they installed or have a job on. Staff: all.
CREATE OR ALTER PROCEDURE [dbo].[sp_GetMeter]
    @actor_user_id INT,
    @meter_id      INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER,TECHNICIAN,SYSTEM_ADMIN,SYSTEM_OFFICER,DSO,TSO';

    DECLARE @role VARCHAR(20), @owner INT, @installer INT;
    SELECT @role = role_code FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;
    SELECT @owner = p.user_id, @installer = m.installed_by_user_id
    FROM [dbo].[METER] AS m JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
    WHERE m.meter_id = @meter_id;

    IF @owner IS NULL
        THROW 50001, 'Meter not found.', 1;
    IF @role = 'CONSUMER' AND @owner <> @actor_user_id
        THROW 50002, 'Permission denied: not your meter.', 1;
    IF @role = 'TECHNICIAN' AND ISNULL(@installer, 0) <> @actor_user_id
       AND NOT EXISTS (SELECT 1 FROM [dbo].[WORK_ORDER] WHERE meter_id = @meter_id AND technician_user_id = @actor_user_id)
        THROW 50002, 'Permission denied: you have no job on this meter.', 1;

    SELECT m.meter_id, m.serial_number, m.network_id, m.firmware_version, m.communication_type,
           m.latitude, m.longitude, m.status, m.activated_at, m.installed_at, m.removed_at,
           m.installation_photo, m.retention_months,
           mt.meter_type_id, mt.type_name, mt.connection_phases, mt.max_amps,
           t.transformer_id, t.name AS transformer_name,
           p.premise_id, p.address AS premise_address, p.district,
           d.document_id, d.doc_type, d.doc_code, d.issue_date, d.expiry_date, d.file_path,
           d.approval_status AS document_status
    FROM [dbo].[METER] AS m
    JOIN [dbo].[METER_TYPE] AS mt ON mt.meter_type_id = m.meter_type_id
    JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = m.transformer_id
    JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
    LEFT JOIN [dbo].[DOCUMENT] AS d ON d.meter_id = m.meter_id
    WHERE m.meter_id = @meter_id
    ORDER BY d.doc_type;
END;
GO

-- [project.pdf §4.1 p.9: meters by geofence; p.2 maps bonus (Leaflet reads latitude / longitude)]
CREATE OR ALTER PROCEDURE [dbo].[sp_ListMeters]
    @actor_user_id  INT,
    @status         VARCHAR(20)  = NULL,
    @transformer_id INT          = NULL,
    @district       NVARCHAR(30) = NULL,
    @page           INT = 1,
    @page_size      INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_ADMIN,SYSTEM_OFFICER,DSO,TSO';
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 500 SET @page_size = 50;

    SELECT v.meter_id, v.serial_number, v.status, v.latitude, v.longitude,
           v.premise_id, v.premise_address, v.district,
           v.transformer_id, v.transformer_name, v.min_lat, v.min_lon, v.max_lat, v.max_lon
    FROM [dbo].[view_METER_LOCATION] AS v
    WHERE (@status IS NULL OR v.status = @status)
      AND (@transformer_id IS NULL OR v.transformer_id = @transformer_id)
      AND (@district IS NULL OR v.district = @district)
    ORDER BY v.meter_id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END;
GO

PRINT 'procedures_04_meters.sql: 8 procedures created.';
GO
