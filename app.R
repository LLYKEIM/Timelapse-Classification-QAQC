# Timelapse Classification QA/QC
# Run with: shiny::runApp("path/to/Timelapse-Classification-QAQC")
#
# This app is meant to run on your own computer: it reads the .ddb in place,
# shows images from the same folder, and saves edits back into the .ddb.

# Stop early with a clear message if a package is missing
local({
  needed <- c("shiny", "bslib", "DT", "dplyr", "tidyr", "stringr", "lubridate",
              "RSQLite", "DBI", "jsonlite")
  missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop("Install these packages first:\n  install.packages(c(",
         paste0('"', missing, '"', collapse = ", "), "))", call. = FALSE)
  }
})

library(shiny)
library(bslib)

# Load the helper files explicitly (rather than relying on Shiny's R/ autoload),
# and stop with a clear message if one is missing.
local({
  for (f in c("R/checks.R", "R/ddb_io.R")) {
    if (!file.exists(f)) {
      stop("Missing ", f, " - copy the whole R folder from the latest zip into the app folder.")
    }
    source(f, local = globalenv())
  }
})

TYPE_STYLE <- list(
  issue  = list(label = "Fix",   colour = "danger"),
  review = list(label = "Check", colour = "warning"),
  info   = list(label = "Note",  colour = "info")
)

AGE_SEX_ABBR <- c(AdultFemale = "AF", AdultMale = "AM", AdultUnknown = "AU",
                  Subadult = "SA", YLY = "YLY", YOY = "YOY", Unknown = "UNK")

# JavaScript that tells the server to open the image viewer from an issue card
js_open <- function(issue_index, id) {
  sprintf(
    "Shiny.setInputValue('open_viewer', {issue: %d, id: %s}, {priority: 'event'}); return false;",
    as.integer(issue_index), jsonlite::toJSON(as.character(id), auto_unbox = TRUE)
  )
}

js_jump <- function(id) {
  sprintf("Shiny.setInputValue('viewer_jump', %s, {priority: 'event'}); return false;",
          jsonlite::toJSON(as.character(id), auto_unbox = TRUE))
}

issue_card <- function(i, check, type, message, ids, files) {
  style <- TYPE_STYLE[[type]]
  n <- length(files)

  file_list <- if (n > 0) {
    tags$details(
      open = if (n <= 10) NA else NULL,
      tags$summary(sprintf("%d image%s", n, if (n == 1) "" else "s")),
      div(class = "file-list",
          lapply(seq_len(n), function(k) {
            div(tags$a(href = "#", onclick = js_open(i, ids[k]), files[k]))
          }))
    )
  }

  card(
    fill = FALSE,
    class = paste0("issue-card mb-3 border-start border-4 border-", style$colour),
    card_header(
      class = "d-flex align-items-center",
      span(class = paste0("badge text-bg-", style$colour, " me-2"), style$label),
      span(check),
      if (n > 0) tags$button(class = "btn btn-sm btn-outline-secondary ms-auto",
                             onclick = js_open(i, ids[1]), "Review images")
    ),
    card_body(p(message, class = "mb-2"), file_list)
  )
}

# "2 AF, 1 YOY" from the age/sex count columns of a data frame
age_sex_summary <- function(df) {
  cols <- intersect(names(AGE_SEX_ABBR), names(df))
  if (!length(cols) || !nrow(df)) return(rep("", nrow(df)))
  vapply(seq_len(nrow(df)), function(i) {
    vals <- suppressWarnings(as.numeric(unlist(df[i, cols])))
    keep <- !is.na(vals) & vals > 0
    paste(paste(vals[keep], AGE_SEX_ABBR[cols][keep]), collapse = ", ")
  }, character(1))
}

ui <- page_sidebar(
  title = "Timelapse Classification QA/QC",
  theme = bs_theme(version = 5),
  # Don't squeeze content to fit the window height; let the page scroll instead
  fillable = FALSE,
  tags$head(tags$style(HTML("
    .issue-card { flex-shrink: 0; min-height: fit-content; }
    .issue-card .card-body { overflow: visible; }
    .media-missing { padding: 3rem 1rem; text-align: center; background: #222;
                     color: #ddd; border-radius: 6px; }
    .file-list { font-family: monospace; font-size: 0.85rem;
                 max-height: 240px; overflow-y: auto; margin-top: 0.5rem; }
    details summary { cursor: pointer; color: var(--bs-secondary-color); }
    .viewer-media { width: 100%; max-height: 62vh; object-fit: contain;
                    background: #111; border-radius: 6px; }
    .ep-strip { display: flex; gap: 6px; overflow-x: auto; padding: 6px 0; }
    .ep-strip a { flex: 0 0 auto; border: 3px solid transparent; border-radius: 4px;
                  text-decoration: none; }
    .ep-strip a.current { border-color: var(--bs-primary); }
    .ep-strip img, .ep-strip .vid { height: 72px; display: block; border-radius: 2px; }
    .ep-strip .vid { width: 100px; background: #333; color: #fff; font-size: 0.75rem;
                     display: flex; align-items: center; justify-content: center; }
    .ep-strip a.flagged img { outline: 2px dashed var(--bs-danger); outline-offset: -2px; }
    .edit-form { max-height: 62vh; overflow-y: auto; padding-right: 6px; }
    .edit-form .form-group, .edit-form .shiny-input-container { margin-bottom: 0.5rem; }
    .edit-grid { display: grid; grid-template-columns: 1fr 1fr; column-gap: 10px; }
    #review_table tbody tr { cursor: pointer; }
    .tab-content { padding-top: 1rem; }
  "))),
  sidebar = sidebar(
    width = 340,
    actionButton("browse", "Choose .ddb file…", icon = icon("folder-open"),
                 class = "btn-primary w-100"),
    helpText("Pick the .ddb in the folder you classified. The file dialog can open behind your browser window."),
    textInput("path_text", "…or paste the full path to the .ddb", width = "100%",
              placeholder = "C:/Cameras/BAN-042/TimelapseData.ddb"),
    actionButton("load_path", "Load", class = "btn-outline-secondary w-100"),
    actionButton("rerun", "Re-run checks", icon = icon("rotate"),
                 class = "btn-outline-secondary w-100"),
    uiOutput("template_status"),
    div(class = "alert alert-warning small mb-0",
        strong("Before editing: "),
        "close this folder in Timelapse. A backup copy of the .ddb is saved next to it before your first change."),
    uiOutput("download_ui")
  ),
  uiOutput("summary_ui"),
  navset_underline(
    id = "main_tabs",
    nav_panel("Checks", value = "checks", uiOutput("issues_ui")),
    nav_panel(
      "Review classifications", value = "review",
      layout_columns(
        fill = FALSE, col_widths = c(5, 4, 3),
        selectizeInput("review_species", "Species", choices = NULL, multiple = TRUE,
                       width = "100%", options = list(placeholder = "All species")),
        radioButtons("review_mode", "One row per", inline = TRUE,
                     choices = c("Classified image" = "image", "Episode" = "episode")),
        checkboxInput("review_flagged", "Only images with issues", value = FALSE)
      ),
      p(class = "small text-muted",
        "Click a row to open its images. Previous/Next steps through the rows in the order shown, ",
        "so sort or search the table first to review one species or one episode at a time."),
      DT::DTOutput("review_table")
    )
  )
)

server <- function(input, output, session) {

  ddb_path   <- reactiveVal(NULL)
  img_base   <- reactiveVal(NULL)
  reload     <- reactiveVal(0)
  backed_up  <- reactiveVal(character(0))
  viewer     <- reactiveVal(NULL)

  # Loading a .ddb ------------------------------------------------------------
  set_path <- function(p) {
    # R serves the images from the .ddb's folder (see serve_image in R/ddb_io.R).
    # A fresh name per load means images from a previous folder aren't cached.
    img_base(session$registerDataObj(
      name = paste0("tlimg", sample.int(1e8, 1)),
      data = dirname(p),
      filterFunc = serve_image
    ))
    ddb_path(p)
    viewer(NULL)
    updateTextInput(session, "path_text", value = p)
  }

  observeEvent(input$browse, {
    p <- choose_ddb()
    if (!is.null(p)) set_path(p)
  })

  observeEvent(input$load_path, {
    p <- trimws(gsub('^"|"$', "", trimws(input$path_text)))  # allow quoted paths
    if (p == "" || !file.exists(p) || dir.exists(p)) {
      showNotification("No .ddb file found at that path.", type = "error")
    } else {
      set_path(normalizePath(p, winslash = "/"))
    }
  })

  observeEvent(input$rerun, reload(reload() + 1))

  result <- reactive({
    req(ddb_path())
    reload()
    tryCatch(
      run_checks(read_timelapse_ddb(ddb_path())),
      error = function(e) list(error = conditionMessage(e))
    )
  })

  # The Timelapse template stored in the .ddb (field order, labels, dropdowns)
  template <- reactive({
    req(ddb_path())
    tryCatch(read_template(ddb_path()),
             error = function(e) structure(list(), error = conditionMessage(e)))
  })

  output$template_status <- renderUI({
    req(ddb_path())
    t <- template()
    err <- attr(t, "error")
    if (!is.null(err)) {
      return(div(class = "alert alert-danger small mb-0",
                 strong("Couldn't read the template: "), err,
                 br(), "Fields will show as plain text boxes."))
    }
    n_drop <- sum(lengths(t$Choices) > 0)
    if (nrow(t) == 0 || n_drop == 0) {
      return(div(class = "alert alert-secondary small mb-0",
                 "No dropdown lists found in this .ddb's template, so fields show as text boxes."))
    }
    div(class = "small text-muted",
        icon("list"), sprintf(" Template: %d fields, %d dropdowns (%s)", nrow(t), n_drop,
                              paste(t$DataLabel[lengths(t$Choices) > 0], collapse = ", ")))
  })

  # Summary and issue list ----------------------------------------------------
  output$summary_ui <- renderUI({
    if (is.null(ddb_path())) {
      return(div(class = "text-muted p-4",
                 "Choose a .ddb file on the left to check its classifications."))
    }
    res <- result()
    if (!is.null(res$error)) {
      return(div(class = "alert alert-danger",
                 strong("Couldn't read this file. "), res$error))
    }

    s <- res$summary
    n_fix <- sum(res$issues$type == "issue")
    n_check <- sum(res$issues$type == "review")

    tagList(
      p(class = "small text-muted mb-2", icon("database"), " ", ddb_path()),
      layout_columns(
        fill = FALSE,
        value_box("Images", format(s$n_images, big.mark = ",")),
        value_box("Classified images", format(s$n_classified, big.mark = ",")),
        value_box("Episodes", format(s$n_episodes, big.mark = ",")),
        value_box("To fix / to check", paste(n_fix, "/", n_check),
                  theme = if (n_fix > 0) "danger" else if (n_check > 0) "warning" else "success")
      ),
      p(class = "text-muted small mt-2",
        strong("Location: "), if (length(s$locations)) paste(s$locations, collapse = ", ") else "none",
        HTML(" &nbsp;\u00B7&nbsp; "),
        strong("Classifier: "), if (length(s$classifiers)) paste(s$classifiers, collapse = ", ") else "none")
    )
  })

  output$issues_ui <- renderUI({
    req(ddb_path())
    res <- result()
    if (!is.null(res$error)) return(NULL)
    issues <- res$issues

    ok <- if (!any(issues$type %in% c("issue", "review"))) {
      div(class = "alert alert-success",
          strong("No problems found."), " This folder passed every check.")
    }

    tagList(
      ok,
      lapply(seq_len(nrow(issues)), function(i) {
        issue_card(i, issues$check[i], issues$type[i], issues$message[i],
                   issues$ids[[i]], issues$files[[i]])
      })
    )
  })

  output$download_ui <- renderUI({
    req(ddb_path())
    res <- result()
    if (!is.null(res$error) || nrow(res$issues) == 0) return(NULL)
    downloadButton("download", "Download issues (CSV)", class = "btn-outline-primary w-100")
  })

  output$download <- downloadHandler(
    filename = function() {
      paste0(tools::file_path_sans_ext(basename(ddb_path())), "_issues.csv")
    },
    content = function(file) {
      write.csv(issues_to_csv_table(result()$issues), file, row.names = FALSE)
    }
  )

  # Review classifications tab ------------------------------------------------
  # Keep the species filter's choices up to date, without losing the selection
  observe({
    res <- result(); req(is.null(res$error))
    cls <- res$data[res$data$Id %in% res$classified_ids, , drop = FALSE]
    species <- sort(setdiff(unique(cls$Species), ""))
    keep <- intersect(isolate(input$review_species), species)
    updateSelectizeInput(session, "review_species", choices = species, selected = keep)
  })

  review_rows <- reactive({
    res <- result(); req(is.null(res$error))
    d <- res$data
    flagged_ids <- unique(unlist(res$issues$ids[res$issues$type != "info"]))
    cls <- d[d$Id %in% res$classified_ids, , drop = FALSE]
    if (length(input$review_species)) cls <- cls[cls$Species %in% input$review_species, , drop = FALSE]
    if (isTRUE(input$review_flagged)) cls <- cls[cls$Id %in% flagged_ids, , drop = FALSE]
    cls <- cls[order(cls$DateTime, as.numeric(cls$Id)), , drop = FALSE]
    cls$Flags <- vapply(cls$Id, function(id) {
      sum(vapply(res$issues$ids, function(x) id %in% x, logical(1)))
    }, integer(1))

    get_col <- function(df, col) if (col %in% names(df)) df[[col]] else rep("", nrow(df))

    if (identical(input$review_mode, "episode")) {
      if (nrow(cls) == 0) {
        return(data.frame(Id = character(), Episode = integer(), Start = character(),
                          `Images in episode` = integer(), Species = character(),
                          Counts = character(), Comments = character(), Flags = integer(),
                          check.names = FALSE))
      }
      ep_sizes <- table(d$EpManual)
      eps <- unique(cls$EpManual)
      do.call(rbind, lapply(eps, function(e) {
        x <- cls[cls$EpManual == e, , drop = FALSE]
        counts <- age_sex_summary(x)
        totals <- paste(ifelse(x$Total == "", "", paste0(x$Species, ": ", x$Total)))
        data.frame(
          Id = x$Id[1],
          Episode = as.integer(e),
          Start = x$DateTime[1],
          `Images in episode` = as.integer(ep_sizes[[as.character(e)]]),
          Species = paste(unique(x$Species[x$Species != ""]), collapse = ", "),
          Counts = paste(c(totals[totals != ""], counts[counts != ""]), collapse = "; "),
          Comments = paste(unique(x$CommentsImages[x$CommentsImages != ""]), collapse = "; "),
          Flags = sum(x$Flags),
          check.names = FALSE, stringsAsFactors = FALSE
        )
      }))
    } else {
      data.frame(
        Id = cls$Id,
        Image = cls$Label,
        `Date/time` = cls$DateTime,
        Episode = as.integer(cls$EpManual),
        Species = cls$Species,
        Total = cls$Total,
        `Age/sex` = age_sex_summary(cls),
        Colour = get_col(cls, "ColourMarkings"),
        Behaviour = get_col(cls, "Behaviour"),
        Comments = cls$CommentsImages,
        Flags = cls$Flags,
        check.names = FALSE, stringsAsFactors = FALSE
      )
    }
  })

  output$review_table <- DT::renderDT({
    rows <- review_rows()
    DT::datatable(
      rows,
      rownames = FALSE,
      selection = "single",
      filter = "none",
      options = list(
        pageLength = 25, lengthMenu = c(25, 50, 100, 500), scrollX = TRUE,
        order = list(), # keep the date/time order we built
        columnDefs = list(list(targets = 0, visible = FALSE))
      )
    ) |>
      DT::formatStyle("Flags", color = DT::styleInterval(0, c("inherit", "#b02a37")),
                      fontWeight = DT::styleInterval(0, c("normal", "bold")))
  })

  review_proxy <- DT::dataTableProxy("review_table")

  observeEvent(input$review_table_rows_selected, {
    rows <- review_rows()
    sel <- input$review_table_rows_selected
    shown <- input$review_table_rows_all %||% seq_len(nrow(rows))  # display order
    DT::selectRows(review_proxy, NULL)  # so clicking the same row again works
    req(length(sel) == 1, sel <= nrow(rows))
    title <- if (identical(input$review_mode, "episode")) "Review: episodes" else "Review: classified images"
    open_viewer(title, as.character(rows$Id[shown]), as.character(rows$Id[sel]))
  })

  # Image viewer --------------------------------------------------------------
  open_viewer <- function(title, ids, current) {
    viewer(list(title = title, ids = ids,
                pos = max(1, match(current, ids, nomatch = 1)),
                current = as.character(current)))
    showModal(modalDialog(
      uiOutput("viewer_body"),
      size = "xl", easyClose = TRUE,
      footer = tagList(
        actionButton("prev_img", "\u2039 Previous"),
        actionButton("next_img", "Next \u203A"),
        modalButton("Close")
      )
    ))
  }

  observeEvent(input$open_viewer, {
    ev <- input$open_viewer
    issues <- result()$issues
    i <- as.integer(ev$issue)
    req(i >= 1, i <= nrow(issues))
    open_viewer(issues$check[i], issues$ids[[i]], ev$id)
  })

  step_viewer <- function(by) {
    v <- viewer(); req(v, length(v$ids) > 0)
    v$pos <- min(max(1, v$pos + by), length(v$ids))
    v$current <- v$ids[v$pos]
    viewer(v)
  }
  observeEvent(input$prev_img, step_viewer(-1))
  observeEvent(input$next_img, step_viewer(1))

  observeEvent(input$viewer_jump, {
    v <- viewer(); req(v)
    v$current <- as.character(input$viewer_jump)
    viewer(v)
  })

  output$viewer_body <- renderUI({
    v <- viewer(); req(v)
    res <- result(); req(is.null(res$error))
    d <- res$data

    row <- d[d$Id == v$current, , drop = FALSE]
    if (nrow(row) == 0) {
      return(div(class = "alert alert-warning", "This image is no longer in the database."))
    }
    row <- as.list(row[1, ])

    folder <- dirname(ddb_path())
    base <- img_base()
    disk <- image_disk_path(folder, row$RelativePath, row$FileName)
    url  <- image_url(base, row$RelativePath, row$FileName)

    media <- if (!file.exists(disk)) {
      div(class = "media-missing",
          strong("Image not found on disk"), br(), code(disk),
          p(class = "small mt-2 mb-0",
            "The .ddb needs to be in the same folder as the images it was made from."))
    } else if (is_video(row$FileName)) {
      tags$video(src = url, controls = NA, class = "viewer-media")
    } else {
      tags$a(href = url, target = "_blank", title = "Open full size",
             tags$img(src = url, class = "viewer-media", alt = row$Label,
                      onerror = "this.outerHTML = '<div class=\"media-missing\">The image is on disk but couldn\\'t be displayed. Try opening it in Timelapse.</div>';"))
    }

    # Other images in the same episode, as clickable thumbnails
    ep <- d[d$EpManual == row$EpManual, , drop = FALSE]
    ep <- ep[order(ep$DateTime, as.numeric(ep$Id)), , drop = FALSE]
    k <- match(row$Id, ep$Id)
    ep <- ep[max(1, k - 10):min(nrow(ep), k + 10), , drop = FALSE]
    flagged_ids <- unique(unlist(res$issues$ids))
    strip <- div(class = "ep-strip", lapply(seq_len(nrow(ep)), function(j) {
      cls <- paste(if (ep$Id[j] == row$Id) "current", if (ep$Id[j] %in% flagged_ids) "flagged")
      tip <- paste0(ep$Label[j], if (ep$Species[j] != "") paste0(" \u2013 ", ep$Species[j]))
      thumb <- if (is_video(ep$FileName[j])) {
        div(class = "vid", "\u25B6 video")
      } else {
        tags$img(src = image_url(base, ep$RelativePath[j], ep$FileName[j]), loading = "lazy")
      }
      tags$a(href = "#", class = cls, title = tip, onclick = js_jump(ep$Id[j]), thumb)
    }))
    n_ep <- sum(d$EpManual == row$EpManual)

    # Checks that flagged this image
    other <- res$issues$check[vapply(res$issues$ids, function(x) row$Id %in% x, logical(1))]

    # Edit form: fields in the same order and with the same labels as Timelapse
    tmpl <- template()
    if (!is.data.frame(tmpl)) tmpl <- NULL
    fields <- intersect(EDIT_FIELDS, names(d))
    if (!is.null(tmpl) && nrow(tmpl) > 0) {
      fields <- c(intersect(tmpl$DataLabel, fields), setdiff(fields, tmpl$DataLabel))
    }
    tmpl_row <- function(f) {
      if (is.null(tmpl)) return(NULL)
      i <- match(f, tmpl$DataLabel)
      if (is.na(i)) NULL else list(label = tmpl$Label[i], type = tmpl$Type[i],
                                   tooltip = tmpl$Tooltip[i], choices = tmpl$Choices[[i]])
    }
    is_counter <- function(f) {
      t <- tmpl_row(f)
      if (is.null(t)) f %in% COUNT_COLS else identical(t$type, "Counter")
    }
    field_input <- function(f) {
      t <- tmpl_row(f)
      id <- paste0("f_", f); val <- row[[f]] %||% ""
      label <- span(title = t$tooltip %||% "", t$label %||% f)
      if (f == "CommentsImages") {
        textAreaInput(id, label, val, rows = 2, width = "100%")
      } else if (length(t$choices)) {
        # A plain dropdown (not selectize): it works reliably inside the pop-up.
        # The current value is kept even if it isn't in the template's list.
        opts <- unique(c(t$choices, val))
        opts <- opts[opts != ""]
        selectInput(id, label, choices = c("(blank)" = "", stats::setNames(opts, opts)),
                    selected = val, selectize = FALSE, width = "100%")
      } else {
        textInput(id, label, val, width = "100%")
      }
    }
    # Group runs of counter fields into a two-column grid
    runs <- rle(vapply(fields, is_counter, logical(1)))
    ends <- cumsum(runs$lengths); starts <- ends - runs$lengths + 1
    form_blocks <- lapply(seq_along(runs$values), function(r) {
      fs <- fields[starts[r]:ends[r]]
      inputs <- lapply(fs, field_input)
      if (runs$values[r]) div(class = "edit-grid", inputs) else inputs
    })

    pos_text <- if (row$Id %in% v$ids) {
      sprintf("%d of %d in \u201c%s\u201d", match(row$Id, v$ids), length(v$ids), v$title)
    } else {
      "Another image in this episode"
    }

    tagList(
      div(class = "d-flex justify-content-between align-items-baseline mb-1",
          h5(class = "mb-0", row$Label),
          span(class = "text-muted small", pos_text)),
      p(class = "small text-muted mb-2",
        row$DateTime, HTML(" &nbsp;\u00B7&nbsp; "), "Episode ", row$EpManual,
        if (length(other)) tagList(HTML(" &nbsp;\u00B7&nbsp; "),
                                   span(class = "text-danger", "Flagged by: ",
                                        paste(other, collapse = "; ")))),
      layout_columns(
        col_widths = breakpoints(sm = c(12, 12), lg = c(8, 4)),
        div(media,
            div(class = "small text-muted mt-2",
                sprintf("Episode %s: %d image%s (blue = this image, dashed = flagged; hover for species)",
                        row$EpManual, n_ep, if (n_ep == 1) "" else "s"),
                if (n_ep > nrow(ep)) " \u2013 showing the 21 nearest"),
            strip),
        div(
          div(class = "edit-form", form_blocks),
          actionButton("save_edit", "Save changes", icon = icon("floppy-disk"),
                       class = "btn-primary w-100 mt-2")
        )
      )
    )
  })

  # Saving edits --------------------------------------------------------------
  observeEvent(input$save_edit, {
    v <- viewer(); req(v)
    res <- result(); req(is.null(res$error))
    row <- res$data[res$data$Id == v$current, , drop = FALSE]
    req(nrow(row) == 1)

    fields <- intersect(EDIT_FIELDS, names(res$data))
    new_vals <- lapply(fields, function(f) {
      x <- input[[paste0("f_", f)]]
      if (is.null(x)) row[[f]] else stringr::str_squish(as.character(x))
    })
    names(new_vals) <- fields
    changed <- new_vals[vapply(fields, function(f) !identical(new_vals[[f]], row[[f]]), logical(1))]

    if (length(changed) == 0) {
      showNotification("Nothing changed.", duration = 3)
      return()
    }

    path <- ddb_path()
    tryCatch({
      if (!path %in% backed_up()) {
        bak <- backup_ddb(path)
        backed_up(c(backed_up(), path))
        showNotification(paste("Backup saved:", basename(bak)), duration = 6)
      }
      write_ddb_fields(path, v$current, changed)
      showNotification(sprintf("Saved %s for %s", paste(names(changed), collapse = ", "), row$Label),
                       type = "message", duration = 4)
      reload(reload() + 1)  # re-run the checks with the new values
    }, error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("locked", msg, ignore.case = TRUE)) {
        msg <- "The .ddb is locked. Close the folder in Timelapse and try again."
      }
      showNotification(paste("Couldn't save:", msg), type = "error", duration = NULL)
    })
  })
}

shinyApp(ui, server)
