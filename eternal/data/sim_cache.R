# Saved simulation results, so the book doesn't re-run every simulation on each render.
#
# cached_sim("name", deps = list(...), { code }) returns the saved result from data/sim_cache/name.rds
# when nothing it depends on has changed, and otherwise runs the code and saves the result. A result
# is re-run when any of these change:
#   - the simulation code (data/fight_sim.R or data/flurry.R),
#   - the code inside the braces,
#   - anything passed in `deps` (the inputs the code uses, such as the gear table or the number of fights).
# The code should set its own seed, so a re-run gives the same result. To force every simulation to
# re-run, delete data/sim_cache/.

sim_code_hash <- function() unname(tools::md5sum(c("data/fight_sim.R", "data/flurry.R")))

cached_sim <- function(name, deps, code) {
  dir.create("data/sim_cache", showWarnings = FALSE)
  path <- file.path("data/sim_cache", paste0(name, ".rds"))
  key  <- rlang::hash(list(sim_code_hash(), deparse(substitute(code)), deps))
  if (file.exists(path)) {
    saved <- readRDS(path)
    if (identical(saved$key, key)) return(saved$value)
  }
  message("Running simulation: ", name)
  value <- code
  saveRDS(list(key = key, value = value), path)
  value
}
