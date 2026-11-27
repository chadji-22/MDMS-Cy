# Technician, Officer and Administrator — User Manual

*Section of the MDMS-Cy user manual. Tasks B5 and B6.*

The technician area supports field operations, meter
installation and document submission.

System officers manage approvals, work orders,
remote commands, GDPR requests and reference catalogs.

System administrators manage accounts, organizations,
audit information and system statistics.

All times are expressed in UTC.

| Role | Demo account |
|---|---|
| Technician | tech1@mdms.cy |
| System Officer | officer1@mdms.cy |
| Second Officer | officer2@mdms.cy |
| Administrator | admin@mdms.cy |

Demo password: Passw0rd!23

---

# Part A — Technician

## 1. Availability

**Purpose.** Define the dates, times and districts
in which a technician is available for assignments.

**Procedures.** sp_GetMyAvailability,
sp_SetAvailability, sp_DeleteAvailability.

1. Log in as a technician.
2. Open **Availability**.
3. Select a date.
4. Enter the start and end times in UTC.
5. Select the district.
6. Press **Save availability**.

The saved slot appears under **My availability**.

Existing slots can be updated or removed using
the available controls, subject to database rules.

![Technician availability](img/tech_01_availability.png){width=4.6in}

![Saved availability slots](img/tech_01b_saved_slots.png){width=4.6in}

## 2. My jobs

**Purpose.** View assigned work orders, scheduled
visits and geographical coordinates.

**Procedure.** sp_ListMyWorkOrders.

1. Open **My jobs**.
2. Locate the assigned work order.
3. Review its type, status, location and scheduled visit.
4. Open the work order number to view its details.

The available actions depend on the current status.

| Action | Result |
|---|---|
| Accept | ASSIGNED to ACCEPTED |
| Decline | ASSIGNED to SUBMITTED |
| Start | ACCEPTED to IN_PROGRESS |
| Complete | IN_PROGRESS to COMPLETED |

A reason must be provided when declining a job.
Findings must be entered when completing a job.
Additional information may be required depending
on the work order type.

The database prevents invalid state transitions.

![Assigned work orders](img/tech_02_my_jobs.png){width=4.6in}

![Work order in progress](img/tech_02b_job_in_progress.png){width=4.6in}

## 3. Work order history

**Purpose.** Review the previous actions and results
of an assigned job.

**Procedure.** sp_GetWorkOrderHistory.

1. Open **My jobs**.
2. Select a work order number.
3. Review its description, status and scheduled visit.
4. Read the **History** table.

The history contains timestamps, actions,
previous states, new states and comments.

Completed jobs also display their findings.

![Technician work order history](img/tech_03_job_history.png){width=4.6in}

## 4. Meter installation

**Purpose.** Register a smart meter during an
installation work order.

1. Accept an installation job.
2. Start the job.
3. Select **Register meter**.
4. Enter the required meter information, including
   serial number, network identifier, meter type,
   firmware, communication technology and coordinates.
5. Submit the registration.

The system can determine the transformer from the
meter coordinates when automatic assignment is used.

The newly registered meter remains PENDING until
the required certificates are approved and an
officer confirms the meter.

![Registered smart meter](img/tech_04_meter_registered.png){width=4.6in}

## 5. Meter certificates

1. Open **Meter certificates** from the installation job.
2. Select the required certificate type.
3. Enter the certificate information.
4. Upload the corresponding PDF.
5. Repeat for all three required certificates.

The certificates cover calibration, CE compliance
and encryption certification.

Uploaded certificates await officer approval.
Uploading certificates does not automatically
activate the meter.

![Uploaded meter certificates](img/tech_05_meter_certificates.png){width=4.6in}

## 6. My documents

**Purpose.** Submit the documents required for
technician approval.

**Procedures.** sp_AddTechnicianDocument,
sp_ListMyDocuments, sp_ResubmitDocument,
sp_ResubmitTechnician.

1. Open **My documents**.
2. Select the document type.
3. Enter its document number and issue date.
4. Enter the expiry date if applicable.
5. Select a PDF file, up to 2 MB.
6. Press **Upload document**.

Submitted documents are initially PENDING.

| Status | Meaning |
|---|---|
| PENDING | Waiting for officer review |
| APPROVED | Accepted by an officer |
| REJECTED | Must be corrected or resubmitted |

For a rejected document, use **Send again** to
provide the corrected file and dates.

An unapproved technician cannot undertake
normal field assignments.

![Technician documents](img/tech_06_my_documents.png){width=4.6in}

![Resubmitted document](img/tech_06b_resubmitted.png){width=4.6in}

---

# Part B — System Officer

## 7. Technician approvals

**Purpose.** Review technician applications and
their supporting documents.

1. Open **Technician approvals**.
2. Select a pending technician or enter the technician ID.
3. Review the application and submitted documents.
4. Approve or reject individual documents.
5. Provide a decision comment where applicable.
6. Complete the technician approval process when
   all required conditions are satisfied.

A rejected document can be resubmitted by the
technician for further review.

![Technician approval](img/officer_01_technician_approvals.png){width=4.6in}

![Document review](img/officer_01b_document_review.png){width=4.6in}

## 8. Meter approvals

**Purpose.** Review newly registered meters and
their supporting certificates.

1. Open **Meter approvals**.
2. Select a pending meter or enter its meter ID.
3. Review the meter information.
4. Inspect the submitted certificates.
5. Approve or reject the certificates.
6. Confirm the meter when all requirements are met.

A confirmed meter becomes ACTIVE.

The database prevents activation when the three
required certificates have not been approved.

![Approved and activated meter](img/officer_02_meter_approvals.png){width=4.6in}

## 9. Work orders

**Purpose.** View work orders and assign available
technicians to submitted requests.

**Procedures.** sp_ListWorkOrders,
sp_FindAvailableTechnicians, sp_AssignWorkOrder,
sp_GetWorkOrderHistory.

1. Open **Work orders**.
2. Select a submitted work order.
3. Enter the visit date, start time and end time.
4. Press **Find technicians**.
5. Select an available technician.
6. Press **Assign**.

The work order becomes ASSIGNED.

Only available technicians satisfying the relevant
district and scheduling conditions can be selected.

The officer can also review the work order history
and the findings of completed jobs.

The database prevents two officers from assigning
the same submitted work order concurrently.

This behaviour was verified in concurrency test C5.3.

![Work order assignment](img/officer_03_work_orders.png){width=4.6in}

![Officer work order history](img/officer_04_work_order_history.png){width=4.6in}

## 10. Remote commands

**Purpose.** Review and dispatch remote meter commands.

**Procedures.** sp_ListCommands,
sp_DecideRemoteCommand, sp_DispatchCommands,
sp_SimulateCommandAcknowledgment.

1. Open **Remote commands**.
2. Filter commands by status if required.
3. Select a command awaiting approval.
4. Approve or reject the command.
5. Dispatch the approved command.
6. Simulate acknowledgment for the dispatched command.

The page displays the command status, attempt
information and history.

The demonstration supports simulated acknowledgment;
it does not require a physical smart meter connection.

![Remote command acknowledgment](img/officer_05_remote_commands.png){width=4.6in}

## 11. GDPR review

**Purpose.** Review privacy and retention requests
using independent officer approvals.

**Procedures.** sp_ListGdprRequests,
sp_AdvanceGdprRequest.

1. Open **GDPR review**.
2. Select a submitted request.
3. Review the request and enter a comment.
4. Move the request through the review process.
5. Pre-approve it using the first officer account.
6. Log in using a different officer account.
7. Give the final approval.

The same officer cannot perform both approval stages.

The review history records the decisions,
timestamps and responsible officers.

Approval and execution are separate stages.

![GDPR request approval](img/officer_06_gdpr_review.png){width=4.6in}

![Same-officer approval rejected](img/officer_06b_same_officer_denied.png){width=4.6in}

![GDPR review history](img/officer_06c_review_history.png){width=4.6in}

## 12. Catalogs

**Purpose.** Manage configurable reference data
without changing the database schema.

The available catalogs include:

- Meter types.
- Service types.
- OBIS codes.
- Tariffs.

1. Open **Catalogs**.
2. Select the appropriate catalog.
3. Enter the required values under **Add entry**.
4. Press **Add entry**.

To modify an existing entry, select **Edit**,
change its values and press **Save changes**.

Catalog entries allow the system to support new
meter types, services and measurements without
structural database changes.

![Service type catalog](img/officer_07_catalogs.png){width=4.6in}

![OBIS code catalog](img/officer_07b_obis.png){width=4.6in}

---

# Part C — System Administrator

## 13. Accounts and organizations

**Purpose.** Create authorized staff accounts,
organizations and organization accounts.

**Procedures.** sp_CreateStaffUser,
sp_CreateOrganization, sp_CreateOrganizationUser,
sp_ListOrganizations.

### Create staff account

Enter the full name, email, initial password,
optional phone number and an authorized staff role.

Press **Create staff account**.

### Create organization

Enter the organization name and select its type.

Press **Create organization**.

### Create organization account

Select an existing organization and enter the
required account information.

Press **Create organization account**.

The current page provides creation forms and
organization selection. It does not provide a
complete account management listing.

![Create staff account](img/admin_01_accounts.png){width=4.6in}

![Create organization](img/admin_01b_organization.png){width=4.6in}

![Create organization account](img/admin_01c_organization_account.png){width=4.6in}

## 14. Audit log

**Purpose.** Review recorded system activity.

Open **Audit log** to inspect recorded actions,
including account logins, document decisions,
meter activation and work order state changes.

The audit log supports traceability of critical
operations by recording the responsible actor,
time, action and relevant state changes.

![System audit log](img/admin_02_audit_log.png){width=4.6in}

## 15. System statistics

**Purpose.** Review system-wide operational reports.

**Procedure.** sp_ReportSystemStatistics.

1. Open **Statistics**.
2. Enter the starting date.
3. Enter the ending date, which is exclusive.
4. Press **Run report**.

The report includes information about meters,
readings, VEE processing, billing, work orders
and recorded events.

These reports help administrators and officers
monitor the operation of the system.

![System statistics](img/admin_03_statistics.png){width=4.6in}

---

# Access control and testing

Protected pages require an authenticated user
with the appropriate role.

Database procedures independently enforce
authorization and business rules.

Manual testing results for these pages are
documented in TESTING_PLAN.md, scenarios E-01
through E-13.

Concurrency testing evidence is available
in evidence/C5/.

The officer work order history was corrected
and verified locally in commit c54b11c.

The local automatic test suites passed.
Remaining deployment checks and manual testing
limitations are recorded in TESTING_PLAN.md.
