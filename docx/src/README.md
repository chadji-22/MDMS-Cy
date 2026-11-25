# docx/src — Markdown sources of the documents

| File | Task | Becomes |
|---|---|---|
| `manual_consumer.md` | D2 | user manual, consumer section |
| `manual_supplier.md` | D2 | user manual, supplier / aggregator section (draft until B4 is merged: `TODO-screenshot`, `TODO (B4)`) |
| `indexes_D11.md` | D11 | the three most important indexes (which, why, how) with the measured before / after |
| `manual_dso_tso.md` | D4 | user manual, DSO + TSO + map section |
| `contention_D8.md` | D8 | second document, part (a); evidence in `evidence/D8` |
| `security_D9.md` | D9 | second document, part (b); evidence in `evidence/D9` |
| `img/` | | screenshots (copies of `evidence/B3`, `evidence/B11`) |

The manual skeleton (D1) did not exist when these were written, so each file is a standalone section with one top-level
heading; drop it into the skeleton and keep its sub-headings.

Build (no local pandoc needed; Podman or Docker):
```bash
cd docx
podman run --rm -v "$(pwd):/data" -w /data/src docker.io/pandoc/core:3.5 manual_consumer.md --resource-path=/data/src -o /data/manual_consumer.docx
```
(On Windows Git Bash prefix with `MSYS_NO_PATHCONV=1` and use `$(pwd -W)`.) Same for the other files.
