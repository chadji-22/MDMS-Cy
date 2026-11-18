/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   create.sql  -  Relational Schema v6 FINAL (T-SQL, Microsoft SQL Server 2022/2025)

   v6 = v5 + fixes from the verification against project.pdf (11/11/2026):
     * TRANSFORMER has an optional rectangle (min/max lat/lon) = its Geofence
       area, so a meter's coordinates can be placed in a Geofence [§4.1 p.9].
     * OBIS 14.7.0 (grid frequency, Hz) added to the reference data [§II.Δ p.3].
     * PAYMENT historical-access check closed against a NULL access_to.
     * An anonymized user must be inactive [§1.4 p.6].
     * AUDIT_LOG old/new state widened to hold technical-data changes [p.5].
     * Passwords hashed in SQL: SHA2_512 over a per-user salt (lecture 20-76),
       so login runs as a stored procedure.
     * Views and triggers moved to views.sql / triggers.sql.

   v5 = simplification agreed with the instructor (meeting 09/11/2026):
     * ONE table for every person (USER_ACCOUNT) + ROLE. Role-specific columns
       are NULL for the roles that do not use them; per-role views
       (vw_CONSUMER, vw_TECHNICIAN, ...) are the "interfaces" over it.
     * Suppliers and aggregators = ORGANIZATION (one table, org_type).
     * The Geofence hierarchy IS the transformer tree (TRANSFORMER.parent).
       Sums are stored for every level of the tree (TRANSFORMER_CURRENT_STATE).
     * No lookup tables for premise attributes, no command batches,
       no separate VEE / approval / GDPR-review / attempt logs:
       VEE values live on METER_READING, every other trail in AUDIT_LOG.
     * Information is stored once (no duplicated columns or parallel tables).

   24 tables, 0 junction tables, 1 weak entity (TECHNICIAN_AVAILABILITY).
   All DATETIME2 values are UTC. Constraint names: PK_/UQ_/CK_/DF_/FK_.
   ============================================================================ */

SET NOCOUNT ON;
GO

/* ============================================================================
   0. DROP (re-runnable): drop every FK, then every table, then the views
   ============================================================================ */
DECLARE @drop_fk NVARCHAR(MAX) = N'';
SELECT @drop_fk += N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) + N'.'
                 + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
                 + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';' + NCHAR(10)
FROM sys.foreign_keys AS fk
WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = N'dbo';
EXEC sys.sp_executesql @drop_fk;
GO

DROP VIEW IF EXISTS dbo.vw_CONSUMER, dbo.vw_TECHNICIAN, dbo.vw_ORGANIZATION_USER, dbo.vw_STAFF,
    dbo.view_CONSUMER, dbo.view_TECHNICIAN, dbo.view_ORGANIZATION_USER, dbo.view_STAFF,
    dbo.view_PREMISE_METER, dbo.view_METER_LOCATION, dbo.view_OPEN_WORK_ORDER, dbo.view_BILL_BALANCE;
GO

-- v5 tables + every table name used by v3/v4, so an old database is cleaned too
DROP TABLE IF EXISTS
    dbo.AUDIT_LOG, dbo.GDPR_REQUEST, dbo.PAYMENT, dbo.BILL, dbo.TARIFF,
    dbo.REMOTE_COMMAND, dbo.WORK_ORDER, dbo.SERVICE_TYPE, dbo.EVENT,
    dbo.TRANSFORMER_CURRENT_STATE, dbo.AGGREGATE, dbo.TRANSFORMER_READING,
    dbo.METER_READING, dbo.TELEMETRY_PACKET, dbo.OBIS_CODE, dbo.DOCUMENT,
    dbo.METER, dbo.METER_TYPE, dbo.PREMISE, dbo.TRANSFORMER,
    dbo.TECHNICIAN_AVAILABILITY, dbo.USER_ACCOUNT, dbo.ORGANIZATION, dbo.ROLE,
    -- v3 / v4 leftovers
    dbo.HISTORICAL_ACCESS, dbo.COMMAND_ATTEMPT, dbo.COMMAND_BATCH, dbo.GEOFENCE_AGGREGATE,
    dbo.METER_AGGREGATE, dbo.VEE_LOG, dbo.VEE_RULE, dbo.GEOFENCE_CURRENT_STATE,
    dbo.CONSUMPTION_ALERT, dbo.METER_INSTALLATION, dbo.APPROVAL_DECISION, dbo.METER_DOCUMENT,
    dbo.WORK_ORDER_EVIDENCE, dbo.WORK_ORDER_NOTIFICATION, dbo.SERVICE_REQUEST,
    dbo.AGGREGATOR_MEMBERSHIP, dbo.AGGREGATOR_USER, dbo.AGGREGATOR, dbo.SUPPLIER_ASSIGNMENT,
    dbo.SUPPLIER_USER, dbo.SUPPLIER, dbo.CONSUMER_PREMISE, dbo.GDPR_REVIEW, dbo.GEOFENCE,
    dbo.RETENTION_POLICY, dbo.COMMUNICATION_TYPE, dbo.PROSUMER_SCHEME, dbo.BANK_ACCOUNT,
    dbo.TECHNICIAN_DOCUMENT, dbo.TECHNICIAN_SPECIALTY, dbo.SPECIALTY, dbo.TECHNICIAN,
    dbo.CONSUMER, dbo.PARISH, dbo.MUNICIPALITY, dbo.DISTRICT, dbo.USER_ROLE;
GO

/* ============================================================================
   1. USERS, ROLES, ORGANIZATIONS   [Κοινές αρχές p.5; §1.1 p.5; §2.1 p.7; §5.1 p.10]
   ============================================================================ */

-- ROLE: natural key, so CHECK constraints on USER_ACCOUNT can name the role
CREATE TABLE dbo.ROLE (
    role_code    VARCHAR(20)    NOT NULL,
    description  NVARCHAR(100)  NOT NULL,

    CONSTRAINT PK_ROLE PRIMARY KEY (role_code)
);
GO

-- ORGANIZATION: supplier or aggregator company  [§II.Ε p.3-4, §5.1 p.10]
CREATE TABLE dbo.ORGANIZATION (
    organization_id  INT IDENTITY(1,1)  NOT NULL,
    name             NVARCHAR(150)      NOT NULL,
    org_type         VARCHAR(20)        NOT NULL,

    CONSTRAINT PK_ORGANIZATION PRIMARY KEY (organization_id),
    CONSTRAINT UQ_ORGANIZATION_name UNIQUE (name),
    CONSTRAINT CK_ORGANIZATION_org_type CHECK (org_type IN ('SUPPLIER', 'AGGREGATOR'))
);
GO

-- USER_ACCOUNT: every physical person, whatever the role  [Κοινές αρχές p.5 "μοναδικό λογαριασμό"]
CREATE TABLE dbo.USER_ACCOUNT (
    user_id          INT IDENTITY(1,1)  NOT NULL,
    email            VARCHAR(255)       NOT NULL,                 -- login name [§2.1 p.7 "ενεργό email"]
    password_hash    VARBINARY(64)      NOT NULL,                 -- HASHBYTES('SHA2_512', salt + password), never plaintext [p.5; lecture 20-76]
    password_salt    VARBINARY(16)      NOT NULL,                 -- CRYPT_GEN_RANDOM(16), one per user
    full_name        NVARCHAR(150)      NOT NULL,
    phone            VARCHAR(20)        NULL,
    approval_status  VARCHAR(20)        NOT NULL  CONSTRAINT DF_USER_ACCOUNT_approval_status DEFAULT 'APPROVED',  -- technicians start PENDING [§2.1 p.7]
    is_active        BIT                NOT NULL  CONSTRAINT DF_USER_ACCOUNT_is_active DEFAULT 1,
    created_at       DATETIME2(0)       NOT NULL  CONSTRAINT DF_USER_ACCOUNT_created_at DEFAULT SYSUTCDATETIME(),
    anonymized_at    DATETIME2(0)       NULL,                     -- right to be forgotten executed [§1.4 p.6]
    -- consumer only  [§1.1 p.5 bank details; §1.2 p.6 notification preferences]
    iban             VARCHAR(34)        NULL,
    notify_email     BIT                NOT NULL  CONSTRAINT DF_USER_ACCOUNT_notify_email DEFAULT 1,
    notify_sms       BIT                NOT NULL  CONSTRAINT DF_USER_ACCOUNT_notify_sms DEFAULT 0,
    -- technician only  [§2.1 p.7]
    birth_date       DATE               NULL,
    photo_path       VARCHAR(500)       NULL,
    specialty        NVARCHAR(100)      NULL,
    -- foreign keys
    role_code        VARCHAR(20)        NOT NULL,
    organization_id  INT                NULL,                     -- supplier / aggregator staff only

    CONSTRAINT PK_USER_ACCOUNT PRIMARY KEY (user_id),
    CONSTRAINT UQ_USER_ACCOUNT_email UNIQUE (email),
    CONSTRAINT CK_USER_ACCOUNT_email CHECK (email LIKE '%_@_%._%'),
    CONSTRAINT CK_USER_ACCOUNT_approval_status CHECK (approval_status IN ('PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED')),
    -- role-specific columns: present for the role that needs them, absent for the rest
    CONSTRAINT CK_USER_ACCOUNT_technician CHECK (role_code <> 'TECHNICIAN' OR (birth_date IS NOT NULL AND photo_path IS NOT NULL AND specialty IS NOT NULL)),
    CONSTRAINT CK_USER_ACCOUNT_not_technician CHECK (role_code = 'TECHNICIAN' OR (birth_date IS NULL AND photo_path IS NULL AND specialty IS NULL)),
    CONSTRAINT CK_USER_ACCOUNT_organization CHECK ((role_code IN ('SUPPLIER', 'AGGREGATOR') AND organization_id IS NOT NULL) OR (role_code NOT IN ('SUPPLIER', 'AGGREGATOR') AND organization_id IS NULL)),
    CONSTRAINT CK_USER_ACCOUNT_iban CHECK (role_code = 'CONSUMER' OR iban IS NULL),
    CONSTRAINT CK_USER_ACCOUNT_anonymized CHECK (anonymized_at IS NULL OR is_active = 0)   -- forgotten users cannot log in [§1.4 p.6]
);
GO

-- TECHNICIAN_AVAILABILITY (weak, owner = technician user)  [§2.1 p.7 "ημερήσια χρονική και γεωγραφική διαθεσιμότητα"]
CREATE TABLE dbo.TECHNICIAN_AVAILABILITY (
    user_id      INT            NOT NULL,
    avail_date   DATE           NOT NULL,
    start_time   TIME(0)        NOT NULL,
    end_time     TIME(0)        NOT NULL,
    district     NVARCHAR(30)   NOT NULL,

    CONSTRAINT PK_TECHNICIAN_AVAILABILITY PRIMARY KEY (user_id, avail_date, start_time),
    CONSTRAINT CK_TECHNICIAN_AVAILABILITY_time CHECK (end_time > start_time),
    CONSTRAINT CK_TECHNICIAN_AVAILABILITY_district CHECK (district IN (N'Λευκωσία', N'Λεμεσός', N'Λάρνακα', N'Πάφος', N'Αμμόχωστος', N'Κερύνεια'))
);
GO

/* ============================================================================
   2. GRID: TRANSFORMER TREE   [§4.1 p.9 - instructor: geofence hierarchy = transformer tree]
   ============================================================================ */

-- level 1 = LV transformer that meters hang on; level n = ancestor whose subtree is "Geofence Ln"
CREATE TABLE dbo.TRANSFORMER (
    transformer_id         INT IDENTITY(1,1)  NOT NULL,
    name                   NVARCHAR(100)      NOT NULL,
    [level]                TINYINT            NOT NULL,
    capacity_kva           DECIMAL(10,2)      NOT NULL,
    latitude               DECIMAL(9,6)       NOT NULL,           -- WGS84, for the map [§4.1 p.9]
    longitude              DECIMAL(9,6)       NOT NULL,
    -- Geofence area of this transformer's subtree as a WGS84 rectangle (spec allows a rectangle) [§4.1 p.9]
    min_lat                DECIMAL(9,6)       NULL,
    min_lon                DECIMAL(9,6)       NULL,
    max_lat                DECIMAL(9,6)       NULL,
    max_lon                DECIMAL(9,6)       NULL,
    parent_transformer_id  INT                NULL,               -- NULL = root of the tree

    CONSTRAINT PK_TRANSFORMER PRIMARY KEY (transformer_id),
    CONSTRAINT UQ_TRANSFORMER_name UNIQUE (name),
    CONSTRAINT CK_TRANSFORMER_level CHECK ([level] >= 1),
    CONSTRAINT CK_TRANSFORMER_capacity CHECK (capacity_kva > 0),
    CONSTRAINT CK_TRANSFORMER_not_own_parent CHECK (parent_transformer_id IS NULL OR parent_transformer_id <> transformer_id),
    CONSTRAINT CK_TRANSFORMER_lat CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT CK_TRANSFORMER_lon CHECK (longitude BETWEEN -180 AND 180),
    -- rectangle: all four corners or none, and min <= max
    CONSTRAINT CK_TRANSFORMER_geofence CHECK (
           (min_lat IS NULL AND min_lon IS NULL AND max_lat IS NULL AND max_lon IS NULL)
        OR (min_lat IS NOT NULL AND min_lon IS NOT NULL AND max_lat IS NOT NULL AND max_lon IS NOT NULL
            AND min_lat BETWEEN -90 AND 90 AND max_lat BETWEEN -90 AND 90
            AND min_lon BETWEEN -180 AND 180 AND max_lon BETWEEN -180 AND 180
            AND min_lat <= max_lat AND min_lon <= max_lon))
);
GO

/* ============================================================================
   3. PREMISES AND METERS   [§1.1 p.5; §2.3 p.7-8]
   ============================================================================ */

CREATE TABLE dbo.PREMISE (
    premise_id               INT IDENTITY(1,1)  NOT NULL,        -- the Premise ID [§1.1 p.5]
    address                  NVARCHAR(250)      NOT NULL,
    latitude                 DECIMAL(9,6)       NOT NULL,
    longitude                DECIMAL(9,6)       NOT NULL,
    usage_type               VARCHAR(20)        NOT NULL,
    district                 NVARCHAR(30)       NOT NULL,        -- administrative area kept as columns (no lookup tables, instructor)
    municipality             NVARCHAR(80)       NOT NULL,
    parish                   NVARCHAR(80)       NOT NULL,
    postal_code              CHAR(4)            NOT NULL,
    prosumer_scheme          VARCHAR(20)        NOT NULL  CONSTRAINT DF_PREMISE_prosumer_scheme DEFAULT 'NONE',  -- [§1.2 p.5]
    monthly_threshold_kwh    DECIMAL(18,4)      NULL,            -- consumption alert threshold [§1.2 p.6]
    user_id                  INT                NOT NULL,        -- consumer who registered the premise [§II.Α p.3, §1.1 p.5]
    supplier_org_id          INT                NULL,            -- chosen supplier [§II.Ε p.4]
    aggregator_org_id        INT                NULL,            -- aggregator portfolio [§5.1 p.10]

    CONSTRAINT PK_PREMISE PRIMARY KEY (premise_id),
    CONSTRAINT CK_PREMISE_usage_type CHECK (usage_type IN ('RESIDENTIAL', 'COMMERCIAL', 'INDUSTRIAL', 'AGRICULTURAL')),
    CONSTRAINT CK_PREMISE_district CHECK (district IN (N'Λευκωσία', N'Λεμεσός', N'Λάρνακα', N'Πάφος', N'Αμμόχωστος', N'Κερύνεια')),
    CONSTRAINT CK_PREMISE_postal_code CHECK (postal_code LIKE '[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_PREMISE_prosumer_scheme CHECK (prosumer_scheme IN ('NONE', 'NET_METERING', 'NET_BILLING')),
    CONSTRAINT CK_PREMISE_threshold CHECK (monthly_threshold_kwh IS NULL OR monthly_threshold_kwh > 0),
    CONSTRAINT CK_PREMISE_lat CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT CK_PREMISE_lon CHECK (longitude BETWEEN -180 AND 180)
);
GO

-- METER_TYPE: meter models defined by officers  [Κοινές αρχές p.5 "πρότυπα μετρητών"; §2.3 p.7]
CREATE TABLE dbo.METER_TYPE (
    meter_type_id      INT IDENTITY(1,1)  NOT NULL,
    type_name          VARCHAR(50)        NOT NULL,
    connection_phases  TINYINT            NOT NULL,
    max_amps           DECIMAL(6,1)       NOT NULL,

    CONSTRAINT PK_METER_TYPE PRIMARY KEY (meter_type_id),
    CONSTRAINT UQ_METER_TYPE_type_name UNIQUE (type_name),
    CONSTRAINT CK_METER_TYPE_phases CHECK (connection_phases IN (1, 3)),
    CONSTRAINT CK_METER_TYPE_max_amps CHECK (max_amps > 0)
);
GO

-- METER: installation data lives on the meter. A replaced meter keeps its row (removed_at set)
-- and its readings, so the premise's older time series survive [§2.3 p.8].
CREATE TABLE dbo.METER (
    meter_id              INT IDENTITY(1,1)  NOT NULL,
    serial_number         VARCHAR(50)        NOT NULL,
    network_id            VARCHAR(60)        NOT NULL,           -- matched with packets [§3.1 p.8]
    firmware_version      VARCHAR(30)        NOT NULL,
    communication_type    VARCHAR(20)        NOT NULL,
    latitude              DECIMAL(9,6)       NOT NULL,
    longitude             DECIMAL(9,6)       NOT NULL,
    status                VARCHAR(20)        NOT NULL  CONSTRAINT DF_METER_status DEFAULT 'PENDING',
    activated_at          DATETIME2(0)       NULL,
    installed_at          DATETIME2(0)       NOT NULL,
    removed_at            DATETIME2(0)       NULL,
    installation_photo    VARCHAR(500)       NULL,
    retention_months      TINYINT            NOT NULL  CONSTRAINT DF_METER_retention DEFAULT 36,  -- 36, or 1 after an approved GDPR request [§1.4 p.6-7]
    meter_type_id         INT                NOT NULL,
    transformer_id        INT                NOT NULL,           -- the LV (level 1) transformer [§4.1 p.9]
    premise_id            INT                NOT NULL,
    installed_by_user_id  INT                NULL,

    CONSTRAINT PK_METER PRIMARY KEY (meter_id),
    CONSTRAINT UQ_METER_serial_number UNIQUE (serial_number),
    CONSTRAINT UQ_METER_network_id UNIQUE (network_id),
    CONSTRAINT CK_METER_communication_type CHECK (communication_type IN ('CELLULAR', 'NB_IOT', 'PLC')),
    CONSTRAINT CK_METER_status CHECK (status IN ('PENDING', 'ACTIVE', 'INACTIVE', 'FAULTY', 'REMOVED')),
    CONSTRAINT CK_METER_active CHECK (status <> 'ACTIVE' OR activated_at IS NOT NULL),   -- active only after officer approval [§2.3 p.8]
    CONSTRAINT CK_METER_removed CHECK ((status = 'REMOVED' AND removed_at IS NOT NULL) OR (status <> 'REMOVED' AND removed_at IS NULL)),
    CONSTRAINT CK_METER_dates CHECK (removed_at IS NULL OR removed_at >= installed_at),
    CONSTRAINT CK_METER_retention CHECK (retention_months IN (1, 36)),
    CONSTRAINT CK_METER_lat CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT CK_METER_lon CHECK (longitude BETWEEN -180 AND 180)
);
GO

-- DOCUMENT: technician documents and meter certificates in ONE table (same columns)  [§2.1 p.7; §2.3 p.7]
CREATE TABLE dbo.DOCUMENT (
    document_id      INT IDENTITY(1,1)  NOT NULL,
    doc_type         VARCHAR(40)        NOT NULL,
    doc_code         VARCHAR(60)        NOT NULL,
    issue_date       DATE               NOT NULL,
    expiry_date      DATE               NULL,
    file_path        VARCHAR(500)       NOT NULL,
    approval_status  VARCHAR(20)        NOT NULL  CONSTRAINT DF_DOCUMENT_approval_status DEFAULT 'PENDING',
    user_id          INT                NULL,                    -- technician document
    meter_id         INT                NULL,                    -- meter certificate

    CONSTRAINT PK_DOCUMENT PRIMARY KEY (document_id),
    CONSTRAINT UQ_DOCUMENT_code UNIQUE (doc_type, doc_code),
    CONSTRAINT CK_DOCUMENT_approval_status CHECK (approval_status IN ('PENDING', 'APPROVED', 'REJECTED')),
    CONSTRAINT CK_DOCUMENT_dates CHECK (expiry_date IS NULL OR expiry_date >= issue_date),
    CONSTRAINT CK_DOCUMENT_owner CHECK (
           (user_id IS NOT NULL AND meter_id IS NULL AND doc_type IN ('ID_CARD', 'INSTALLER_LICENSE', 'TRAINING_CERT'))
        OR (meter_id IS NOT NULL AND user_id IS NULL AND doc_type IN ('CALIBRATION_CERT', 'CE_DECLARATION', 'ENCRYPTION_CERT')))
);
GO

/* ============================================================================
   4. TELEMETRY, VEE, AGGREGATES   [§3 p.8-9; §4.2 p.10; Appendix p.15]
   ============================================================================ */

CREATE TABLE dbo.OBIS_CODE (
    obis_code         VARCHAR(20)    NOT NULL,
    description       NVARCHAR(200)  NOT NULL,
    unit              VARCHAR(10)    NOT NULL,
    measurement_kind  VARCHAR(15)    NOT NULL,                   -- CUMULATIVE register or INSTANTANEOUS value [Appendix p.15]
    valid_min         DECIMAL(18,4)  NULL,                       -- VEE range check [§3.2 p.8]
    valid_max         DECIMAL(18,4)  NULL,

    CONSTRAINT PK_OBIS_CODE PRIMARY KEY (obis_code),
    CONSTRAINT CK_OBIS_CODE_kind CHECK (measurement_kind IN ('CUMULATIVE', 'INSTANTANEOUS')),
    CONSTRAINT CK_OBIS_CODE_range CHECK (valid_min IS NULL OR valid_max IS NULL OR valid_max >= valid_min)
);
GO

-- TELEMETRY_PACKET: every incoming packet, matched or not  [§3.1 p.8 "όχι να χάνονται σιωπηρά"]
CREATE TABLE dbo.TELEMETRY_PACKET (
    packet_id               BIGINT IDENTITY(1,1)  NOT NULL,
    meter_network_id        VARCHAR(60)           NOT NULL,
    transmission_timestamp  DATETIME2(0)          NOT NULL,
    received_at             DATETIME2(0)          NOT NULL  CONSTRAINT DF_TELEMETRY_PACKET_received_at DEFAULT SYSUTCDATETIME(),
    network_type            VARCHAR(30)           NULL,
    signal_dbm              SMALLINT              NULL,
    raw_payload             NVARCHAR(4000)        NOT NULL,     -- keeps the OBIS/value pairs of unmatched packets
    match_status            VARCHAR(20)           NOT NULL,
    meter_id                INT                   NULL,

    CONSTRAINT PK_TELEMETRY_PACKET PRIMARY KEY (packet_id),
    CONSTRAINT CK_TELEMETRY_PACKET_json CHECK (ISJSON(raw_payload) = 1),
    CONSTRAINT CK_TELEMETRY_PACKET_status CHECK (match_status IN ('MATCHED', 'UNMATCHED', 'COMM_ERROR', 'QUARANTINED')),
    CONSTRAINT CK_TELEMETRY_PACKET_match CHECK (
           (match_status = 'MATCHED'   AND meter_id IS NOT NULL)
        OR (match_status = 'UNMATCHED' AND meter_id IS NULL)
        OR  match_status IN ('COMM_ERROR', 'QUARANTINED'))
);
GO

-- METER_READING: one value per meter / OBIS / 15-min, with its VEE outcome on the same row
-- [§3.1 p.8; §3.2 p.8-9: status, original value, corrected value, origin of the change]
CREATE TABLE dbo.METER_READING (
    reading_id          BIGINT IDENTITY(1,1)  NOT NULL,
    reading_timestamp   DATETIME2(0)          NOT NULL,
    [value]             DECIMAL(18,4)         NOT NULL,          -- value in use (measured, estimated or edited)
    delta_value         DECIMAL(18,4)         NULL,              -- 15-min energy for CUMULATIVE registers
    status              VARCHAR(20)           NOT NULL  CONSTRAINT DF_METER_READING_status DEFAULT 'PENDING',
    original_value      DECIMAL(18,4)         NULL,              -- value before Editing (NULL if never edited)
    vee_rule            VARCHAR(40)           NULL,              -- rule that flagged / estimated / edited it
    vee_note            NVARCHAR(300)         NULL,
    is_final            BIT                   NOT NULL  CONSTRAINT DF_METER_READING_is_final DEFAULT 0,
    finalized_at        DATETIME2(0)          NULL,
    meter_id            INT                   NOT NULL,
    obis_code           VARCHAR(20)           NOT NULL,
    packet_id           BIGINT                NULL,              -- NULL for estimated readings
    edited_by_user_id   INT                   NULL,              -- NULL = automatic VEE

    CONSTRAINT PK_METER_READING PRIMARY KEY (reading_id),
    CONSTRAINT UQ_METER_READING_slot UNIQUE (meter_id, obis_code, reading_timestamp),
    CONSTRAINT CK_METER_READING_slot CHECK (DATEPART(MINUTE, reading_timestamp) % 15 = 0 AND DATEPART(SECOND, reading_timestamp) = 0),
    CONSTRAINT CK_METER_READING_status CHECK (status IN ('PENDING', 'VALID', 'SUSPECT', 'ESTIMATED', 'EDITED')),
    CONSTRAINT CK_METER_READING_edited CHECK (status <> 'EDITED' OR (original_value IS NOT NULL AND edited_by_user_id IS NOT NULL)),
    CONSTRAINT CK_METER_READING_estimated CHECK (status <> 'ESTIMATED' OR (packet_id IS NULL AND vee_rule IS NOT NULL)),
    CONSTRAINT CK_METER_READING_final CHECK (is_final = 0 OR (finalized_at IS NOT NULL AND status IN ('VALID', 'ESTIMATED', 'EDITED')))
);
GO

-- TRANSFORMER_READING: grid measurements, kept permanently  [§1.4 p.7]
CREATE TABLE dbo.TRANSFORMER_READING (
    transformer_reading_id  BIGINT IDENTITY(1,1)  NOT NULL,
    reading_timestamp       DATETIME2(0)          NOT NULL,
    [value]                 DECIMAL(18,4)         NOT NULL,
    transformer_id          INT                   NOT NULL,
    obis_code               VARCHAR(20)           NOT NULL,

    CONSTRAINT PK_TRANSFORMER_READING PRIMARY KEY (transformer_reading_id),
    CONSTRAINT UQ_TRANSFORMER_READING_slot UNIQUE (transformer_id, obis_code, reading_timestamp),
    CONSTRAINT CK_TRANSFORMER_READING_slot CHECK (DATEPART(MINUTE, reading_timestamp) % 15 = 0 AND DATEPART(SECOND, reading_timestamp) = 0)
);
GO

-- AGGREGATE: historical aggregates of a meter OR of a transformer subtree, in one table
-- [§1.2 p.6 day/month/year; §4.2 p.10 immutable history; §5.2 p.11 provisional intraday = is_final 0]
CREATE TABLE dbo.AGGREGATE (
    aggregate_id    BIGINT IDENTITY(1,1)  NOT NULL,
    period_type     VARCHAR(12)           NOT NULL,
    period_start    DATETIME2(0)          NOT NULL,
    [value]         DECIMAL(20,4)         NOT NULL,
    sample_count    INT                   NOT NULL,              -- readings (meter) or meters (transformer) that contributed
    is_final        BIT                   NOT NULL  CONSTRAINT DF_AGGREGATE_is_final DEFAULT 0,
    calculated_at   DATETIME2(0)          NOT NULL  CONSTRAINT DF_AGGREGATE_calculated_at DEFAULT SYSUTCDATETIME(),
    meter_id        INT                   NULL,
    transformer_id  INT                   NULL,
    obis_code       VARCHAR(20)           NOT NULL,

    CONSTRAINT PK_AGGREGATE PRIMARY KEY (aggregate_id),
    CONSTRAINT CK_AGGREGATE_period_type CHECK (period_type IN ('QUARTER_HOUR', 'DAY', 'MONTH', 'YEAR')),
    CONSTRAINT CK_AGGREGATE_owner CHECK ((meter_id IS NOT NULL AND transformer_id IS NULL) OR (meter_id IS NULL AND transformer_id IS NOT NULL)),
    CONSTRAINT CK_AGGREGATE_sample_count CHECK (sample_count >= 0)
);
GO

-- TRANSFORMER_CURRENT_STATE: latest VEE-verified 15-min sum for EVERY transformer of the tree
-- [§4.2 p.10: intermediate table, whole hierarchy, ancestors updated, only 1.8.0 / 2.8.0]
CREATE TABLE dbo.TRANSFORMER_CURRENT_STATE (
    state_id          BIGINT IDENTITY(1,1)  NOT NULL,
    reference_15_min  DATETIME2(0)          NOT NULL,
    sum_value         DECIMAL(20,4)         NOT NULL,
    meter_count       INT                   NOT NULL,
    computed_at       DATETIME2(0)          NOT NULL  CONSTRAINT DF_TRANSFORMER_CURRENT_STATE_computed_at DEFAULT SYSUTCDATETIME(),
    transformer_id    INT                   NOT NULL,
    obis_code         VARCHAR(20)           NOT NULL,

    CONSTRAINT PK_TRANSFORMER_CURRENT_STATE PRIMARY KEY (state_id),
    CONSTRAINT UQ_TRANSFORMER_CURRENT_STATE_latest UNIQUE (transformer_id, obis_code),
    CONSTRAINT CK_TRANSFORMER_CURRENT_STATE_slot CHECK (DATEPART(MINUTE, reference_15_min) % 15 = 0 AND DATEPART(SECOND, reference_15_min) = 0),
    CONSTRAINT CK_TRANSFORMER_CURRENT_STATE_obis CHECK (obis_code IN ('1.8.0', '2.8.0'))
);
GO

/* ============================================================================
   5. OPERATIONS: EVENTS, WORK ORDERS, REMOTE COMMANDS   [§1.3 p.6; §2.2 p.7; §2.4 p.8]
   ============================================================================ */

-- EVENT: telemetry / grid incidents (Event Log)  [§2.4 p.8; §3.1 p.8]
CREATE TABLE dbo.EVENT (
    event_id         BIGINT IDENTITY(1,1)  NOT NULL,
    event_timestamp  DATETIME2(0)          NOT NULL,
    event_type       VARCHAR(40)           NOT NULL,
    severity         VARCHAR(10)           NOT NULL,
    description      NVARCHAR(500)         NULL,
    meter_id         INT                   NULL,
    transformer_id   INT                   NULL,
    packet_id        BIGINT                NULL,

    CONSTRAINT PK_EVENT PRIMARY KEY (event_id),
    CONSTRAINT CK_EVENT_severity CHECK (severity IN ('INFO', 'WARNING', 'CRITICAL')),
    CONSTRAINT CK_EVENT_source CHECK (meter_id IS NOT NULL OR transformer_id IS NOT NULL OR packet_id IS NOT NULL)
);
GO

-- SERVICE_TYPE: chargeable services defined by officers (e.g. historical data access, meter check)
-- [Κοινές αρχές p.5 "τύπους υπηρεσιών"; §1.2 p.6; §1.3 p.6 MDMS-Cy fee]
CREATE TABLE dbo.SERVICE_TYPE (
    service_type_id  INT IDENTITY(1,1)  NOT NULL,
    service_name     NVARCHAR(100)      NOT NULL,
    fee              DECIMAL(10,2)      NOT NULL,
    is_active        BIT                NOT NULL  CONSTRAINT DF_SERVICE_TYPE_is_active DEFAULT 1,

    CONSTRAINT PK_SERVICE_TYPE PRIMARY KEY (service_type_id),
    CONSTRAINT UQ_SERVICE_TYPE_name UNIQUE (service_name),
    CONSTRAINT CK_SERVICE_TYPE_fee CHECK (fee >= 0)
);
GO

-- WORK_ORDER: also the consumer's check / fault request (one table instead of SERVICE_REQUEST + WORK_ORDER)
-- [§1.3 p.6 request with status, assigned to a technician; §2.2 p.7; §2.4 p.8 anti-tamper checks]
CREATE TABLE dbo.WORK_ORDER (
    work_order_id         INT IDENTITY(1,1)  NOT NULL,
    work_type             VARCHAR(20)        NOT NULL,
    origin                VARCHAR(20)        NOT NULL,
    description           NVARCHAR(1000)     NULL,
    status                VARCHAR(20)        NOT NULL  CONSTRAINT DF_WORK_ORDER_status DEFAULT 'SUBMITTED',
    created_at            DATETIME2(0)       NOT NULL  CONSTRAINT DF_WORK_ORDER_created_at DEFAULT SYSUTCDATETIME(),
    scheduled_start       DATETIME2(0)       NULL,
    scheduled_end         DATETIME2(0)       NULL,
    accepted_at           DATETIME2(0)       NULL,
    completed_at          DATETIME2(0)       NULL,
    findings              NVARCHAR(2000)     NULL,
    evidence_path         VARCHAR(500)       NULL,
    persons_to_notify     NVARCHAR(500)      NULL,               -- [§2.4 p.8]
    requested_by_user_id  INT                NOT NULL,           -- consumer or officer
    technician_user_id    INT                NULL,
    premise_id            INT                NULL,
    meter_id              INT                NULL,
    event_id              BIGINT             NULL,
    service_type_id       INT                NULL,               -- fee, when the request is chargeable

    CONSTRAINT PK_WORK_ORDER PRIMARY KEY (work_order_id),
    CONSTRAINT CK_WORK_ORDER_type CHECK (work_type IN ('INSTALLATION', 'REPLACEMENT', 'TECHNICAL_CHECK', 'FAULT_REPAIR', 'ANTI_TAMPER')),
    CONSTRAINT CK_WORK_ORDER_origin CHECK (origin IN ('CONSUMER_REQUEST', 'EVENT', 'OFFICER')),
    CONSTRAINT CK_WORK_ORDER_status CHECK (status IN ('SUBMITTED', 'ASSIGNED', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT CK_WORK_ORDER_target CHECK (premise_id IS NOT NULL OR meter_id IS NOT NULL),
    CONSTRAINT CK_WORK_ORDER_event CHECK (origin <> 'EVENT' OR event_id IS NOT NULL),
    CONSTRAINT CK_WORK_ORDER_assigned CHECK (status IN ('SUBMITTED', 'CANCELLED') OR technician_user_id IS NOT NULL),
    CONSTRAINT CK_WORK_ORDER_completed CHECK (status <> 'COMPLETED' OR completed_at IS NOT NULL),
    CONSTRAINT CK_WORK_ORDER_schedule CHECK (scheduled_end IS NULL OR scheduled_start IS NULL OR scheduled_end >= scheduled_start)
);
GO

-- REMOTE_COMMAND: each attempt and the approval are also written to AUDIT_LOG  [§2.4 p.8; §II.Δ p.3 shedding]
CREATE TABLE dbo.REMOTE_COMMAND (
    command_id             INT IDENTITY(1,1)  NOT NULL,
    command_type           VARCHAR(20)        NOT NULL,
    parameters             NVARCHAR(500)      NULL,
    status                 VARCHAR(20)        NOT NULL  CONSTRAINT DF_REMOTE_COMMAND_status DEFAULT 'PENDING_APPROVAL',
    requested_at           DATETIME2(0)       NOT NULL  CONSTRAINT DF_REMOTE_COMMAND_requested_at DEFAULT SYSUTCDATETIME(),
    attempt_count          SMALLINT           NOT NULL  CONSTRAINT DF_REMOTE_COMMAND_attempt_count DEFAULT 0,
    last_attempt_at        DATETIME2(0)       NULL,
    ack_at                 DATETIME2(0)       NULL,
    result                 NVARCHAR(300)      NULL,
    meter_id               INT                NOT NULL,
    requested_by_user_id   INT                NOT NULL,
    executed_by_user_id    INT                NULL,

    CONSTRAINT PK_REMOTE_COMMAND PRIMARY KEY (command_id),
    CONSTRAINT CK_REMOTE_COMMAND_type CHECK (command_type IN ('DISCONNECT', 'RECONNECT', 'FIRMWARE_UPGRADE')),
    CONSTRAINT CK_REMOTE_COMMAND_status CHECK (status IN ('PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'SENT', 'ACKNOWLEDGED', 'FAILED')),
    CONSTRAINT CK_REMOTE_COMMAND_ack CHECK ((status = 'ACKNOWLEDGED' AND ack_at IS NOT NULL) OR (status <> 'ACKNOWLEDGED' AND ack_at IS NULL)),
    CONSTRAINT CK_REMOTE_COMMAND_attempts CHECK (attempt_count >= 0)
);
GO

/* ============================================================================
   6. BILLING AND PAYMENTS   [§1.2 p.6; §1.3 p.6]
   ============================================================================ */

CREATE TABLE dbo.TARIFF (
    tariff_id    INT IDENTITY(1,1)  NOT NULL,
    tariff_name  NVARCHAR(100)      NOT NULL,
    rate         DECIMAL(10,4)      NOT NULL,                    -- per kWh
    valid_from   DATE               NOT NULL,
    valid_to     DATE               NULL,

    CONSTRAINT PK_TARIFF PRIMARY KEY (tariff_id),
    CONSTRAINT UQ_TARIFF_name_from UNIQUE (tariff_name, valid_from),
    CONSTRAINT CK_TARIFF_rate CHECK (rate >= 0),
    CONSTRAINT CK_TARIFF_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);
GO

-- BILL keeps consumer and supplier as they were when issued (the premise may change supplier later)
CREATE TABLE dbo.BILL (
    bill_id          INT IDENTITY(1,1)  NOT NULL,
    issue_date       DATE               NOT NULL,
    due_date         DATE               NOT NULL,
    period_start     DATE               NOT NULL,
    period_end       DATE               NOT NULL,
    amount           DECIMAL(12,2)      NOT NULL,
    status           VARCHAR(20)        NOT NULL  CONSTRAINT DF_BILL_status DEFAULT 'ISSUED',
    premise_id       INT                NOT NULL,
    user_id          INT                NOT NULL,
    supplier_org_id  INT                NOT NULL,
    tariff_id        INT                NOT NULL,

    CONSTRAINT PK_BILL PRIMARY KEY (bill_id),
    CONSTRAINT CK_BILL_amount CHECK (amount >= 0),
    CONSTRAINT CK_BILL_status CHECK (status IN ('ISSUED', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'CANCELLED')),
    CONSTRAINT CK_BILL_dates CHECK (due_date >= issue_date AND period_end >= period_start)
);
GO

-- PAYMENT: pays a bill (instalments allowed) OR a service fee; paid historical access is a service payment
-- [§1.3 p.6; §1.2 p.6 "πρόσθετη χρέωση" for previous months]
CREATE TABLE dbo.PAYMENT (
    payment_id             INT IDENTITY(1,1)  NOT NULL,
    payment_date           DATETIME2(0)       NOT NULL  CONSTRAINT DF_PAYMENT_payment_date DEFAULT SYSUTCDATETIME(),
    amount                 DECIMAL(12,2)      NOT NULL,
    method                 VARCHAR(20)        NOT NULL,
    status                 VARCHAR(20)        NOT NULL  CONSTRAINT DF_PAYMENT_status DEFAULT 'COMPLETED',
    transaction_reference  VARCHAR(60)        NULL,
    access_from            DATE               NULL,              -- historical access bought
    access_to              DATE               NULL,
    user_id                INT                NOT NULL,
    bill_id                INT                NULL,
    service_type_id        INT                NULL,
    access_meter_id        INT                NULL,

    CONSTRAINT PK_PAYMENT PRIMARY KEY (payment_id),
    CONSTRAINT CK_PAYMENT_amount CHECK (amount > 0),
    CONSTRAINT CK_PAYMENT_method CHECK (method IN ('BANK_TRANSFER', 'CARD', 'CASH', 'DIRECT_DEBIT')),
    CONSTRAINT CK_PAYMENT_status CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED', 'REFUNDED')),
    CONSTRAINT CK_PAYMENT_purpose CHECK ((CASE WHEN bill_id IS NULL THEN 0 ELSE 1 END + CASE WHEN service_type_id IS NULL THEN 0 ELSE 1 END) = 1),
    CONSTRAINT CK_PAYMENT_access CHECK (
           (access_meter_id IS NULL AND access_from IS NULL AND access_to IS NULL)
        OR (access_meter_id IS NOT NULL AND service_type_id IS NOT NULL AND access_from IS NOT NULL
            AND access_to IS NOT NULL AND access_to >= access_from))
);
GO

/* ============================================================================
   7. GDPR AND AUDIT   [§1.4 p.6-7; Κοινές αρχές p.5]
   ============================================================================ */

-- GDPR_REQUEST: stage-by-stage reviews (submission, review, pre-approval, final approval) are AUDIT_LOG rows
CREATE TABLE dbo.GDPR_REQUEST (
    gdpr_request_id  INT IDENTITY(1,1)  NOT NULL,
    request_type     VARCHAR(30)        NOT NULL,
    status           VARCHAR(20)        NOT NULL  CONSTRAINT DF_GDPR_REQUEST_status DEFAULT 'SUBMITTED',
    submitted_at     DATETIME2(0)       NOT NULL  CONSTRAINT DF_GDPR_REQUEST_submitted_at DEFAULT SYSUTCDATETIME(),
    decided_at       DATETIME2(0)       NULL,
    user_id          INT                NOT NULL,
    meter_id         INT                NULL,                    -- retention reduction is per meter [§1.4 p.7]

    CONSTRAINT PK_GDPR_REQUEST PRIMARY KEY (gdpr_request_id),
    CONSTRAINT CK_GDPR_REQUEST_type CHECK (request_type IN ('RIGHT_TO_BE_FORGOTTEN', 'RETENTION_REDUCTION')),
    CONSTRAINT CK_GDPR_REQUEST_status CHECK (status IN ('SUBMITTED', 'UNDER_REVIEW', 'PRE_APPROVED', 'APPROVED', 'REJECTED', 'EXECUTED')),
    CONSTRAINT CK_GDPR_REQUEST_meter CHECK (request_type <> 'RETENTION_REDUCTION' OR meter_id IS NOT NULL)
);
GO

-- AUDIT_LOG: the one trail for approvals, status changes, GDPR stages, command attempts, VEE edits
-- [Κοινές αρχές p.5: object, user or mechanism, timestamp, previous/new state, result or comment]
CREATE TABLE dbo.AUDIT_LOG (
    log_id        BIGINT IDENTITY(1,1)  NOT NULL,
    logged_at     DATETIME2(0)          NOT NULL  CONSTRAINT DF_AUDIT_LOG_logged_at DEFAULT SYSUTCDATETIME(),
    actor_type    VARCHAR(10)           NOT NULL,
    mechanism     VARCHAR(60)           NULL,                    -- e.g. 'VEE_JOB', 'INGESTION', meter network id
    action        VARCHAR(50)           NOT NULL,                -- e.g. APPROVE, REJECT, STATUS_CHANGE, COMMAND_ATTEMPT
    object_type   VARCHAR(30)           NOT NULL,                -- e.g. USER_ACCOUNT, METER, DOCUMENT, WORK_ORDER
    object_id     VARCHAR(30)           NOT NULL,
    old_state     NVARCHAR(200)         NULL,                    -- status, or the old value of a technical field
    new_state     NVARCHAR(200)         NULL,
    comment       NVARCHAR(500)         NULL,
    user_id       INT                   NULL,

    CONSTRAINT PK_AUDIT_LOG PRIMARY KEY (log_id),
    CONSTRAINT CK_AUDIT_LOG_actor_type CHECK (actor_type IN ('USER', 'SYSTEM', 'DEVICE')),
    CONSTRAINT CK_AUDIT_LOG_actor CHECK ((actor_type = 'USER' AND user_id IS NOT NULL) OR (actor_type <> 'USER' AND mechanism IS NOT NULL))
);
GO

/* ============================================================================
   8. FOREIGN KEYS (one per relationship of the ER diagram)
   ============================================================================ */
ALTER TABLE dbo.USER_ACCOUNT ADD
    CONSTRAINT FK_USER_ACCOUNT_role         FOREIGN KEY (role_code)       REFERENCES dbo.ROLE(role_code),
    CONSTRAINT FK_USER_ACCOUNT_organization FOREIGN KEY (organization_id) REFERENCES dbo.ORGANIZATION(organization_id);
ALTER TABLE dbo.TECHNICIAN_AVAILABILITY ADD
    CONSTRAINT FK_TECHNICIAN_AVAILABILITY_user FOREIGN KEY (user_id) REFERENCES dbo.USER_ACCOUNT(user_id) ON DELETE CASCADE;
ALTER TABLE dbo.TRANSFORMER ADD
    CONSTRAINT FK_TRANSFORMER_parent FOREIGN KEY (parent_transformer_id) REFERENCES dbo.TRANSFORMER(transformer_id);
ALTER TABLE dbo.PREMISE ADD
    CONSTRAINT FK_PREMISE_user       FOREIGN KEY (user_id)           REFERENCES dbo.USER_ACCOUNT(user_id),
    CONSTRAINT FK_PREMISE_supplier   FOREIGN KEY (supplier_org_id)   REFERENCES dbo.ORGANIZATION(organization_id),
    CONSTRAINT FK_PREMISE_aggregator FOREIGN KEY (aggregator_org_id) REFERENCES dbo.ORGANIZATION(organization_id);
ALTER TABLE dbo.METER ADD
    CONSTRAINT FK_METER_meter_type   FOREIGN KEY (meter_type_id)        REFERENCES dbo.METER_TYPE(meter_type_id),
    CONSTRAINT FK_METER_transformer  FOREIGN KEY (transformer_id)       REFERENCES dbo.TRANSFORMER(transformer_id),
    CONSTRAINT FK_METER_premise      FOREIGN KEY (premise_id)           REFERENCES dbo.PREMISE(premise_id),
    CONSTRAINT FK_METER_installed_by FOREIGN KEY (installed_by_user_id) REFERENCES dbo.USER_ACCOUNT(user_id);
ALTER TABLE dbo.DOCUMENT ADD
    CONSTRAINT FK_DOCUMENT_user  FOREIGN KEY (user_id)  REFERENCES dbo.USER_ACCOUNT(user_id),
    CONSTRAINT FK_DOCUMENT_meter FOREIGN KEY (meter_id) REFERENCES dbo.METER(meter_id);
ALTER TABLE dbo.TELEMETRY_PACKET ADD
    CONSTRAINT FK_TELEMETRY_PACKET_meter FOREIGN KEY (meter_id) REFERENCES dbo.METER(meter_id);
ALTER TABLE dbo.METER_READING ADD
    CONSTRAINT FK_METER_READING_meter     FOREIGN KEY (meter_id)          REFERENCES dbo.METER(meter_id),
    CONSTRAINT FK_METER_READING_obis      FOREIGN KEY (obis_code)         REFERENCES dbo.OBIS_CODE(obis_code),
    CONSTRAINT FK_METER_READING_packet    FOREIGN KEY (packet_id)         REFERENCES dbo.TELEMETRY_PACKET(packet_id),
    CONSTRAINT FK_METER_READING_edited_by FOREIGN KEY (edited_by_user_id) REFERENCES dbo.USER_ACCOUNT(user_id);
ALTER TABLE dbo.TRANSFORMER_READING ADD
    CONSTRAINT FK_TRANSFORMER_READING_transformer FOREIGN KEY (transformer_id) REFERENCES dbo.TRANSFORMER(transformer_id),
    CONSTRAINT FK_TRANSFORMER_READING_obis        FOREIGN KEY (obis_code)      REFERENCES dbo.OBIS_CODE(obis_code);
ALTER TABLE dbo.AGGREGATE ADD
    CONSTRAINT FK_AGGREGATE_meter       FOREIGN KEY (meter_id)       REFERENCES dbo.METER(meter_id),
    CONSTRAINT FK_AGGREGATE_transformer FOREIGN KEY (transformer_id) REFERENCES dbo.TRANSFORMER(transformer_id),
    CONSTRAINT FK_AGGREGATE_obis        FOREIGN KEY (obis_code)      REFERENCES dbo.OBIS_CODE(obis_code);
ALTER TABLE dbo.TRANSFORMER_CURRENT_STATE ADD
    CONSTRAINT FK_TRANSFORMER_CURRENT_STATE_transformer FOREIGN KEY (transformer_id) REFERENCES dbo.TRANSFORMER(transformer_id),
    CONSTRAINT FK_TRANSFORMER_CURRENT_STATE_obis        FOREIGN KEY (obis_code)      REFERENCES dbo.OBIS_CODE(obis_code);
ALTER TABLE dbo.EVENT ADD
    CONSTRAINT FK_EVENT_meter       FOREIGN KEY (meter_id)       REFERENCES dbo.METER(meter_id),
    CONSTRAINT FK_EVENT_transformer FOREIGN KEY (transformer_id) REFERENCES dbo.TRANSFORMER(transformer_id),
    CONSTRAINT FK_EVENT_packet      FOREIGN KEY (packet_id)      REFERENCES dbo.TELEMETRY_PACKET(packet_id);
ALTER TABLE dbo.WORK_ORDER ADD
    CONSTRAINT FK_WORK_ORDER_requested_by FOREIGN KEY (requested_by_user_id) REFERENCES dbo.USER_ACCOUNT(user_id),
    CONSTRAINT FK_WORK_ORDER_technician   FOREIGN KEY (technician_user_id)   REFERENCES dbo.USER_ACCOUNT(user_id),
    CONSTRAINT FK_WORK_ORDER_premise      FOREIGN KEY (premise_id)           REFERENCES dbo.PREMISE(premise_id),
    CONSTRAINT FK_WORK_ORDER_meter        FOREIGN KEY (meter_id)             REFERENCES dbo.METER(meter_id),
    CONSTRAINT FK_WORK_ORDER_event        FOREIGN KEY (event_id)             REFERENCES dbo.EVENT(event_id),
    CONSTRAINT FK_WORK_ORDER_service_type FOREIGN KEY (service_type_id)      REFERENCES dbo.SERVICE_TYPE(service_type_id);
ALTER TABLE dbo.REMOTE_COMMAND ADD
    CONSTRAINT FK_REMOTE_COMMAND_meter        FOREIGN KEY (meter_id)             REFERENCES dbo.METER(meter_id),
    CONSTRAINT FK_REMOTE_COMMAND_requested_by FOREIGN KEY (requested_by_user_id) REFERENCES dbo.USER_ACCOUNT(user_id),
    CONSTRAINT FK_REMOTE_COMMAND_executed_by  FOREIGN KEY (executed_by_user_id)  REFERENCES dbo.USER_ACCOUNT(user_id);
ALTER TABLE dbo.BILL ADD
    CONSTRAINT FK_BILL_premise  FOREIGN KEY (premise_id)      REFERENCES dbo.PREMISE(premise_id),
    CONSTRAINT FK_BILL_user     FOREIGN KEY (user_id)         REFERENCES dbo.USER_ACCOUNT(user_id),
    CONSTRAINT FK_BILL_supplier FOREIGN KEY (supplier_org_id) REFERENCES dbo.ORGANIZATION(organization_id),
    CONSTRAINT FK_BILL_tariff   FOREIGN KEY (tariff_id)       REFERENCES dbo.TARIFF(tariff_id);
ALTER TABLE dbo.PAYMENT ADD
    CONSTRAINT FK_PAYMENT_user         FOREIGN KEY (user_id)         REFERENCES dbo.USER_ACCOUNT(user_id),
    CONSTRAINT FK_PAYMENT_bill         FOREIGN KEY (bill_id)         REFERENCES dbo.BILL(bill_id),
    CONSTRAINT FK_PAYMENT_service_type FOREIGN KEY (service_type_id) REFERENCES dbo.SERVICE_TYPE(service_type_id),
    CONSTRAINT FK_PAYMENT_access_meter FOREIGN KEY (access_meter_id) REFERENCES dbo.METER(meter_id);
ALTER TABLE dbo.GDPR_REQUEST ADD
    CONSTRAINT FK_GDPR_REQUEST_user  FOREIGN KEY (user_id)  REFERENCES dbo.USER_ACCOUNT(user_id),
    CONSTRAINT FK_GDPR_REQUEST_meter FOREIGN KEY (meter_id) REFERENCES dbo.METER(meter_id);
ALTER TABLE dbo.AUDIT_LOG ADD
    CONSTRAINT FK_AUDIT_LOG_user FOREIGN KEY (user_id) REFERENCES dbo.USER_ACCOUNT(user_id);
GO

/* ============================================================================
   9. FILTERED UNIQUE INDEXES
   ============================================================================ */
-- one meter in service per premise; removed meters stay for history [§2.3 p.8]
CREATE UNIQUE INDEX UQ_METER_one_active_per_premise ON dbo.METER (premise_id) WHERE removed_at IS NULL;
-- one aggregate per owner / OBIS / period
CREATE UNIQUE INDEX UQ_AGGREGATE_meter       ON dbo.AGGREGATE (meter_id, obis_code, period_type, period_start)       WHERE meter_id IS NOT NULL;
CREATE UNIQUE INDEX UQ_AGGREGATE_transformer ON dbo.AGGREGATE (transformer_id, obis_code, period_type, period_start) WHERE transformer_id IS NOT NULL;
-- payment reference unique when present
CREATE UNIQUE INDEX UQ_PAYMENT_transaction_reference ON dbo.PAYMENT (transaction_reference) WHERE transaction_reference IS NOT NULL;
GO

/* ============================================================================
   10-11. VIEWS and TRIGGERS live in views.sql and triggers.sql (see MDMS_Cy_SQL_Build_Spec.md)
   ============================================================================ */

/* ============================================================================
   12. REFERENCE DATA
   ============================================================================ */
INSERT INTO dbo.ROLE (role_code, description) VALUES
 ('SYSTEM_ADMIN',   N'Διαχειριστής Συστήματος (ΔΣ)'),
 ('SYSTEM_OFFICER', N'Λειτουργός Συστήματος (ΛΣ)'),
 ('CONSUMER',       N'Καταναλωτής / Απλός Χρήστης (ΚΧ)'),
 ('TECHNICIAN',     N'Τεχνικός Πεδίου (ΤΠ)'),
 ('DSO',            N'Διαχειριστής Διανομής'),
 ('TSO',            N'Διαχειριστής Δικτύου'),
 ('SUPPLIER',       N'Χρήστης προμηθευτή'),
 ('AGGREGATOR',     N'Χρήστης aggregator');

INSERT INTO dbo.OBIS_CODE (obis_code, description, unit, measurement_kind, valid_min, valid_max) VALUES
 ('1.8.0',  N'Total Active Import',          'kWh',   'CUMULATIVE',    0, NULL),
 ('1.8.1',  N'Active Import - Peak/Day',     'kWh',   'CUMULATIVE',    0, NULL),
 ('1.8.2',  N'Active Import - Off-Peak',     'kWh',   'CUMULATIVE',    0, NULL),
 ('2.8.0',  N'Total Active Export (PV)',     'kWh',   'CUMULATIVE',    0, NULL),
 ('3.8.0',  N'Total Reactive Import',        'kVARh', 'CUMULATIVE',    0, NULL),
 ('4.8.0',  N'Total Reactive Export',        'kVARh', 'CUMULATIVE',    0, NULL),
 ('32.7.0', N'Voltage L1',                   'V',     'INSTANTANEOUS', 0, 400),
 ('52.7.0', N'Voltage L2',                   'V',     'INSTANTANEOUS', 0, 400),
 ('72.7.0', N'Voltage L3',                   'V',     'INSTANTANEOUS', 0, 400),
 ('31.7.0', N'Current L1',                   'A',     'INSTANTANEOUS', 0, NULL),
 ('51.7.0', N'Current L2',                   'A',     'INSTANTANEOUS', 0, NULL),
 ('71.7.0', N'Current L3',                   'A',     'INSTANTANEOUS', 0, NULL),
 ('14.7.0', N'Grid frequency (TSO, transformer level)', 'Hz', 'INSTANTANEOUS', 45, 55);   -- [§II.Δ p.3: 50 Hz nominal]
GO

-- services the stored procedures look up by name [Κοινές αρχές p.5; §1.2 p.6; §1.3 p.6]
INSERT INTO dbo.SERVICE_TYPE (service_name, fee) VALUES
 (N'HISTORICAL_ACCESS', 2.00),     -- fee per month of past data bought
 (N'METER_CHECK',       25.00);    -- consumer-requested technical check
GO

PRINT 'MDMS-Cy schema v6 (final) created.';
GO
