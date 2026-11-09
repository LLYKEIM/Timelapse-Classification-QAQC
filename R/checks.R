# Timelapse classification checks
# ---------------------------------
# The error-checking logic from the original script, wrapped in functions so it
# can be used from the Shiny app or from a plain R session:
#
#   raw <- read_timelapse_ddb("path/to/TimelapseData.ddb")
#   res <- run_checks(raw)
#   res$issues   # one row per problem found (with the affected images)
#   res$summary  # counts and metadata about the folder
#   res$data     # the full, formatted DataTable (with episode numbers)

library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(RSQLite)

# Fields the checks rely on. "Episode" is only needed for MegaDetector folders,
# so it is checked separately.
REQUIRED_COLS <- c(
  "Id", "File", "DateTime", "CommentsImages", "ColourMarkings", "Tag",
  "DirectionTravel", "Total", "Horses", "DogsOnLeash", "DogsOffLeash",
  "AdultFemale", "AdultMale", "AdultUnknown", "Subadult", "YLY", "YOY",
  "Unknown", "Behaviour", "Species", "Illegal", "MegaDetect",
  "CameraServicing", "Location", "DateStart", "Classifier"
)

COUNT_COLS <- c("Total", "AdultFemale", "AdultMale", "AdultUnknown",
                "Subadult", "YLY", "YOY", "Unknown")

HUMANS <- c("Biker", "Hiker", "Horse Rider", "Quad/Vehicle/Motorbike",
            "Snowmobile", "Skier", "Snowshoer", "Runner", "Watercraft")

# Species values that aren't an animal (used by the CameraObscured same-day check)
NOT_ANIMALS <- c(HUMANS, "CameraObscured", "FirstImage", "LastImage", "None")

# The camera takes a timelapse image at noon each day. Only images taken at
# exactly 12:00:00 count as that day's noon image.
TIMELAPSE_TIME <- "12:00:00"


# Read the DataTable from a Timelapse .ddb file --------------------------------
read_timelapse_ddb <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  if (!"DataTable" %in% DBI::dbListTables(con)) {
    stop("This file has no 'DataTable' table. Is it a Timelapse .ddb file?")
  }
  DBI::dbReadTable(con, "DataTable")
}


# Label shown for an image: subfolder/file if the image is in a subfolder
image_label <- function(relative_path, file_name) {
  rel <- gsub("\\\\", "/", relative_path)
  ifelse(rel == "", file_name, paste0(rel, "/", file_name))
}


# Format the data and work out episodes ----------------------------------------
prepare_timelapse <- function(TL_data) {
  missing <- setdiff(REQUIRED_COLS, names(TL_data))
  if (length(missing) > 0) {
    stop("The DataTable is missing these fields: ",
         paste(missing, collapse = ", "),
         ". Was this folder classified with the standard template?")
  }
  if (nrow(TL_data) == 0) stop("The database doesn't contain any images.")
  if (!"RelativePath" %in% names(TL_data)) TL_data$RelativePath <- ""

  names(TL_data)[names(TL_data) == "File"] <- "FileName"  # 'file' is a base R function
  TL_data[is.na(TL_data)] <- ""                            # NAs to blanks
  TL_data <- TL_data %>%
    mutate(across(everything(), ~ str_squish(as.character(.x))))  # collapse extra whitespace

  # Episode number: a new episode starts when more than 10 minutes (600 s)
  # have passed since the previous image
  TL_data <- TL_data %>%
    arrange(DateTime) %>%
    mutate(
      Tdiff = as.numeric(abs(difftime(DateTime, lag(DateTime), units = "secs"))),
      NewEp = ifelse(is.na(Tdiff) | Tdiff >= 601, 1, 0)
    ) %>%
    mutate(EpManual = cumsum(NewEp)) %>%
    arrange(as.numeric(Id)) %>%
    mutate(Label = image_label(RelativePath, FileName))

  MD <- any(TL_data$MegaDetect != "")

  # Only the rows that have been populated
  a <- TL_data %>%
    filter(CommentsImages != "" | ColourMarkings != "" | Tag != "" |
             DirectionTravel != "" | Total != "" | Horses != "" |
             DogsOnLeash != "" | DogsOffLeash != "" | AdultFemale != "" |
             AdultMale != "" | AdultUnknown != "" | Subadult != "" |
             YLY != "" | YOY != "" | Unknown != "" | Behaviour != "" |
             Species != "" | Illegal == "Yes" | MegaDetect != "")

  a <- a %>%
    mutate(across(all_of(COUNT_COLS),
                  ~ replace_na(suppressWarnings(as.numeric(.x)), 0))) %>%
    mutate(
      Total2 = AdultFemale + AdultMale + AdultUnknown + Subadult + YLY + YOY + Unknown,
      DateTime = suppressWarnings(as_datetime(DateTime))
    )

  list(TL_data = TL_data, a = a, MD = MD)
}


# Noon timelapse images, CameraObscured tags and camera effort -----------------
# TL_data is the formatted DataTable from prepare_timelapse().
#   total_days:    calendar days from the first image to the last (both included)
#   obscured_days: days with at least one CameraObscured tag
#   effort_days:   total_days - number of obscured days
#   missing_noon:  days the camera was out at noon but has no noon image
summarise_effort <- function(TL_data) {
  dt <- suppressWarnings(as_datetime(TL_data$DateTime))
  ok <- !is.na(dt)
  empty_date <- as.Date(character(0))
  if (!any(ok)) {
    return(list(total_days = 0L, first = NA, last = NA, timelapse_ids = character(0),
                timelapse_dates = empty_date, missing_noon = empty_date,
                obscured_ids = character(0), obscured_days = empty_date, effort_days = 0L))
  }
  day <- as.Date(dt)
  clock <- format(dt, "%H:%M:%S")

  first <- min(dt[ok]); last <- max(dt[ok])
  first_day <- as.Date(first); last_day <- as.Date(last)
  total_days <- as.integer(last_day - first_day) + 1L

  # Noon images: one image taken at exactly 12:00:00 on each day
  is_noon <- ok & clock == TIMELAPSE_TIME
  noon <- TL_data[is_noon, , drop = FALSE]
  noon$day <- day[is_noon]
  noon$dt <- dt[is_noon]
  noon <- noon[order(noon$dt, as.numeric(noon$Id)), , drop = FALSE]
  noon <- noon[!duplicated(noon$day), , drop = FALSE]

  # Days the camera was out at noon: skip the first day if it was set up after
  # noon, and the last day if it was picked up before noon
  from <- first_day + if (format(first, "%H:%M:%S") > TIMELAPSE_TIME) 1L else 0L
  to   <- last_day  - if (format(last, "%H:%M:%S") < TIMELAPSE_TIME) 1L else 0L
  expected <- if (from <= to) seq(from, to, by = "day") else empty_date
  missing_noon <- if (nrow(noon) > 0) expected[!expected %in% noon$day] else empty_date

  is_obscured <- TL_data$Species == "CameraObscured"
  obscured_days <- sort(unique(day[is_obscured & ok]))

  list(
    total_days      = total_days,
    first           = first,
    last            = last,
    timelapse_ids   = as.character(noon$Id),
    timelapse_dates = noon$day,
    missing_noon    = missing_noon,
    obscured_ids    = as.character(TL_data$Id[is_obscured][order(dt[is_obscured])]),
    obscured_days   = obscured_days,
    effort_days     = total_days - length(obscured_days)
  )
}

# "Jun 20, Jun 21, Jun 25" (or a shortened list if there are many)
format_days <- function(days, max_shown = 15) {
  txt <- format(days, "%b %d, %Y")
  if (length(txt) > max_shown) {
    txt <- c(txt[seq_len(max_shown)], sprintf("and %d more", length(txt) - max_shown))
  }
  paste(txt, collapse = "; ")
}


# Run every check ---------------------------------------------------------------
# Each problem is recorded with a type:
#   "issue"  - needs fixing
#   "review" - may be fine, but worth a look
#   "info"   - just a note
run_checks <- function(raw) {
  prep <- prepare_timelapse(raw)
  TL_data <- prep$TL_data
  a <- prep$a
  MD <- prep$MD

  issues <- list()
  # rows: a data frame of the affected images (needs Id and Label columns)
  flag <- function(check, message, rows = NULL, type = "issue") {
    if (is.null(rows) || nrow(rows) == 0) {
      ids <- character(0); labels <- character(0)
    } else {
      keep <- !duplicated(rows$Id)
      ids <- as.character(rows$Id[keep]); labels <- rows$Label[keep]
    }
    issues[[length(issues) + 1]] <<- list(
      check = check, type = type, message = message, ids = ids, files = labels
    )
  }

  if (MD) {
    flag("MegaDetector",
         "This folder appears to have been classified with MegaDetector. If it wasn't, check the MegaDetector field for unintentional entries.",
         type = "info")
  }

  if (nrow(a) == 0) {
    flag("No classifications",
         "None of the images in this database have any classification information.")
  } else {

    # Camera servicing ----------------------------------------------------------
    first_ep <- a$EpManual == min(a$EpManual)
    if (!"Yes" %in% a$CameraServicing[first_ep]) {
      flag("Servicing: first episode",
           "Camera servicing is not marked as 'Yes' in the first episode. This is fine if the first image doesn't correspond to a servicing (e.g. multiple folders created).",
           a[first_ep, ], type = "review")
      if (a$Species[1] == "") {
        flag("Servicing: first episode",
             "The first image is not labelled 'FirstImage'.", a[1, ])
      }
    }

    last_ep <- a$EpManual == max(a$EpManual)
    if (!"Yes" %in% a$CameraServicing[last_ep]) {
      flag("Servicing: last episode",
           "Camera servicing is not marked as 'Yes' in the last episode. This is fine if the last image doesn't correspond to a servicing (e.g. multiple folders created).",
           a[last_ep, ], type = "review")
      if (a$Species[nrow(a)] == "") {
        flag("Servicing: last episode",
             "The last image is not labelled 'LastImage'.", a[nrow(a), ])
      }
    }

    b <- a %>% filter(CameraServicing == "Yes")
    if (nrow(b) > 0 && !any(str_detect(tolower(b$CommentsImages), "parks staff"))) {
      flag("Servicing comment",
           "No servicing image is commented with 'Parks staff'.", b)
    }

    # Location ------------------------------------------------------------------
    locs <- unique(a$Location)
    if (length(locs) != 1) {
      shown <- ifelse(locs == "", "(blank)", locs)
      flag("Location",
           paste0("There is more than one location in this folder, or some locations are blank. Found: ",
                  paste(shown, collapse = ", ")))
    }

    # Missing metadata ----------------------------------------------------------
    b <- a %>% filter(Location == "" | DateStart == "" | Classifier == "")
    if (nrow(b) > 0) {
      flag("Missing metadata",
           "These images are missing a location, start date, or classifier initials.", b)
    }

    # Counts and totals ---------------------------------------------------------
    b <- a %>% filter(Total != Total2 & !(Species %in% HUMANS))
    if (nrow(b) > 0) {
      flag("Totals",
           "These images have a total that doesn't equal the sum of adults/juveniles/unknowns.", b)
    }

    b <- a %>% filter((Total2 != 0 | Total != 0) & Species == "")
    if (nrow(b) > 0) {
      flag("Counts without species",
           "These images have total/adult/juvenile/unknown counts but no species.", b)
    }

    b <- a %>%
      filter(Species != "" &
               !Species %in% c("CameraObscured", "FirstImage", "LastImage") &
               (Total2 + Total == 0))
    if (nrow(b) > 0) {
      flag("Species without counts",
           "These images have a species but no total/adult/juvenile/unknown counts.", b)
    }

    b <- a %>% filter(Species %in% HUMANS & Total2 != 0)
    if (nrow(b) > 0) {
      flag("Human demographics",
           "Remove demographic information from these human-use images.", b)
    }

    b <- a %>% filter(Species == "Unknown" & Unknown == 0)
    if (nrow(b) > 0) {
      flag("Unknown species",
           "These images have an Unknown species but no count in the UNK subclassification.", b)
    }

    # Bear and wolf colours -----------------------------------------------------
    b <- a %>%
      filter(Species %in% c("Wolf", "Grizzly Bear", "Black Bear", "Unknown Bear") &
               ColourMarkings == "")
    if (nrow(b) > 0) {
      flag("Bear/wolf colour",
           "Colour information is missing from these wolf or bear images.", b)
    }

    # Dogs ----------------------------------------------------------------------
    if (!MD) {
      b <- a %>%
        filter((DogsOnLeash != "" | DogsOffLeash != "") & !(Species %in% HUMANS))
      if (nrow(b) > 0) {
        flag("Dogs without people",
             "Off/on-leash dogs are classified without people in these images. If possible, move the dog classification to the image classified with people.", b)
      }
    } else if (!"Episode" %in% names(a)) {
      flag("Dogs (MegaDetector)",
           "Couldn't check for duplicate dog classifications because the Episode field is missing.",
           type = "info")
    } else {
      b <- a %>%
        filter(DogsOnLeash != "" | DogsOffLeash != "") %>%
        mutate(Episode2 = str_extract(Episode, "^[^:]+"))
      dup <- b$Episode2[duplicated(b$Episode2)]
      if (length(dup) > 0) {
        flag("Dogs in one episode",
             "Dogs are classified as on/off leash more than once within the same episode. Move all counts to one image.",
             b[b$Episode2 %in% dup, ])
      }
    }

    # Horses --------------------------------------------------------------------
    b <- a %>% filter(Horses != "" & Species != "Horse Rider")
    if (nrow(b) > 0) {
      flag("Horses without riders",
           "Horses are classified without the 'Horse Rider' species in these images. Move the horses to the image with 'Horse Rider', or use 'Horse Domestic' or 'Horse Wild' if no riders were seen.", b)
    }

    b <- a %>% filter(Species == "Horse Rider" & Horses == "")
    if (nrow(b) > 0) {
      flag("Horse riders without horses",
           "Horses were not counted in these horse-rider images.", b)
    }

    b <- a %>% filter(Species == "Horse Domestic")
    if (nrow(b) > 0) {
      flag("Horse Domestic",
           "These images use the 'Horse Domestic' species. Only use this if no humans were seen in the episode.",
           b, type = "review")
    }

    # Illegal activity ----------------------------------------------------------
    b <- a %>% filter(Illegal == "Yes")
    dup <- b$EpManual[duplicated(b$EpManual)]
    if (length(dup) > 0) {
      flag("Illegal flags",
           "Illegal is flagged more than once within the same episode. Use only one illegal flag per episode.",
           b[b$EpManual %in% dup, ])
    }

    b <- a %>% filter(Illegal == "Yes" & CommentsImages == "")
    if (nrow(b) > 0) {
      flag("Illegal without comment",
           "These images are flagged illegal without a comment describing the behaviour.", b)
    }

    b <- a %>% filter(Species == "Quad/Vehicle/Motorbike" & CommentsImages == "")
    if (nrow(b) > 0) {
      flag("Vehicle without comment",
           "These vehicle images are missing a comment. They are either illegal or should be commented as Parks staff.", b)
    }

    # Multiple classifications in an episode ------------------------------------
    # Skipped for MegaDetector folders and for locations starting with "93"
    # (the original regex "^93S*" matched anything starting with 93).
    dup_groups <- a %>% count(EpManual, Species, Location) %>% filter(n > 1)
    if (nrow(dup_groups) > 0 && !MD && !any(str_detect(dup_groups$Location, "^93"))) {
      rows <- a %>% semi_join(dup_groups, by = c("EpManual", "Species", "Location"))
      flag("Multiple classifications in an episode",
           "These images are classified more than once within the same episode (could be comments, illegal flags, or the same species classified twice).",
           rows)
    }
  }

  # Noon timelapse images and CameraObscured ------------------------------------
  effort <- summarise_effort(TL_data)
  if (length(effort$timelapse_ids) == 0) {
    flag("Noon timelapse images",
         "No noon timelapse images were found (images taken at exactly 12:00:00). Camera effort is counted from the first image to the last.",
         type = "info")
  } else if (length(effort$missing_noon) > 0) {
    n <- length(effort$missing_noon)
    flag("Missing noon images",
         sprintf("There is no noon timelapse image on %d day%s: %s. The camera may have stopped or been moved on these days. Check them, and adjust the camera effort if the camera wasn't working.",
                 n, if (n == 1) "" else "s", format_days(effort$missing_noon)),
         type = "review")
  }

  if (length(effort$obscured_days) > 0) {
    dt <- suppressWarnings(as_datetime(TL_data$DateTime))
    day <- as.Date(dt)
    is_obscured <- TL_data$Species == "CameraObscured"
    is_animal <- TL_data$Species != "" & !TL_data$Species %in% NOT_ANIMALS
    clash <- sort(unique(day[is_obscured & !is.na(day) & day %in% day[is_animal]]))
    if (length(clash) > 0) {
      rows <- TL_data[day %in% clash & (is_obscured | is_animal), , drop = FALSE]
      rows <- rows[order(rows$DateTime), , drop = FALSE]
      flag("CameraObscured on a day with animals",
           sprintf("CameraObscured is tagged on the same day as an animal (%s). If the camera could see the animal, it may not have been obscured all day. Check the CameraObscured tag, because obscured days are taken off the camera effort.",
                   format_days(clash)),
           rows, type = "review")
    }
  }

  issues_df <- tibble::tibble(
    check   = vapply(issues, function(x) x$check, character(1)),
    type    = vapply(issues, function(x) x$type, character(1)),
    message = vapply(issues, function(x) x$message, character(1)),
    ids     = lapply(issues, function(x) x$ids),
    files   = lapply(issues, function(x) x$files)
  )
  # Order: things to fix, then things to check, then notes
  issues_df <- issues_df[order(match(issues_df$type, c("issue", "review", "info"))), ]

  list(
    issues = issues_df,
    data = TL_data,
    classified_ids = as.character(a$Id),
    summary = list(
      n_images     = nrow(TL_data),
      n_classified = nrow(a),
      n_episodes   = max(TL_data$EpManual),
      locations    = setdiff(unique(a$Location), ""),
      classifiers  = setdiff(unique(a$Classifier), ""),
      megadetector = MD,
      effort       = effort
    )
  )
}


# Flatten issues to one row per image, for the CSV download --------------------
issues_to_csv_table <- function(issues) {
  if (nrow(issues) == 0) {
    return(tibble::tibble(check = character(), type = character(),
                          message = character(), id = character(), file = character()))
  }
  issues %>%
    unnest(c(ids, files), keep_empty = TRUE) %>%
    rename(id = ids, file = files) %>%
    mutate(id = replace_na(id, ""), file = replace_na(file, ""))
}
