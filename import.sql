/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   import.sql  -  Build Spec §12: the small data set
   Every row is inserted THROUGH THE STORED PROCEDURES (this also tests them) [project.pdf §IV p.12].
   The script only reads tables directly to pick up the keys the procedures created.
   Re-runnable: when users already exist it does nothing (run create.sql first for a fresh load).
   The two days of telemetry are the last two days of the previous month, so that the month
   closes and a bill can be issued in the demo.
   All demo accounts use the password  Passw0rd!23
   ============================================================================ */
SET NOCOUNT ON;
GO
IF EXISTS (SELECT 1 FROM [dbo].[USER_ACCOUNT])
BEGIN
    PRINT 'import.sql: users already exist - nothing imported. Run create.sql first for a fresh load.';
    SET NOEXEC ON;
END
GO

DECLARE @pw NVARCHAR(128) = N'Passw0rd!23';
DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @d2 DATE = EOMONTH(@today, -1);                 -- last day of the previous month
DECLARE @d1 DATE = DATEADD(DAY, -1, @d2);
DECLARE @t0 DATETIME2(0) = CAST(@d1 AS DATETIME2(0));   -- first slot of the telemetry
DECLARE @t_end DATETIME2(0) = DATEADD(MINUTE, -15, DATEADD(DAY, 2, @t0));   -- last slot
DECLARE @month_start DATE = DATEFROMPARTS(YEAR(@d2), MONTH(@d2), 1);
DECLARE @bill_year INT = YEAR(@d2), @bill_month INT = MONTH(@d2);

/* ---------------------------------------------------------------------------
   1. Administrator and staff   [Κοινές αρχές p.5]
   --------------------------------------------------------------------------- */
DECLARE @admin INT, @off1 INT, @off2 INT, @dso INT, @tso INT;
EXEC [dbo].[sp_BootstrapAdmin] 'admin@mdms.cy', @pw, N'Διαχειριστής Συστήματος';
SELECT @admin = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'admin@mdms.cy';

EXEC [dbo].[sp_CreateStaffUser] @admin, 'officer1@mdms.cy', @pw, N'Ελένη Γεωργίου',   '99100001', 'SYSTEM_OFFICER';
EXEC [dbo].[sp_CreateStaffUser] @admin, 'officer2@mdms.cy', @pw, N'Μάριος Χριστοδούλου', '99100002', 'SYSTEM_OFFICER';
EXEC [dbo].[sp_CreateStaffUser] @admin, 'dso@mdms.cy',      @pw, N'Άννα Παπαδοπούλου', '99100003', 'DSO';
EXEC [dbo].[sp_CreateStaffUser] @admin, 'tso@mdms.cy',      @pw, N'Πέτρος Νικολάου',   '99100004', 'TSO';
SELECT @off1 = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'officer1@mdms.cy';
SELECT @off2 = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'officer2@mdms.cy';
SELECT @dso  = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'dso@mdms.cy';
SELECT @tso  = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'tso@mdms.cy';

/* ---------------------------------------------------------------------------
   2. Suppliers and aggregator, one user each   [§II.Ε p.3-4; §5.1 p.10]
   --------------------------------------------------------------------------- */
DECLARE @sup1 INT, @sup2 INT, @agg INT, @sup1_user INT, @sup2_user INT, @agg_user INT;
EXEC [dbo].[sp_CreateOrganization] @admin, N'EAC Supply',        'SUPPLIER';
EXEC [dbo].[sp_CreateOrganization] @off1,  N'GreenEnergy Supply', 'SUPPLIER';
EXEC [dbo].[sp_CreateOrganization] @off1,  N'FlexPool Aggregator', 'AGGREGATOR';
SELECT @sup1 = organization_id FROM [dbo].[ORGANIZATION] WHERE name = N'EAC Supply';
SELECT @sup2 = organization_id FROM [dbo].[ORGANIZATION] WHERE name = N'GreenEnergy Supply';
SELECT @agg  = organization_id FROM [dbo].[ORGANIZATION] WHERE name = N'FlexPool Aggregator';

EXEC [dbo].[sp_CreateOrganizationUser] @off1, @sup1, 'billing@eacsupply.cy',  @pw, N'Κώστας Ιωάννου',  '99200001';
EXEC [dbo].[sp_CreateOrganizationUser] @off1, @sup2, 'billing@greenenergy.cy', @pw, N'Μαρία Λοΐζου',    '99200002';
EXEC [dbo].[sp_CreateOrganizationUser] @off1, @agg,  'desk@flexpool.cy',       @pw, N'Γιώργος Σάββα',   '99200003';
SELECT @sup1_user = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'billing@eacsupply.cy';
SELECT @sup2_user = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'billing@greenenergy.cy';
SELECT @agg_user  = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'desk@flexpool.cy';

/* ---------------------------------------------------------------------------
   3. Meter types and tariffs   [Κοινές αρχές p.5]
   --------------------------------------------------------------------------- */
DECLARE @type1 INT, @type3 INT;
EXEC [dbo].[sp_UpsertMeterType] @off1, NULL, 'Single-Phase 1x60A', 1, 60;
EXEC [dbo].[sp_UpsertMeterType] @off1, NULL, 'Three-Phase 3x80A',  3, 80;
SELECT @type1 = meter_type_id FROM [dbo].[METER_TYPE] WHERE type_name = 'Single-Phase 1x60A';
SELECT @type3 = meter_type_id FROM [dbo].[METER_TYPE] WHERE type_name = 'Three-Phase 3x80A';

EXEC [dbo].[sp_UpsertTariff] @off1, NULL, N'Standard', 0.2800, '2025-01-01', '2025-12-31';   -- the older period
EXEC [dbo].[sp_UpsertTariff] @off1, NULL, N'Standard', 0.3200, '2026-01-01', NULL;

/* ---------------------------------------------------------------------------
   4. Transformer tree: 1 (L4) -> 2 (L3) -> 4 (L2) -> 8 (L1), with rectangles   [§4.1 p.9]
   --------------------------------------------------------------------------- */
DECLARE @tr TABLE (name NVARCHAR(100), lvl TINYINT, kva DECIMAL(10,2), parent NVARCHAR(100),
                   min_lat DECIMAL(9,6), min_lon DECIMAL(9,6), max_lat DECIMAL(9,6), max_lon DECIMAL(9,6));
INSERT INTO @tr VALUES
 (N'TX-L4 Cyprus',            4, 20000, NULL,                      34.500, 32.900, 35.300, 34.000),
 (N'TX-L3 Nicosia',           3,  8000, N'TX-L4 Cyprus',           35.050, 33.200, 35.250, 33.500),
 (N'TX-L3 South',             3,  8000, N'TX-L4 Cyprus',           34.600, 32.950, 35.000, 33.700),
 (N'TX-L2 Nicosia West',      2,  2000, N'TX-L3 Nicosia',          35.050, 33.200, 35.250, 33.350),
 (N'TX-L2 Nicosia East',      2,  2000, N'TX-L3 Nicosia',          35.050, 33.350, 35.250, 33.500),
 (N'TX-L2 Limassol',          2,  2000, N'TX-L3 South',            34.600, 32.950, 34.800, 33.150),
 (N'TX-L2 Larnaca',           2,  2000, N'TX-L3 South',            34.850, 33.550, 35.000, 33.700),
 (N'TX-L1 Strovolos',         1,   400, N'TX-L2 Nicosia West',     35.050, 33.200, 35.150, 33.350),
 (N'TX-L1 Engomi',            1,   400, N'TX-L2 Nicosia West',     35.150, 33.200, 35.250, 33.350),
 (N'TX-L1 Aglantzia',         1,   400, N'TX-L2 Nicosia East',     35.050, 33.350, 35.150, 33.500),
 (N'TX-L1 Kaimakli',          1,   400, N'TX-L2 Nicosia East',     35.150, 33.350, 35.250, 33.500),
 (N'TX-L1 Limassol Centre',   1,   400, N'TX-L2 Limassol',         34.600, 32.950, 34.700, 33.150),
 (N'TX-L1 Agios Athanasios',  1,   400, N'TX-L2 Limassol',         34.700, 32.950, 34.800, 33.150),
 (N'TX-L1 Larnaca Centre',    1,   400, N'TX-L2 Larnaca',          34.850, 33.550, 34.925, 33.700),
 (N'TX-L1 Aradippou',         1,   400, N'TX-L2 Larnaca',          34.925, 33.550, 35.000, 33.700);

DECLARE @name NVARCHAR(100), @lvl TINYINT, @kva DECIMAL(10,2), @parent NVARCHAR(100), @parent_id INT,
        @min_lat DECIMAL(9,6), @min_lon DECIMAL(9,6), @max_lat DECIMAL(9,6), @max_lon DECIMAL(9,6),
        @lat DECIMAL(9,6), @lon DECIMAL(9,6);
DECLARE c_tr CURSOR LOCAL FAST_FORWARD FOR
    SELECT name, lvl, kva, parent, min_lat, min_lon, max_lat, max_lon FROM @tr ORDER BY lvl DESC, name;
OPEN c_tr;
FETCH NEXT FROM c_tr INTO @name, @lvl, @kva, @parent, @min_lat, @min_lon, @max_lat, @max_lon;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @parent_id = NULL;
    SELECT @parent_id = transformer_id FROM [dbo].[TRANSFORMER] WHERE name = @parent;
    SELECT @lat = (@min_lat + @max_lat) / 2, @lon = (@min_lon + @max_lon) / 2;
    EXEC [dbo].[sp_UpsertTransformer] @actor_user_id = @tso, @transformer_id = NULL, @name = @name, @level = @lvl,
         @capacity_kva = @kva, @latitude = @lat, @longitude = @lon,
         @min_lat = @min_lat, @min_lon = @min_lon, @max_lat = @max_lat, @max_lon = @max_lon,
         @parent_transformer_id = @parent_id;
    FETCH NEXT FROM c_tr INTO @name, @lvl, @kva, @parent, @min_lat, @min_lon, @max_lat, @max_lon;
END
CLOSE c_tr; DEALLOCATE c_tr;

/* ---------------------------------------------------------------------------
   5. Three technicians: registration, 3 documents, availability for 7 days, approval   [§2.1 p.7; UC-09]
   --------------------------------------------------------------------------- */
DECLARE @techs TABLE (n INT, email VARCHAR(255), full_name NVARCHAR(150), phone VARCHAR(20), birth DATE,
                      specialty NVARCHAR(100), district NVARCHAR(30));
INSERT INTO @techs VALUES
 (1, 'tech1@mdms.cy', N'Ανδρέας Κυριάκου',   '99300001', '1988-04-12', N'Ηλεκτρολόγος Α΄', N'Λευκωσία'),
 (2, 'tech2@mdms.cy', N'Στέλιος Δημητρίου',  '99300002', '1992-09-30', N'Ηλεκτρολόγος Α΄', N'Λεμεσός'),
 (3, 'tech3@mdms.cy', N'Χρίστος Αντωνίου',   '99300003', '1985-01-20', N'Τηλεπικοινωνίες',  N'Λάρνακα');

DECLARE @n INT, @email VARCHAR(255), @full NVARCHAR(150), @phone VARCHAR(20), @birth DATE,
        @spec NVARCHAR(100), @district NVARCHAR(30), @tech INT, @doc INT, @k INT, @day DATE,
        @code VARCHAR(60), @path VARCHAR(500);
DECLARE c_te CURSOR LOCAL FAST_FORWARD FOR SELECT n, email, full_name, phone, birth, specialty, district FROM @techs ORDER BY n;
OPEN c_te;
FETCH NEXT FROM c_te INTO @n, @email, @full, @phone, @birth, @spec, @district;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @path = '/uploads/tech/photo_' + CAST(@n AS VARCHAR(5)) + '.jpg';
    EXEC [dbo].[sp_RegisterTechnician] @email, @pw, @full, @phone, @birth, @path, @spec;
    SELECT @tech = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = @email;

    SET @code = 'ID-' + CAST(100000 + @n AS VARCHAR(10));  SET @path = '/uploads/tech/id_' + CAST(@n AS VARCHAR(5)) + '.pdf';
    EXEC [dbo].[sp_AddTechnicianDocument] @tech, 'ID_CARD', @code, '2020-01-15', '2030-01-15', @path;
    SET @code = 'LIC-' + CAST(200000 + @n AS VARCHAR(10)); SET @path = '/uploads/tech/licence_' + CAST(@n AS VARCHAR(5)) + '.pdf';
    EXEC [dbo].[sp_AddTechnicianDocument] @tech, 'INSTALLER_LICENSE', @code, '2022-03-01', '2029-03-01', @path;
    SET @code = 'TRN-' + CAST(300000 + @n AS VARCHAR(10)); SET @path = '/uploads/tech/training_' + CAST(@n AS VARCHAR(5)) + '.pdf';
    EXEC [dbo].[sp_AddTechnicianDocument] @tech, 'TRAINING_CERT', @code, '2024-06-10', NULL, @path;

    SET @k = 0;
    WHILE @k < 7
    BEGIN
        SET @day = DATEADD(DAY, @k, @today);
        EXEC [dbo].[sp_SetAvailability] @tech, @day, '08:00', '16:00', @district;
        SET @k = @k + 1;
    END

    -- the officer checks the three documents, then approves the technician
    WHILE EXISTS (SELECT 1 FROM [dbo].[DOCUMENT] WHERE user_id = @tech AND approval_status = 'PENDING')
    BEGIN
        SELECT TOP (1) @doc = document_id FROM [dbo].[DOCUMENT] WHERE user_id = @tech AND approval_status = 'PENDING' ORDER BY document_id;
        EXEC [dbo].[sp_DecideDocument] @off1, @doc, 'APPROVED', N'Έλεγχος εγγράφου: εντάξει';
    END
    EXEC [dbo].[sp_DecideTechnician] @off1, @tech, 'APPROVED', N'Πλήρης φάκελος';
    FETCH NEXT FROM c_te INTO @n, @email, @full, @phone, @birth, @spec, @district;
END
CLOSE c_te; DEALLOCATE c_te;

/* ---------------------------------------------------------------------------
   6. Ten consumers, twelve premises (3 prosumers), suppliers and aggregator   [§1.1 p.5; UC-01]
   --------------------------------------------------------------------------- */
DECLARE @cons TABLE (n INT, full_name NVARCHAR(150), iban VARCHAR(34), sms BIT);
INSERT INTO @cons VALUES
 (1, N'Νίκος Παναγιώτου',     'CY17002001280000001200527600', 0),
 (2, N'Σοφία Χαραλάμπους',    'CY17002001280000001200527601', 1),
 (3, N'Δημήτρης Μιχαήλ',      'CY17002001280000001200527602', 0),
 (4, N'Κατερίνα Στυλιανού',   'CY17002001280000001200527603', 0),
 (5, N'Παύλος Ευαγγέλου',     'CY17002001280000001200527604', 1),
 (6, N'Ιωάννα Κωνσταντίνου',  'CY17002001280000001200527605', 0),
 (7, N'Αντώνης Θεοδώρου',     'CY17002001280000001200527606', 0),
 (8, N'Ελπίδα Ηλία',          'CY17002001280000001200527607', 1),
 (9, N'Μιχάλης Πέτρου',       'CY17002001280000001200527608', 0),
 (10, N'Χρυστάλλα Λουκά',     'CY17002001280000001200527609', 0);

DECLARE @iban VARCHAR(34), @sms BIT;
DECLARE c_co CURSOR LOCAL FAST_FORWARD FOR SELECT n, full_name, iban, sms FROM @cons ORDER BY n;
OPEN c_co;
FETCH NEXT FROM c_co INTO @n, @full, @iban, @sms;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @email = 'consumer' + CAST(@n AS VARCHAR(5)) + '@example.cy';
    SET @phone = '9940' + RIGHT('0000' + CAST(@n AS VARCHAR(5)), 4);
    EXEC [dbo].[sp_RegisterConsumer] @email, @pw, @full, @phone, @iban, 1, @sms;
    FETCH NEXT FROM c_co INTO @n, @full, @iban, @sms;
END
CLOSE c_co; DEALLOCATE c_co;

-- premise n: owner, place, scheme, supplier (1 / 2), aggregator member, technician of the district, three-phase
DECLARE @prem TABLE (n INT, consumer INT, address NVARCHAR(250), lat DECIMAL(9,6), lon DECIMAL(9,6), usage VARCHAR(20),
                     district NVARCHAR(30), municipality NVARCHAR(80), parish NVARCHAR(80), postal CHAR(4),
                     scheme VARCHAR(20), supplier INT, in_agg BIT, tech INT, three_phase BIT);
INSERT INTO @prem VALUES
 (1,  1, N'Λεωφ. Στροβόλου 101',       35.100, 33.250, 'RESIDENTIAL',  N'Λευκωσία', N'Στρόβολος',        N'Άγιος Δημήτριος',  '2018', 'NONE',         1, 0, 1, 0),
 (2,  1, N'Οδός Γρίβα Διγενή 12',      35.200, 33.300, 'RESIDENTIAL',  N'Λευκωσία', N'Έγκωμη',           N'Άγιος Νικόλαος',   '2414', 'NONE',         1, 1, 1, 0),
 (3,  2, N'Λεωφ. Αγλαντζιάς 45',       35.120, 33.400, 'RESIDENTIAL',  N'Λευκωσία', N'Αγλαντζιά',        N'Άγιος Γεώργιος',   '2108', 'NET_METERING', 2, 1, 1, 0),
 (4,  2, N'Λεωφ. Καϊμακλίου 7',        35.180, 33.450, 'COMMERCIAL',   N'Λευκωσία', N'Λευκωσία',         N'Καϊμακλί',         '1026', 'NONE',         1, 0, 1, 1),
 (5,  3, N'Οδός Αθαλάσσας 30',         35.080, 33.280, 'RESIDENTIAL',  N'Λευκωσία', N'Στρόβολος',        N'Χρυσελεούσα',      '2023', 'NONE',         2, 0, 1, 0),
 (6,  4, N'Οδός Κυρηνείας 88',         35.220, 33.420, 'RESIDENTIAL',  N'Λευκωσία', N'Λευκωσία',         N'Καϊμακλί',         '1027', 'NONE',         1, 0, 1, 0),
 (7,  5, N'Οδός Ανεξαρτησίας 55',      34.650, 33.000, 'RESIDENTIAL',  N'Λεμεσός',  N'Λεμεσός',          N'Αγία Νάπα',        '3040', 'NET_METERING', 2, 1, 2, 0),
 (8,  6, N'Βιομηχανική Περιοχή 3',     34.750, 33.050, 'INDUSTRIAL',   N'Λεμεσός',  N'Άγιος Αθανάσιος',  N'Άγιος Αθανάσιος',  '4101', 'NONE',         1, 0, 2, 1),
 (9,  7, N'Λεωφ. Μακαρίου Γ΄ 200',     34.680, 33.100, 'RESIDENTIAL',  N'Λεμεσός',  N'Λεμεσός',          N'Καθολική',         '3030', 'NONE',         2, 0, 2, 0),
 (10, 8, N'Οδός Ερμού 14',             34.900, 33.600, 'RESIDENTIAL',  N'Λάρνακα',  N'Λάρνακα',          N'Σωτήρος',          '6023', 'NET_BILLING',  1, 1, 3, 0),
 (11, 9, N'Οδός Αρχ. Κυπριανού 9',     34.950, 33.650, 'RESIDENTIAL',  N'Λάρνακα',  N'Αραδίππου',        N'Άγιος Λουκάς',     '7101', 'NONE',         2, 0, 3, 0),
 (12, 10, N'Αγρόκτημα Αραδίππου 2',    34.970, 33.620, 'AGRICULTURAL', N'Λάρνακα',  N'Αραδίππου',        N'Απόστολος Λουκάς', '7103', 'NONE',         1, 0, 3, 1);

/* ---------------------------------------------------------------------------
   7. Per premise: add it, then INSTALLATION job -> assign -> accept -> start -> install the meter ->
      3 certificates -> officer approves them -> officer confirms the meter -> job completed   [UC-01, UC-10]
   --------------------------------------------------------------------------- */
DECLARE @pn INT, @consumer_n INT, @address NVARCHAR(250), @usage VARCHAR(20), @municipality NVARCHAR(80),
        @parish NVARCHAR(80), @postal CHAR(4), @scheme VARCHAR(20), @supplier_n INT, @in_agg BIT, @tech_n INT, @three BIT;
DECLARE @consumer INT, @supplier INT, @premise INT, @wo INT, @meter INT, @type INT,
        @serial VARCHAR(50), @net VARCHAR(60), @start DATETIME2(0), @finish DATETIME2(0);
DECLARE @slot_of_tech TABLE (tech INT PRIMARY KEY, used INT);
INSERT INTO @slot_of_tech VALUES (1, 0), (2, 0), (3, 0);
DECLARE @visit_day DATE = DATEADD(DAY, 1, @today);

DECLARE c_pr CURSOR LOCAL FAST_FORWARD FOR
    SELECT n, consumer, address, lat, lon, usage, district, municipality, parish, postal, scheme, supplier, in_agg, tech, three_phase
    FROM @prem ORDER BY n;
OPEN c_pr;
FETCH NEXT FROM c_pr INTO @pn, @consumer_n, @address, @lat, @lon, @usage, @district, @municipality, @parish, @postal,
                          @scheme, @supplier_n, @in_agg, @tech_n, @three;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @consumer = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer' + CAST(@consumer_n AS VARCHAR(5)) + '@example.cy';
    SELECT @tech = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'tech' + CAST(@tech_n AS VARCHAR(5)) + '@mdms.cy';
    SET @supplier = CASE WHEN @supplier_n = 1 THEN @sup1 ELSE @sup2 END;
    SET @type = CASE WHEN @three = 1 THEN @type3 ELSE @type1 END;

    EXEC [dbo].[sp_AddPremise] @consumer, @address, @lat, @lon, @usage, @district, @municipality, @parish, @postal, @scheme, @supplier;
    SELECT @premise = MAX(premise_id) FROM [dbo].[PREMISE] WHERE user_id = @consumer;
    IF @in_agg = 1
        EXEC [dbo].[sp_SetPremiseAggregator] @consumer, @premise, @agg;

    EXEC [dbo].[sp_CreateWorkOrder] @off1, 'INSTALLATION', @premise, NULL, NULL, N'Εγκατάσταση έξυπνου μετρητή', NULL, NULL;
    SELECT @wo = MAX(work_order_id) FROM [dbo].[WORK_ORDER] WHERE premise_id = @premise;

    -- one-hour visits tomorrow, inside the 08:00 - 16:00 availability of the technician
    SELECT @k = used FROM @slot_of_tech WHERE tech = @tech_n;
    UPDATE @slot_of_tech SET used = used + 1 WHERE tech = @tech_n;
    SET @start  = DATEADD(HOUR, 8 + @k, CAST(@visit_day AS DATETIME2(0)));
    SET @finish = DATEADD(HOUR, 1, @start);

    EXEC [dbo].[sp_AssignWorkOrder] @off1, @wo, @tech, @start, @finish;
    EXEC [dbo].[sp_AcceptWorkOrder] @tech, @wo;
    EXEC [dbo].[sp_StartWorkOrder]  @tech, @wo;

    SET @serial = 'SN-2026-' + RIGHT('0000' + CAST(@pn AS VARCHAR(5)), 4);
    SET @net    = 'NET-' + RIGHT('0000' + CAST(@pn AS VARCHAR(5)), 4);
    SET @path   = '/uploads/meters/install_' + CAST(@pn AS VARCHAR(5)) + '.jpg';
    -- no transformer given: the geofence is found from the coordinates (fn_FindGeofence)
    EXEC [dbo].[sp_InstallMeter] @tech, @wo, @serial, @net, 'FW-1.0.0', 'NB_IOT', @lat, @lon, @type, @path, NULL;
    SELECT @meter = meter_id FROM [dbo].[METER] WHERE serial_number = @serial;

    SET @code = 'CAL-' + CAST(@pn AS VARCHAR(5)); SET @path = '/uploads/meters/cal_' + CAST(@pn AS VARCHAR(5)) + '.pdf';
    EXEC [dbo].[sp_AddMeterDocument] @tech, @meter, 'CALIBRATION_CERT', @code, '2026-01-10', '2031-01-10', @path;
    SET @code = 'CE-' + CAST(@pn AS VARCHAR(5));  SET @path = '/uploads/meters/ce_' + CAST(@pn AS VARCHAR(5)) + '.pdf';
    EXEC [dbo].[sp_AddMeterDocument] @tech, @meter, 'CE_DECLARATION', @code, '2026-01-10', NULL, @path;
    SET @code = 'ENC-' + CAST(@pn AS VARCHAR(5)); SET @path = '/uploads/meters/enc_' + CAST(@pn AS VARCHAR(5)) + '.pdf';
    EXEC [dbo].[sp_AddMeterDocument] @tech, @meter, 'ENCRYPTION_CERT', @code, '2026-01-10', '2028-01-10', @path;

    WHILE EXISTS (SELECT 1 FROM [dbo].[DOCUMENT] WHERE meter_id = @meter AND approval_status = 'PENDING')
    BEGIN
        SELECT TOP (1) @doc = document_id FROM [dbo].[DOCUMENT] WHERE meter_id = @meter AND approval_status = 'PENDING' ORDER BY document_id;
        EXEC [dbo].[sp_DecideDocument] @off2, @doc, 'APPROVED', NULL;
    END
    EXEC [dbo].[sp_ConfirmMeter] @off2, @meter, 'APPROVE', N'Τα πιστοποιητικά ελέγχθηκαν';
    EXEC [dbo].[sp_CompleteWorkOrder] @tech, @wo, N'Ο μετρητής εγκαταστάθηκε και επικοινωνεί.', '/uploads/evidence/install.jpg', NULL;

    FETCH NEXT FROM c_pr INTO @pn, @consumer_n, @address, @lat, @lon, @usage, @district, @municipality, @parish, @postal,
                              @scheme, @supplier_n, @in_agg, @tech_n, @three;
END
CLOSE c_pr; DEALLOCATE c_pr;

/* ---------------------------------------------------------------------------
   8. Two days of packets in the JSON format of the Appendix, through sp_IngestTelemetryBatch   [§3.1 p.8; UC-15]
      192 packets per meter (96 slots x 2 days). Planted cases:
        meter 1, slot 100 : register reads 25.4 kWh too high for one slot (spike, then back to normal)
        meter 2, slot 50  : packet missing (gap -> estimated)
        meter 3, slot 10  : voltage 198.5 V (the example of the spec -> VOLTAGE_SAG)
        meter 4, slot 5   : an OBIS code the system does not know
        meter 8, slot 20  : one phase current far below the others (phase unbalance)
        plus one packet with an unknown network id and one malformed packet
   --------------------------------------------------------------------------- */
DECLARE @packets TABLE (mn INT, n INT, json NVARCHAR(4000));

WITH d AS (SELECT v FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS x(v)),
slots AS (SELECT TOP (192) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n FROM d AS a CROSS JOIN d AS b CROSS JOIN d AS c),
base AS (
    SELECT p.n AS mn, s.n, p.three_phase, p.scheme,
           DATEADD(MINUTE, 15 * s.n, @t0) AS ts,
           -- 15-min import: a small load with an evening peak
           0.20 + 0.02 * (s.n % 10) + CASE WHEN (s.n % 96) BETWEEN 72 AND 88 THEN 0.15 ELSE 0 END AS imp,
           -- 15-min export of the prosumers around noon
           CASE WHEN p.scheme <> 'NONE' AND (s.n % 96) BETWEEN 40 AND 60 THEN 0.12 ELSE 0 END AS ex
    FROM @prem AS p CROSS JOIN slots AS s),
reg AS (
    SELECT b.*,
           1000.0 * b.mn + SUM(b.imp) OVER (PARTITION BY b.mn ORDER BY b.n ROWS UNBOUNDED PRECEDING)
             + CASE WHEN b.mn = 1 AND b.n = 100 THEN 25.4 ELSE 0 END AS r180,
           500.0 + SUM(b.ex) OVER (PARTITION BY b.mn ORDER BY b.n ROWS UNBOUNDED PRECEDING) AS r280
    FROM base AS b)
INSERT INTO @packets (mn, n, json)
SELECT r.mn, r.n,
       CONCAT(N'{"Meter_Network_ID":"NET-', RIGHT('0000' + CAST(r.mn AS VARCHAR(5)), 4),
              N'","Transmission_Timestamp":"', CONVERT(VARCHAR(19), DATEADD(MINUTE, 2, r.ts), 126), N'Z',
              N'","Network_Type":"NB-IoT","Cell_Signal_Strength_dBm":', -80 - (r.n % 15),
              N',"Telemetry_Payload":[',
              N'{"obis":"1.8.0","value":', CAST(r.r180 AS DECIMAL(18,4)), N',"unit":"kWh"}',
              CASE WHEN r.scheme <> 'NONE' THEN CONCAT(N',{"obis":"2.8.0","value":', CAST(r.r280 AS DECIMAL(18,4)), N',"unit":"kWh"}') END,
              N',{"obis":"32.7.0","value":', CASE WHEN r.mn = 3 AND r.n = 10 THEN 198.5 ELSE 227.0 + (r.n % 7) END, N',"unit":"V"}',
              CASE WHEN r.three_phase = 1 THEN CONCAT(
                   N',{"obis":"52.7.0","value":', 228.0 + (r.n % 5), N',"unit":"V"}',
                   N',{"obis":"72.7.0","value":', 229.0 + (r.n % 3), N',"unit":"V"}',
                   N',{"obis":"31.7.0","value":', 10.0 + (r.n % 5), N',"unit":"A"}',
                   N',{"obis":"51.7.0","value":', 11.0 + (r.n % 4), N',"unit":"A"}',
                   N',{"obis":"71.7.0","value":', CASE WHEN r.mn = 8 AND r.n = 20 THEN 2.0 ELSE 9.0 + (r.n % 3) END, N',"unit":"A"}') END,
              CASE WHEN r.mn = 4 AND r.n = 5 THEN N',{"obis":"99.9.9","value":1,"unit":"X"}' END,
              N']}')
FROM reg AS r
WHERE NOT (r.mn = 2 AND r.n = 50);

DECLARE @json NVARCHAR(MAX);
SET @pn = 1;
WHILE @pn <= 12
BEGIN
    SELECT @json = N'[' + STRING_AGG(CAST(json AS NVARCHAR(MAX)), N',') WITHIN GROUP (ORDER BY n) + N']'
    FROM @packets WHERE mn = @pn;
    EXEC [dbo].[sp_IngestTelemetryBatch] @off1, @json;
    SET @pn = @pn + 1;
END

-- a packet from a network id that no meter has, and a malformed element
SET @json = CONCAT(N'[{"Meter_Network_ID":"NET-UNKNOWN-999","Transmission_Timestamp":"', CONVERT(VARCHAR(19), @t0, 126),
                   N'Z","Network_Type":"LTE","Cell_Signal_Strength_dBm":-101,"Telemetry_Payload":[{"obis":"1.8.0","value":42.0,"unit":"kWh"}]},',
                   N'"this is not a telemetry packet"]');
EXEC [dbo].[sp_IngestTelemetryBatch] @dso, @json;

/* ---------------------------------------------------------------------------
   9. VEE, officer decisions, finalization, transformer aggregates, tree state   [§3.2 p.8-9; §4.2 p.10; UC-16, UC-17]
   --------------------------------------------------------------------------- */
EXEC [dbo].[sp_RunVEE] @off1, @t0, @t_end, NULL;
EXEC [dbo].[sp_ListSuspectReadings] @off1, @t0, @t_end, 1, 50;

-- the spike: the officer corrects it to the value on the line between its neighbours (Editing)
DECLARE @reading BIGINT, @fixed DECIMAL(18,4), @m1 INT;
SELECT @m1 = meter_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0001';
SELECT @reading = r.reading_id,
       @fixed = (SELECT (p.[value] + nx.[value]) / 2
                 FROM [dbo].[METER_READING] AS p, [dbo].[METER_READING] AS nx
                 WHERE p.meter_id = r.meter_id AND p.obis_code = r.obis_code AND p.reading_timestamp = DATEADD(MINUTE, -15, r.reading_timestamp)
                   AND nx.meter_id = r.meter_id AND nx.obis_code = r.obis_code AND nx.reading_timestamp = DATEADD(MINUTE, 15, r.reading_timestamp))
FROM [dbo].[METER_READING] AS r
WHERE r.meter_id = @m1 AND r.obis_code = '1.8.0' AND r.status = 'SUSPECT' AND r.vee_rule IN ('SPIKE', 'OVER_CAPACITY');
EXEC [dbo].[sp_EditReading] @dso, @reading, @fixed, N'Στιγμιαίο σφάλμα καταχωρητή: διόρθωση με βάση τις γειτονικές τιμές';

-- what is still suspect was only a consequence of the spike: the officer accepts it as it is
WHILE EXISTS (SELECT 1 FROM [dbo].[METER_READING] WHERE status = 'SUSPECT')
BEGIN
    SELECT TOP (1) @reading = reading_id FROM [dbo].[METER_READING] WHERE status = 'SUSPECT' ORDER BY reading_id;
    EXEC [dbo].[sp_AcceptSuspectReading] @off1, @reading, N'Σωστή τιμή μετά τη διόρθωση της προηγούμενης';
END

EXEC [dbo].[sp_FinalizeReadings] @off1, @d1, NULL;
EXEC [dbo].[sp_FinalizeReadings] @off1, @d2, NULL;          -- last day of the month: the MONTH aggregates follow
EXEC [dbo].[sp_BuildTransformerAggregates] @dso, @d1, 0;
EXEC [dbo].[sp_BuildTransformerAggregates] @dso, @d2, 0;
EXEC [dbo].[sp_RefreshTransformerState] @tso, NULL;

/* ---------------------------------------------------------------------------
   10. Bills, payments, historical access, GDPR   [§1.3 p.6; §1.2 p.6; §1.4 p.6-7; UC-03, UC-06, UC-07, UC-08]
   --------------------------------------------------------------------------- */
EXEC [dbo].[sp_IssueMonthlyBills] @sup1_user, @bill_year, @bill_month, NULL;      -- the supplier bills its own customers
EXEC [dbo].[sp_IssueMonthlyBills] @off1, @bill_year, @bill_month, @sup2;          -- the officer runs it for the other supplier

-- consumer 1 pays one bill in two instalments
DECLARE @c1 INT, @bill INT, @amount DECIMAL(12,2), @half DECIMAL(12,2), @rest DECIMAL(12,2);
SELECT @c1 = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer1@example.cy';
SELECT TOP (1) @bill = bill_id, @amount = amount FROM [dbo].[BILL] WHERE user_id = @c1 ORDER BY bill_id;
SET @half = ROUND(@amount / 2, 2);
SET @rest = @amount - @half;
EXEC [dbo].[sp_PayBill] @c1, @bill, @half, 'CARD', 'TXN-IMPORT-0001';
EXEC [dbo].[sp_PayBill] @c1, @bill, @rest, 'BANK_TRANSFER', 'TXN-IMPORT-0002';

-- consumer 2 buys access to the previous month for one meter
DECLARE @c2 INT, @m3 INT;
SELECT @c2 = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer2@example.cy';
SELECT @m3 = meter_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0003';
EXEC [dbo].[sp_GetHistoricalAccessQuote] @c2, @m3, @month_start, @d2;
EXEC [dbo].[sp_BuyHistoricalAccess] @c2, @m3, @month_start, @d2, 'CARD', 'TXN-IMPORT-0003';

-- consumer 9: retention reduced to one month for their meter (all stages; two different officers)
DECLARE @c9 INT, @m11 INT, @gdpr INT;
SELECT @c9 = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer9@example.cy';
SELECT @m11 = meter_id FROM [dbo].[METER] WHERE serial_number = 'SN-2026-0011';
EXEC [dbo].[sp_SubmitGdprRequest] @c9, 'RETENTION_REDUCTION', @m11;
SELECT @gdpr = MAX(gdpr_request_id) FROM [dbo].[GDPR_REQUEST] WHERE user_id = @c9;
EXEC [dbo].[sp_AdvanceGdprRequest] @off1, @gdpr, 'UNDER_REVIEW', NULL;
EXEC [dbo].[sp_AdvanceGdprRequest] @off1, @gdpr, 'PRE_APPROVED', N'Ο μετρητής ανήκει στον αιτούντα';
EXEC [dbo].[sp_AdvanceGdprRequest] @off2, @gdpr, 'APPROVED', N'Τελική έγκριση';
EXEC [dbo].[sp_ExecuteGdprRequest] @off2, @gdpr;

-- consumer 10: right to be forgotten (all stages)
DECLARE @c10 INT;
SELECT @c10 = user_id FROM [dbo].[USER_ACCOUNT] WHERE email = 'consumer10@example.cy';
EXEC [dbo].[sp_SubmitGdprRequest] @c10, 'RIGHT_TO_BE_FORGOTTEN', NULL;
SELECT @gdpr = MAX(gdpr_request_id) FROM [dbo].[GDPR_REQUEST] WHERE user_id = @c10;
EXEC [dbo].[sp_AdvanceGdprRequest] @off1, @gdpr, 'UNDER_REVIEW', NULL;
EXEC [dbo].[sp_AdvanceGdprRequest] @off1, @gdpr, 'PRE_APPROVED', N'Δεν υπάρχουν εκκρεμείς υποχρεώσεις που να το εμποδίζουν';
EXEC [dbo].[sp_AdvanceGdprRequest] @off2, @gdpr, 'APPROVED', N'Τελική έγκριση';
EXEC [dbo].[sp_ExecuteGdprRequest] @off2, @gdpr;
GO

SET NOEXEC OFF;
GO

/* ---------------------------------------------------------------------------
   What was loaded
   --------------------------------------------------------------------------- */
SELECT t.name AS table_name, SUM(p.rows) AS row_count
FROM sys.tables AS t
JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.name IN ('USER_ACCOUNT','ORGANIZATION','TRANSFORMER','PREMISE','METER','DOCUMENT','TECHNICIAN_AVAILABILITY',
                 'WORK_ORDER','TELEMETRY_PACKET','METER_READING','AGGREGATE','TRANSFORMER_CURRENT_STATE','EVENT',
                 'BILL','PAYMENT','GDPR_REQUEST','AUDIT_LOG','TARIFF','METER_TYPE')
GROUP BY t.name
ORDER BY t.name;
PRINT 'import.sql finished.';
GO
