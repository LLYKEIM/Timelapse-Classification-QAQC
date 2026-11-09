# Timelapse Classification QA/QC

Local R Shiny app that checks Timelapse camera-trap classifications (.ddb SQLite files),
shows flagged images, and saves fixes back into the .ddb. Used by Parks Canada classifiers
on Windows. The roadmap is in `docs/WORKPLAN.md`; work through it one phase at a time.

## Commands

- Run the app: `Rscript -e 'shiny::runApp(".", launch.browser = TRUE)'`
- Run checks without the UI:
  `source("R/checks.R"); run_checks(read_timelapse_ddb("test_folder/TimelapseData.ddb"))$issues`
- Tests (once Phase 1 exists): `Rscript -e 'testthat::test_dir("tests/testthat")'`

## Layout

- `app.R`: UI and server. Sources `R/checks.R` and `R/ddb_io.R` explicitly.
- `R/checks.R`: `prepare_timelapse()` formats data and assigns episodes; `run_checks()` holds
  all rules. Each rule calls `flag(check, message, rows, type)`, where `type` is
  `"issue"` (Fix), `"review"` (Check) or `"info"` (Note).
- `R/ddb_io.R`: file dialog, template parsing, image serving, backup, `write_ddb_fields()`.
- `test_folder/`: synthetic images and .ddb with planted errors (each image has its error
  written on it).

## Timelapse facts

- Data lives in the `DataTable` table; `Id` is the integer primary key; `File` is renamed
  to `FileName` in R; `RelativePath` is relative to the .ddb's folder and may use `\`.
- The template is in `TemplateTable`, which mirrors the .tdb. Only `Type == "FixedChoice"`
  fields are dropdowns. Their `List` is JSON (`{"IncludeEmptyChoice":true,"ChoiceListNonEmpty":[...]}`)
  in current templates, or `a|b|<EMPTY>` in older ones. `Note` fields can also have a
  `List`, which is autocomplete history and should be ignored.
- Everything in `DataTable` is text, and counters may be blank.
- An episode is a run of images less than 601 seconds apart (`EpManual`). MegaDetector
  folders also have a Timelapse `Episode` field like `"3:1|5"`.

## Rules

- **Never commit real data**: no real .ddb/.tdb files, images, or `*.backup-*` files.
  Only `test_folder/` is allowed.
- Only write to a .ddb through `write_ddb_fields()`, and only after `backup_ddb()` has run
  for that file in the session.
- Keep the check messages in plain language for classifiers. When a check's logic changes,
  say so in the PR description, because it changes what classifiers are told.
- Don't add package dependencies without asking. Optional extras (e.g. `magick`) must
  degrade gracefully when missing.
- The app must keep working in a narrow window (laptop screens).
- Maddy can't share real folders with you. Build fixtures that reproduce problems instead.
