# Final Database Data Dictionary

*MDMS-Cy — EPL342 Databases, Group 10.*

Generated from the SQL Server system catalogs.

Database: MDMS_ELIANA_TEST.

Schema: dbo.

## Database overview

| Object | Count |
|---|---:|
| Tables | 25 |
| Triggers | 24 |
| Stored procedures | 118 |
| Foreign keys | 50 |

PK = Primary key; FK = Foreign key.

The following sections describe each table,
its columns, constraints, indexes and triggers.

## 1. AGGREGATE

Stored measurement aggregates.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| aggregate_id | BIGINT | No | PK | IDENTITY |
| period_type | VARCHAR(12) | No | - | - |
| period_start | DATETIME2(0) | No | - | - |
| value | DECIMAL(20,4) | No | - | - |
| sample_count | INT | No | - | - |
| is_final | BIT | No | - | ((0)) |
| calculated_at | DATETIME2(0) | No | - | (sysutcdatetime()) |
| meter_id | INT | Yes | FK | - |
| transformer_id | INT | Yes | FK | - |
| obis_code | VARCHAR(20) | No | FK | - |

### Foreign keys

- `FK_AGGREGATE_meter`: `meter_id` → `METER.meter_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_AGGREGATE_obis`: `obis_code` → `OBIS_CODE.obis_code`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_AGGREGATE_transformer`: `transformer_id` → `TRANSFORMER.transformer_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_AGGREGATE_owner**

~~~sql
([meter_id] IS NOT NULL AND [transformer_id] IS NULL OR [meter_id] IS NULL AND [transformer_id] IS NOT NULL)
~~~

**CK_AGGREGATE_period_type**

~~~sql
([period_type]='YEAR' OR [period_type]='MONTH' OR [period_type]='DAY' OR [period_type]='QUARTER_HOUR')
~~~

**CK_AGGREGATE_sample_count**

~~~sql
([sample_count]>=(0))
~~~


### Keys and indexes

- `PK_AGGREGATE` (PRIMARY KEY, CLUSTERED): aggregate_id
- `UQ_AGGREGATE_meter` (UNIQUE INDEX, NONCLUSTERED): meter_id, obis_code, period_type, period_start; WHERE ([meter_id] IS NOT NULL)
- `UQ_AGGREGATE_transformer` (UNIQUE INDEX, NONCLUSTERED): transformer_id, obis_code, period_type, period_start; WHERE ([transformer_id] IS NOT NULL)

### Triggers

- `tr_AGGREGATE_immutable`
- `tr_AGGREGATE_threshold_alert`

---

## 2. AUDIT_LOG

Traceable records of critical system actions.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| log_id | BIGINT | No | PK | IDENTITY |
| logged_at | DATETIME2(0) | No | - | (sysutcdatetime()) |
| actor_type | VARCHAR(10) | No | - | - |
| mechanism | VARCHAR(60) | Yes | - | - |
| action | VARCHAR(50) | No | - | - |
| object_type | VARCHAR(30) | No | - | - |
| object_id | VARCHAR(30) | No | - | - |
| old_state | NVARCHAR(200) | Yes | - | - |
| new_state | NVARCHAR(200) | Yes | - | - |
| comment | NVARCHAR(500) | Yes | - | - |
| user_id | INT | Yes | FK | - |

### Foreign keys

- `FK_AUDIT_LOG_user`: `user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_AUDIT_LOG_actor**

~~~sql
([actor_type]='USER' AND [user_id] IS NOT NULL OR [actor_type]<>'USER' AND [mechanism] IS NOT NULL)
~~~

**CK_AUDIT_LOG_actor_type**

~~~sql
([actor_type]='DEVICE' OR [actor_type]='SYSTEM' OR [actor_type]='USER')
~~~


### Keys and indexes

- `IX_AUDIT_LOG_object` (INDEX, NONCLUSTERED): object_type, object_id, logged_at
- `PK_AUDIT_LOG` (PRIMARY KEY, CLUSTERED): log_id

### Triggers

- `tr_AUDIT_LOG_append_only`

---

## 3. BILL

Issued electricity bills.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| bill_id | INT | No | PK | IDENTITY |
| issue_date | DATE | No | - | - |
| due_date | DATE | No | - | - |
| period_start | DATE | No | - | - |
| period_end | DATE | No | - | - |
| amount | DECIMAL(12,2) | No | - | - |
| status | VARCHAR(20) | No | - | ('ISSUED') |
| premise_id | INT | No | FK | - |
| user_id | INT | No | FK | - |
| supplier_org_id | INT | No | FK | - |
| tariff_id | INT | No | FK | - |

### Foreign keys

- `FK_BILL_premise`: `premise_id` → `PREMISE.premise_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_BILL_supplier`: `supplier_org_id` → `ORGANIZATION.organization_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_BILL_tariff`: `tariff_id` → `TARIFF.tariff_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_BILL_user`: `user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_BILL_amount**

~~~sql
([amount]>=(0))
~~~

**CK_BILL_dates**

~~~sql
([due_date]>=[issue_date] AND [period_end]>=[period_start])
~~~

**CK_BILL_status**

~~~sql
([status]='CANCELLED' OR [status]='OVERDUE' OR [status]='PAID' OR [status]='PARTIALLY_PAID' OR [status]='ISSUED')
~~~


### Keys and indexes

- `PK_BILL` (PRIMARY KEY, CLUSTERED): bill_id
- `UQ_BILL_premise_period` (UNIQUE INDEX, NONCLUSTERED): premise_id, period_start; WHERE ([status]<>'CANCELLED')

### Triggers

- `tr_BILL_no_delete`

---

## 4. DOCUMENT

Supporting technical documents and certificates.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| document_id | INT | No | PK | IDENTITY |
| doc_type | VARCHAR(40) | No | - | - |
| doc_code | VARCHAR(60) | No | - | - |
| issue_date | DATE | No | - | - |
| expiry_date | DATE | Yes | - | - |
| file_path | VARCHAR(500) | No | - | - |
| approval_status | VARCHAR(20) | No | - | ('PENDING') |
| user_id | INT | Yes | FK | - |
| meter_id | INT | Yes | FK | - |

### Foreign keys

- `FK_DOCUMENT_meter`: `meter_id` → `METER.meter_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_DOCUMENT_user`: `user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_DOCUMENT_approval_status**

~~~sql
([approval_status]='REJECTED' OR [approval_status]='APPROVED' OR [approval_status]='PENDING')
~~~

**CK_DOCUMENT_dates**

~~~sql
([expiry_date] IS NULL OR [expiry_date]>=[issue_date])
~~~

**CK_DOCUMENT_owner**

~~~sql
([user_id] IS NOT NULL AND [meter_id] IS NULL AND ([doc_type]='TRAINING_CERT' OR [doc_type]='INSTALLER_LICENSE' OR [doc_type]='ID_CARD') OR [meter_id] IS NOT NULL AND [user_id] IS NULL AND ([doc_type]='ENCRYPTION_CERT' OR [doc_type]='CE_DECLARATION' OR [doc_type]='CALIBRATION_CERT'))
~~~


### Keys and indexes

- `PK_DOCUMENT` (PRIMARY KEY, CLUSTERED): document_id
- `UQ_DOCUMENT_code` (UNIQUE CONSTRAINT, NONCLUSTERED): doc_type, doc_code

### Triggers

- `tr_DOCUMENT_audit`

---

## 5. EVENT

Operational events and alerts.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| event_id | BIGINT | No | PK | IDENTITY |
| event_timestamp | DATETIME2(0) | No | - | - |
| event_type | VARCHAR(40) | No | - | - |
| severity | VARCHAR(10) | No | - | - |
| description | NVARCHAR(500) | Yes | - | - |
| meter_id | INT | Yes | FK | - |
| transformer_id | INT | Yes | FK | - |
| packet_id | BIGINT | Yes | FK | - |

### Foreign keys

- `FK_EVENT_meter`: `meter_id` → `METER.meter_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_EVENT_packet`: `packet_id` → `TELEMETRY_PACKET.packet_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_EVENT_transformer`: `transformer_id` → `TRANSFORMER.transformer_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_EVENT_severity**

~~~sql
([severity]='CRITICAL' OR [severity]='WARNING' OR [severity]='INFO')
~~~

**CK_EVENT_source**

~~~sql
([meter_id] IS NOT NULL OR [transformer_id] IS NOT NULL OR [packet_id] IS NOT NULL)
~~~


### Keys and indexes

- `IX_EVENT_meter_time` (INDEX, NONCLUSTERED): meter_id, event_timestamp; INCLUDE event_type, severity
- `PK_EVENT` (PRIMARY KEY, CLUSTERED): event_id

### Triggers

- `tr_EVENT_notify`
- `tr_EVENT_work_order`

---

## 6. GDPR_REQUEST

Privacy and data retention requests.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| gdpr_request_id | INT | No | PK | IDENTITY |
| request_type | VARCHAR(30) | No | - | - |
| status | VARCHAR(20) | No | - | ('SUBMITTED') |
| submitted_at | DATETIME2(0) | No | - | (sysutcdatetime()) |
| decided_at | DATETIME2(0) | Yes | - | - |
| user_id | INT | No | FK | - |
| meter_id | INT | Yes | FK | - |

### Foreign keys

- `FK_GDPR_REQUEST_meter`: `meter_id` → `METER.meter_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_GDPR_REQUEST_user`: `user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_GDPR_REQUEST_meter**

~~~sql
([request_type]<>'RETENTION_REDUCTION' OR [meter_id] IS NOT NULL)
~~~

**CK_GDPR_REQUEST_status**

~~~sql
([status]='EXECUTED' OR [status]='REJECTED' OR [status]='APPROVED' OR [status]='PRE_APPROVED' OR [status]='UNDER_REVIEW' OR [status]='SUBMITTED')
~~~

**CK_GDPR_REQUEST_type**

~~~sql
([request_type]='RETENTION_REDUCTION' OR [request_type]='RIGHT_TO_BE_FORGOTTEN')
~~~


### Keys and indexes

- `PK_GDPR_REQUEST` (PRIMARY KEY, CLUSTERED): gdpr_request_id

### Triggers

- `tr_GDPR_REQUEST_audit`

---

## 7. METER

Installed smart meters and technical attributes.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| meter_id | INT | No | PK | IDENTITY |
| serial_number | VARCHAR(50) | No | - | - |
| network_id | VARCHAR(60) | No | - | - |
| firmware_version | VARCHAR(30) | No | - | - |
| communication_type | VARCHAR(20) | No | - | - |
| latitude | DECIMAL(9,6) | No | - | - |
| longitude | DECIMAL(9,6) | No | - | - |
| status | VARCHAR(20) | No | - | ('PENDING') |
| activated_at | DATETIME2(0) | Yes | - | - |
| installed_at | DATETIME2(0) | No | - | - |
| removed_at | DATETIME2(0) | Yes | - | - |
| installation_photo | VARCHAR(500) | Yes | - | - |
| retention_months | TINYINT | No | - | ((36)) |
| meter_type_id | INT | No | FK | - |
| transformer_id | INT | No | FK | - |
| premise_id | INT | No | FK | - |
| installed_by_user_id | INT | Yes | FK | - |

### Foreign keys

- `FK_METER_installed_by`: `installed_by_user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_METER_meter_type`: `meter_type_id` → `METER_TYPE.meter_type_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_METER_premise`: `premise_id` → `PREMISE.premise_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_METER_transformer`: `transformer_id` → `TRANSFORMER.transformer_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_METER_active**

~~~sql
([status]<>'ACTIVE' OR [activated_at] IS NOT NULL)
~~~

**CK_METER_communication_type**

~~~sql
([communication_type]='PLC' OR [communication_type]='NB_IOT' OR [communication_type]='CELLULAR')
~~~

**CK_METER_dates**

~~~sql
([removed_at] IS NULL OR [removed_at]>=[installed_at])
~~~

**CK_METER_lat**

~~~sql
([latitude]>=(-90) AND [latitude]<=(90))
~~~

**CK_METER_lon**

~~~sql
([longitude]>=(-180) AND [longitude]<=(180))
~~~

**CK_METER_removed**

~~~sql
([status]='REMOVED' AND [removed_at] IS NOT NULL OR [status]<>'REMOVED' AND [removed_at] IS NULL)
~~~

**CK_METER_retention**

~~~sql
([retention_months]=(36) OR [retention_months]=(1))
~~~

**CK_METER_status**

~~~sql
([status]='REMOVED' OR [status]='FAULTY' OR [status]='INACTIVE' OR [status]='ACTIVE' OR [status]='PENDING')
~~~


### Keys and indexes

- `IX_METER_premise` (INDEX, NONCLUSTERED): premise_id; INCLUDE status, removed_at
- `IX_METER_transformer` (INDEX, NONCLUSTERED): transformer_id; INCLUDE status, premise_id
- `PK_METER` (PRIMARY KEY, CLUSTERED): meter_id
- `UQ_METER_network_id` (UNIQUE CONSTRAINT, NONCLUSTERED): network_id
- `UQ_METER_one_active_per_premise` (UNIQUE INDEX, NONCLUSTERED): premise_id; WHERE ([removed_at] IS NULL)
- `UQ_METER_serial_number` (UNIQUE CONSTRAINT, NONCLUSTERED): serial_number

### Triggers

- `tr_METER_activation_guard`
- `tr_METER_audit`
- `tr_METER_transformer_guard`

---

## 8. METER_READING

Individual meter measurements.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| reading_id | BIGINT | No | PK | IDENTITY |
| reading_timestamp | DATETIME2(0) | No | - | - |
| value | DECIMAL(18,4) | No | - | - |
| delta_value | DECIMAL(18,4) | Yes | - | - |
| status | VARCHAR(20) | No | - | ('PENDING') |
| original_value | DECIMAL(18,4) | Yes | - | - |
| vee_rule | VARCHAR(40) | Yes | - | - |
| vee_note | NVARCHAR(300) | Yes | - | - |
| is_final | BIT | No | - | ((0)) |
| finalized_at | DATETIME2(0) | Yes | - | - |
| meter_id | INT | No | FK | - |
| obis_code | VARCHAR(20) | No | FK | - |
| packet_id | BIGINT | Yes | FK | - |
| edited_by_user_id | INT | Yes | FK | - |

### Foreign keys

- `FK_METER_READING_edited_by`: `edited_by_user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_METER_READING_meter`: `meter_id` → `METER.meter_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_METER_READING_obis`: `obis_code` → `OBIS_CODE.obis_code`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_METER_READING_packet`: `packet_id` → `TELEMETRY_PACKET.packet_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_METER_READING_edited**

~~~sql
([status]<>'EDITED' OR [original_value] IS NOT NULL AND [edited_by_user_id] IS NOT NULL)
~~~

**CK_METER_READING_estimated**

~~~sql
([status]<>'ESTIMATED' OR [packet_id] IS NULL AND [vee_rule] IS NOT NULL)
~~~

**CK_METER_READING_final**

~~~sql
([is_final]=(0) OR [finalized_at] IS NOT NULL AND ([status]='EDITED' OR [status]='ESTIMATED' OR [status]='VALID'))
~~~

**CK_METER_READING_slot**

~~~sql
(datepart(minute,[reading_timestamp])%(15)=(0) AND datepart(second,[reading_timestamp])=(0))
~~~

**CK_METER_READING_status**

~~~sql
([status]='EDITED' OR [status]='ESTIMATED' OR [status]='SUSPECT' OR [status]='VALID' OR [status]='PENDING')
~~~


### Keys and indexes

- `IX_METER_READING_not_final` (INDEX, NONCLUSTERED): meter_id, reading_timestamp; INCLUDE obis_code, value, delta_value, status; WHERE ([is_final]=(0))
- `IX_METER_READING_obis_slot` (INDEX, NONCLUSTERED): obis_code, reading_timestamp; INCLUDE meter_id, delta_value, status
- `IX_METER_READING_packet` (INDEX, NONCLUSTERED): packet_id; WHERE ([packet_id] IS NOT NULL)
- `PK_METER_READING` (PRIMARY KEY, CLUSTERED): reading_id
- `UQ_METER_READING_slot` (UNIQUE CONSTRAINT, NONCLUSTERED): meter_id, obis_code, reading_timestamp

### Triggers

- `tr_METER_READING_edit_audit`
- `tr_METER_READING_immutable`

---

## 9. METER_TYPE

Smart meter model reference data.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| meter_type_id | INT | No | PK | IDENTITY |
| type_name | VARCHAR(50) | No | - | - |
| connection_phases | TINYINT | No | - | - |
| max_amps | DECIMAL(6,1) | No | - | - |

### Foreign keys

None.

### CHECK constraints

**CK_METER_TYPE_max_amps**

~~~sql
([max_amps]>(0))
~~~

**CK_METER_TYPE_phases**

~~~sql
([connection_phases]=(3) OR [connection_phases]=(1))
~~~


### Keys and indexes

- `PK_METER_TYPE` (PRIMARY KEY, CLUSTERED): meter_type_id
- `UQ_METER_TYPE_type_name` (UNIQUE CONSTRAINT, NONCLUSTERED): type_name

### Triggers

None.

---

## 10. NOTIFICATION

Notification records and delivery status.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| notification_id | BIGINT | No | PK | IDENTITY |
| created_at | DATETIME2(0) | No | - | (sysutcdatetime()) |
| channel | VARCHAR(10) | No | - | - |
| recipient | VARCHAR(255) | Yes | - | - |
| status | VARCHAR(12) | No | - | - |
| message | NVARCHAR(500) | Yes | - | - |
| event_id | BIGINT | No | FK | - |
| user_id | INT | No | FK | - |

### Foreign keys

- `FK_NOTIFICATION_event`: `event_id` → `EVENT.event_id`. ON DELETE CASCADE; ON UPDATE NO_ACTION.
- `FK_NOTIFICATION_user`: `user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_NOTIFICATION_channel**

~~~sql
([channel]='SMS' OR [channel]='EMAIL')
~~~

**CK_NOTIFICATION_status**

~~~sql
([status]='FAILED' OR [status]='SENT' OR [status]='SIMULATED')
~~~


### Keys and indexes

- `IX_NOTIFICATION_user` (INDEX, NONCLUSTERED): user_id, created_at
- `PK_NOTIFICATION` (PRIMARY KEY, CLUSTERED): notification_id
- `UQ_NOTIFICATION_event_channel` (UNIQUE CONSTRAINT, NONCLUSTERED): event_id, channel

### Triggers

None.

---

## 11. OBIS_CODE

Measurement codes, units and validation ranges.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| obis_code | VARCHAR(20) | No | PK | - |
| description | NVARCHAR(200) | No | - | - |
| unit | VARCHAR(10) | No | - | - |
| measurement_kind | VARCHAR(15) | No | - | - |
| valid_min | DECIMAL(18,4) | Yes | - | - |
| valid_max | DECIMAL(18,4) | Yes | - | - |

### Foreign keys

None.

### CHECK constraints

**CK_OBIS_CODE_kind**

~~~sql
([measurement_kind]='INSTANTANEOUS' OR [measurement_kind]='CUMULATIVE')
~~~

**CK_OBIS_CODE_range**

~~~sql
([valid_min] IS NULL OR [valid_max] IS NULL OR [valid_max]>=[valid_min])
~~~


### Keys and indexes

- `PK_OBIS_CODE` (PRIMARY KEY, CLUSTERED): obis_code

### Triggers

None.

---

## 12. ORGANIZATION

Supplier and aggregator organizations.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| organization_id | INT | No | PK | IDENTITY |
| name | NVARCHAR(150) | No | - | - |
| org_type | VARCHAR(20) | No | - | - |

### Foreign keys

None.

### CHECK constraints

**CK_ORGANIZATION_org_type**

~~~sql
([org_type]='AGGREGATOR' OR [org_type]='SUPPLIER')
~~~


### Keys and indexes

- `PK_ORGANIZATION` (PRIMARY KEY, CLUSTERED): organization_id
- `UQ_ORGANIZATION_name` (UNIQUE CONSTRAINT, NONCLUSTERED): name

### Triggers

None.

---

## 13. PAYMENT

Financial transactions and payments.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| payment_id | INT | No | PK | IDENTITY |
| payment_date | DATETIME2(0) | No | - | (sysutcdatetime()) |
| amount | DECIMAL(12,2) | No | - | - |
| method | VARCHAR(20) | No | - | - |
| status | VARCHAR(20) | No | - | ('COMPLETED') |
| transaction_reference | VARCHAR(60) | Yes | - | - |
| access_from | DATE | Yes | - | - |
| access_to | DATE | Yes | - | - |
| user_id | INT | No | FK | - |
| bill_id | INT | Yes | FK | - |
| service_type_id | INT | Yes | FK | - |
| access_meter_id | INT | Yes | FK | - |

### Foreign keys

- `FK_PAYMENT_access_meter`: `access_meter_id` → `METER.meter_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_PAYMENT_bill`: `bill_id` → `BILL.bill_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_PAYMENT_service_type`: `service_type_id` → `SERVICE_TYPE.service_type_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_PAYMENT_user`: `user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_PAYMENT_access**

~~~sql
([access_meter_id] IS NULL AND [access_from] IS NULL AND [access_to] IS NULL OR [access_meter_id] IS NOT NULL AND [service_type_id] IS NOT NULL AND [access_from] IS NOT NULL AND [access_to] IS NOT NULL AND [access_to]>=[access_from])
~~~

**CK_PAYMENT_amount**

~~~sql
([amount]>(0))
~~~

**CK_PAYMENT_method**

~~~sql
([method]='DIRECT_DEBIT' OR [method]='CASH' OR [method]='CARD' OR [method]='BANK_TRANSFER')
~~~

**CK_PAYMENT_purpose**

~~~sql
((case when [bill_id] IS NULL then (0) else (1) end+case when [service_type_id] IS NULL then (0) else (1) end)=(1))
~~~

**CK_PAYMENT_status**

~~~sql
([status]='REFUNDED' OR [status]='FAILED' OR [status]='COMPLETED' OR [status]='PENDING')
~~~


### Keys and indexes

- `IX_PAYMENT_bill` (INDEX, NONCLUSTERED): bill_id; INCLUDE amount, status; WHERE ([bill_id] IS NOT NULL)
- `PK_PAYMENT` (PRIMARY KEY, CLUSTERED): payment_id
- `UQ_PAYMENT_transaction_reference` (UNIQUE INDEX, NONCLUSTERED): transaction_reference; WHERE ([transaction_reference] IS NOT NULL)

### Triggers

- `tr_PAYMENT_bill_status`
- `tr_PAYMENT_no_delete`

---

## 14. PREMISE

Consumer premises.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| premise_id | INT | No | PK | IDENTITY |
| address | NVARCHAR(250) | No | - | - |
| latitude | DECIMAL(9,6) | No | - | - |
| longitude | DECIMAL(9,6) | No | - | - |
| usage_type | VARCHAR(20) | No | - | - |
| district | NVARCHAR(30) | No | - | - |
| municipality | NVARCHAR(80) | No | - | - |
| parish | NVARCHAR(80) | No | - | - |
| postal_code | CHAR(4) | No | - | - |
| prosumer_scheme | VARCHAR(20) | No | - | ('NONE') |
| monthly_threshold_kwh | DECIMAL(18,4) | Yes | - | - |
| user_id | INT | No | FK | - |
| supplier_org_id | INT | Yes | FK | - |
| aggregator_org_id | INT | Yes | FK | - |

### Foreign keys

- `FK_PREMISE_aggregator`: `aggregator_org_id` → `ORGANIZATION.organization_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_PREMISE_supplier`: `supplier_org_id` → `ORGANIZATION.organization_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_PREMISE_user`: `user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_PREMISE_district**

~~~sql
([district]=N'Κερύνεια' OR [district]=N'Αμμόχωστος' OR [district]=N'Πάφος' OR [district]=N'Λάρνακα' OR [district]=N'Λεμεσός' OR [district]=N'Λευκωσία')
~~~

**CK_PREMISE_lat**

~~~sql
([latitude]>=(-90) AND [latitude]<=(90))
~~~

**CK_PREMISE_lon**

~~~sql
([longitude]>=(-180) AND [longitude]<=(180))
~~~

**CK_PREMISE_postal_code**

~~~sql
([postal_code] like '[0-9][0-9][0-9][0-9]')
~~~

**CK_PREMISE_prosumer_scheme**

~~~sql
([prosumer_scheme]='NET_BILLING' OR [prosumer_scheme]='NET_METERING' OR [prosumer_scheme]='NONE')
~~~

**CK_PREMISE_threshold**

~~~sql
([monthly_threshold_kwh] IS NULL OR [monthly_threshold_kwh]>(0))
~~~

**CK_PREMISE_usage_type**

~~~sql
([usage_type]='AGRICULTURAL' OR [usage_type]='INDUSTRIAL' OR [usage_type]='COMMERCIAL' OR [usage_type]='RESIDENTIAL')
~~~


### Keys and indexes

- `IX_PREMISE_aggregator` (INDEX, NONCLUSTERED): aggregator_org_id; INCLUDE prosumer_scheme
- `IX_PREMISE_supplier` (INDEX, NONCLUSTERED): supplier_org_id; INCLUDE prosumer_scheme
- `PK_PREMISE` (PRIMARY KEY, CLUSTERED): premise_id

### Triggers

- `tr_PREMISE_guard`

---

## 15. REMOTE_COMMAND

Remote meter commands and execution state.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| command_id | INT | No | PK | IDENTITY |
| command_type | VARCHAR(20) | No | - | - |
| parameters | NVARCHAR(500) | Yes | - | - |
| status | VARCHAR(20) | No | - | ('PENDING_APPROVAL') |
| requested_at | DATETIME2(0) | No | - | (sysutcdatetime()) |
| attempt_count | SMALLINT | No | - | ((0)) |
| last_attempt_at | DATETIME2(0) | Yes | - | - |
| ack_at | DATETIME2(0) | Yes | - | - |
| result | NVARCHAR(300) | Yes | - | - |
| meter_id | INT | No | FK | - |
| requested_by_user_id | INT | No | FK | - |
| executed_by_user_id | INT | Yes | FK | - |

### Foreign keys

- `FK_REMOTE_COMMAND_executed_by`: `executed_by_user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_REMOTE_COMMAND_meter`: `meter_id` → `METER.meter_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_REMOTE_COMMAND_requested_by`: `requested_by_user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_REMOTE_COMMAND_ack**

~~~sql
([status]='ACKNOWLEDGED' AND [ack_at] IS NOT NULL OR [status]<>'ACKNOWLEDGED' AND [ack_at] IS NULL)
~~~

**CK_REMOTE_COMMAND_attempts**

~~~sql
([attempt_count]>=(0))
~~~

**CK_REMOTE_COMMAND_status**

~~~sql
([status]='FAILED' OR [status]='ACKNOWLEDGED' OR [status]='SENT' OR [status]='REJECTED' OR [status]='APPROVED' OR [status]='PENDING_APPROVAL')
~~~

**CK_REMOTE_COMMAND_type**

~~~sql
([command_type]='FIRMWARE_UPGRADE' OR [command_type]='RECONNECT' OR [command_type]='DISCONNECT')
~~~


### Keys and indexes

- `PK_REMOTE_COMMAND` (PRIMARY KEY, CLUSTERED): command_id

### Triggers

- `tr_REMOTE_COMMAND_audit`
- `tr_REMOTE_COMMAND_guard`

---

## 16. ROLE

Available user roles.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| role_code | VARCHAR(20) | No | PK | - |
| description | NVARCHAR(100) | No | - | - |

### Foreign keys

None.

### CHECK constraints

None.

### Keys and indexes

- `PK_ROLE` (PRIMARY KEY, CLUSTERED): role_code

### Triggers

None.

---

## 17. SERVICE_TYPE

Configurable chargeable services.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| service_type_id | INT | No | PK | IDENTITY |
| service_name | NVARCHAR(100) | No | - | - |
| fee | DECIMAL(10,2) | No | - | - |
| is_active | BIT | No | - | ((1)) |

### Foreign keys

None.

### CHECK constraints

**CK_SERVICE_TYPE_fee**

~~~sql
([fee]>=(0))
~~~


### Keys and indexes

- `PK_SERVICE_TYPE` (PRIMARY KEY, CLUSTERED): service_type_id
- `UQ_SERVICE_TYPE_name` (UNIQUE CONSTRAINT, NONCLUSTERED): service_name

### Triggers

None.

---

## 18. TARIFF

Electricity tariff definitions.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| tariff_id | INT | No | PK | IDENTITY |
| tariff_name | NVARCHAR(100) | No | - | - |
| rate | DECIMAL(10,4) | No | - | - |
| valid_from | DATE | No | - | - |
| valid_to | DATE | Yes | - | - |

### Foreign keys

None.

### CHECK constraints

**CK_TARIFF_dates**

~~~sql
([valid_to] IS NULL OR [valid_to]>=[valid_from])
~~~

**CK_TARIFF_rate**

~~~sql
([rate]>=(0))
~~~


### Keys and indexes

- `PK_TARIFF` (PRIMARY KEY, CLUSTERED): tariff_id
- `UQ_TARIFF_name_from` (UNIQUE CONSTRAINT, NONCLUSTERED): tariff_name, valid_from

### Triggers

None.

---

## 19. TECHNICIAN_AVAILABILITY

Technician scheduling availability.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| user_id | INT | No | PK, FK | - |
| avail_date | DATE | No | PK | - |
| start_time | TIME(0) | No | PK | - |
| end_time | TIME(0) | No | - | - |
| district | NVARCHAR(30) | No | - | - |

### Foreign keys

- `FK_TECHNICIAN_AVAILABILITY_user`: `user_id` → `USER_ACCOUNT.user_id`. ON DELETE CASCADE; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_TECHNICIAN_AVAILABILITY_district**

~~~sql
([district]=N'Κερύνεια' OR [district]=N'Αμμόχωστος' OR [district]=N'Πάφος' OR [district]=N'Λάρνακα' OR [district]=N'Λεμεσός' OR [district]=N'Λευκωσία')
~~~

**CK_TECHNICIAN_AVAILABILITY_time**

~~~sql
([end_time]>[start_time])
~~~


### Keys and indexes

- `PK_TECHNICIAN_AVAILABILITY` (PRIMARY KEY, CLUSTERED): user_id, avail_date, start_time

### Triggers

None.

---

## 20. TELEMETRY_PACKET

Incoming telemetry packets.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| packet_id | BIGINT | No | PK | IDENTITY |
| meter_network_id | VARCHAR(60) | No | - | - |
| transmission_timestamp | DATETIME2(0) | No | - | - |
| received_at | DATETIME2(0) | No | - | (sysutcdatetime()) |
| network_type | VARCHAR(30) | Yes | - | - |
| signal_dbm | SMALLINT | Yes | - | - |
| raw_payload | NVARCHAR(4000) | No | - | - |
| match_status | VARCHAR(20) | No | - | - |
| meter_id | INT | Yes | FK | - |

### Foreign keys

- `FK_TELEMETRY_PACKET_meter`: `meter_id` → `METER.meter_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_TELEMETRY_PACKET_json**

~~~sql
(isjson([raw_payload])=(1))
~~~

**CK_TELEMETRY_PACKET_match**

~~~sql
([match_status]='MATCHED' AND [meter_id] IS NOT NULL OR [match_status]='UNMATCHED' AND [meter_id] IS NULL OR ([match_status]='QUARANTINED' OR [match_status]='COMM_ERROR'))
~~~

**CK_TELEMETRY_PACKET_status**

~~~sql
([match_status]='QUARANTINED' OR [match_status]='COMM_ERROR' OR [match_status]='UNMATCHED' OR [match_status]='MATCHED')
~~~


### Keys and indexes

- `IX_TELEMETRY_PACKET_network` (INDEX, NONCLUSTERED): meter_network_id, received_at
- `PK_TELEMETRY_PACKET` (PRIMARY KEY, CLUSTERED): packet_id

### Triggers

- `tr_TELEMETRY_PACKET_failure_event`

---

## 21. TRANSFORMER

Transformer hierarchy and geographical areas.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| transformer_id | INT | No | PK | IDENTITY |
| name | NVARCHAR(100) | No | - | - |
| level | TINYINT | No | - | - |
| capacity_kva | DECIMAL(10,2) | No | - | - |
| latitude | DECIMAL(9,6) | No | - | - |
| longitude | DECIMAL(9,6) | No | - | - |
| min_lat | DECIMAL(9,6) | Yes | - | - |
| min_lon | DECIMAL(9,6) | Yes | - | - |
| max_lat | DECIMAL(9,6) | Yes | - | - |
| max_lon | DECIMAL(9,6) | Yes | - | - |
| parent_transformer_id | INT | Yes | FK | - |

### Foreign keys

- `FK_TRANSFORMER_parent`: `parent_transformer_id` → `TRANSFORMER.transformer_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_TRANSFORMER_capacity**

~~~sql
([capacity_kva]>(0))
~~~

**CK_TRANSFORMER_geofence**

~~~sql
([min_lat] IS NULL AND [min_lon] IS NULL AND [max_lat] IS NULL AND [max_lon] IS NULL OR [min_lat] IS NOT NULL AND [min_lon] IS NOT NULL AND [max_lat] IS NOT NULL AND [max_lon] IS NOT NULL AND ([min_lat]>=(-90) AND [min_lat]<=(90)) AND ([max_lat]>=(-90) AND [max_lat]<=(90)) AND ([min_lon]>=(-180) AND [min_lon]<=(180)) AND ([max_lon]>=(-180) AND [max_lon]<=(180)) AND [min_lat]<=[max_lat] AND [min_lon]<=[max_lon])
~~~

**CK_TRANSFORMER_lat**

~~~sql
([latitude]>=(-90) AND [latitude]<=(90))
~~~

**CK_TRANSFORMER_level**

~~~sql
([level]>=(1))
~~~

**CK_TRANSFORMER_lon**

~~~sql
([longitude]>=(-180) AND [longitude]<=(180))
~~~

**CK_TRANSFORMER_not_own_parent**

~~~sql
([parent_transformer_id] IS NULL OR [parent_transformer_id]<>[transformer_id])
~~~


### Keys and indexes

- `IX_TRANSFORMER_parent` (INDEX, NONCLUSTERED): parent_transformer_id
- `PK_TRANSFORMER` (PRIMARY KEY, CLUSTERED): transformer_id
- `UQ_TRANSFORMER_name` (UNIQUE CONSTRAINT, NONCLUSTERED): name

### Triggers

- `tr_TRANSFORMER_tree_guard`

---

## 22. TRANSFORMER_CURRENT_STATE

Current transformer operating state.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| state_id | BIGINT | No | PK | IDENTITY |
| reference_15_min | DATETIME2(0) | No | - | - |
| sum_value | DECIMAL(20,4) | No | - | - |
| meter_count | INT | No | - | - |
| computed_at | DATETIME2(0) | No | - | (sysutcdatetime()) |
| transformer_id | INT | No | FK | - |
| obis_code | VARCHAR(20) | No | FK | - |

### Foreign keys

- `FK_TRANSFORMER_CURRENT_STATE_obis`: `obis_code` → `OBIS_CODE.obis_code`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_TRANSFORMER_CURRENT_STATE_transformer`: `transformer_id` → `TRANSFORMER.transformer_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_TRANSFORMER_CURRENT_STATE_obis**

~~~sql
([obis_code]='2.8.0' OR [obis_code]='1.8.0')
~~~

**CK_TRANSFORMER_CURRENT_STATE_slot**

~~~sql
(datepart(minute,[reference_15_min])%(15)=(0) AND datepart(second,[reference_15_min])=(0))
~~~


### Keys and indexes

- `PK_TRANSFORMER_CURRENT_STATE` (PRIMARY KEY, CLUSTERED): state_id
- `UQ_TRANSFORMER_CURRENT_STATE_latest` (UNIQUE CONSTRAINT, NONCLUSTERED): transformer_id, obis_code

### Triggers

None.

---

## 23. TRANSFORMER_READING

Transformer-level measurements.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| transformer_reading_id | BIGINT | No | PK | IDENTITY |
| reading_timestamp | DATETIME2(0) | No | - | - |
| value | DECIMAL(18,4) | No | - | - |
| transformer_id | INT | No | FK | - |
| obis_code | VARCHAR(20) | No | FK | - |

### Foreign keys

- `FK_TRANSFORMER_READING_obis`: `obis_code` → `OBIS_CODE.obis_code`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_TRANSFORMER_READING_transformer`: `transformer_id` → `TRANSFORMER.transformer_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_TRANSFORMER_READING_slot**

~~~sql
(datepart(minute,[reading_timestamp])%(15)=(0) AND datepart(second,[reading_timestamp])=(0))
~~~


### Keys and indexes

- `PK_TRANSFORMER_READING` (PRIMARY KEY, CLUSTERED): transformer_reading_id
- `UQ_TRANSFORMER_READING_slot` (UNIQUE CONSTRAINT, NONCLUSTERED): transformer_id, obis_code, reading_timestamp

### Triggers

None.

---

## 24. USER_ACCOUNT

User identity, role and account information.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| user_id | INT | No | PK | IDENTITY |
| email | VARCHAR(255) | No | - | - |
| password_hash | VARBINARY(64) | No | - | - |
| password_salt | VARBINARY(16) | No | - | - |
| full_name | NVARCHAR(150) | No | - | - |
| phone | VARCHAR(20) | Yes | - | - |
| approval_status | VARCHAR(20) | No | - | ('APPROVED') |
| is_active | BIT | No | - | ((1)) |
| created_at | DATETIME2(0) | No | - | (sysutcdatetime()) |
| anonymized_at | DATETIME2(0) | Yes | - | - |
| iban | VARCHAR(34) | Yes | - | - |
| notify_email | BIT | No | - | ((1)) |
| notify_sms | BIT | No | - | ((0)) |
| birth_date | DATE | Yes | - | - |
| photo_path | VARCHAR(500) | Yes | - | - |
| specialty | NVARCHAR(100) | Yes | - | - |
| role_code | VARCHAR(20) | No | FK | - |
| organization_id | INT | Yes | FK | - |

### Foreign keys

- `FK_USER_ACCOUNT_organization`: `organization_id` → `ORGANIZATION.organization_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_USER_ACCOUNT_role`: `role_code` → `ROLE.role_code`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_USER_ACCOUNT_anonymized**

~~~sql
([anonymized_at] IS NULL OR [is_active]=(0))
~~~

**CK_USER_ACCOUNT_approval_status**

~~~sql
([approval_status]='SUSPENDED' OR [approval_status]='REJECTED' OR [approval_status]='APPROVED' OR [approval_status]='PENDING')
~~~

**CK_USER_ACCOUNT_email**

~~~sql
([email] like '%_@_%._%')
~~~

**CK_USER_ACCOUNT_iban**

~~~sql
([role_code]='CONSUMER' OR [iban] IS NULL)
~~~

**CK_USER_ACCOUNT_not_technician**

~~~sql
([role_code]='TECHNICIAN' OR [birth_date] IS NULL AND [photo_path] IS NULL AND [specialty] IS NULL)
~~~

**CK_USER_ACCOUNT_organization**

~~~sql
(([role_code]='AGGREGATOR' OR [role_code]='SUPPLIER') AND [organization_id] IS NOT NULL OR NOT ([role_code]='AGGREGATOR' OR [role_code]='SUPPLIER') AND [organization_id] IS NULL)
~~~

**CK_USER_ACCOUNT_technician**

~~~sql
([role_code]<>'TECHNICIAN' OR [birth_date] IS NOT NULL AND [photo_path] IS NOT NULL AND [specialty] IS NOT NULL)
~~~


### Keys and indexes

- `PK_USER_ACCOUNT` (PRIMARY KEY, CLUSTERED): user_id
- `UQ_USER_ACCOUNT_email` (UNIQUE CONSTRAINT, NONCLUSTERED): email

### Triggers

- `tr_USER_ACCOUNT_audit`
- `tr_USER_ACCOUNT_no_delete`

---

## 25. WORK_ORDER

Field operations and consumer service requests.

### Columns

| Column | Data type | Nullable | Key | Default / Other |
|---|---|---|---|---|
| work_order_id | INT | No | PK | IDENTITY |
| work_type | VARCHAR(20) | No | - | - |
| origin | VARCHAR(20) | No | - | - |
| description | NVARCHAR(1000) | Yes | - | - |
| status | VARCHAR(20) | No | - | ('SUBMITTED') |
| created_at | DATETIME2(0) | No | - | (sysutcdatetime()) |
| scheduled_start | DATETIME2(0) | Yes | - | - |
| scheduled_end | DATETIME2(0) | Yes | - | - |
| accepted_at | DATETIME2(0) | Yes | - | - |
| completed_at | DATETIME2(0) | Yes | - | - |
| findings | NVARCHAR(2000) | Yes | - | - |
| evidence_path | VARCHAR(500) | Yes | - | - |
| persons_to_notify | NVARCHAR(500) | Yes | - | - |
| requested_by_user_id | INT | No | FK | - |
| technician_user_id | INT | Yes | FK | - |
| premise_id | INT | Yes | FK | - |
| meter_id | INT | Yes | FK | - |
| event_id | BIGINT | Yes | FK | - |
| service_type_id | INT | Yes | FK | - |

### Foreign keys

- `FK_WORK_ORDER_event`: `event_id` → `EVENT.event_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_WORK_ORDER_meter`: `meter_id` → `METER.meter_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_WORK_ORDER_premise`: `premise_id` → `PREMISE.premise_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_WORK_ORDER_requested_by`: `requested_by_user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_WORK_ORDER_service_type`: `service_type_id` → `SERVICE_TYPE.service_type_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.
- `FK_WORK_ORDER_technician`: `technician_user_id` → `USER_ACCOUNT.user_id`. ON DELETE NO_ACTION; ON UPDATE NO_ACTION.

### CHECK constraints

**CK_WORK_ORDER_assigned**

~~~sql
([status]='CANCELLED' OR [status]='SUBMITTED' OR [technician_user_id] IS NOT NULL)
~~~

**CK_WORK_ORDER_completed**

~~~sql
([status]<>'COMPLETED' OR [completed_at] IS NOT NULL)
~~~

**CK_WORK_ORDER_event**

~~~sql
([origin]<>'EVENT' OR [event_id] IS NOT NULL)
~~~

**CK_WORK_ORDER_origin**

~~~sql
([origin]='OFFICER' OR [origin]='EVENT' OR [origin]='CONSUMER_REQUEST')
~~~

**CK_WORK_ORDER_schedule**

~~~sql
([scheduled_end] IS NULL OR [scheduled_start] IS NULL OR [scheduled_end]>=[scheduled_start])
~~~

**CK_WORK_ORDER_status**

~~~sql
([status]='CANCELLED' OR [status]='COMPLETED' OR [status]='IN_PROGRESS' OR [status]='ACCEPTED' OR [status]='ASSIGNED' OR [status]='SUBMITTED')
~~~

**CK_WORK_ORDER_target**

~~~sql
([premise_id] IS NOT NULL OR [meter_id] IS NOT NULL)
~~~

**CK_WORK_ORDER_type**

~~~sql
([work_type]='ANTI_TAMPER' OR [work_type]='FAULT_REPAIR' OR [work_type]='TECHNICAL_CHECK' OR [work_type]='REPLACEMENT' OR [work_type]='INSTALLATION')
~~~


### Keys and indexes

- `IX_WORK_ORDER_open` (INDEX, NONCLUSTERED): technician_user_id, status; INCLUDE scheduled_start, scheduled_end; WHERE ([status] IN ('ASSIGNED', 'ACCEPTED', 'IN_PROGRESS'))
- `PK_WORK_ORDER` (PRIMARY KEY, CLUSTERED): work_order_id

### Triggers

- `tr_WORK_ORDER_audit`
- `tr_WORK_ORDER_technician_guard`

---
