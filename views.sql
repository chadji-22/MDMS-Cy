/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   views.sql  -  Build Spec §7 (run after functions.sql)
   The per-role views are the "interfaces" over the single USER_ACCOUNT table.
   Views are read-only and are used by the stored procedures, never by PHP.
   [AR: the user views are created WITH ENCRYPTION, as in lab 10 exercise 5]
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf §1.1 p.5: consumer account]
CREATE OR ALTER VIEW [dbo].[view_CONSUMER]
WITH ENCRYPTION
AS
SELECT user_id, email, full_name, phone, iban, notify_email, notify_sms, is_active, created_at, anonymized_at
FROM [dbo].[USER_ACCOUNT]
WHERE role_code = 'CONSUMER';
GO

-- [project.pdf §2.1 p.7: technician profile]
CREATE OR ALTER VIEW [dbo].[view_TECHNICIAN]
WITH ENCRYPTION
AS
SELECT user_id, email, full_name, phone, birth_date, photo_path, specialty, approval_status, is_active
FROM [dbo].[USER_ACCOUNT]
WHERE role_code = 'TECHNICIAN';
GO

-- [project.pdf §5.1 p.10: supplier and aggregator users]
CREATE OR ALTER VIEW [dbo].[view_ORGANIZATION_USER]
WITH ENCRYPTION
AS
SELECT u.user_id, u.email, u.full_name, u.role_code, u.organization_id,
       o.name AS organization_name, o.org_type
FROM [dbo].[USER_ACCOUNT] AS u
JOIN [dbo].[ORGANIZATION] AS o ON o.organization_id = u.organization_id;
GO

-- [project.pdf Κοινές αρχές p.5: administrator, officers, DSO, TSO]
CREATE OR ALTER VIEW [dbo].[view_STAFF]
WITH ENCRYPTION
AS
SELECT user_id, email, full_name, phone, role_code, is_active
FROM [dbo].[USER_ACCOUNT]
WHERE role_code IN ('SYSTEM_ADMIN', 'SYSTEM_OFFICER', 'DSO', 'TSO');
GO

-- [project.pdf §1.1 p.5, §2.3 p.8: a premise with the meter currently in service]
CREATE OR ALTER VIEW [dbo].[view_PREMISE_METER]
AS
SELECT p.premise_id, p.address, p.latitude, p.longitude, p.usage_type, p.district, p.municipality,
       p.parish, p.postal_code, p.prosumer_scheme, p.monthly_threshold_kwh, p.user_id,
       p.supplier_org_id, p.aggregator_org_id,
       m.meter_id, m.serial_number, m.status AS meter_status, m.transformer_id,
       s.name AS supplier_name, a.name AS aggregator_name
FROM [dbo].[PREMISE] AS p
LEFT JOIN [dbo].[METER] AS m ON m.premise_id = p.premise_id AND m.removed_at IS NULL
LEFT JOIN [dbo].[ORGANIZATION] AS s ON s.organization_id = p.supplier_org_id
LEFT JOIN [dbo].[ORGANIZATION] AS a ON a.organization_id = p.aggregator_org_id;
GO

-- [project.pdf §2.2 p.7 geographic position; §4.1 p.9 geofence; p.2 maps bonus (Leaflet)]
CREATE OR ALTER VIEW [dbo].[view_METER_LOCATION]
AS
SELECT m.meter_id, m.serial_number, m.status, m.latitude, m.longitude,
       p.premise_id, p.address AS premise_address, p.district,
       t.transformer_id, t.name AS transformer_name,
       t.min_lat, t.min_lon, t.max_lat, t.max_lon
FROM [dbo].[METER] AS m
JOIN [dbo].[PREMISE] AS p ON p.premise_id = m.premise_id
JOIN [dbo].[TRANSFORMER] AS t ON t.transformer_id = m.transformer_id;
GO

-- [project.pdf §2.2 p.7: the technician sees the jobs and where they are]
CREATE OR ALTER VIEW [dbo].[view_OPEN_WORK_ORDER]
AS
SELECT w.work_order_id, w.work_type, w.origin, w.description, w.status, w.created_at,
       w.scheduled_start, w.scheduled_end, w.accepted_at, w.requested_by_user_id,
       w.technician_user_id, w.meter_id, w.event_id, w.service_type_id,
       p.premise_id, p.address AS premise_address, p.district,
       p.latitude AS premise_latitude, p.longitude AS premise_longitude,
       m.latitude AS meter_latitude, m.longitude AS meter_longitude,
       tech.full_name AS technician_name
FROM [dbo].[WORK_ORDER] AS w
LEFT JOIN [dbo].[METER] AS m ON m.meter_id = w.meter_id
LEFT JOIN [dbo].[PREMISE] AS p ON p.premise_id = COALESCE(w.premise_id, m.premise_id)
LEFT JOIN [dbo].[USER_ACCOUNT] AS tech ON tech.user_id = w.technician_user_id
WHERE w.status NOT IN ('COMPLETED', 'CANCELLED');
GO

-- [project.pdf §1.3 p.6: charges and payments of a bill]
CREATE OR ALTER VIEW [dbo].[view_BILL_BALANCE]
AS
SELECT b.bill_id, b.issue_date, b.due_date, b.period_start, b.period_end, b.amount, b.status,
       b.premise_id, b.user_id, b.supplier_org_id, b.tariff_id,
       [dbo].[fn_BillPaid](b.bill_id) AS paid,
       b.amount - [dbo].[fn_BillPaid](b.bill_id) AS remaining
FROM [dbo].[BILL] AS b;
GO

PRINT 'views.sql: 8 views created.';
GO
