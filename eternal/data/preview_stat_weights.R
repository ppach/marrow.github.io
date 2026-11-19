# A quick preview of the Stat Weights chapter, with the two chapters it builds on, in _preview/. It runs no new
# wowsims sims: anything not cached yet is left blank. Run from eternal/:  Rscript data/preview_stat_weights.R
options(wowsims.cached_only = TRUE, wowsims.offline = TRUE)   # no wowsims update mid-preview
bookdown::render_book("index.Rmd", config_file = "_preview_bookdown.yml", quiet = TRUE)
