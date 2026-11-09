# Timelapse Classification QA/QC

Checks a Timelapse-classified camera folder for common classification errors, shows the
flagged images, and lets you fix them in place. A second tab lets you review every
classified image or episode.

## Install

You'll need R (4.1 or newer). Then install the packages once:

```r
install.packages(c("shiny", "bslib", "DT", "dplyr", "tidyr", "stringr",
                   "lubridate", "RSQLite", "DBI", "jsonlite"))
```

## Run

```r
shiny::runApp("path/to/Timelapse-Classification-QAQC")
```

1. Click **Choose .ddb file…** and pick the `.ddb` in the folder you classified. The dialog
   sometimes opens behind the browser window. You can also paste the path instead.
2. **Checks tab:** fix the red **Fix** items and look over the yellow **Check** items. Click
   an image name or **Review images** to open the viewer.
3. **Review classifications tab:** click any row to see its images and episode, and correct
   the tags if needed.

**Close the folder in Timelapse before editing in this app.** Before your first change, the
app saves a backup copy next to the `.ddb` (`TimelapseData.ddb.backup-<date-time>`).

## Try it

Open `test_folder/TimelapseData.ddb`. Each test image has its planted mistake written on it.
