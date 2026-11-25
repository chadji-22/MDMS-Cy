# C6 page matrix (real SQL Server 2022, fresh build)

59 pages x 8 roles + anonymous = 531 requests, 0 failed.

| page | role | HTTP | expected | result | note |
|---|---|---|---|---|---|
| account/documents.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Faccount%2Fdocuments.php |
| account/documents.php | CONSUMER | 403 | 403 | OK |  |
| account/documents.php | TECHNICIAN | 200 | allowed | OK |  |
| account/documents.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| account/documents.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| account/documents.php | DSO | 403 | 403 | OK |  |
| account/documents.php | TSO | 403 | 403 | OK |  |
| account/documents.php | SUPPLIER | 403 | 403 | OK |  |
| account/documents.php | AGGREGATOR | 403 | 403 | OK |  |
| account/password.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Faccount%2Fpassword.php |
| account/password.php | CONSUMER | 200 | allowed | OK |  |
| account/password.php | TECHNICIAN | 200 | allowed | OK |  |
| account/password.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| account/password.php | SYSTEM_ADMIN | 200 | allowed | OK |  |
| account/password.php | DSO | 200 | allowed | OK |  |
| account/password.php | TSO | 200 | allowed | OK |  |
| account/password.php | SUPPLIER | 200 | allowed | OK |  |
| account/password.php | AGGREGATOR | 200 | allowed | OK |  |
| account/photo.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Faccount%2Fphoto.php |
| account/photo.php | CONSUMER | 403 | 403 | OK |  |
| account/photo.php | TECHNICIAN | 404 | allowed | OK |  |
| account/photo.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| account/photo.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| account/photo.php | DSO | 403 | 403 | OK |  |
| account/photo.php | TSO | 403 | 403 | OK |  |
| account/photo.php | SUPPLIER | 403 | 403 | OK |  |
| account/photo.php | AGGREGATOR | 403 | 403 | OK |  |
| account/profile.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Faccount%2Fprofile.php |
| account/profile.php | CONSUMER | 200 | allowed | OK |  |
| account/profile.php | TECHNICIAN | 200 | allowed | OK |  |
| account/profile.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| account/profile.php | SYSTEM_ADMIN | 200 | allowed | OK |  |
| account/profile.php | DSO | 200 | allowed | OK |  |
| account/profile.php | TSO | 200 | allowed | OK |  |
| account/profile.php | SUPPLIER | 200 | allowed | OK |  |
| account/profile.php | AGGREGATOR | 200 | allowed | OK |  |
| consumer/aggregates.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fconsumer%2Faggregates.php |
| consumer/aggregates.php | CONSUMER | 200 | allowed | OK |  |
| consumer/aggregates.php | TECHNICIAN | 403 | 403 | OK |  |
| consumer/aggregates.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| consumer/aggregates.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| consumer/aggregates.php | DSO | 403 | 403 | OK |  |
| consumer/aggregates.php | TSO | 403 | 403 | OK |  |
| consumer/aggregates.php | SUPPLIER | 403 | 403 | OK |  |
| consumer/aggregates.php | AGGREGATOR | 403 | 403 | OK |  |
| consumer/bills.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fconsumer%2Fbills.php |
| consumer/bills.php | CONSUMER | 200 | allowed | OK |  |
| consumer/bills.php | TECHNICIAN | 403 | 403 | OK |  |
| consumer/bills.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| consumer/bills.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| consumer/bills.php | DSO | 403 | 403 | OK |  |
| consumer/bills.php | TSO | 403 | 403 | OK |  |
| consumer/bills.php | SUPPLIER | 403 | 403 | OK |  |
| consumer/bills.php | AGGREGATOR | 403 | 403 | OK |  |
| consumer/events.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fconsumer%2Fevents.php |
| consumer/events.php | CONSUMER | 200 | allowed | OK |  |
| consumer/events.php | TECHNICIAN | 403 | 403 | OK |  |
| consumer/events.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| consumer/events.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| consumer/events.php | DSO | 403 | 403 | OK |  |
| consumer/events.php | TSO | 403 | 403 | OK |  |
| consumer/events.php | SUPPLIER | 403 | 403 | OK |  |
| consumer/events.php | AGGREGATOR | 403 | 403 | OK |  |
| consumer/gdpr.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fconsumer%2Fgdpr.php |
| consumer/gdpr.php | CONSUMER | 200 | allowed | OK |  |
| consumer/gdpr.php | TECHNICIAN | 403 | 403 | OK |  |
| consumer/gdpr.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| consumer/gdpr.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| consumer/gdpr.php | DSO | 403 | 403 | OK |  |
| consumer/gdpr.php | TSO | 403 | 403 | OK |  |
| consumer/gdpr.php | SUPPLIER | 403 | 403 | OK |  |
| consumer/gdpr.php | AGGREGATOR | 403 | 403 | OK |  |
| consumer/history.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fconsumer%2Fhistory.php |
| consumer/history.php | CONSUMER | 200 | allowed | OK |  |
| consumer/history.php | TECHNICIAN | 403 | 403 | OK |  |
| consumer/history.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| consumer/history.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| consumer/history.php | DSO | 403 | 403 | OK |  |
| consumer/history.php | TSO | 403 | 403 | OK |  |
| consumer/history.php | SUPPLIER | 403 | 403 | OK |  |
| consumer/history.php | AGGREGATOR | 403 | 403 | OK |  |
| consumer/index.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fconsumer%2Findex.php |
| consumer/index.php | CONSUMER | 200 | allowed | OK |  |
| consumer/index.php | TECHNICIAN | 403 | 403 | OK |  |
| consumer/index.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| consumer/index.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| consumer/index.php | DSO | 403 | 403 | OK |  |
| consumer/index.php | TSO | 403 | 403 | OK |  |
| consumer/index.php | SUPPLIER | 403 | 403 | OK |  |
| consumer/index.php | AGGREGATOR | 403 | 403 | OK |  |
| consumer/readings.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fconsumer%2Freadings.php |
| consumer/readings.php | CONSUMER | 200 | allowed | OK |  |
| consumer/readings.php | TECHNICIAN | 403 | 403 | OK |  |
| consumer/readings.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| consumer/readings.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| consumer/readings.php | DSO | 403 | 403 | OK |  |
| consumer/readings.php | TSO | 403 | 403 | OK |  |
| consumer/readings.php | SUPPLIER | 403 | 403 | OK |  |
| consumer/readings.php | AGGREGATOR | 403 | 403 | OK |  |
| consumer/request.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fconsumer%2Frequest.php |
| consumer/request.php | CONSUMER | 200 | allowed | OK | alert: Work order not found. |
| consumer/request.php | TECHNICIAN | 403 | 403 | OK |  |
| consumer/request.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| consumer/request.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| consumer/request.php | DSO | 403 | 403 | OK |  |
| consumer/request.php | TSO | 403 | 403 | OK |  |
| consumer/request.php | SUPPLIER | 403 | 403 | OK |  |
| consumer/request.php | AGGREGATOR | 403 | 403 | OK |  |
| consumer/requests.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fconsumer%2Frequests.php |
| consumer/requests.php | CONSUMER | 200 | allowed | OK |  |
| consumer/requests.php | TECHNICIAN | 403 | 403 | OK |  |
| consumer/requests.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| consumer/requests.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| consumer/requests.php | DSO | 403 | 403 | OK |  |
| consumer/requests.php | TSO | 403 | 403 | OK |  |
| consumer/requests.php | SUPPLIER | 403 | 403 | OK |  |
| consumer/requests.php | AGGREGATOR | 403 | 403 | OK |  |
| dso/events.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fdso%2Fevents.php |
| dso/events.php | CONSUMER | 403 | 403 | OK |  |
| dso/events.php | TECHNICIAN | 403 | 403 | OK |  |
| dso/events.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| dso/events.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| dso/events.php | DSO | 200 | allowed | OK |  |
| dso/events.php | TSO | 200 | allowed | OK |  |
| dso/events.php | SUPPLIER | 403 | 403 | OK |  |
| dso/events.php | AGGREGATOR | 403 | 403 | OK |  |
| dso/finalize.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fdso%2Ffinalize.php |
| dso/finalize.php | CONSUMER | 403 | 403 | OK |  |
| dso/finalize.php | TECHNICIAN | 403 | 403 | OK |  |
| dso/finalize.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| dso/finalize.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| dso/finalize.php | DSO | 200 | allowed | OK |  |
| dso/finalize.php | TSO | 403 | 403 | OK |  |
| dso/finalize.php | SUPPLIER | 403 | 403 | OK |  |
| dso/finalize.php | AGGREGATOR | 403 | 403 | OK |  |
| dso/index.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fdso%2Findex.php |
| dso/index.php | CONSUMER | 403 | 403 | OK |  |
| dso/index.php | TECHNICIAN | 403 | 403 | OK |  |
| dso/index.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| dso/index.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| dso/index.php | DSO | 200 | allowed | OK |  |
| dso/index.php | TSO | 403 | 403 | OK |  |
| dso/index.php | SUPPLIER | 403 | 403 | OK |  |
| dso/index.php | AGGREGATOR | 403 | 403 | OK |  |
| dso/ingest.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fdso%2Fingest.php |
| dso/ingest.php | CONSUMER | 403 | 403 | OK |  |
| dso/ingest.php | TECHNICIAN | 403 | 403 | OK |  |
| dso/ingest.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| dso/ingest.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| dso/ingest.php | DSO | 200 | allowed | OK |  |
| dso/ingest.php | TSO | 403 | 403 | OK |  |
| dso/ingest.php | SUPPLIER | 403 | 403 | OK |  |
| dso/ingest.php | AGGREGATOR | 403 | 403 | OK |  |
| dso/reports.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fdso%2Freports.php |
| dso/reports.php | CONSUMER | 403 | 403 | OK |  |
| dso/reports.php | TECHNICIAN | 403 | 403 | OK |  |
| dso/reports.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| dso/reports.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| dso/reports.php | DSO | 200 | allowed | OK |  |
| dso/reports.php | TSO | 403 | 403 | OK |  |
| dso/reports.php | SUPPLIER | 403 | 403 | OK |  |
| dso/reports.php | AGGREGATOR | 403 | 403 | OK |  |
| dso/suspects.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fdso%2Fsuspects.php |
| dso/suspects.php | CONSUMER | 403 | 403 | OK |  |
| dso/suspects.php | TECHNICIAN | 403 | 403 | OK |  |
| dso/suspects.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| dso/suspects.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| dso/suspects.php | DSO | 200 | allowed | OK |  |
| dso/suspects.php | TSO | 403 | 403 | OK |  |
| dso/suspects.php | SUPPLIER | 403 | 403 | OK |  |
| dso/suspects.php | AGGREGATOR | 403 | 403 | OK |  |
| dso/vee.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fdso%2Fvee.php |
| dso/vee.php | CONSUMER | 403 | 403 | OK |  |
| dso/vee.php | TECHNICIAN | 403 | 403 | OK |  |
| dso/vee.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| dso/vee.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| dso/vee.php | DSO | 200 | allowed | OK |  |
| dso/vee.php | TSO | 403 | 403 | OK |  |
| dso/vee.php | SUPPLIER | 403 | 403 | OK |  |
| dso/vee.php | AGGREGATOR | 403 | 403 | OK |  |
| home.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fhome.php |
| home.php | CONSUMER | 200 | allowed | OK |  |
| home.php | TECHNICIAN | 200 | allowed | OK |  |
| home.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| home.php | SYSTEM_ADMIN | 200 | allowed | OK |  |
| home.php | DSO | 200 | allowed | OK |  |
| home.php | TSO | 200 | allowed | OK |  |
| home.php | SUPPLIER | 200 | allowed | OK |  |
| home.php | AGGREGATOR | 200 | allowed | OK |  |
| index.php | (anonymous) | 303 | any (public page) | OK | /home.php |
| index.php | CONSUMER | 303 | any (public page) | OK | /home.php |
| index.php | TECHNICIAN | 303 | any (public page) | OK | /home.php |
| index.php | SYSTEM_OFFICER | 303 | any (public page) | OK | /home.php |
| index.php | SYSTEM_ADMIN | 303 | any (public page) | OK | /home.php |
| index.php | DSO | 303 | any (public page) | OK | /home.php |
| index.php | TSO | 303 | any (public page) | OK | /home.php |
| index.php | SUPPLIER | 303 | any (public page) | OK | /home.php |
| index.php | AGGREGATOR | 303 | any (public page) | OK | /home.php |
| login.php | (anonymous) | 200 | any (public page) | OK |  |
| login.php | CONSUMER | 303 | any (public page) | OK | /home.php |
| login.php | TECHNICIAN | 303 | any (public page) | OK | /home.php |
| login.php | SYSTEM_OFFICER | 303 | any (public page) | OK | /home.php |
| login.php | SYSTEM_ADMIN | 303 | any (public page) | OK | /home.php |
| login.php | DSO | 303 | any (public page) | OK | /home.php |
| login.php | TSO | 303 | any (public page) | OK | /home.php |
| login.php | SUPPLIER | 303 | any (public page) | OK | /home.php |
| login.php | AGGREGATOR | 303 | any (public page) | OK | /home.php |
| market/api/day-ahead.php | (anonymous) | 401 | any (public page) | OK |  |
| market/api/day-ahead.php | CONSUMER | 403 | any (public page) | OK |  |
| market/api/day-ahead.php | TECHNICIAN | 403 | any (public page) | OK |  |
| market/api/day-ahead.php | SYSTEM_OFFICER | 403 | any (public page) | OK |  |
| market/api/day-ahead.php | SYSTEM_ADMIN | 403 | any (public page) | OK |  |
| market/api/day-ahead.php | DSO | 403 | any (public page) | OK |  |
| market/api/day-ahead.php | TSO | 403 | any (public page) | OK |  |
| market/api/day-ahead.php | SUPPLIER | 200 | any (public page) | OK |  |
| market/api/day-ahead.php | AGGREGATOR | 200 | any (public page) | OK |  |
| market/api/intraday.php | (anonymous) | 401 | any (public page) | OK |  |
| market/api/intraday.php | CONSUMER | 403 | any (public page) | OK |  |
| market/api/intraday.php | TECHNICIAN | 403 | any (public page) | OK |  |
| market/api/intraday.php | SYSTEM_OFFICER | 403 | any (public page) | OK |  |
| market/api/intraday.php | SYSTEM_ADMIN | 403 | any (public page) | OK |  |
| market/api/intraday.php | DSO | 403 | any (public page) | OK |  |
| market/api/intraday.php | TSO | 403 | any (public page) | OK |  |
| market/api/intraday.php | SUPPLIER | 200 | any (public page) | OK |  |
| market/api/intraday.php | AGGREGATOR | 200 | any (public page) | OK |  |
| market/api/portfolio.php | (anonymous) | 401 | any (public page) | OK |  |
| market/api/portfolio.php | CONSUMER | 403 | any (public page) | OK |  |
| market/api/portfolio.php | TECHNICIAN | 403 | any (public page) | OK |  |
| market/api/portfolio.php | SYSTEM_OFFICER | 403 | any (public page) | OK |  |
| market/api/portfolio.php | SYSTEM_ADMIN | 403 | any (public page) | OK |  |
| market/api/portfolio.php | DSO | 403 | any (public page) | OK |  |
| market/api/portfolio.php | TSO | 403 | any (public page) | OK |  |
| market/api/portfolio.php | SUPPLIER | 200 | any (public page) | OK |  |
| market/api/portfolio.php | AGGREGATOR | 200 | any (public page) | OK |  |
| market/bills.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fmarket%2Fbills.php |
| market/bills.php | CONSUMER | 403 | 403 | OK |  |
| market/bills.php | TECHNICIAN | 403 | 403 | OK |  |
| market/bills.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| market/bills.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| market/bills.php | DSO | 403 | 403 | OK |  |
| market/bills.php | TSO | 403 | 403 | OK |  |
| market/bills.php | SUPPLIER | 200 | allowed | OK |  |
| market/bills.php | AGGREGATOR | 403 | 403 | OK |  |
| market/data.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fmarket%2Fdata.php |
| market/data.php | CONSUMER | 403 | 403 | OK |  |
| market/data.php | TECHNICIAN | 403 | 403 | OK |  |
| market/data.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| market/data.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| market/data.php | DSO | 403 | 403 | OK |  |
| market/data.php | TSO | 403 | 403 | OK |  |
| market/data.php | SUPPLIER | 200 | allowed | OK |  |
| market/data.php | AGGREGATOR | 200 | allowed | OK |  |
| market/day-ahead.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fmarket%2Fday-ahead.php |
| market/day-ahead.php | CONSUMER | 403 | 403 | OK |  |
| market/day-ahead.php | TECHNICIAN | 403 | 403 | OK |  |
| market/day-ahead.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| market/day-ahead.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| market/day-ahead.php | DSO | 403 | 403 | OK |  |
| market/day-ahead.php | TSO | 403 | 403 | OK |  |
| market/day-ahead.php | SUPPLIER | 200 | allowed | OK |  |
| market/day-ahead.php | AGGREGATOR | 200 | allowed | OK |  |
| market/index.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fmarket%2Findex.php |
| market/index.php | CONSUMER | 403 | 403 | OK |  |
| market/index.php | TECHNICIAN | 403 | 403 | OK |  |
| market/index.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| market/index.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| market/index.php | DSO | 403 | 403 | OK |  |
| market/index.php | TSO | 403 | 403 | OK |  |
| market/index.php | SUPPLIER | 200 | allowed | OK |  |
| market/index.php | AGGREGATOR | 200 | allowed | OK |  |
| market/intraday.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fmarket%2Fintraday.php |
| market/intraday.php | CONSUMER | 403 | 403 | OK |  |
| market/intraday.php | TECHNICIAN | 403 | 403 | OK |  |
| market/intraday.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| market/intraday.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| market/intraday.php | DSO | 403 | 403 | OK |  |
| market/intraday.php | TSO | 403 | 403 | OK |  |
| market/intraday.php | SUPPLIER | 200 | allowed | OK |  |
| market/intraday.php | AGGREGATOR | 200 | allowed | OK |  |
| register-technician.php | (anonymous) | 200 | any (public page) | OK |  |
| register-technician.php | CONSUMER | 303 | any (public page) | OK | /home.php |
| register-technician.php | TECHNICIAN | 303 | any (public page) | OK | /home.php |
| register-technician.php | SYSTEM_OFFICER | 303 | any (public page) | OK | /home.php |
| register-technician.php | SYSTEM_ADMIN | 303 | any (public page) | OK | /home.php |
| register-technician.php | DSO | 303 | any (public page) | OK | /home.php |
| register-technician.php | TSO | 303 | any (public page) | OK | /home.php |
| register-technician.php | SUPPLIER | 303 | any (public page) | OK | /home.php |
| register-technician.php | AGGREGATOR | 303 | any (public page) | OK | /home.php |
| register.php | (anonymous) | 200 | any (public page) | OK |  |
| register.php | CONSUMER | 303 | any (public page) | OK | /home.php |
| register.php | TECHNICIAN | 303 | any (public page) | OK | /home.php |
| register.php | SYSTEM_OFFICER | 303 | any (public page) | OK | /home.php |
| register.php | SYSTEM_ADMIN | 303 | any (public page) | OK | /home.php |
| register.php | DSO | 303 | any (public page) | OK | /home.php |
| register.php | TSO | 303 | any (public page) | OK | /home.php |
| register.php | SUPPLIER | 303 | any (public page) | OK | /home.php |
| register.php | AGGREGATOR | 303 | any (public page) | OK | /home.php |
| staff/accounts.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Faccounts.php |
| staff/accounts.php | CONSUMER | 403 | 403 | OK |  |
| staff/accounts.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/accounts.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| staff/accounts.php | SYSTEM_ADMIN | 200 | allowed | OK |  |
| staff/accounts.php | DSO | 403 | 403 | OK |  |
| staff/accounts.php | TSO | 403 | 403 | OK |  |
| staff/accounts.php | SUPPLIER | 403 | 403 | OK |  |
| staff/accounts.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/audit.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Faudit.php |
| staff/audit.php | CONSUMER | 403 | 403 | OK |  |
| staff/audit.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/audit.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| staff/audit.php | SYSTEM_ADMIN | 200 | allowed | OK |  |
| staff/audit.php | DSO | 403 | 403 | OK |  |
| staff/audit.php | TSO | 403 | 403 | OK |  |
| staff/audit.php | SUPPLIER | 403 | 403 | OK |  |
| staff/audit.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/catalogs.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Fcatalogs.php |
| staff/catalogs.php | CONSUMER | 403 | 403 | OK |  |
| staff/catalogs.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/catalogs.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| staff/catalogs.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| staff/catalogs.php | DSO | 403 | 403 | OK |  |
| staff/catalogs.php | TSO | 403 | 403 | OK |  |
| staff/catalogs.php | SUPPLIER | 403 | 403 | OK |  |
| staff/catalogs.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/gdpr.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Fgdpr.php |
| staff/gdpr.php | CONSUMER | 403 | 403 | OK |  |
| staff/gdpr.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/gdpr.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| staff/gdpr.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| staff/gdpr.php | DSO | 403 | 403 | OK |  |
| staff/gdpr.php | TSO | 403 | 403 | OK |  |
| staff/gdpr.php | SUPPLIER | 403 | 403 | OK |  |
| staff/gdpr.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/index.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Findex.php |
| staff/index.php | CONSUMER | 403 | 403 | OK |  |
| staff/index.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/index.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| staff/index.php | SYSTEM_ADMIN | 200 | allowed | OK |  |
| staff/index.php | DSO | 403 | 403 | OK |  |
| staff/index.php | TSO | 403 | 403 | OK |  |
| staff/index.php | SUPPLIER | 403 | 403 | OK |  |
| staff/index.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/meter-review.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Fmeter-review.php |
| staff/meter-review.php | CONSUMER | 403 | 403 | OK |  |
| staff/meter-review.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/meter-review.php | SYSTEM_OFFICER | 400 | allowed | OK |  |
| staff/meter-review.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| staff/meter-review.php | DSO | 403 | 403 | OK |  |
| staff/meter-review.php | TSO | 403 | 403 | OK |  |
| staff/meter-review.php | SUPPLIER | 403 | 403 | OK |  |
| staff/meter-review.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/meters.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Fmeters.php |
| staff/meters.php | CONSUMER | 403 | 403 | OK |  |
| staff/meters.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/meters.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| staff/meters.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| staff/meters.php | DSO | 403 | 403 | OK |  |
| staff/meters.php | TSO | 403 | 403 | OK |  |
| staff/meters.php | SUPPLIER | 403 | 403 | OK |  |
| staff/meters.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/remote-commands.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Fremote-commands.php |
| staff/remote-commands.php | CONSUMER | 403 | 403 | OK |  |
| staff/remote-commands.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/remote-commands.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| staff/remote-commands.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| staff/remote-commands.php | DSO | 403 | 403 | OK |  |
| staff/remote-commands.php | TSO | 403 | 403 | OK |  |
| staff/remote-commands.php | SUPPLIER | 403 | 403 | OK |  |
| staff/remote-commands.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/statistics.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Fstatistics.php |
| staff/statistics.php | CONSUMER | 403 | 403 | OK |  |
| staff/statistics.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/statistics.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| staff/statistics.php | SYSTEM_ADMIN | 200 | allowed | OK |  |
| staff/statistics.php | DSO | 403 | 403 | OK |  |
| staff/statistics.php | TSO | 403 | 403 | OK |  |
| staff/statistics.php | SUPPLIER | 403 | 403 | OK |  |
| staff/statistics.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/technician-review.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Ftechnician-review.php |
| staff/technician-review.php | CONSUMER | 403 | 403 | OK |  |
| staff/technician-review.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/technician-review.php | SYSTEM_OFFICER | 400 | allowed | OK |  |
| staff/technician-review.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| staff/technician-review.php | DSO | 403 | 403 | OK |  |
| staff/technician-review.php | TSO | 403 | 403 | OK |  |
| staff/technician-review.php | SUPPLIER | 403 | 403 | OK |  |
| staff/technician-review.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/technicians.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Ftechnicians.php |
| staff/technicians.php | CONSUMER | 403 | 403 | OK |  |
| staff/technicians.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/technicians.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| staff/technicians.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| staff/technicians.php | DSO | 403 | 403 | OK |  |
| staff/technicians.php | TSO | 403 | 403 | OK |  |
| staff/technicians.php | SUPPLIER | 403 | 403 | OK |  |
| staff/technicians.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/work-order.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Fwork-order.php |
| staff/work-order.php | CONSUMER | 403 | 403 | OK |  |
| staff/work-order.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/work-order.php | SYSTEM_OFFICER | 400 | allowed | OK |  |
| staff/work-order.php | SYSTEM_ADMIN | 400 | allowed | OK |  |
| staff/work-order.php | DSO | 403 | 403 | OK |  |
| staff/work-order.php | TSO | 403 | 403 | OK |  |
| staff/work-order.php | SUPPLIER | 403 | 403 | OK |  |
| staff/work-order.php | AGGREGATOR | 403 | 403 | OK |  |
| staff/work-orders.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Fstaff%2Fwork-orders.php |
| staff/work-orders.php | CONSUMER | 403 | 403 | OK |  |
| staff/work-orders.php | TECHNICIAN | 403 | 403 | OK |  |
| staff/work-orders.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| staff/work-orders.php | SYSTEM_ADMIN | 200 | allowed | OK |  |
| staff/work-orders.php | DSO | 403 | 403 | OK |  |
| staff/work-orders.php | TSO | 403 | 403 | OK |  |
| staff/work-orders.php | SUPPLIER | 403 | 403 | OK |  |
| staff/work-orders.php | AGGREGATOR | 403 | 403 | OK |  |
| technician/availability.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftechnician%2Favailability.php |
| technician/availability.php | CONSUMER | 403 | 403 | OK |  |
| technician/availability.php | TECHNICIAN | 200 | allowed | OK |  |
| technician/availability.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| technician/availability.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| technician/availability.php | DSO | 403 | 403 | OK |  |
| technician/availability.php | TSO | 403 | 403 | OK |  |
| technician/availability.php | SUPPLIER | 403 | 403 | OK |  |
| technician/availability.php | AGGREGATOR | 403 | 403 | OK |  |
| technician/index.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftechnician%2Findex.php |
| technician/index.php | CONSUMER | 403 | 403 | OK |  |
| technician/index.php | TECHNICIAN | 200 | allowed | OK |  |
| technician/index.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| technician/index.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| technician/index.php | DSO | 403 | 403 | OK |  |
| technician/index.php | TSO | 403 | 403 | OK |  |
| technician/index.php | SUPPLIER | 403 | 403 | OK |  |
| technician/index.php | AGGREGATOR | 403 | 403 | OK |  |
| technician/install-meter.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftechnician%2Finstall-meter.php |
| technician/install-meter.php | CONSUMER | 403 | 403 | OK |  |
| technician/install-meter.php | TECHNICIAN | 400 | allowed | OK |  |
| technician/install-meter.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| technician/install-meter.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| technician/install-meter.php | DSO | 403 | 403 | OK |  |
| technician/install-meter.php | TSO | 403 | 403 | OK |  |
| technician/install-meter.php | SUPPLIER | 403 | 403 | OK |  |
| technician/install-meter.php | AGGREGATOR | 403 | 403 | OK |  |
| technician/job.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftechnician%2Fjob.php |
| technician/job.php | CONSUMER | 403 | 403 | OK |  |
| technician/job.php | TECHNICIAN | 400 | allowed | OK |  |
| technician/job.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| technician/job.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| technician/job.php | DSO | 403 | 403 | OK |  |
| technician/job.php | TSO | 403 | 403 | OK |  |
| technician/job.php | SUPPLIER | 403 | 403 | OK |  |
| technician/job.php | AGGREGATOR | 403 | 403 | OK |  |
| technician/meter-certificates.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftechnician%2Fmeter-certificates.php |
| technician/meter-certificates.php | CONSUMER | 403 | 403 | OK |  |
| technician/meter-certificates.php | TECHNICIAN | 400 | allowed | OK |  |
| technician/meter-certificates.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| technician/meter-certificates.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| technician/meter-certificates.php | DSO | 403 | 403 | OK |  |
| technician/meter-certificates.php | TSO | 403 | 403 | OK |  |
| technician/meter-certificates.php | SUPPLIER | 403 | 403 | OK |  |
| technician/meter-certificates.php | AGGREGATOR | 403 | 403 | OK |  |
| tso/frequency.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftso%2Ffrequency.php |
| tso/frequency.php | CONSUMER | 403 | 403 | OK |  |
| tso/frequency.php | TECHNICIAN | 403 | 403 | OK |  |
| tso/frequency.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| tso/frequency.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| tso/frequency.php | DSO | 200 | allowed | OK |  |
| tso/frequency.php | TSO | 200 | allowed | OK |  |
| tso/frequency.php | SUPPLIER | 403 | 403 | OK |  |
| tso/frequency.php | AGGREGATOR | 403 | 403 | OK |  |
| tso/index.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftso%2Findex.php |
| tso/index.php | CONSUMER | 403 | 403 | OK |  |
| tso/index.php | TECHNICIAN | 403 | 403 | OK |  |
| tso/index.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| tso/index.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| tso/index.php | DSO | 403 | 403 | OK |  |
| tso/index.php | TSO | 200 | allowed | OK |  |
| tso/index.php | SUPPLIER | 403 | 403 | OK |  |
| tso/index.php | AGGREGATOR | 403 | 403 | OK |  |
| tso/map-data.php | (anonymous) | 401 | any (public page) | OK |  |
| tso/map-data.php | CONSUMER | 403 | any (public page) | OK |  |
| tso/map-data.php | TECHNICIAN | 403 | any (public page) | OK |  |
| tso/map-data.php | SYSTEM_OFFICER | 200 | any (public page) | OK |  |
| tso/map-data.php | SYSTEM_ADMIN | 200 | any (public page) | OK |  |
| tso/map-data.php | DSO | 200 | any (public page) | OK |  |
| tso/map-data.php | TSO | 200 | any (public page) | OK |  |
| tso/map-data.php | SUPPLIER | 403 | any (public page) | OK |  |
| tso/map-data.php | AGGREGATOR | 403 | any (public page) | OK |  |
| tso/map.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftso%2Fmap.php |
| tso/map.php | CONSUMER | 403 | 403 | OK |  |
| tso/map.php | TECHNICIAN | 403 | 403 | OK |  |
| tso/map.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| tso/map.php | SYSTEM_ADMIN | 200 | allowed | OK |  |
| tso/map.php | DSO | 200 | allowed | OK |  |
| tso/map.php | TSO | 200 | allowed | OK |  |
| tso/map.php | SUPPLIER | 403 | 403 | OK |  |
| tso/map.php | AGGREGATOR | 403 | 403 | OK |  |
| tso/shedding.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftso%2Fshedding.php |
| tso/shedding.php | CONSUMER | 403 | 403 | OK |  |
| tso/shedding.php | TECHNICIAN | 403 | 403 | OK |  |
| tso/shedding.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| tso/shedding.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| tso/shedding.php | DSO | 403 | 403 | OK |  |
| tso/shedding.php | TSO | 200 | allowed | OK |  |
| tso/shedding.php | SUPPLIER | 403 | 403 | OK |  |
| tso/shedding.php | AGGREGATOR | 403 | 403 | OK |  |
| tso/state.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftso%2Fstate.php |
| tso/state.php | CONSUMER | 403 | 403 | OK |  |
| tso/state.php | TECHNICIAN | 403 | 403 | OK |  |
| tso/state.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| tso/state.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| tso/state.php | DSO | 200 | allowed | OK |  |
| tso/state.php | TSO | 200 | allowed | OK |  |
| tso/state.php | SUPPLIER | 403 | 403 | OK |  |
| tso/state.php | AGGREGATOR | 403 | 403 | OK |  |
| tso/transformer.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftso%2Ftransformer.php |
| tso/transformer.php | CONSUMER | 403 | 403 | OK |  |
| tso/transformer.php | TECHNICIAN | 403 | 403 | OK |  |
| tso/transformer.php | SYSTEM_OFFICER | 403 | 403 | OK |  |
| tso/transformer.php | SYSTEM_ADMIN | 403 | 403 | OK |  |
| tso/transformer.php | DSO | 403 | 403 | OK |  |
| tso/transformer.php | TSO | 200 | allowed | OK |  |
| tso/transformer.php | SUPPLIER | 403 | 403 | OK |  |
| tso/transformer.php | AGGREGATOR | 403 | 403 | OK |  |
| tso/tree.php | (anonymous) | 303 | redirect to login / refused | OK | /login.php?next=%2Ftso%2Ftree.php |
| tso/tree.php | CONSUMER | 403 | 403 | OK |  |
| tso/tree.php | TECHNICIAN | 403 | 403 | OK |  |
| tso/tree.php | SYSTEM_OFFICER | 200 | allowed | OK |  |
| tso/tree.php | SYSTEM_ADMIN | 200 | allowed | OK |  |
| tso/tree.php | DSO | 200 | allowed | OK |  |
| tso/tree.php | TSO | 200 | allowed | OK |  |
| tso/tree.php | SUPPLIER | 403 | 403 | OK |  |
| tso/tree.php | AGGREGATOR | 403 | 403 | OK |  |
