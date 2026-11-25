---
title: "MDMS-Cy — User Manual"
subtitle: "Meter Data Management System for Cyprus"
author: "Group 10 — EPL342 Databases"
date: "December 2026"
lang: en
---

# 1. Introduction

MDMS-Cy is a Meter Data Management System designed
to support electricity metering, telemetry processing,
meter installation, service requests, billing and
network monitoring.

The system consists of a Microsoft SQL Server database
and a web application implemented using PHP, HTML,
CSS and the Microsoft SQLSRV driver.

The application supports eight user roles with different
responsibilities and access permissions.

# 2. System requirements

- Microsoft SQL Server 2025 or 2022.
- PHP version 8.0 or later.
- Microsoft SQLSRV extension for PHP.
- Microsoft ODBC Driver 17 or 18.
- Apache web server or equivalent PHP hosting.
- A modern web browser.
- University VPN when required for remote access.

# 3. Database installation

The database must be initialized before the application
can be used.

1. Connect to the appropriate SQL Server instance using
   SQL Server Management Studio or sqlcmd.
2. Select the database assigned to the project.
3. Execute build_all.sql according to the repository
   instructions.
4. Verify that the database tables, views, functions,
   triggers, stored procedures and indexes were created.
5. Verify that the demonstration dataset is available.

The build script also configures the restricted
application database user, mdms_php.

WARNING: The build script replaces existing MDMS-Cy
objects and data. Never rebuild the shared demonstration
database without coordinating with the team.

# 4. Web application installation

## 4.1 University deployment

The application can be deployed on the University
of Cyprus department web server.

The SQL Server instance used for the demonstration is:

    mssql.cs.ucy.ac.cy\SQL2025

The shared demonstration database is ichara09.

Installation steps:

1. Upload deploy/mdms-app.zip and deploy/install.sh
   to the home directory of the university Linux account.
2. Connect to a department Linux machine.
3. Execute:

       bash ~/install.sh

4. Open:

       https://students.cs.ucy.ac.cy/~<login>/mdms/

The installation script configures the required file
permissions, application folders and public symbolic link.

For complete installation and troubleshooting
instructions, refer to deploy/DEPLOY.md.

## 4.2 Local development and testing

The application can also run locally using Podman
or Docker and a separate SQL Server database.

The development image includes Apache, PHP,
the SQLSRV driver and the required ODBC driver.

Build the database locally and configure the web
container using the database connection settings.

The application can then be accessed at:

    http://localhost:8080/

Detailed configuration instructions are provided
in sources/README.md.

Tests that modify data must use a separate local
database rather than the shared demonstration database.

# 5. Connecting and logging in

On the university deployment, the Connect page
appears before the application login page.

1. Enter the database name.
2. Enter the SQL Server username.
3. Enter the SQL Server password.
4. Connect to the database.
5. Log in with an MDMS-Cy account.

The database credentials and the MDMS-Cy account
credentials are separate.

Database passwords must never be stored in the
repository or in server configuration files.

# 6. Demonstration accounts

The following accounts are provided by the demonstration
dataset imported through import.sql.

| Role | Demo account |
|---|---|
| Consumer | consumer1@example.cy |
| Technician | tech1@mdms.cy |
| System Officer | officer1@mdms.cy |
| Second System Officer | officer2@mdms.cy |
| System Administrator | admin@mdms.cy |
| Distribution System Operator | dso@mdms.cy |
| Transmission System Operator | tso@mdms.cy |
| Electricity Supplier | billing@eacsupply.cy |
| Aggregator | desk@flexpool.cy |

The demonstration password for these accounts is:

    Passw0rd!23

These credentials are intended only for the
demonstration dataset.

# 7. Navigation and access control

After a successful login, the navigation menu displays
the functions available to the current user role.

Users cannot access protected pages belonging
to unauthorized roles.

The database also verifies permissions and ownership
when executing stored procedures.

The application provides:

- Home page and role-specific navigation.
- My profile and password management.
- Role-specific operational pages.
- Log out functionality.

Logging out of an MDMS-Cy account keeps the database
connection on the university deployment.

Selecting Disconnect removes the database connection
from the session.

# 8. Common messages

| Message | Meaning |
|---|---|
| Login failed | Invalid account credentials or unavailable account. |
| Permission denied | The operation is not permitted for this user. |
| Access denied | The current role cannot access the requested page. |
| Invalid input | A supplied value is missing or invalid. |
| Duplicate | The requested operation conflicts with existing data. |
| Busy | Another operation is currently using the required resource. |
| The form is no longer valid | Reload the page and submit again. |
| Service problem | An unexpected database or server problem occurred. |

After repeated unsuccessful login attempts, a temporary
login restriction is applied.

Unexpected database errors are displayed using a neutral
message and a reference identifier when debug mode
is disabled.

# 9. Organization of the user manual

The following sections describe the application
from the perspective of each user role.

| Section | Markdown source |
|---|---|
| Consumer | manual_consumer.md |
| Technician, Officer and Administrator | manual_technician_staff.md |
| Supplier and Aggregator | manual_supplier.md |
| DSO, TSO and Map | manual_dso_tso.md |
| Design choices and implementation | design_choices.md |
| Database structure and data dictionary | data_dictionary.md |
| Limitations and future improvements | limits_improvements.md |

Each role-specific section explains the available
operations, required inputs, expected results
and relevant screenshots.

All timestamps are expressed in UTC unless
explicitly stated otherwise.
