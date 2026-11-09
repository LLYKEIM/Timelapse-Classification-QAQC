# Timelapse Classification QA/QC

A simple R Shiny app used to QAQC image data tagged in Timelapse. The app allows you to
browse for the .ddb file in the folder you just finished classifying, shows the flagged 
images, and lets you edit the .ddb file directly in the app. A second tab lets you 
review every classified image or episode so you can quickly review all tags.

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
   sometimes opens behind the browser window.
2. **Camera effort** (top of the page): total days from the first to the last image, the
   number of noon timelapse images (and any days missing one), the days tagged
   `CameraObscured`, and the camera effort (total days minus obscured days). Use **Review
   noon images** or **Review CameraObscured images** to page through them.
3. **Checks tab:** fix the red **Fix** items and look over the yellow **Check** items. Click
   an image name or **Review images** to open the viewer.
4. **Review classifications tab:** click any row to see its images and episode, and correct
   the tags if needed.

In the image viewer, the arrows on the image step through every image in the same episode,
and the box above the form shows the episode's tags on every image in it. After saving any
change, **Download tagging changes (CSV)** in the sidebar lists every field changed this
session (old and new values). Download it before closing the app.

**Close the folder in Timelapse before editing in this app.** Saving only changes the fields
you edited on that one image. Everything else in the `.ddb` (other images, other fields, the
template and the table layout) stays exactly as it was, so the `.ddb` still works in later
workflows. The app doesn't make a backup copy; use **Download tagging changes (CSV)** as the
record of what was changed and what the old values were.

## Try it

Open `test_folder/TimelapseData.ddb`. Each test image has its planted mistake written on it.
The folder has noon timelapse images for June 1–29 except June 20–21, and `CameraObscured`
tags on June 14 (the same day as a black bear, so it warns) and June 22–24, plus a second
`CameraObscured` tag on June 23 (only one is allowed per day, so it warns). That gives 30 total
days and 26 days of camera effort.
