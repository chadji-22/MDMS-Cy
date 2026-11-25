# Part (c) — Future Extension of the System

*MDMS-Cy — EPL342 Databases, Group 10.*

## 1. Extensible database design

MDMS-Cy was designed to accommodate future
requirements without requiring a complete
redesign of the relational database.

Configurable information is represented through
reference tables rather than separate columns
for every possible category.

Stored procedures provide controlled mechanisms
for introducing and updating reference entries.

New reference data can therefore be introduced
while preserving existing relationships,
historical records and integrity constraints.

## 2. Supported extension mechanisms

The following table describes how the future
extensions requested in the project specification
can be supported.

| Future extension | Implementation approach |
|---|---|
| New meter types | Insert a row into METER_TYPE through sp_UpsertMeterType. |
| New telemetry protocols | TELEMETRY_PACKET.network_type accepts free text. The CHECK constraint on METER.communication_type can be extended. |
| New prosumer classes | Extend the CHECK constraint on PREMISE.prosumer_scheme. |
| New VEE rules | Extend the validation logic in sp_RunVEE. METER_READING.vee_rule can store the new rule identifier. |
| New measured quantities | Insert a row into OBIS_CODE through sp_UpsertObisCode. |
| New services | Insert a row into SERVICE_TYPE through sp_UpsertServiceType. |
| New tariffs | Add the corresponding rows to TARIFF through the authorized procedures. |
| New event types | Introduce additional EVENT.event_type values, which are not restricted by a CHECK list. |

Most reference-data extensions require only
additional rows in existing tables.

Communication technologies and prosumer schemes
require changes to their CHECK constraints.

New validation rules or operational behavior may
require changes to stored procedures or application
logic, but not necessarily new database entities.

## 3. Worked example — UC-20

UC-20 in select.sql demonstrates administrative
operations and the extension of reference data.

Two examples are particularly relevant:

- Adding a reconnection service fee.
- Adding a new measured quantity.

Both are supported by the existing database
structure and authorized officer procedures.

## 4. Example A — New reconnection service

Assume that MDMS-Cy must support a new
reconnection service with a fee of EUR 15.

Instead of adding a new table or column,
the officer creates a reference entry in
SERVICE_TYPE.

The following commands are taken from UC-20
in select.sql.

~~~sql
SET @id = NULL;

SELECT @id = service_type_id
FROM dbo.SERVICE_TYPE
WHERE service_name = N'RECONNECTION_FEE';

EXEC dbo.sp_UpsertServiceType
    @off1,
    @id,
    N'RECONNECTION_FEE',
    15.00,
    1;
~~~

The lookup allows the procedure to update
an existing matching entry or create a new
entry when one does not exist.

The new service is represented by:

| Attribute | Value |
|---|---|
| Service name | RECONNECTION_FEE |
| Fee | EUR 15.00 |
| Active | Yes |

The existing service catalog can accommodate
the additional fee without adding a new
financial table or changing existing
payment relationships.

Implementing a complete new reconnection
workflow may still require additional
business logic.

## 5. Example B — New OBIS measured quantity

Assume that the system must recognize a new
measurement representing power factor.

The existing OBIS_CODE reference table
supports the definition of measured quantities.

UC-20 introduces the following entry:

~~~sql
EXEC dbo.sp_UpsertObisCode
    @off1,
    '13.7.0',
    N'Power factor',
    '-',
    'INSTANTANEOUS',
    0,
    1;
~~~

The new measurement is represented by:

| Attribute | Value |
|---|---|
| OBIS code | 13.7.0 |
| Description | Power factor |
| Unit | Dimensionless (-) |
| Measurement type | INSTANTANEOUS |
| Minimum | 0 |
| Maximum | 1 |

The existing meter reading model associates
measurements with OBIS codes.

Consequently, the new measurement does not
require a dedicated power factor column in
METER_READING.

Additional validation or reporting logic
can be introduced where necessary.

## 6. Extension through the web application

Authorized system officers can manage
reference data through the Catalogs page.

To introduce a supported reference entry:

1. Log in as a System Officer.
2. Open Catalogs.
3. Select the appropriate reference catalog.
4. Enter the required attributes.
5. Press Add entry.

Existing entries can also be edited through
the corresponding catalog controls.

The web application calls the relevant
stored procedures rather than directly
modifying the reference tables.

Manual scenario E-11 verified the addition
of a service type and an OBIS code through
the local web application.

## 7. Benefits and limitations

The adopted design provides:

- Reduced need for structural database changes.
- Centralized validation and authorization.
- Reuse of existing relationships and procedures.
- Compatibility with existing historical records.
- Controlled management of reference data.

However, extensibility does not imply that
every future requirement can be implemented
without code changes.

New operational workflows, validation rules
and specialized reports may require additional
procedures or application functionality.

Requirements involving new relationships,
such as complete tenant history, may require
new database entities.

## 8. Conclusion

MDMS-Cy supports future extension through
configurable reference data and reusable
relational structures.

UC-20 demonstrates that a new service and a
new measured quantity can be introduced
without changing the structure of the
existing tables.

This provides a flexible foundation for
future electricity metering requirements
while maintaining the integrity of the
existing system.

## References within the project

- project.pdf, p.13
- REPORT.md, section 6.6
- select.sql, UC-20
- create.sql
- procedures_11_admin.sql
- TESTING_PLAN.md, E-11
- sources/public/staff/catalogs.php
