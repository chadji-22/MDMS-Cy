# How we write the Phase B documents

For: Ioannis, Kostis and Eliana (Group 10).
Deadline: **Friday 4/12/2026, 12:00** on Moodle. The printed copy of `docx/` is handed in at the lab.

## 1. What we hand in

`project.pdf` Section V asks for **two documents** in `docx/`:

| File (final name) | Template | Contents required by `project.pdf` |
|---|---|---|
| `10_user_manual.docx` (+ `.pdf`) | `10_user_manual_TEMPLATE.docx` | A short user manual: how to use the application, the main database design choices, extra functions, difficulties, **final ER diagram**, **data dictionary**, **limitations and possible improvements** (Section V, p. 14). |
| `10_technical_document.docx` (+ `.pdf`) | `10_technical_document_TEMPLATE.docx` | (a) contention points and how we handle them, (b) security, (c) future extension (Section V, p. 14). We added (d) the **three main indexes**, one **before/after cost case** and the **95% under 2 s** result. Section IV asks for these "in the documentation" (p. 12). |

Only `docx/` is printed, so the printed pages must read well without the code.

The rest of the zip (`sources/`, `sql/`, `data/`) is described in Appendix A of the manual.

## 2. Who writes what

The task IDs come from `PROJECT_STATUS_AND_CHECKLIST.md`. Each yellow **TODO box** in the templates names its task.

| Document → section | Task | Owner | Start from | Evidence |
|---|---|---|---|---|
| Manual → cover, Introduction, Getting started, Appendix A | D1 | Eliana | `src/manual_intro.md` | `sources/README.md`, `build_all.sql` |
| Manual → Consumer (ΚΧ) | D2 | Ioannis | `src/manual_consumer.md` | `evidence/B3` |
| Manual → Field technician (ΤΠ) | D3 | Eliana | `src/manual_technician_staff.md`, Part A | technician pages |
| Manual → Officer (ΛΣ) and administrator (ΔΣ) | D3 | Eliana | `src/manual_technician_staff.md`, Parts B and C (one section: renumber their sub-sections from 1, the draft has 7–15) | staff pages |
| Manual → DSO, TSO, Map | D4 | Kostis | `src/manual_dso_tso.md` (Parts A, B, C). Each part becomes its own section; Part B is numbered from 1 | `evidence/B11` |
| Manual → Suppliers and aggregators | D2 | Ioannis | `src/manual_supplier.md` | market pages |
| Manual → Main design choices, Additional functions, Difficulties | D5 | Eliana | `src/design_choices.md` (its sections 9 and 10 are *Additional functions* and *Difficulties we met*), `REPORT.md` §3 and §7 | |
| Manual → Final ER diagram, Data dictionary | D6 | Eliana | `MDMS_Cy_ERD_v7.erdplus` (image `src/img/MDMS_Cy_ERD_v7.png`), `src/data_dictionary.md`, the deployed DB | queries in §6 below |
| Manual → Limitations and possible improvements | D7 | Eliana | `src/limits_improvements.md`, `REPORT.md` §7.4 | |
| Technical → Introduction | D1 | Eliana | template | |
| Technical → (a) Contention | D8 | Kostis | `src/contention_D8.md` | `evidence/D8` |
| Technical → (b) Security | D9 | Kostis | `src/security_D9.md` | `evidence/D9` |
| Technical → (c) Future extension | D10 | Eliana | `src/future_extension_D10.md`, `REPORT.md` §6.6 | |
| Technical → (d) Indexes and performance | D11 (+ C1) | Ioannis | `src/indexes_D11.md` | `evidence/performance-sql2025` |
| Assembly of both documents, final PDF, print | D1, D12 | Eliana (assembly), any (print) | | |
| Review (see §8) | | all | | |

Eliana has the most sections. Anyone who finishes early takes one of hers: D7 or D10 are the easiest to hand over. Say so in the group chat first.

Owner names appear **only in this guide**, never in the documents. The course requires every member to work on every stage, so the documents speak as "we". Every member must be able to explain every section at the oral exam.

## 3. Format (already set in the templates — do not change it)

- **Times New Roman** everywhere: body 12 pt, Heading 1 16 pt, Heading 2 13 pt, Heading 3 12 pt italic, captions 10 pt italic.
- The one exception is code and SQL, which use **Courier New 10 pt**: styles *Source Code* for blocks and *Verbatim Char* for inline code. Code needs a monospace font to keep its alignment. If we decide code must also be Times New Roman, change these two styles and nothing else.
- A4, margins 2.5 cm, **one column**, body text justified, line spacing 1.15.
- Page "X of Y" in the footer and the document name in the header. The cover page has neither.
- Every Heading 1 starts on a new page, and the table of contents shows Heading 1 and Heading 2.

**Use styles, never manual formatting.** Do not pick a font, size or colour by hand. If you paste from another file, use *Paste → Keep Text Only* or *Use destination styles*, otherwise Calibri or Arial creeps in.

| Use this style | For |
|---|---|
| Heading 1 | The sections already in the template. Do not add new ones without telling the group. |
| Heading 2 | Sub-sections, numbered inside the section as the drafts do (`1. My premises`, `2. …`). |
| Heading 3 | Rarely, if a sub-section really needs parts. |
| Body Text | Normal paragraphs. |
| List Bullet / List Number | Lists. Steps a user follows are always a numbered list. |
| Table Caption | Above every table: `Table N – text`. |
| Image Caption | Below every figure: `Figure N – text`. |
| Source Code | SQL or code blocks. Keep them short: 15 lines at most, and point to the file in `sql/` for the rest. |
| Template Note | The yellow TODO boxes. **Delete each one when its section is done.** |

Numbering of tables and figures runs 1, 2, 3 … through each document. Renumber when you merge.

## 4. Two ways to write

**A. Markdown, then pandoc (what D2, D4, D8, D9 and D11 already use).** Write in `docx/src/<file>.md` and build it with the template as reference. It then gets exactly our fonts and styles:

```bash
cd docx
MSYS_NO_PATHCONV=1 podman run --rm -v "$(pwd -W):/data" -w /data/src docker.io/pandoc/core:3.5 \
  manual_consumer.md --resource-path=/data/src \
  --reference-doc=/data/10_user_manual_TEMPLATE.docx -o /data/manual_consumer.docx
```

For the technical sections, use `--reference-doc=/data/10_technical_document_TEMPLATE.docx`. Docker works the same way as podman.

In the `.md` file:
- Use `#` for the section title. When the section is pasted in, the template's Heading 1 replaces it, so drop suffixes such as "— user manual".
- Use `##` for the sub-sections. They must match the Heading 2 titles in the template. If your real pages differ, change the template headings too, so the table of contents stays right.
- Images: `![Figure 3 – My premises](img/consumer_01_premises.png){width=14cm}`.

**B. Directly in Word.** Make a copy of the template, write only in your sections, and use the styles in §3.

**Working in the shared files.** Each document is one shared `.docx` that all three of us edit at the same time.
- Keep it as a **Word file** (OneDrive / Word for the web or desktop Word). Do not convert it to Google Docs: that drops our styles, the Times New Roman theme and the table of contents.
- Write only inside **your own sections** (§2). Replace the template's placeholder text and headings there.
- If you wrote a section in Markdown (way A), build it with pandoc and paste it in with *Use destination styles*.
- Use Word comments to talk about someone else's section. Do not edit their text directly.
- Eliana updates the table of contents and renumbers the figures and tables at the end (D1).

## 5. How to write

- **Language:** English, as in the drafts. Use the Greek role abbreviations from `project.pdf` once per section title (ΚΧ, ΤΠ, ΛΣ, ΔΣ) and the English role names in the text.
- **Short and concrete.** The PDF asks for a *συνοπτικό* (concise) manual. One sentence on what a page is for, then numbered steps, one screenshot, and what the user sees on success and on refusal.
- **The manual speaks to the user** ("Open **My premises**, choose …"). **Design choices and the technical document speak as the team** ("We store …, because …").
- **Explain why, not only what.** Examiners grade design reasoning. "We use a filtered index because VEE reads only non-final rows" beats a list of index names.
- **Names exactly as in the code.** Write procedure, table and page names in `monospace` and copy them from the code; don't retype them. Button and menu names go in **bold**, as they appear on screen.
- **Same words everywhere:** premise (not property), reading (one 15-minute value), packet (one telemetry message), work order (not job or ticket), finalize / finalization, aggregate (daily, monthly or yearly total), officer, administrator. Keep one spelling style. The drafts mix British and US spellings ("unauthorised", "finalize"), so pick one during the merge.
- **Every number must have a source.** Row counts, timings, test results and object counts come from the deployed database on SQL2025 or from a file in `evidence/`. Don't copy them from older notes: `REPORT.md` says 24 tables and the checklist says 25. If a number is from a run, say when and on which server.
- **State limits honestly.** A limit we state costs less than one the examiner finds.
- **Screenshots:**
  - PNG, using demo data only (never real people), cropped to the page content without the browser bar.
  - Inserted at 14 cm width.
  - Text in the image must be readable when printed.
  - Keep them in `docx/src/img/` named `<area>_<nn>_<what>.png`.

### Page budget (guide, not a rule)

| Part | Pages |
|---|---|
| Manual: Introduction + Getting started | 2–3 |
| Manual: each role section | 2–4 |
| Manual: design choices + extra functions + difficulties | 3–4 |
| Manual: ER diagram | 1–2 |
| Manual: data dictionary | as needed (tables are compact) |
| Manual: limitations | 1 |
| Technical document: whole | 10–15 |

## 6. Data dictionary — take it from the database

Run these on our database on SQL2025 and use the results, not older counts. The shared database also holds the lab tables, so leave out anything that is not MDMS-Cy:

```sql
-- object counts by kind
SELECT o.type_desc, COUNT(*) AS n
FROM sys.objects o
WHERE o.is_ms_shipped = 0
GROUP BY o.type_desc ORDER BY o.type_desc;

-- columns of every table
SELECT t.name AS table_name, c.column_id, c.name AS column_name,
       ty.name AS type_name, c.max_length, c.precision, c.scale, c.is_nullable
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
ORDER BY t.name, c.column_id;

-- non-primary-key indexes
SELECT t.name AS table_name, i.name AS index_name, i.type_desc, i.has_filter, i.filter_definition
FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
WHERE i.is_primary_key = 0 AND i.type > 0
ORDER BY t.name, i.name;
```

For keys and CHECK constraints use `sys.foreign_keys`, `sys.check_constraints` and `sys.key_constraints`, or copy them from `create.sql`. The "Meaning" column is written by hand, one short phrase per column.

## 7. Dates

| When | What |
|---|---|
| Fri 27/11 | Templates and this guide in `docx/`. Everyone reads the template of their sections. |
| Tue 1/12 | All sections drafted in the shared files, every TODO in your sections filled. |
| Wed 2/12 | Cross-review (§8). Fixes the same evening. |
| Thu 3/12 | Final check (§9), export to PDF, print `docx/`. |
| Fri 4/12, 12:00 | Upload `10.zip` to Moodle. |

## 8. Review

Each member reads another member's sections in the shared file and checks them against `project.pdf` and the live site:
- Ioannis reviews Kostis's sections.
- Kostis reviews Eliana's.
- Eliana reviews Ioannis's.

Check three things:
- Can a reader follow the steps on the real site?
- Is every requirement of the matching `project.pdf` paragraph covered?
- Are numbers and names correct?

Use Word comments, and the owner fixes them.

## 9. Before printing — checklist

- [ ] Search both documents for `TODO`: zero results. No yellow boxes or yellow highlight are left.
- [ ] Cover filled: the three names, IDs and e-mails, and the version date.
- [ ] Table of contents updated: right-click → *Update Field* → *Update entire table*.
- [ ] Every figure and table has a caption, and the numbers run in order.
- [ ] Fonts: export to PDF, open it in a PDF reader and check *File → Properties → Fonts*. Only Times New Roman should be listed, plus Courier New for code. Symbol and Arial for the bullet marks are fine.
- [ ] Every screenshot is readable in print and shows demo data only.
- [ ] Every requirement of Section V is present:
  - user instructions
  - design choices
  - extra functions
  - difficulties
  - final ER diagram
  - data dictionary
  - limitations and improvements
  - (a) contention
  - (b) security
  - (c) extension
- [ ] The three indexes, the before/after case and the 95% under 2 s result are present (Section IV).
- [ ] The final files are named `10_user_manual` and `10_technical_document`, saved as both `.docx` and `.pdf` in `docx/`. The `_TEMPLATE` files and the per-section `.docx` drafts are removed from the zip.
