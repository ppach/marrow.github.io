# Render the Eternal book and publish it to Posit Connect Cloud (account: ppach).
# Run from this directory: Rscript deploy.R
# Requires: bookdown, rsconnect (>= 1.8), pandoc, and a saved login (rsconnect::connectCloudUser()).

bookdown::render_book("index.Rmd", "bookdown::gitbook")

# rendering wipes _book/, so restore the tracked deployment record. It pins the existing
# content, so redeploys update it instead of creating a duplicate.
file.copy("rsconnect", "_book", recursive = TRUE)

rsconnect::deployApp(
  appDir = "_book",
  appName = "marrow_eternal_compendium",
  appTitle = "Marrow's Eternal Compendium of Dragonslaying",
  account = "ppach",
  server = "connect.posit.cloud",
  launch.browser = FALSE,
  forceUpdate = TRUE
)
