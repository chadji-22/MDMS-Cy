# B11 — Notifications (simulated): evidence

[project.pdf §1.2 p.6: the consumer sets consumption thresholds and chooses to be notified by email or SMS]

## What was built (agreed with Ioannis 22/11/2026: a real record in a new table)
| Object | File | Role |
|---|---|---|
| table `NOTIFICATION` (channel, recipient, status, message, event_id, user_id, created_at; UQ event+channel; FK to EVENT `ON DELETE CASCADE`) | `create.sql`, `drop.sql` | the record of each delivery attempt |
| trigger `tr_EVENT_notify` (TR23) | `triggers.sql` | on every `THRESHOLD_EXCEEDED` event (from TR21 or `sp_CheckConsumptionThresholds`), one row per channel the owner switched on, in the same transaction |
| procedure `sp_ListMyNotifications` | `procedures_02_consumer.sql` | the consumer's list (own premises only, 50002 otherwise) |
| `sp_ExecuteGdprRequest` step 4 | `procedures_09_gdpr.sql` | right to be forgotten erases the stored recipient [§1.4 p.6] |
| index `IX_NOTIFICATION_user` | `indexes.sql` | the consumer's list |
| events page, "Notifications" section | `sources/public/consumer/events.php` | shows channel, address, **SIMULATED** status, message, event |

**Status values:** `SIMULATED` (no gateway is connected; nothing leaves the system), `FAILED` (SMS chosen but no phone
number). `SENT` exists in the CHECK for a future real gateway and is never written by this code.
Limit for the manual: email / SMS are not really sent; a real gateway would read the SIMULATED rows and mark them SENT.

## Proof
- `demo_threshold_notification.sql` → `demo_threshold_notification_output.txt`: as `mdms_php`, consumer8 sets 5 kWh,
  the officer job raises `THRESHOLD_EXCEEDED` for October (60.42 kWh), TR23 records EMAIL + SMS, both `SIMULATED`.
- `events_simulated_notifications.png`: the same, on consumer8's events page.
- `tests.sql` section M (M1–M6): both channels → 2 SIMULATED rows with the right recipients and no SENT; both off → none;
  SMS without phone → FAILED; consumer list; other premise → 50002; M6 runs the real right-to-be-forgotten flow
  (submit, review, pre-approve, approval by a second officer, execute) in a rolled-back transaction and checks the
  stored recipient is erased. Mutation check: with `io`'s `sp_ExecuteGdprRequest` (no step 4) M6 FAILS (recipient
  still there); with the B11 version it passes.
  Run on `ichara09` after an additive deploy, with the C1 data present: **82/82 PASS**; telemetry tests **26/26 PASS**; `select.sql` UC-01…UC-20 no error.
- `sources/tests/consumer_pages.sh`: 53/53 (read-only part), including the notifications section and the 50002 refusal.

Not yet run: `build_all.sql` twice on a fresh database (the rebuild of the shared DB needs Ioannis's go-ahead).
