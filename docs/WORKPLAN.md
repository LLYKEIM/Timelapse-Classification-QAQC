# Timelapse Classification QA/QC – Work Plan

A local R Shiny app that checks Timelapse camera-image classifications for errors, shows the
flagged images, lets classifiers fix them in place, and supports a second-pass review of all
classified images.

This plan is written so each phase can be handed to Claude Code as its own planning session
(see "Using this plan with Claude Code" at the end).

---

## 1. Goals

- **Catch classification errors before data leaves the classifier**, using the rules in the
  original QA script (servicing, totals, demographics, colours, dogs, horses, illegal flags,
  duplicate classifications in an episode).
- **Make fixing fast**: see the image and its episode, edit the fields, save, re-check.
- **Support review**: let a second person page through classified images or episodes and
  confirm the tags.
- **Stay safe with the data**: never lose classifications, always back up before editing, and
  never put camera data in the repo.

**Users:** classifiers on the multi-species camera network (mixed R experience) and the
person reviewing their work.

**Runs:** locally, on the classifier's own Windows computer, launched from R/RStudio. No
hosting, so no data leaves the machine.

---

## 2. Where things stand (v0.3, Nov 2026)

Working, per testing on Maddy's machine:
- Choose a .ddb by file dialog (the pasted-path box was removed in v0.4)
- All checks from the original script, grouped into Fix / Check / Note cards, plus CSV export
- Image viewer with episode thumbnail strip, previous/next, edit form, save with automatic
  re-check after save (no backup copies since v0.5; saves change only the edited fields)

New in v0.3, **not yet confirmed on a real folder**:
- Images served by R (to handle spaces in names and OneDrive files)
- Dropdowns as plain HTML selects, with a sidebar line showing what was read from the template
- "Review classifications" tab: table by image or by episode, species filter, "only images
  with issues", click a row to open the viewer, prev/next follows the table order

Known gaps:
- No automated tests; everything has been tested by hand
- Review table jumps back to page 1 after a save
- Videos play but can't be scrubbed (no range requests)
- Thumbnails load full-size images, which is slow on large episodes and on OneDrive
- Saves while Timelapse has the folder open aren't detected beyond a "locked" error
- Check rules (species lists, the "93" location exception) are hard-coded

---

## 3. Repo setup (Phase 0)

**Structure** (current, kept as a plain Shiny app folder for now):

```
Timelapse-Classification-QAQC/
├── app.R                  # UI and server
├── R/
│   ├── checks.R           # prepare_timelapse(), run_checks(), the rules
│   └── ddb_io.R           # file dialog, template, image serving, backup, saving
├── test_folder/           # synthetic test images + .ddb (no real data)
├── docs/WORKPLAN.md
├── CLAUDE.md              # context for Claude Code
├── README.md
└── .gitignore             # blocks real .ddb files, backups and images
```

**Steps**
1. Create the GitHub repo. **Decide: personal account (private) or a Parks Canada org.**
   Keep it private until the data question below is settled.
2. `git init`, commit this folder as-is, push.
3. Add `renv` (`renv::init()`) so everyone runs the same package versions.
4. Confirm `.gitignore` works: real `.ddb`/`.tdb` files, `*.backup-*`, and image folders must
   never be committed. Only `test_folder/` is allowed through.

**Data question to settle first:** is the Timelapse template (species list, field names) OK to
put in a repo? The test `.ddb` contains a copy of it. If not, the repo should be private or the
fixture should use a trimmed template.

---

## 4. Phases

### Phase 1 – Tests and a safety net
*Goal: change the code without fear of breaking the checks.*

- Add `testthat` (`tests/testthat/`).
- Write an R script `tests/make_fixtures.R` that builds small `.ddb` files from data frames,
  one per scenario (clean folder, each error type, MegaDetector folder, blank folder,
  missing fields, old pipe-style template, JSON template). Replaces the Python generator used
  so far.
- One test per check: the flagged images are exactly the planted ones; a clean folder flags
  nothing.
- Tests for `read_template()` (JSON `ChoiceListNonEmpty`, pipe lists, `<EMPTY>`, Note fields
  ignored), `write_ddb_fields()` (round trip, rejects unknown fields, exactly one row),
  `serve_image()` (spaces, backslashes in RelativePath, `..` rejected).
- **Done when:** `testthat::test_dir("tests/testthat")` passes and covers every check.

### Phase 2 – Fix known gaps
- Review table keeps its page and sort after a save (use `DT::replaceData()` on a proxy).
- Video range requests so videos can be scrubbed.
- Faster thumbnails: optional cached thumbnails (`magick`, in a temp folder), falling back
  to full images if `magick` isn't installed.
- Warn if the `.ddb` changed on disk since it was loaded (e.g. Timelapse saved), and reload.
- OneDrive: detect `-<computername>` conflict copies of the `.ddb` and warn.
- **Done when:** each item has a test or a written manual test step.

### Phase 3 – Better review workflow
- **Reviewed marks**: a "Looks right" button in the viewer.
  **Decide where this lives**: a sidecar CSV next to the .ddb (`<name>.review.csv`,
  doesn't touch Timelapse data), or a new Timelapse field (visible in Timelapse, needs a
  template change). Recommendation: sidecar CSV.
- Review progress in the table (reviewed / not reviewed column and filter).
- Keyboard shortcuts in the viewer: ←/→ previous/next, Ctrl+S save, Esc close.
- "Move to image" helper for the dog/horse rules: move counts from one image to another in
  the same episode.
- Reviewer notes exported with the issues CSV.

### Phase 4 – Easy install for classifiers
- Convert to an R package (e.g. `tlqaqc`) with `launch_app()`; checks callable from scripts.
- Install with `remotes::install_github(...)`; one-page instructions with screenshots.
- Version number and "what's new" in the app footer; `NEWS.md`.
- Optional: an RStudio addin or a desktop shortcut (`.bat`) that launches the app.

### Phase 5 – Rules without code changes (optional)
- Move species groups (humans, bears/wolves needing colour), the episode gap (600 s), and
  location exceptions (the `93` prefix) into a `rules.yml` that a lead can edit.
- Show the active rules in an "About these checks" panel.

---

## 5. Decisions needed from Maddy

| Decision | Options | Suggested |
|---|---|---|
| Where the repo lives | Personal private / Parks Canada org | Personal private for now |
| Template in repo | Full template / trimmed fixture | Ask data steward; trimmed if unsure |
| Can classifiers edit, or only reviewers? | Everyone / read-only mode toggle | Everyone, plus a read-only toggle |
| Where "reviewed" status lives | Sidecar CSV / Timelapse field | Sidecar CSV |
| `"93"` location exception | Keep hard-coded / move to rules file | Rules file (Phase 5) |

---

## 6. Risks

- **Editing while Timelapse is open** can lose one side's changes. Mitigation: banner,
  locked-file message, change detection (Phase 2), tagging-changes CSV.
- **OneDrive sync conflicts** can create duplicate .ddb files. Mitigation: warning (Phase 2);
  recommend "Always keep on this device" for folders being worked on.
- **Camera data in git**: blocked by `.gitignore`; double-check before the first push.
- **Template changes** (new fields or species) could break checks. Mitigation: required-field
  check at load (already in place), fixture tests (Phase 1).

---

## 7. Using this plan with Claude Code

1. Open the repo folder in Claude Code. It reads `CLAUDE.md` automatically.
2. Start in plan mode and ask, for example:
   > Read docs/WORKPLAN.md and plan Phase 1. List the files you'll add, the fixture
   > scenarios, and the tests, then wait for my OK.
3. Work one phase per branch and pull request. Ask Claude Code to tick off items in this file
   as they're done and to add new findings to "Known gaps".
4. After each phase, run the app against a real folder (copied, not the original) before
   merging.
