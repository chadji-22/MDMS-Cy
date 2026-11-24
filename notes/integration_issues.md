# Integration issues (24/11/2026) — for Kostis and Eliana

No page failed on real SQL Server 2022 (see evidence/C6-integration/pages.md). Open points, none blocking:

| Owner | File | What | Why it matters |
|---|---|---|---|
| Eliana | `data/*.dat`, `bulk_import.sql` (C4) | `NOTIFICATION.dat` does not exist and `bulk_import.sql` does not list the 25th table; not run in this proof | needed before E1 / E2 (bulk import on a clean DB) |
| Eliana | D6 | data dictionary: 25 tables, 24 triggers, 118 procedures | counts changed after B11 and Kostis's procedures |
| Kostis | `tests/audit_pages.php` | 15 "to review" hints (unescaped `$page + 1` style integer output, e.g. staff/technicians.php:51) | harmless integers, but he may want to cast or escape them |
| Both | 18 procedures not called by any page | e.g. sp_CancelBill, sp_ChangeSupplier, sp_CreateWorkOrder | fine if they are for tests / internal use; mention in the manual if a page is expected |
