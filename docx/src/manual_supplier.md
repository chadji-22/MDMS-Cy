# Suppliers and aggregators — user manual

*Section of the MDMS-Cy user manual. Spec: project.pdf §II.Ε pp. 3–4, §5.1–§5.2 pp. 10–11.*

> **Draft status (22/11/2026).** The pages of this area are task B4 (Kostis) and are not merged yet. The text below is written from the stored procedures they call: `sp_GetPortfolioSummary`, `sp_GetDayAheadAggregates`, `sp_GetIntradayProvisional`, `sp_ListSupplierBills`. Menu names, field labels and the endpoint URLs must be checked against the pages when B4 is merged. Places marked **TODO-screenshot** wait for those pages.

A **supplier** sells energy to consumers. An **aggregator** groups the flexibility of prosumers. Each user of a supplier or aggregator belongs to one organization, created by the administrator. After logging in, the user sees only the data of the premises linked to that organization:

- a supplier sees the premises whose supplier is the organization;
- an aggregator sees the premises in its portfolio.

**What these users never see** (§5.1 p.10; §1.4 p.6):

- raw 15-minute rows of a single meter;
- personal data of a consumer.

Every figure is a **sum over a group of meters**, grouped by transformer (the geofence hierarchy of §4.1). A group with **fewer than 3 meters is not shown at all**, so that no single household can be singled out.

Demo accounts: `billing@eacsupply.cy` (supplier EAC Supply), `billing@greenenergy.cy` (supplier GreenEnergy Supply), `desk@flexpool.cy` (aggregator FlexPool). Password `Passw0rd!23`.

---

## 1. Portfolio

**Purpose.** The size and kind of the organization's customer base (§5.1 p.10).
**Who.** Supplier and aggregator users.
**Procedure.** `sp_GetPortfolioSummary`.

**What it shows.** One line per district, with:

- the number of customers;
- the number of premises;
- the prosumers, split into Net Metering and Net Billing;
- the meters installed and the meters active.

**TODO-screenshot:** portfolio page.

## 2. Day-Ahead data (validated)

**Purpose.** The validated (after VEE), final daily energy of the organization's meters, for forecasting and market scheduling on the next day (§5.2 p.11).
**Who.** Supplier and aggregator users.
**Procedure.** `sp_GetDayAheadAggregates(from, to, group level, optional root transformer)`.

**Steps.**

1. Choose the first and last day.
2. Choose the grouping level of the transformer tree: level 1 = the low-voltage transformers, higher levels = larger areas.
3. Optionally choose one transformer, to see only its subtree.

**What it shows.** One line per day and transformer group:

- the transformer name;
- import kWh (1.8.0), export kWh (2.8.0) and net kWh;
- the number of meters in the group.

Only **final** daily aggregates are used, so the numbers do not change afterwards.

**Errors.** "Invalid input: the period must have from <= to." A group with fewer than 3 meters is simply missing from the result. If nothing appears, try a higher grouping level.

**TODO-screenshot:** Day-Ahead page.

## 3. Intraday data (provisional)

**Purpose.** The most recent 15-minute energy, available **before** validation (VEE) is complete, so that the organization can follow the current day (§5.2 p.11).
**Who.** Supplier and aggregator users.
**Procedure.** `sp_GetIntradayProvisional(from, to, group level)`. The window is at most 24 hours.

**What it shows.** One line per 15-minute slot and transformer group:

- import, export and net kWh;
- the number of meters;
- the flag **provisional = yes**.

These figures can still change: validation may estimate missing slots or correct values. Readings that validation marked as suspect are left out. Groups with fewer than 3 meters are suppressed, as for Day-Ahead.

**Errors.** "Invalid input: the window must have from < to and at most 24 hours."

**TODO-screenshot:** Intraday page.

## 4. Data for other systems (JSON)

**Purpose.** The specification asks that suppliers and aggregators can receive the aggregates through APIs (§II.Ε p.4, §5.1 p.10). The Day-Ahead and Intraday data are also offered as JSON, for the organization's own forecasting tools. They use the same login session, the same filters and the same rules: own organization only, no group under 3 meters.

**TODO (B4):** the endpoint URLs and one example response, once the endpoints are merged.

## 5. Customers' bills (suppliers)

**Purpose.** A supplier follows the bills of its own customers (§1.3 p.6). It never sees the bills of another supplier's customers.
**Procedure.** `sp_ListSupplierBills(status, year, month, page, page size)`.

**What it shows.** For each bill:

- the bill id, issue date, due date and period;
- the amount, paid and remaining;
- the status (ISSUED, PARTIALLY_PAID, PAID, OVERDUE, CANCELLED) and the premise.

**TODO-screenshot:** supplier bills page.

---

**What a supplier or aggregator user cannot do.** Open the consumer pages (403), see single meters, see consumers' names, or change any data of a premise. The consumer chooses the supplier and the aggregator of each premise (`sp_ChangeSupplier`, `sp_SetPremiseAggregator`).
