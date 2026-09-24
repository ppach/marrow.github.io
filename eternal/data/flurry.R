# Flurry as a Markov chain. Used by the Flurry chapter.
#
# The state is how many Flurry charges are left before a white swing (0 to charges - 1). On each
# swing, Flurry is triggered with probability `p` (a crit on that swing, or a yellow crit since the
# last one), which refills the charges. A swing is hasted when it triggers Flurry or a charge is left,
# and every hasted swing uses up one charge.

flurry_chain <- function(p, charges = 3) {
  k <- charges                      # states 0..k-1, stored at index state + 1
  P <- matrix(0, k, k)
  for (s in 0:(k - 1)) {
    P[s + 1, k] <- P[s + 1, k] + p                        # triggered: refilled, one charge used
    P[s + 1, max(s - 1, 0) + 1] <- P[s + 1, max(s - 1, 0) + 1] + (1 - p)
  }
  # long-run share of swings in each state: the left eigenvector of P for eigenvalue 1
  e <- eigen(t(P))
  pi <- Re(e$vectors[, which.min(abs(e$values - 1))]); pi <- pi / sum(pi)
  list(P = P, pi = pi, hasted = p + (1 - p) * (1 - pi[1]))
}

# Flurry for a warrior with white crit chance `crit_white` per swing (after crit suppression, and
# capped by the crit cap), plus `yellow_cps` yellow attacks per second that crit with `crit_yellow`.
# `swings_base` is white swings per second with no haste (1 / MH speed + 1 / OH speed).
# Yellow crits depend on the time between swings, which depends on Flurry, so we solve by iterating.
flurry_stats <- function(crit_white, haste = 0.25, charges = 3, yellow_cps = 0, crit_yellow = 0,
                         swings_base = 1 / 2.7 + 1 / 2.0) {
  h <- 0
  for (i in 1:100) {
    m <- h / (1 + haste) + (1 - h)                       # average swing time, relative to no haste
    q <- 1 - exp(-yellow_cps * crit_yellow * m / swings_base)
    p <- 1 - (1 - crit_white) * (1 - q)
    h_new <- flurry_chain(p, charges)$hasted
    if (abs(h_new - h) < 1e-12) break
    h <- h_new
  }
  m <- h / (1 + haste) + (1 - h)
  tibble::tibble(p_trigger = p, hasted_swings = h,
                 time_share = h / (1 + haste) / m,       # share of time the weapons swing hasted
                 swing_mult = 1 / m)                     # swings per second, relative to no Flurry
}

# The old Classic rule of thumb: uptime = 1 - (1 - crit)^A, with A = 4.
flurry_classic <- function(crit, A = 4) 1 - (1 - crit)^A
