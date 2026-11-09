# This file only needs to exist. It stops Shiny from sourcing the R/ folder on its
# own before app.R runs, so app.R can install any missing packages first and then
# source R/checks.R and R/ddb_io.R itself.
