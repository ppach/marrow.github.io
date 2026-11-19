# Runs the Stat Weights chapter's wowsims sims ahead of a render (they're cached). Run from eternal/:
#   Rscript data/sw_prewarm.R
suppressMessages(library(tidyverse))
source("data/stat_weights.R")
gear <- tibble(phase = c("Pre-BiS", "Phase 1", "Phase 2", "Phase 3", "Phase 4"), dps = c(42, 51, 58, (58 + 73) / 2, 73),
               ap = c(1000, 1150, 1300, 1400, 1500), crit = c(0.20, 0.25, 0.28, 0.30, 0.32))
t0 <- Sys.time(); sw <- sw_build(gear); print(Sys.time() - t0)
print(as.data.frame(sw$phases))
