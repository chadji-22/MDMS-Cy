# System Limitations and Future Improvements

*MDMS-Cy — EPL342 Databases, Group 10.*

## 1. Introduction

The current implementation supports the main
operational requirements of MDMS-Cy.

However, several design decisions and limitations
remain due to the project scope, infrastructure
restrictions and implementation complexity.

This section identifies these limitations and
proposes possible future improvements.

## 2. Technician specialties

**Current limitation.**

Each technician has one recorded specialty.

This limits the representation of technicians
with multiple technical qualifications.

**Proposed improvement.**

Introduce a specialty reference table and a
many-to-many relationship between technicians
and specialties.

Work order assignment could then consider
multiple qualifications.

## 3. Work order evidence

**Current limitation.**

Each work order supports one evidence file.

Complex field operations may require several
photographs, reports or supporting documents.

**Proposed improvement.**

Introduce a WORK_ORDER_ATTACHMENT entity linked
to the corresponding work order.

Each attachment could record its type, upload
timestamp, uploader and storage path.

## 4. Supplier and tenant history

**Current limitation.**

Historical supplier information is preserved
through issued bills, but there is no complete
supplier change history.

The system does not maintain a separate tenant
history for each premise.

**Proposed improvement.**

Introduce historical relationships with
effective start and end dates.

This would support accurate reconstruction
of supplier and occupancy changes while
respecting data protection requirements.

## 5. Geographical representation

**Current limitation.**

Transformer geofences are represented as
rectangular geographical areas.

Rectangles cannot accurately represent every
irregular geographical boundary.

**Proposed improvement.**

Support general geographical polygons.

Spatial validation should also detect invalid
boundaries and manage overlapping areas.

The existing Leaflet interface could display
these more detailed geographical regions.

## 6. Event lifecycle

**Current limitation.**

Events do not have a dedicated closed state.

The grid overview identifies recent critical
events using a 24-hour time window.

This does not distinguish all unresolved
incidents from incidents that have been resolved.

**Proposed improvement.**

Introduce an event lifecycle with statuses
such as OPEN, UNDER_REVIEW and CLOSED.

Record the responsible user, resolution
timestamp and resolution comments.

## 7. Email and SMS notifications

**Current limitation.**

Consumers can select notification preferences
and the system records threshold notifications.

However, the demonstration environment does
not connect to a real email or SMS gateway.

Notifications are marked as SIMULATED rather
than incorrectly reported as delivered.

**Proposed improvement.**

Integrate external email and SMS providers.

A background delivery service could process
pending notifications, record delivery results
and retry temporary failures.

Delivery credentials must be stored securely
outside the public web application.

## 8. Partial installation and removal days

**Current limitation.**

Daily finalization requires a complete set
of 96 fifteen-minute energy readings.

The day on which a meter is installed or
removed may therefore remain unfinalized.

Consequently, the energy associated with that
partial day is not included in billing.

**Proposed improvement.**

Support partial-day aggregation based on
the meter's actual installation and removal
timestamps.

Validation should distinguish genuinely
missing readings from intervals in which
the meter was not in service.

Billing should include only the validated
energy of the applicable service interval.

## 9. University database capacity

**Current limitation.**

The course database environment has documented
storage and transaction log restrictions.

The constrained environment was limited to
approximately 27 MB of data and 12 MB of log.

These restrictions limit large-scale testing
and can affect repeated database operations.

**Proposed improvement.**

Use a production environment with appropriately
sized data and transaction log files.

Introduce capacity monitoring, database
maintenance and suitable backup procedures.

Large-scale performance testing should continue
on an isolated SQL Server environment.

## 10. Remote meter communication

**Current limitation.**

Remote command acknowledgments can be simulated
through the demonstration interface.

The project does not establish a live connection
to physical smart meters for command execution.

**Proposed improvement.**

Integrate a real device communication gateway.

The gateway should support authenticated
communication, command delivery, acknowledgments
and controlled retries.

The existing command state machine and audit
history provide a foundation for this extension.

## 11. Security improvements

The existing security mechanisms include
role-based authorization, restricted database
access, salted password hashing, parameterized
procedure calls and session protection.

The following improvements are proposed.

### 11.1 Database connection privileges

Use a dedicated application login with only
the required database permissions.

Alternatively, prevent reversal of the
restricted execution context using the
appropriate SQL Server mechanism.

### 11.2 Password hashing

Replace the fast SHA2-512 password hash with
a dedicated password hashing algorithm such
as Argon2id or bcrypt.

This would improve resistance to offline
password guessing if credential data were
compromised.

### 11.3 Session management

Invalidate other authenticated sessions when
a user's password is changed.

### 11.4 Uploaded files

Introduce malware scanning before accepting
uploaded documents and evidence files.

### 11.5 Aggregated data privacy

The minimum group size reduces direct
disclosure of household-level data.

However, differences between overlapping
aggregate queries may reveal individual values.

Future improvements could include stricter
query controls and privacy-preserving
aggregation policies.

Further security details are documented
separately in security_D9.md.

## 12. Administration interface

**Current limitation.**

The Accounts and organizations page supports
account creation and organization creation.

It does not provide a complete account
management listing.

**Proposed improvement.**

Provide searchable, paginated account and
organization listings with authorized
management operations.

All changes should continue to be performed
through stored procedures and recorded in
the audit trail.

## 13. Priorities for future development

| Improvement | Proposed priority |
|---|---|
| Dedicated application database login | High |
| Partial-day energy billing | High |
| Real notification delivery | High |
| Secure device communication | High |
| Stronger password hashing | High |
| Historical supplier and tenant records | Medium |
| Event lifecycle management | Medium |
| Multiple technician specialties | Medium |
| Multiple work order attachments | Medium |
| Complete account management interface | Medium |
| General polygon geofences | Medium |

These priorities are proposed for future
development and do not represent completed
project functionality.

## 14. Conclusion

The current MDMS-Cy implementation provides
a foundation for electricity metering,
operational workflows and network monitoring.

The identified limitations provide clear
directions for further development.

Future improvements should preserve the
existing principles of data integrity,
authorization, traceability and extensibility.

## References within the project

- REPORT.md, section 7.4
- PROJECT_STATUS_AND_CHECKLIST.md
- TESTING_PLAN.md
- docx/src/security_D9.md
- docx/src/manual_consumer.md
- docx/src/manual_technician_staff.md
- deploy/DEPLOY.md
