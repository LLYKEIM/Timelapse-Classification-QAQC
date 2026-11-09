# Working with the .ddb file on disk: choosing it, reading the template,
# serving images, backing up, and saving edits.

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# Fields that can be edited in the app (only those present in the .ddb are shown)
EDIT_FIELDS <- c(
  "Location", "DateStart", "Classifier", "Species", "CameraServicing",
  "Total", "Horses", "DogsOnLeash", "DogsOffLeash", "AdultFemale", "AdultMale",
  "AdultUnknown", "Subadult", "YLY", "YOY", "Unknown", "Duration",
  "ColourMarkings", "Tag", "Behaviour", "CommentsImages", "DirectionTravel",
  "Illegal", "MegaDetect"
)


# Open the computer's own file dialog. This only works because the app runs on
# the same computer as R. Returns NULL if cancelled.
choose_ddb <- function() {
  path <- tryCatch({
    if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
      rstudioapi::selectFile(caption = "Choose a Timelapse .ddb file",
                             filter = "Timelapse database (*.ddb)")
    } else if (.Platform$OS.type == "windows") {
      utils::choose.files(caption = "Choose a Timelapse .ddb file", multi = FALSE,
                          filters = matrix(c("Timelapse database (*.ddb)", "*.ddb"), nrow = 1))
    } else {
      file.choose()
    }
  }, error = function(e) NULL)

  if (length(path) == 0 || is.na(path[1]) || path[1] == "") return(NULL)
  normalizePath(path[1], winslash = "/")
}


# Parse one Timelapse choice list. Handles the newer JSON format
# ({"IncludeEmptyChoice":true,"ChoiceListNonEmpty":[...]}) and the older
# "a|b|<EMPTY>" format.
parse_choice_list <- function(l) {
  if (is.na(l) || trimws(l) == "") return(character(0))
  l <- trimws(l)
  choices <- if (startsWith(l, "{")) {
    j <- tryCatch(jsonlite::fromJSON(l), error = function(e) list())
    unlist(j$ChoiceListNonEmpty %||% j$Choices %||% character(0))
  } else {
    strsplit(l, "|", fixed = TRUE)[[1]]
  }
  choices <- trimws(as.character(choices))
  choices[choices != "" & choices != "<EMPTY>"]
}


# The template stored inside the .ddb: field order, labels, tooltips, and the
# choice lists for FixedChoice fields. Returns a data frame (possibly empty).
read_template <- function(path) {
  empty <- data.frame(DataLabel = character(), Label = character(), Type = character(),
                      Tooltip = character(), stringsAsFactors = FALSE)
  empty$Choices <- list()

  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!"TemplateTable" %in% DBI::dbListTables(con)) return(empty)

  tt <- DBI::dbReadTable(con, "TemplateTable")
  if (!"DataLabel" %in% names(tt)) return(empty)
  for (col in c("Label", "Type", "Tooltip", "List")) if (!col %in% names(tt)) tt[[col]] <- ""
  if (!"ControlOrder" %in% names(tt)) tt$ControlOrder <- seq_len(nrow(tt))

  tt <- tt[order(suppressWarnings(as.numeric(tt$ControlOrder))), ]
  out <- data.frame(
    DataLabel = tt$DataLabel,
    Label     = ifelse(is.na(tt$Label) | trimws(tt$Label) == "", tt$DataLabel, trimws(tt$Label)),
    Type      = ifelse(is.na(tt$Type), "", tt$Type),
    Tooltip   = ifelse(is.na(tt$Tooltip), "", tt$Tooltip),
    stringsAsFactors = FALSE
  )
  # Only FixedChoice fields are dropdowns; Note fields can also have a list
  # (Timelapse's autocomplete history), which we ignore.
  out$Choices <- lapply(seq_len(nrow(tt)), function(i) {
    if (identical(out$Type[i], "FixedChoice")) parse_choice_list(tt$List[i]) else character(0)
  })
  out
}


# Update fields for one image. `values` is a named list: field -> new value.
# Only the named fields of that one row are written; every other row, field,
# table and the schema are left exactly as they were. The update runs in a
# transaction and is rolled back unless exactly one image was changed.
write_ddb_fields <- function(path, id, values) {
  if (length(values) == 0) return(invisible(0))
  bad <- setdiff(names(values), EDIT_FIELDS)
  if (length(bad)) stop("Not an editable field: ", paste(bad, collapse = ", "))

  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  cols <- as.character(DBI::dbQuoteIdentifier(con, names(values)))
  sql <- paste0("UPDATE DataTable SET ", paste0(cols, " = ?", collapse = ", "),
                " WHERE Id = ?")
  DBI::dbWithTransaction(con, {
    n <- DBI::dbExecute(con, sql, params = c(unname(lapply(values, as.character)),
                                             list(as.integer(id))))
    if (n != 1) stop("Expected to update 1 image but would have updated ", n, ", so nothing was saved.")
  })
  invisible(n)
}


# Images ------------------------------------------------------------------------
# Images are served by R itself (through session$registerDataObj) rather than as
# static files. That copes with spaces and odd characters in folder and file
# names, and with OneDrive files that need downloading before they can be read.

path_parts <- function(relative_path, file_name) {
  rel <- gsub("\\\\", "/", relative_path %||% "")
  parts <- c(strsplit(rel, "/", fixed = TRUE)[[1]], file_name)
  parts[!is.na(parts) & parts != ""]
}

image_disk_path <- function(folder, relative_path, file_name) {
  do.call(file.path, as.list(c(folder, path_parts(relative_path, file_name))))
}

# base_url comes from session$registerDataObj and already has a query string
image_url <- function(base_url, relative_path, file_name) {
  paste0(base_url,
         "&rel=", utils::URLencode(gsub("\\\\", "/", relative_path %||% ""), reserved = TRUE),
         "&f=", utils::URLencode(file_name, reserved = TRUE))
}

media_type <- function(file_name) {
  switch(tolower(tools::file_ext(file_name)),
         jpg = , jpeg = "image/jpeg", png = "image/png", gif = "image/gif",
         bmp = "image/bmp", mp4 = , m4v = "video/mp4", webm = "video/webm",
         mov = "video/quicktime", avi = "video/x-msvideo",
         "application/octet-stream")
}

# Request handler: `folder` is the folder holding the .ddb
serve_image <- function(folder, req) {
  q <- shiny::parseQueryString(req$QUERY_STRING %||% "")
  parts <- path_parts(q$rel, q$f %||% "")
  if (length(parts) == 0 || any(parts %in% c(".", ".."))) {
    return(shiny::httpResponse(400L, "text/plain", "Bad image path"))
  }
  path <- do.call(file.path, as.list(c(folder, parts)))
  if (!file.exists(path)) {
    return(shiny::httpResponse(404L, "text/plain", paste("Not found:", path)))
  }
  body <- tryCatch(readBin(path, "raw", n = file.info(path)$size), error = function(e) NULL)
  if (is.null(body)) {
    return(shiny::httpResponse(500L, "text/plain", paste("Couldn't read:", path)))
  }
  shiny::httpResponse(200L, media_type(path), body,
                      headers = list("Cache-Control" = "private, max-age=600"))
}

is_video <- function(file_name) {
  tolower(tools::file_ext(file_name)) %in% c("mp4", "webm", "mov", "m4v", "avi")
}
