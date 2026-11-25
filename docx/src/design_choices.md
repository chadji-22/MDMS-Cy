# Design Choices, Extra Functions and Implementation Difficulties

*MDMS-Cy — EPL342 Databases, Group 10.*

## 1. Database-centered architecture

MDMS-Cy was designed around a relational database
implemented in Microsoft SQL Server.

The web application is responsible for presenting
information, collecting user input and maintaining
authenticated sessions.

The database is responsible for business rules,
authorization, validation, transactions and
data integrity.

PHP pages communicate with the database through
stored procedures using bound parameters.

The restricted application database role does not
have direct access to modify or query the tables.

This approach centralizes the business logic and
prevents different application pages from implementing
inconsistent versions of the same rules.

## 2. Relational database design

The database separates users, premises, meters,
transformers, readings, work orders, payments,
documents and other operational information into
related entities.

Primary keys identify individual records.
Foreign keys maintain relationships between entities.
CHECK constraints enforce permitted values, while
unique constraints and indexes prevent invalid
duplicate records.

A single USER_ACCOUNT entity represents the
different user roles.

Role-specific permissions are enforced through
the application and the stored procedures.

This avoids unnecessary duplication of account
information across separate user tables.

## 3. State machines

Several entities represent operational workflows
rather than independent records.

Their status values describe the current stage
of each workflow.

### 3.1 Work orders

A normal work order follows the sequence:

SUBMITTED → ASSIGNED → ACCEPTED →
IN_PROGRESS → COMPLETED.

Alternative transitions support cancellation and
technician refusal where permitted.

When a technician declines an assigned job,
the work order returns to SUBMITTED so that an
officer can assign another technician.

The expected previous status is checked before
the update takes place.

This prevents users from skipping required stages
or modifying a work order that has already been
processed by another user.

### 3.2 Meter approval

New meters are initially PENDING.

The technician registers the meter and submits
the required supporting certificates.

An officer reviews the certificates before
confirming the meter.

The database prevents activation when the required
certificates have not been approved.

### 3.3 Technician approval

Technician applications and supporting documents
are reviewed by authorized officers.

Rejected documents can be corrected and resubmitted.

The approval conditions must be satisfied before
the technician can undertake normal field operations.

### 3.4 Remote commands

Remote commands are reviewed before dispatch.

The normal successful sequence includes approval,
dispatch and acknowledgment.

Command attempts and results are recorded so that
the progress of a command remains traceable.

Acknowledgments can be simulated in the
demonstration environment.

### 3.5 GDPR requests

A GDPR request follows the sequence:

SUBMITTED → UNDER_REVIEW → PRE_APPROVED →
APPROVED → EXECUTED.

Rejection is supported during the review process
where permitted.

The final approval must be performed by an officer
different from the officer who provided the
pre-approval.

This separation of responsibilities prevents one
officer from independently approving a sensitive
privacy operation.

## 4. Transactions and concurrency

Operations involving multiple related changes
are implemented using transactions.

The implementation uses XACT_ABORT, TRY/CATCH,
rollback and THROW to maintain atomicity.

If an operation fails, its incomplete changes
are rolled back.

Guarded updates verify the expected previous state.

Row locks and application locks are used where
concurrent operations could cause inconsistent
results.

The concurrency scenarios were verified using
two independent SQL Server Management Studio sessions.

| Scenario | Protection | Observed result |
|---|---|---|
| Concurrent bill payments | Bill row locking and state validation | Only one full payment was recorded |
| Concurrent VEE execution | Exclusive application lock per meter | The competing execution timed out |
| Concurrent work order assignment | Transaction and guarded state update | The first assignment was preserved |

All three C5 scenarios passed.

The detailed results and screenshots are available
in evidence/C5/.

## 5. Audit trail

Critical system actions must remain traceable.

The AUDIT_LOG table stores information about
operational changes, including the responsible
actor, timestamp, affected object and relevant
previous and new values.

Audit triggers record changes automatically.

The internal logging procedure supports additional
application and database events.

Examples include:

- Work order assignment and completion.
- Technician and document decisions.
- Meter activation and technical changes.
- Remote command attempts.
- GDPR review stages.
- Account login activity.

The audit trail supports accountability and
investigation of operational problems.

Sensitive credentials must not be included
in audit records.

## 6. Immutability and data integrity

Some records must remain unchanged once they
represent finalized historical information.

Database triggers enforce important integrity
rules independently of the web interface.

Finalized readings and aggregates cannot be
modified through ordinary operational updates.

The audit log is append-only.

Financial and user records are protected against
unauthorized deletion.

Privacy operations follow controlled anonymization
and retention procedures.

When a reading is corrected before finalization,
its original value and correction information
are retained.

This preserves the history of the measurement
and supports later investigation.

## 7. Telemetry and VEE design

Telemetry packets are retained even when they
cannot be matched or processed successfully.

Incoming readings are associated with standardized
15-minute time slots.

The VEE process validates readings, identifies
suspect measurements and estimates missing values.

Suspect readings can be reviewed by authorized
operators before finalization.

Verified daily, monthly and yearly aggregates
allow historical reports to use stored summaries
instead of repeatedly processing raw readings.

Transformer aggregates support hierarchical
network monitoring.

This design separates raw measurements,
validation results and finalized information.

## 8. Row-based extensibility

The system uses reference tables for information
that may change or expand in the future.

Examples include:

| Reference table | Extension |
|---|---|
| METER_TYPE | Additional meter models |
| OBIS_CODE | New measured quantities |
| SERVICE_TYPE | New chargeable services |
| TARIFF | Additional tariff definitions |

Authorized officers can manage reference entries
through the Catalogs pages.

Adding a supported reference entry does not
require a new table or column.

For example, UC-20 demonstrates adding a new
service type and a new OBIS code.

Some categories, such as communication technology
and prosumer schemes, are controlled by CHECK
constraints.

Extending those categories requires updating the
relevant constraint, but not redesigning the
relational structure.

Future extension is described separately in
the D10 documentation.

## 9. Additional implemented functions

### 9.1 Interactive geographical map

The application provides a Leaflet map displaying
meter locations and transformer geofences.

The geographical data originates from the database.

This supports visual inspection of the electrical
network and its geographical organization.

### 9.2 Notification records

Consumers can configure notification preferences
for consumption threshold alerts.

The system records notification information
for the selected channels.

Email and SMS delivery are simulated because
the demonstration installation does not include
a real messaging gateway.

### 9.3 System statistics and audit review

Administration pages provide operational
statistics and access to audit information.

Reports include information about service fees,
work orders, events and other system activity.

### 9.4 Synthetic data generation

The database includes sp_GenerateSyntheticData,
which creates synthetic consumers, meters and
measurement data.

This supports repeatable testing with larger
datasets independently of the small demonstration
dataset.

### 9.5 Automated testing

The project includes SQL tests, demonstration
scenarios and PHP application tests.

The tests cover business rules, permissions,
input handling, authentication and navigation.

Manual concurrency testing complements these
automated checks.

### 9.6 Deployment and installation

A deployment archive and installation script
support installation on the department web server.

A local container-based development environment
supports independent testing without modifying
the shared demonstration database.

## 10. Difficulties and solutions

### 10.1 University database capacity

The team encountered database capacity
restrictions on the course SQL Server.

The documented limits of the constrained
environment were approximately 27 MB for
the data file and 12 MB for the transaction log.

Large datasets could not be accommodated,
and repeated builds could fill the transaction log.

A local SQL Server environment was used for
larger datasets, independent testing and
performance-related work.

The university database was retained for
the demonstration environment.

### 10.2 Fifteen-minute timestamp calculation

The fn_Floor15 function associates a timestamp
with the beginning of its 15-minute slot.

A difficulty was identified for timestamps
before the reference date of 2000-01-01.

Integer division in T-SQL truncates toward zero,
which can produce an incorrect result for
negative offsets.

The function was corrected using normalized
modulo arithmetic:

    @m - ((@m % 15) + 15) % 15

This correctly rounds the timestamp down
to its slot, including negative offsets.

Dedicated tests K1 and K2 verify this behavior.

### 10.3 Monthly aggregation and meter replacement

The original month-closing rule required every
day of a calendar month to be finalized.

A meter installed or replaced during a month
could therefore never satisfy this condition.

The rule was changed so that a month closes
when every full day during which the meter
was in service has been finalized.

This allows monthly aggregation and billing
for meters installed or replaced mid-month.

The partial installation or removal day remains
a known limitation.

### 10.4 Historical data access

Testing identified an access-control issue when
a meter had readings outside its installation
period.

A consumer could incorrectly access some past
measurements without purchasing historical access.

The access check was corrected to cover every
meter with data in the requested time window.

### 10.5 Data export and import

The university SQL login did not have the
permissions required for BULK INSERT.

The required command-line tools were also
not initially available on every development PC.

Data export and bulk-import verification were
therefore performed using a local SQL Server
environment with the necessary permissions.

### 10.6 T-SQL procedure arguments

Some expressions could not be passed directly
as arguments to EXEC.

Intermediate variables were introduced to
calculate the values before the procedure call.

### 10.7 Web application deployment

The department web server required specific
directory permissions and deployment paths.

Only the public application directory is
exposed through the web server.

Database credentials are entered through the
Connect page instead of being stored in
a readable server configuration file.

### 10.8 Local file upload permissions

During technician registration and document
testing, the local PHP container initially
could not write to the upload directories.

The required directories were created with
permissions allowing the PHP process to
store the uploaded files.

The private upload directories remain outside
the public web root.

### 10.9 Officer work order history

Manual test E-08 identified that the officer
work order page did not display the full
work order history and findings.

The page was updated to retrieve the authorized
history through sp_GetWorkOrderHistory and
display the available findings and history.

The correction was verified locally and
committed as c54b11c.

The remaining deployment verification is
recorded in TESTING_PLAN.md.

## 11. Conclusion

The design prioritizes data integrity,
traceability, authorization and extensibility.

Database-level enforcement reduces dependence
on the web interface for critical business rules.

Transactions, guarded state transitions,
audit records and integrity triggers support
consistent operational behavior.

The implementation difficulties identified during
development and testing were used to improve
the system and document its remaining limitations.

## References within the project

- project.pdf
- REPORT.md, sections 3, 6 and 7
- PROJECT_STATUS_AND_CHECKLIST.md
- create.sql
- functions.sql
- triggers.sql
- security.sql
- Stored procedure modules
- TESTING_PLAN.md
- C5_SSMS_demo.md
- evidence/C5/README.md
- sources/README.md
- deploy/DEPLOY.md
