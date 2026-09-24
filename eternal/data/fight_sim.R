# Event-based fight simulator for a level 60 dual-wield warrior against a boss.
# Used by the Rage Design Proposals chapter. Each white swing rolls on the attack table, and a
# rage model decides how much rage a landed swing gives. A simple priority rotation spends it.

sim_defaults <- list(
  fight_len = 180,        # seconds
  mh_speed = 2.7, oh_speed = 2.0,
  ap = 1200, armor = 0.75, crit = 0.30,
  miss = 0.20, dodge = 0.065, glance = 0.40, glance_dmg = 0.65,
  flurry_haste = 0.25, flurry_charges = 3,
  ubw_chance = 0.60, ubw_rage = 1,   # intended 5/5 rate; the logs show about 36% (see the Rage Generation chapter)
  gcd = 1.5,
  bt_cost = 30, bt_cd = 6, ww_cost = 25, ww_cd = 10,
  hs_cost = 13, hs_threshold = 60,   # queue Heroic Strike when rage is at least this much
  rage_cap = 100
)

# Rage for one landed white swing. `hand` is "MH" or "OH"; `dmg` is the landed damage (after armor,
# crit and glancing); `speed` is the weapon's tooltip speed.
make_rage_models <- function(forever_rates, C60, scale_rps, hybrid_alpha, hybrid_cap_rps) {
  # forever_rates: list(MH = vector of observed rage/speed, OH = ...) sampled from the logs
  forever_swing <- function(hand, speed) sample(forever_rates[[hand]], 1) * speed
  hand_share <- c(MH = 1 / 1.5, OH = 0.5 / 1.5)
  list(
    `Classic`              = function(hand, dmg, speed) 15 * dmg / C60,
    `Forever (today)`      = function(hand, dmg, speed) forever_swing(hand, speed),
    `Proposal: sigmoid`    = function(hand, dmg, speed) forever_swing(hand, speed) * scale_rps[["sigmoid"]],
    `Proposal: saturating` = function(hand, dmg, speed) forever_swing(hand, speed) * scale_rps[["saturating"]],
    `Proposal: hybrid`     = function(hand, dmg, speed) forever_swing(hand, speed) +
      min(hybrid_alpha * 15 * dmg / C60, hybrid_cap_rps * speed * hand_share[[hand]])
  )
}

simulate_fight <- function(rage_fn, wpn_dps, p = sim_defaults, trace = FALSE) {
  rage <- 0; t <- 0
  next_mh <- runif(1, 0, p$mh_speed); next_oh <- runif(1, 0, p$oh_speed)
  bt_ready <- 0; ww_ready <- 0; gcd_ready <- 0
  flurry <- 0; hs_queued <- FALSE
  wasted <- 0; starved <- 0; last_t <- 0; generated <- 0
  n <- c(bt = 0, ww = 0, hs = 0)
  tr <- if (trace) list() else NULL

  base_dmg <- function(speed, hand) {
    d <- (wpn_dps * speed + p$ap / 14 * speed) * p$armor
    if (hand == "OH") d * 0.5 else d
  }
  add_rage <- function(x) {
    generated <<- generated + x   # all rage from swings and procs, including what the cap wastes
    over <- max(rage + x - p$rage_cap, 0)
    wasted <<- wasted + over
    rage <<- min(rage + x, p$rage_cap)
  }

  while (t < p$fight_len) {
    # Next event: a swing, or the moment an ability comes off cooldown / off the global cooldown.
    # An ability that is already ready but unaffordable is not an event: only a swing can add rage.
    ability_t <- max(gcd_ready, min(bt_ready, ww_ready))
    t_new <- min(next_mh, next_oh, if (ability_t > t) ability_t else Inf)
    if (t_new > p$fight_len) break
    # Time spent with Bloodthirst ready but not enough rage to press it.
    if (bt_ready <= last_t && gcd_ready <= last_t && rage < p$bt_cost) starved <- starved + (t_new - last_t)
    t <- t_new; last_t <- t

    # Abilities, by priority, whenever the global cooldown is free.
    if (t >= gcd_ready) {
      if (t >= bt_ready && rage >= p$bt_cost) {
        rage <- rage - p$bt_cost; bt_ready <- t + p$bt_cd; gcd_ready <- t + p$gcd; n["bt"] <- n["bt"] + 1
      } else if (t >= ww_ready && rage >= p$ww_cost && t + 1 < bt_ready) {
        rage <- rage - p$ww_cost; ww_ready <- t + p$ww_cd; gcd_ready <- t + p$gcd; n["ww"] <- n["ww"] + 1
      }
    }

    for (hand in c("MH", "OH")) {
      nxt <- if (hand == "MH") next_mh else next_oh
      if (nxt > t) next
      speed <- if (hand == "MH") p$mh_speed else p$oh_speed
      if (hand == "MH" && !hs_queued && rage >= p$hs_threshold + p$hs_cost) hs_queued <- TRUE
      if (hand == "MH" && hs_queued) {
        # Heroic Strike replaces the white swing: it costs rage and the swing gives none.
        rage <- rage - p$hs_cost; hs_queued <- FALSE; n["hs"] <- n["hs"] + 1
      } else {
        roll <- runif(1)
        landed <- roll >= p$miss + p$dodge
        if (landed) {
          is_glance <- roll < p$miss + p$dodge + p$glance
          is_crit <- !is_glance && runif(1) < p$crit / (1 - p$miss - p$dodge - p$glance)
          dmg <- base_dmg(speed, hand) * (if (is_glance) p$glance_dmg else if (is_crit) 2 else 1)
          add_rage(rage_fn(hand, dmg, speed))
          if (runif(1) < p$ubw_chance) add_rage(p$ubw_rage)
          if (is_crit) flurry <- p$flurry_charges
        }
      }
      haste <- if (flurry > 0) 1 + p$flurry_haste else 1
      if (flurry > 0) flurry <- flurry - 1
      if (hand == "MH") next_mh <- t + speed / haste else next_oh <- t + speed / haste
    }
    if (trace) tr[[length(tr) + 1]] <- c(t = t, rage = rage)
  }

  per_min <- 60 / p$fight_len
  out <- tibble::tibble(bt_pm = n[["bt"]] * per_min, ww_pm = n[["ww"]] * per_min, hs_pm = n[["hs"]] * per_min,
                        wasted_pm = wasted * per_min, starved_share = starved / p$fight_len,
                        rps = generated / p$fight_len)
  if (trace) attr(out, "trace") <- do.call(rbind, tr)
  out
}
