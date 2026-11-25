# Integration issues (24/11/2026) — for Kostis and Eliana

No page failed on real SQL Server 2022 (see evidence/C6-integration/pages.md). Open points, none blocking:

| Owner | File | What | Why it matters |
|---|---|---|---|
| Eliana | `data/*.dat`, `bulk_import.sql` (C4) | C4 works on today's schema (re-checked 25/11, evidence/C4-recheck): all 24 files load. Only `NOTIFICATION` (0 rows in the demo data) is not in the list | optional: empty `NOTIFICATION.dat` + one line, so the script covers all 25 tables |
| Eliana | D6 | data dictionary: 25 tables, 24 triggers, 118 procedures | counts changed after B11 and Kostis's procedures |
| Kostis | `tests/audit_pages.php` | 15 "to review" hints (unescaped `$page + 1` style integer output, e.g. staff/technicians.php:51) | harmless integers, but he may want to cast or escape them |
| Both | 18 procedures not called by any page | e.g. sp_CancelBill, sp_ChangeSupplier, sp_CreateWorkOrder | fine if they are for tests / internal use; mention in the manual if a page is expected |
