# One-off: carry the Stat Weights chapter's cached wowsims results from one commit to another, without re-running them,
# when the two commits give the same numbers for the book's warrior. Run from eternal/:
#   Rscript data/sw_rekey.R <old commit, full hash>
# A result is re-keyed only if its stored key is exactly the key the old commit would give for the same job, so a
# result from any other setup or code is left alone (and is re-run as usual). Each re-keyed result keeps a note of the
# commit that produced it (value$rekeyed_from). On 2026-11-19, c831b30 -> 74a0545: 39 sims re-run at 74a0545 matched
# c831b30 to the cent, and the 16 commits between them touch nothing the book's warrior uses.
suppressMessages(library(tidyverse))
source("data/stat_weights.R")
old <- commandArgs(trailingOnly = TRUE)[[1]]
if (identical(old, "NULL")) old <- NULL   # results keyed with no commit (a session that missed its basis)
new_v <- wowsims_ensure()
basis <- wowsims_basis()   # the commit the caches are keyed on (see wowsims_basis() in data/wowsims.R)
moved <- 0L; kept <- 0L; other <- 0L

cached_wowsims_many <- function(jobs, workers = 1) {
  dir <- "data/sim_cache/wowsims/jobs"
  code <- lapply(list(book_wowsims, book_bonus_stats, book_weapon, wowsims_settings, wowsims_request, wowsims_siml), deparse)
  key_at <- function(j, commit) rlang::hash(list(j, commit, readLines(j$p$apl %||% wowsims_defaults$apl),
                                                 wowsims_defaults[setdiff(names(wowsims_defaults), "apl")], code))
  for (n in names(jobs)) {
    f <- file.path(dir, paste0(n, ".rds"))
    if (!file.exists(f)) { other <<- other + 1L; next }
    r <- readRDS(f)
    if (identical(r$key, key_at(jobs[[n]], basis))) { kept <<- kept + 1L; next }
    if (!identical(r$key, key_at(jobs[[n]], old))) { other <<- other + 1L; next }
    r$value$rekeyed_from <- r$value$rekeyed_from %||% r$value$version
    r$value$version <- readRDS("data/sim_cache/wowsims/basis.rds")$basis   # stamp it with the basis it stands for
    r$key <- key_at(jobs[[n]], basis)
    saveRDS(r, f)
    moved <<- moved + 1L
  }
  stats::setNames(lapply(names(jobs), function(n) NULL), names(jobs))
}

gear <- tibble(phase = c("Pre-BiS", "Phase 1", "Phase 2", "Phase 3", "Phase 4"), dps = c(42, 51, 58, (58 + 73) / 2, 73),
               ap = c(1000, 1150, 1300, 1400, 1500), crit = c(0.20, 0.25, 0.28, 0.30, 0.32))
invisible(suppressWarnings(try(sw_build(gear), silent = TRUE)))
cat(sprintf("re-keyed %d, already at the basis %d, left alone %d\n", moved, kept, other))
