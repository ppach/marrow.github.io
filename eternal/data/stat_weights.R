# The Stat Weights chapter's wowsims runs: the book's warrior at a gear point, and the same warrior one small step
# either side in each stat, so the difference is the stat's weight there (a central difference). Every run of a point
# and its steps uses the same random seed, so they share most of their luck and the differences are precise.
#
# A gear point is one row with these columns (shares, as in the rest of the book: 0.28 is 28%):
#   dps    weapon DPS (both weapons; 2.7 and 2.0 speed)    ap     attack power on the character sheet
#   crit   crit in the fight (sheet + Berserker Stance)     hit    hit from gear
#   haste  attack speed from gear (10 rating per 1%)        exp    expertise (10 rating per 1%; 1% takes 1% off dodge)
#   skill  weapon skill from gear (no race gets any in Forever), e.g. 5 for +5
source("data/wowsims.R")

sw_cols  <- c("dps", "ap", "crit", "hit", "haste", "exp", "skill")
# The step each side of the point, for each stat. Percent stats step by 1%, attack power by 50, weapon DPS by 1.
sw_steps <- c(ap = 50, crit = 0.01, hit = 0.01, haste = 0.01, exp = 0.01, dps = 1)
sw_pct   <- c("crit", "hit", "haste", "exp")   # weights of these are per 1%; the others per point

sw_fill <- function(pts) {
  pts <- tibble::as_tibble(pts)
  for (c in setdiff(sw_cols, names(pts))) pts[[c]] <- 0
  pts
}

# Mean DPS in wowsims for each row of `pts`, at `iters` iterations and random seed `seed` (cached per row).
sw_run <- function(pts, iters, seed) {
  pts <- as.data.frame(sw_fill(pts))[sw_cols]
  nm <- sprintf("sw_%.1f_%.0f_%.3f_%.3f_%.3f_%.3f_%d_i%d_s%d", pts$dps, pts$ap, pts$crit, pts$hit, pts$haste, pts$exp,
                as.integer(pts$skill), as.integer(iters), as.integer(seed))
  u <- which(!duplicated(nm))
  jobs <- stats::setNames(lapply(u, function(i) {
    x <- pts[i, ]
    p <- list(bonus_stats = c(haste_rating = x$haste * 1000, expertise_rating = x$exp * 1000))
    if (x$skill) p$weapon_skill <- x$skill
    list(dps = x$dps, ap = x$ap, crit = x$crit, hit = x$hit, p = p, iterations = iters, seed = seed)
  }), nm[u])
  res <- cached_wowsims_many(jobs)
  dps <- vapply(res, function(r) if (is.null(r)) NA_real_ else r$dps[["mean"]], 0)
  out <- unname(dps[nm])
  done <- Filter(Negate(is.null), res)
  attr(out, "version") <- if (length(done)) done[[1]]$version else wowsims_ensure()
  out
}

# Weights at each row of `pts`: w_<stat> for each stat in `stats` (DPS per 1% for percent stats, per point for attack
# power and weapon DPS), sim_dps at the point, and w_skill5, what +5 weapon skill adds (a step, not a slope). Where a
# stat is too close to 0 for a step down, both steps go up instead (from 0 to 2%).
sw_weights <- function(pts, stats = names(sw_steps), iters, seed, with_skill = TRUE) {
  pts <- sw_fill(pts) %>% dplyr::mutate(.id = dplyr::row_number())
  rows <- list(dplyr::mutate(pts, .what = "base"))
  for (s in stats) {
    lo <- pmax(pts[[s]] - sw_steps[[s]], 0)
    rows <- c(rows, list(dplyr::mutate(pts, .what = paste0(s, "_lo"), !!s := lo),
                         dplyr::mutate(pts, .what = paste0(s, "_hi"), !!s := lo + 2 * sw_steps[[s]])))
  }
  if (with_skill) rows <- c(rows, list(dplyr::mutate(pts, .what = "skill5", skill = skill + 5)))
  all <- dplyr::bind_rows(rows)
  sim <- sw_run(all, iters, seed)
  all$sim <- as.numeric(sim)
  wide <- tidyr::pivot_wider(dplyr::select(all, .id, .what, sim), names_from = .what, values_from = sim)
  out <- dplyr::left_join(pts, wide, by = ".id")
  for (s in stats) {
    span <- 2 * sw_steps[[s]] * (if (s %in% sw_pct) 100 else 1)
    out[[paste0("w_", s)]] <- (out[[paste0(s, "_hi")]] - out[[paste0(s, "_lo")]]) / span
  }
  if (with_skill) out$w_skill5 <- out$skill5 - out$base
  out <- dplyr::select(out, -.id, -dplyr::ends_with("_lo"), -dplyr::ends_with("_hi"), -dplyr::any_of("skill5"))
  out <- dplyr::rename(out, sim_dps = base)
  attr(out, "version") <- attr(sim, "version")
  out
}

# ---- The chapter's runs ----------------------------------------------------------------------------------------------
# `gear` is the How Damage Scales chapter's table of phases (phase, dps, ap, crit); every phase has 7% hit, as the
# book's warrior does elsewhere. The chapter runs:
#   phases  weights for every stat at each phase, twice (seeds sw_seed and sw_seed2), at 20,000 iterations: the second seed
#           measures the noise
#   lines   the phase 2 warrior with one stat moved at a time, at 20,000 iterations
#   slice   weights for attack power, crit, hit, haste and expertise at every crit and hit, at five levels of attack
#           power, at 8,000 iterations; the 2000 attack power layer again with sw_seed2, for the noise
sw_hit0 <- 0.07
# wowsims seeds fight i with seed + i, so two runs only get different fights if their seeds are further apart than the
# number of fights. The second seed is far from the first for that reason.
sw_seed <- 7; sw_seed2 <- 1000007
sw_iters_fine <- 20000; sw_iters_grid <- 8000
sw_slice_ap   <- c(1000, 1500, 2000, 2500, 3000)
sw_slice_crit <- seq(0.15, 0.45, by = 0.05)
sw_slice_hit  <- seq(0, 0.15, by = 0.025)
sw_slice_dps  <- 58

sw_build <- function(gear) {
  ph <- dplyr::transmute(gear, phase, dps, ap, crit, hit = sw_hit0)
  p2 <- dplyr::filter(ph, phase == "Phase 2")
  one_stat <- function(stat, values) dplyr::mutate(sw_fill(dplyr::select(p2, -phase))[rep(1, length(values)), ],
                                                   stat = stat, x = values, !!stat := values)
  lines <- dplyr::bind_rows(
    one_stat("crit", seq(0.15, 0.45, by = 0.025)), one_stat("hit", seq(0, 0.15, by = 0.01)),
    one_stat("exp", seq(0, 0.08, by = 0.01)), one_stat("haste", seq(0, 0.20, by = 0.025)),
    one_stat("ap", seq(900, 2500, by = 100)), one_stat("skill", 0:15))
  lines$sim_dps <- as.numeric(sw_run(lines, sw_iters_fine, sw_seed))
  slice_pts <- tidyr::expand_grid(dps = sw_slice_dps, ap = sw_slice_ap, crit = sw_slice_crit, hit = sw_slice_hit) %>%
    dplyr::mutate(dplyr::across(c(crit, hit), ~ round(.x, 3)))
  slice_stats <- c("ap", "crit", "hit", "haste", "exp")
  list(
    phases = dplyr::bind_rows(
      dplyr::mutate(sw_weights(ph, iters = sw_iters_fine, seed = sw_seed), seed = sw_seed),
      dplyr::mutate(sw_weights(ph, iters = sw_iters_fine, seed = sw_seed2), seed = sw_seed2)),
    lines = lines,
    slice = sw_weights(slice_pts, slice_stats, iters = sw_iters_grid, seed = sw_seed, with_skill = FALSE),
    slice_repeat = sw_weights(dplyr::filter(slice_pts, ap == 2000), slice_stats, iters = sw_iters_grid, seed = sw_seed2,
                              with_skill = FALSE),
    version = wowsims_ensure())
}
