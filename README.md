# Timelapse Classification QA/QC

An app that checks the tags in a Timelapse folder you just classified, shows you the images
with problems, and lets you fix the tags right in the app. Your fixes are saved straight
into the folder's `.ddb` file.

## First-time setup

You only do this once per computer.
1. **Get the app.** Clone this repository to your computer using the instructions outlined in the Intro to Git documents 

You don't need to install any R packages yourself. The first time you start the app it
installs everything it needs, which can take a few minutes and needs an internet connection.
If R asks whether to use a personal library, answer **Yes**.

## Start the app

1. Open RStudio.
2. Click **File → Open File…** and open `run_app.R` from the app folder.
3. Click **Source** (top right of the code pane). The app opens in your web browser.

To stop the app, close the browser tab and click the red **Stop** sign in RStudio's console.

## Check a folder

1. **Close the folder in Timelapse first.**
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

If you cloned the repository, pull the latest changes (for example **Pull** in GitHub
Desktop) before you start the app. If you downloaded a ZIP, download a new one.
