# B3 — Consumer pages: evidence

Run on 22/11/2026 against the course database `ichara09` (small data set of `import.sql`), web app in the
`mdms-php-dev` container (PHP 8.3 + sqlsrv), connection running as `mdms_php` (EXECUTE only).

## Pages (all in `sources/public/consumer/`, guard `Auth::requireRole('CONSUMER')`, procedures only)

| Page | Spec | Procedures | Screenshot |
|---|---|---|---|
| `index.php` My premises (list, add) | §1.1 p.5 | `sp_ListMyPremises`, `sp_ListSuppliers`, `sp_AddPremise` | `01_premises.png` |
| `readings.php` 15-min readings, prosumer import/export side by side | §1.2 p.5 | `sp_GetPremiseReadings` | `02_readings_prosumer.png` |
| same, past month not bought → reason shown, no empty table | §1.2 p.6 | `sp_GetPremiseReadings` (50008) | `03_readings_hidden_50008.png` |
| `aggregates.php` daily / monthly / yearly totals | §1.2 p.6 | `sp_GetPremiseAggregates` | `04_totals_daily.png` |
| `history.php` price and purchase of past months | §1.2 p.6 | `sp_GetHistoricalAccessQuote`, `sp_BuyHistoricalAccess`, `sp_GetMyBillsAndPayments` | `05_past_data_quote.png` |
| `events.php` voltage / threshold events, threshold, email/SMS preference | §1.2 p.5-6 | `sp_GetPremiseEvents`, `sp_SetPremiseThreshold`, `sp_GetMyProfile`, `sp_UpdateMyProfile` | `06_events.png` |
| `requests.php` / `request.php` check & fault requests, status and history, cancel | §1.3 p.6 | `sp_SubmitServiceRequest`, `sp_ListMyWorkOrders`, `sp_GetWorkOrderHistory`, `sp_CancelWorkOrder` | `07_requests.png`, `07b_request_history.png` |
| `bills.php` bills, pay bill, pay service fee, payment history | §1.3 p.6 | `sp_GetMyBillsAndPayments`, `sp_PayBill`, `sp_ListServiceTypes`, `sp_PayServiceFee` | `08_bills.png` |
| `gdpr.php` right to be forgotten / retention reduction, stages | §1.4 p.6-7 | `sp_SubmitGdprRequest`, `sp_ListGdprRequests` | `09_gdpr.png` |
| wrong role (officer on a consumer page) → 403 | Κοινές αρχές p.5; §IV p.13 | `Auth::requireRole` | `10_wrong_role_403.png` |

## Automated check

`sources/tests/consumer_pages.sh` (curl). `consumer_pages_run.txt` is the full run with `WRITE=1`:
**61 passed, 0 failed** — no-session redirects, 403 for officer / technician / DSO / supplier, every page as consumer2,
prosumer import/export, 50008 message with the reason, 50002 for another consumer's premise, 50004 for a bad postal
code and for a window > 31 days, CSRF refusal, and the write flows (threshold, preferences, request + cancel,
service fee, retention-limited purchase refused, purchase accepted, GDPR request).

B1 tests after the change: `tests/smoke.sh` all passed; `tests/errors_test.php` all passed with `APP_DEBUG=0`
(its "hides the SQL text" case fails by design when the container runs with `APP_DEBUG=1`, also on `io` without B3).

## Large data set (C1)
After C1 (`evidence/C1`, batch SYN2) the read-only part was run again: **59 / 59** (`consumer_pages_run_readonly_large.txt`).
The 8 extra checks log in as the synthetic prosumer `syn2_000004@synthetic.cy` and show the **current month free** rule
with real rows (no purchase): readings with import / export side by side, daily totals of the current month (the 21/11 row
comes from the VEE + finalize run of C1), and every page opens.
Screenshots: `11_large_set_readings_current_month.png`, `12_large_set_totals_current_month.png`.

Screenshots were rendered with headless Chrome from the pages' real HTML (same CSS); times are UTC.
