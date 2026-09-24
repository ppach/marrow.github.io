# Event-based fight simulator for a level 60 dual-wield warrior against a boss.
# Used by the Rage Design Proposals, Flurry and Abilities chapters. Each white swing rolls on the
# attack table, and a rage model decides how much rage a landed swing gives. A simple priority
# rotation spends it. Damage is tracked for every source, so we can compare abilities.
#
# Talents follow the most popular Fury build on talentsforever.com (17/34/0), in its Forever and
# Classic versions: see `forever_talents` and `classic_talents` below, and data/talents/README.md.

sim_defaults <- list(
  fight_len = 180,        # seconds
  mh_speed = 2.7, oh_speed = 2.0,
  ap = 1200, armor = 0.75, crit = 0.30,
  miss = 0.20,            # white miss chance for a dual wielder with some hit gear (before off-hand talents)
  dodge = 0.065, glance = 0.40, glance_dmg = 0.65,
  yellow_miss = 0.01,     # yellow attacks don't get the dual wield penalty (19% lower than white)
  crit_mult_yellow = 2.2, # 2x, plus Impale 2/2
  wpn_norm = 2.4,         # normalised speed of a one-handed weapon, used by Whirlwind
  gcd = 1.5,
  bt_cost = 30, bt_cd = 6, ww_cost = 25, ww_cd = 10,
  hs_cost = 12, hs_bonus = 157, # rank 9, with Improved Heroic Strike 3/3
  hs_threshold = 60,      # queue Heroic Strike when rage is at least this much
  priority = "bt_first",  # or "ww_first"
  execute_at = NA,        # seconds into the fight when the boss reaches 20% health (NA: no execute phase)
  exec_cost = 15, exec_base = 600, exec_per_rage = 15,   # rank 5, the same in both games
  ubw_rage = 1
)

# Forever 17/34/0: Dual Wield Specialization 5/5 (+25% off-hand damage, +100% off-hand rage, +10% off-hand
# hit), Anger Management (1 rage every 3 sec), Boundless Rage 3/3 (+30 max rage), Raging Blows
# (Whirlwind also hits with the off hand), Flurry 25%, Unbridled Wrath 60% (tooltip), Bloodthirst
# 35% of AP + 48 (rank 4).
forever_talents <- list(
  oh_dmg_mult = 1.25, oh_rage_mult = 2, oh_hit_bonus = 0.10, anger_rps = 1 / 3, rage_cap = 130,
  raging_blows = TRUE, flurry_haste = 0.25, flurry_charges = 3, ubw_chance = 0.60,
  bt_ap = 0.35, bt_flat = 48
)
# Classic 17/34/0: Dual Wield Specialization only adds damage, no Boundless Rage or Raging Blows,
# Flurry 30%, Unbridled Wrath 40%, Bloodthirst 45% of AP.
classic_talents <- list(
  oh_dmg_mult = 1.25, oh_rage_mult = 1, oh_hit_bonus = 0, anger_rps = 1 / 3, rage_cap = 100,
  raging_blows = FALSE, flurry_haste = 0.30, flurry_charges = 3, ubw_chance = 0.40,
  bt_ap = 0.45, bt_flat = 0
)
sim_defaults <- modifyList(sim_defaults, forever_talents)

# Rage for one landed white swing, before talents. `hand` is "MH" or "OH"; `dmg` is the landed damage
# (after armor, crit and glancing); `speed` is the weapon's tooltip speed. The simulator applies
# `oh_rage_mult` on top.
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
  n <- c(bt = 0, ww = 0, hs = 0, exec = 0)
  dmg <- c(white = 0, hs = 0, bt = 0, ww = 0, exec = 0)
  exec_rage <- numeric(0)   # rage spent on each Execute
  tr <- if (trace) list() else NULL

  hand_mult <- function(hand) if (hand == "OH") 0.5 * p$oh_dmg_mult else 1
  base_dmg <- function(speed, hand) (wpn_dps * speed + p$ap / 14 * speed) * p$armor * hand_mult(hand)
  add_rage <- function(x) {
    generated <<- generated + x   # all rage gained, including what the cap wastes
    over <- max(rage + x - p$rage_cap, 0)
    wasted <<- wasted + over
    rage <<- min(rage + x, p$rage_cap)
  }
  # A yellow attack: one roll for miss / dodge, then a separate roll for crit. Crits start Flurry.
  yellow <- function(d) {
    roll <- runif(1)
    if (roll < p$yellow_miss + p$dodge) return(0)
    if (runif(1) < p$crit) { flurry <<- p$flurry_charges; return(d * p$crit_mult_yellow) }
    d
  }
  ww_hit <- function(hand, speed) (wpn_dps * speed + p$ap / 14 * p$wpn_norm) * p$armor * hand_mult(hand)

  while (t < p$fight_len) {
    # Next event: a swing, an Anger Management tick, or the moment an ability comes off cooldown / off the
    # global cooldown. An ability that is ready but unaffordable is not an event.
    ability_t <- max(gcd_ready, min(bt_ready, ww_ready))
    tick_t <- if (p$anger_rps > 0) (floor(t * p$anger_rps + 1e-9) + 1) / p$anger_rps else Inf
    t_new <- min(next_mh, next_oh, tick_t, if (ability_t > t) ability_t else Inf)
    if (t_new > p$fight_len) break
    # Time spent with Bloodthirst ready but not enough rage to press it.
    if (bt_ready <= last_t && gcd_ready <= last_t && rage < p$bt_cost) starved <- starved + (t_new - last_t)
    t <- t_new; last_t <- t
    if (abs(t - tick_t) < 1e-9) add_rage(1)   # Anger Management: 1 rage every 3 sec

    # Execute phase: Execute with all your rage whenever the global cooldown is free.
    in_execute <- !is.na(p$execute_at) && t >= p$execute_at
    if (in_execute && t >= gcd_ready && rage >= p$exec_cost) {
      spent <- rage; rage <- 0; gcd_ready <- t + p$gcd; n["exec"] <- n["exec"] + 1
      exec_rage <- c(exec_rage, spent)
      dmg["exec"] <- dmg["exec"] + yellow((p$exec_base + p$exec_per_rage * (spent - p$exec_cost)) * p$armor)
    }
    # Abilities, by priority, whenever the global cooldown is free.
    if (!in_execute && t >= gcd_ready) {
      bt_ok <- t >= bt_ready && rage >= p$bt_cost
      ww_ok <- t >= ww_ready && rage >= p$ww_cost
      use <- if (p$priority == "ww_first") {
        if (ww_ok) "ww" else if (bt_ok) "bt" else ""
      } else {
        if (bt_ok) "bt" else if (ww_ok && t + 1 < bt_ready) "ww" else ""
      }
      if (use == "bt") {
        rage <- rage - p$bt_cost; bt_ready <- t + p$bt_cd; gcd_ready <- t + p$gcd; n["bt"] <- n["bt"] + 1
        dmg["bt"] <- dmg["bt"] + yellow((p$bt_ap * p$ap + p$bt_flat) * p$armor)
      } else if (use == "ww") {
        rage <- rage - p$ww_cost; ww_ready <- t + p$ww_cd; gcd_ready <- t + p$gcd; n["ww"] <- n["ww"] + 1
        dmg["ww"] <- dmg["ww"] + yellow(ww_hit("MH", p$mh_speed))
        if (p$raging_blows) dmg["ww"] <- dmg["ww"] + yellow(ww_hit("OH", p$oh_speed))
      }
    }

    for (hand in c("MH", "OH")) {
      nxt <- if (hand == "MH") next_mh else next_oh
      if (nxt > t) next
      speed <- if (hand == "MH") p$mh_speed else p$oh_speed
      if (hand == "MH" && !in_execute && !hs_queued && rage >= p$hs_threshold + p$hs_cost) hs_queued <- TRUE
      if (hand == "MH" && hs_queued) {
        # Heroic Strike replaces the white swing: it costs rage, rolls as a yellow attack, and gives no rage.
        rage <- rage - p$hs_cost; hs_queued <- FALSE; n["hs"] <- n["hs"] + 1
        dmg["hs"] <- dmg["hs"] + yellow(base_dmg(speed, hand) + p$hs_bonus * p$armor)
      } else {
        miss <- if (hand == "OH") p$miss - p$oh_hit_bonus else p$miss
        roll <- runif(1)
        if (roll >= miss + p$dodge) {
          is_glance <- roll < miss + p$dodge + p$glance
          is_crit <- !is_glance && runif(1) < p$crit / (1 - miss - p$dodge - p$glance)
          d <- base_dmg(speed, hand) * (if (is_glance) p$glance_dmg else if (is_crit) 2 else 1)
          dmg["white"] <- dmg["white"] + d
          add_rage(rage_fn(hand, d, speed) * (if (hand == "OH") p$oh_rage_mult else 1))
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
                        rps = generated / p$fight_len,
                        total_dps = sum(dmg) / p$fight_len,
                        dps_white = dmg[["white"]] / p$fight_len, dps_hs = dmg[["hs"]] / p$fight_len,
                        dps_bt = dmg[["bt"]] / p$fight_len, dps_ww = dmg[["ww"]] / p$fight_len,
                        dps_exec = dmg[["exec"]] / p$fight_len, exec_n = n[["exec"]], exec_rage = list(exec_rage),
                        dpr_bt = if (n[["bt"]] > 0) dmg[["bt"]] / (n[["bt"]] * p$bt_cost) else NA_real_,
                        dpr_ww = if (n[["ww"]] > 0) dmg[["ww"]] / (n[["ww"]] * p$ww_cost) else NA_real_)
  if (trace) attr(out, "trace") <- do.call(rbind, tr)
  out
}
