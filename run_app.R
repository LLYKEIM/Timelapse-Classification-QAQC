# Start the Timelapse Classification QA/QC app.
# In RStudio: open this file and click "Source" (top right of the script pane).
# From a terminal: Rscript run_app.R
#
# The first time, this installs any missing R packages (needs internet).

local({
  # Find the folder this file is in, so the app runs from anywhere
  candidates <- c(
    tryCatch(sys.frame(1)$ofile, error = function(e) NULL),           # source() / RStudio
    sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)),  # Rscript
    "."                                                                 # current folder
  )
  dirs <- dirname(normalizePath(candidates, mustWork = FALSE))
  dirs[candidates == "."] <- normalizePath(".")
  app_dir <- dirs[file.exists(file.path(dirs, "app.R"))][1]
  if (is.na(app_dir)) {
    stop("Can't find app.R. Open run_app.R from the Timelapse-Classification-QAQC folder ",
         "and click Source.", call. = FALSE)
  }

  # Shiny is needed to start the app; app.R installs the other packages itself
  if (!requireNamespace("shiny", quietly = TRUE)) {
    message("Installing the shiny package (one-time setup)...")
    repos <- getOption("repos")
    cran <- if ("CRAN" %in% names(repos)) unname(repos[["CRAN"]]) else ""
    if (is.na(cran) || !nzchar(cran) || cran == "@CRAN@") {
      repos <- c(CRAN = "https://cloud.r-project.org")
    }
    try(install.packages("shiny", repos = repos), silent = TRUE)
    if (!requireNamespace("shiny", quietly = TRUE)) {
      stop("Couldn't install the shiny package automatically. Check your internet ",
           "connection, then run this in R and try again:\n  install.packages(\"shiny\")",
           call. = FALSE)
    }
  }

  shiny::runApp(app_dir, launch.browser = TRUE)
})
