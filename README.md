# Timelapse Classification QA/QC

An app that checks the tags in a Timelapse folder you just classified, shows you the images
with problems, and lets you fix the tags right in the app. Your fixes are saved straight
into the folder's `.ddb` file.

## First-time setup

You only do this once per computer.

1. **Get the app.** Clone this repository into RStudio by following
   [Clone an existing team repo](https://github.com/LLYKEIM/LLYKEIM-intro-to-git/blob/main/docs/03-r-rstudio-projects.md#a-clone-an-existing-team-repo-most-common)
   in the Intro to Git handbook. Clone it into your **GitHub folder**: `C:\Users\<name>\NotSynced\GitHub`
   if OneDrive syncs your Desktop, otherwise `Desktop\GitHub`
   ([how to check](https://github.com/LLYKEIM/LLYKEIM-intro-to-git/blob/main/docs/team-conventions.md#where-to-keep-projects)).
   Don't use **Download ZIP**, because a ZIP copy can't pull updates.

You don't need to install any R packages yourself. The first time you start the app it
installs everything it needs, which can take a few minutes and needs an internet connection.
If R asks whether to use a personal library, answer **Yes**.

## Start the app

1. Open the project RStudio.
2. Open the `app.R` file and click **Run App**. Make sure you give it a second to load. Keep an
   eye on the R Studio Console to check for any errors if the app doesn't seem to be loading correctly.

To stop the app, close the app window. The app has stopped running if the small stop sign icon disappears 
from the top right corner of the console window.

## Check a folder

1. If you just finished classifying, **close the image set in Timelapse first.**
2. Click **Choose .ddb file…** and pick the `.ddb` in the folder you classified.
   (The file window sometimes opens behind your browser.)
3. **Camera effort** (top of the page) shows the total days, noon images, days tagged
   `CameraObscured`, and the camera effort. Use the **Review** buttons to look through
   those images.
4. **Checks tab:** fix every red **Fix** item and look over the yellow **Check** items.
   Click an image name or **Review images** to open it.
5. **Review classifications tab:** click any row to see its images and correct the tags
   if needed.
6. In the image viewer, use the arrows on the image to step through the episode, change
   any tags, and click **Save changes**.
7. **Before you close the app, click Download tagging changes (CSV)** in the sidebar.
   It lists every change you made, with the old and new values. The app doesn't keep a
   backup copy of the `.ddb`, so this CSV is your record.

Saving only changes the fields you edited on that one image. Everything else in the `.ddb`
stays exactly as it was, so it still works in later workflows.

## Try it on the test folder

Open `test_folder/TimelapseData.ddb`. Each test image has its planted mistake written on
it, so you can see what each check catches.

## Getting updates

Before you start the app, open the project in RStudio and click **Pull** in the **Git** tab
to get the latest version (see the handbook's
[everyday workflow](https://github.com/LLYKEIM/LLYKEIM-intro-to-git/blob/main/docs/06-everyday-workflow.md#the-daily-loop)).
