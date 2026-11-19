# Event-based fight simulator for a level 60 dual-wield warrior against a boss.
# Used by the How Damage Scales, Rage on Crit, Flurry and Abilities chapters. Each white swing rolls on the
# attack table, and a rage model decides how much rage a landed swing gives. A simple priority
# rotation spends it. Damage is tracked for every source, so we can compare abilities.
#
# Talents follow the most popular Fury build on talentsforever.com (17/34/0), in its Forever and
# Classic versions: see `forever_talents` and `classic_talents` below, and data/talents/README.md.
# Forever's rules are the ones in the game since Blizzard's 2 Nov 2026 development notes (the launch build), which
# came on top of the 1 Oct rework and its 1 to 2 Oct hotfixes.
#
# This is not meant to be a full simulator. The Classic mechanics follow the two Classic simulators,
# WarriorSim (github.com/GuybrushGit/WarriorSim) and ClassicSim (github.com/timhul/ClassicSim), and the
# Classic warrior wiki (github.com/magey/classic-warrior/wiki), which we use to check our assumptions.
# Where WarriorSim and ClassicSim disagree we follow WarriorSim, which is still maintained. Forever uses
# the same mechanics, except where wowsims (github.com/wowsims/forever, the source of truth for today's game: its code
# and its combat-log evidence, docs/evidence/EV-*.md) says otherwise: rage per white swing, no rage from dodged swings
# or Heroic Strike, a crit giving twice the rage, Whirlwind hitting with both weapons for 25 rage (there is no Raging
# Blows), glancing blows at 70% damage, Heroic Strike rank 8 (+138 damage), Unbridled Wrath rolling on landed white
# swings, Windfury Totem's strike and Heroic Strike (EV-0148), Reckless Swings charges spent by landed white swings,
# Windfury Totem's strike and each Heroic Strike cast whether it lands or not, but not by Bloodthirst or Whirlwind
# (EV-0138), Windfury Totem's strike using no Flurry charge (EV-0138, EV-0140), and a queued Heroic Strike no longer
# raising off-hand hit. Since 2 Nov: Flurry 3/3 gives 30%, Improved Whirlwind 2/2 cuts Whirlwind's cooldown to 8 sec
# and adds 30% to its damage, and Reckless Swings gives 5 extra rage on each of your next 4 attacks.

sim_defaults <- list(
  fight_len = 180,        # seconds
  mh_speed = 2.7, oh_speed = 2.0,
  ap = 1200, armor = 0.75,
  crit = 0.30,            # crit on the character sheet
  crit_suppression = 0.048, # crit lost against a +3 boss: 3% from the level gap, plus 1.8% on crit from
                            # talents, gear and buffs (Classic wiki, "Crit aura suppression"; WarriorSim)
  miss = 0.20,            # white miss chance for a dual wielder with some hit gear (before off-hand talents)
  dodge = 0.065, glance = 0.40, glance_dmg = 0.65,
  yellow_miss = 0.01,     # without the dual wield penalty (19% lower than white): yellow attacks, and in Classic
                          # off-hand swings while Heroic Strike is queued (`hs_oh_hit`)
  crit_mult_yellow = 2.2, # 2x, plus Impale 2/2
  wpn_norm = 2.4,         # normalised speed of a one-handed weapon, used by Whirlwind
  gcd = 1.5,
  bt_cost = 30, bt_cd = 6, ww_cd = 10, ww_dmg_mult = 1,
  hs_cost = 12, hs_bonus = 157, # rank 9, with Improved Heroic Strike 3/3 (Classic; Forever has rank 8, see forever_talents)
  hs_threshold = 60,      # queue Heroic Strike when rage is at least this much
  refund = 0.80,          # share of the cost given back when Bloodthirst or Heroic Strike misses or is dodged
                          # (not Whirlwind or Execute)
  deep_wounds = 0.60,     # Deep Wounds 3/3 (in both builds, since Impale needs it): a crit makes the boss bleed
                          # for 60% of the main hand's average damage over 12 sec, in 4 ticks. A new crit restarts it.
  wf = FALSE,             # Windfury Totem (rank 3), off unless switched on: a 20% chance when a main-hand swing
  wf_chance = 0.20, wf_ap = 315, wf_icd = 1.5,   # or an instant attack lands, of an extra main-hand swing with +315 AP
  priority = "bt_first",  # or "ww_first"
  execute_at = NA,        # seconds into the fight when the boss reaches 20% health (NA: no execute phase)
  exec_cost = 15, exec_base = 600, exec_per_rage = 15,   # rank 5, the same in both games
  ubw_rage = 1,
  # Reckless Swings (Forever only): pressed whenever it and the global cooldown are ready (first in the priority, as in wowsims). Your next `rs_charges`
  # attacks within `rs_dur` sec each give `rs_rage` extra rage. As in wowsims (EV-0138), a charge goes to each landed
  # white swing (Windfury Totem's strike included) and to each Heroic Strike cast, landed or not; a missed or dodged
  # white swing, Bloodthirst and Whirlwind use none. Its health cost (25% of base health) is left to the healers.
  # `rs_rage = 0` switches it off. Other readings, for comparison: Bloodthirst and Whirlwind use a charge when they
  # land (`rs_bt_ww`), a Heroic Strike only uses one when it lands (`rs_hs_land`), only white swings use a charge
  # (`rs_white_only`), a missed or dodged white swing uses one for nothing (`rs_miss`), a white crit doubles the extra
  # rage (`rs_crit`), and Dual Wield Specialization raises it on off-hand swings (`rs_oh`).
  rs_rage = 0, rs_charges = 4, rs_dur = 8, rs_cd = 15, rs_gcd = 1,   # it triggers a 1 sec global cooldown (wowsims)
  rs_bt_ww = FALSE, rs_hs_land = FALSE, rs_white_only = FALSE, rs_miss = FALSE, rs_crit = FALSE, rs_oh = FALSE,
  ubw_hs = FALSE,         # Unbridled Wrath also rolls on a landed Heroic Strike (Forever, EV-0148)
  wf_flurry = TRUE,       # Windfury Totem's extra swing uses a Flurry charge (Classic, WarriorSim); not in Forever
  # Off unless switched on (the Rage on Crit chapter):
  flurry_rage = 0,        # extra rage from each white swing that lands while Flurry speeds it up (a design option)
  extra_haste = 1         # attack speed from outside Flurry, e.g. 1.03 for weapon enchants
)

# Forever 17/34/0 (the 2 Nov tree, as in wowsims): Dual Wield Specialization 5/5 (+25% off-hand damage, +50% off-hand
# rage), Furious Precision 3/3 (+10% off-hand hit), Anger Management (1 rage every 3 sec), Reckless Swings, Flurry 3/3
# (30%), Improved Whirlwind 2/2 (8 sec cooldown, +30% damage), Unbridled Wrath 60% (tooltip; wowsims' logs measure
# 58.8%, EV-0148), Bloodthirst 45% of AP + 48 (rank 4), Whirlwind 25 rage, Heroic Strike rank 8 (+138, 12 rage with
# Improved Heroic Strike), glancing blows at 70% damage. No Boundless Rage any more, so the cap is 100. Whirlwind hits with both weapons without a talent. A white crit gives twice
# the rage of a normal hit (`crit_rage_mult`). A dodged white swing gives no rage (logs), and a queued Heroic
# Strike no longer raises off-hand hit.
forever_talents <- list(
  oh_dmg_mult = 1.25, oh_rage_mult = 1.5, oh_hit_bonus = 0.10, anger_rps = 1 / 3, rage_cap = 100,
  ww_offhand = TRUE, ww_cost = 25, ww_cd = 8, ww_dmg_mult = 1.3, flurry_haste = 0.30, flurry_charges = 3,
  ubw_chance = 0.60, bt_ap = 0.45, bt_flat = 48, dodge_rage = 0, crit_rage_mult = 2, hs_oh_hit = FALSE, rs_rage = 5,
  glance_dmg = 0.70, hs_bonus = 138, ubw_hs = TRUE, wf_flurry = FALSE
)
# Classic 17/34/0: Dual Wield Specialization only adds damage, Whirlwind only hits with the main hand, Flurry 30%,
# Unbridled Wrath 40%, Bloodthirst 45% of AP. A dodged white swing gives the rage of 75% of an average hit
# (WarriorSim). Classic's rage already grows with a crit's damage, so `crit_rage_mult` stays at 1.
classic_talents <- list(
  oh_dmg_mult = 1.25, oh_rage_mult = 1, oh_hit_bonus = 0, anger_rps = 1 / 3, rage_cap = 100,
  ww_offhand = FALSE, ww_cost = 25, ww_cd = 10, ww_dmg_mult = 1, flurry_haste = 0.30, flurry_charges = 3,
  ubw_chance = 0.40, bt_ap = 0.45, bt_flat = 0, dodge_rage = 0.75, crit_rage_mult = 1, hs_oh_hit = TRUE, rs_rage = 0,
  glance_dmg = 0.65, hs_bonus = 157, ubw_hs = FALSE, wf_flurry = TRUE
)
# Forever's rules before the 1 Oct rework (September 2026), which the archived Rage Design Proposals chapter
# (archive/03-rage-proposals.Rmd) was written against: Dual Wield Specialization doubled off-hand rage and gave +10% off-hand hit, Boundless Rage 3/3 raised the
# cap to 130, crits gave no extra rage, Bloodthirst was 35% of AP + 48, Whirlwind cost 25 (Raging Blows only gave it
# the off-hand hit) and a queued Heroic Strike still raised off-hand hit.
# Forever's rules from the 1 Oct rework until 2 Nov: Flurry 5/5 gave 25%, there was no Improved Whirlwind or
# Reckless Swings, and Raging Blows took Whirlwind to 22 rage. The other mechanics are today's, from wowsims.
forever_oct_talents <- modifyList(forever_talents, list(
  flurry_haste = 0.25, ww_cd = 10, ww_dmg_mult = 1, rs_rage = 0, ww_cost = 22
))
forever_sep_talents <- modifyList(forever_oct_talents, list(
  oh_rage_mult = 2, rage_cap = 130, crit_rage_mult = 1, bt_ap = 0.35, ww_cost = 25, hs_oh_hit = TRUE
))
sim_defaults <- modifyList(sim_defaults, forever_talents)

# Rage for one landed white swing, before talents. `hand` is "MH" or "OH"; `dmg` is the landed damage
# (after armor, crit and glancing); `speed` is the weapon's tooltip speed. The simulator applies
# `oh_rage_mult` on top. `k` is Classic's rage per point of damage, divided by C (7.5).
make_rage_models <- function(forever_rates, C60, scale_rps, hybrid_alpha, hybrid_cap_rps, k) {
  # forever_rates: list(MH = vector of observed rage/speed, OH = ...) sampled from the logs
  forever_swing <- function(hand, speed) sample(forever_rates[[hand]], 1) * speed
  hand_share <- c(MH = 1 / 1.5, OH = 0.5 / 1.5)
  list(
    `Classic`              = function(hand, dmg, speed) k * dmg / C60,
    `Forever (September)`  = function(hand, dmg, speed) forever_swing(hand, speed),
    `Proposal: sigmoid`    = function(hand, dmg, speed) forever_swing(hand, speed) * scale_rps[["sigmoid"]],
    `Proposal: saturating` = function(hand, dmg, speed) forever_swing(hand, speed) * scale_rps[["saturating"]],
    `Proposal: hybrid`     = function(hand, dmg, speed) forever_swing(hand, speed) +
      min(hybrid_alpha * k * dmg / C60, hybrid_cap_rps * speed * hand_share[[hand]])
  )
}

simulate_fight <- function(rage_fn, wpn_dps, p = sim_defaults, trace = FALSE) {
  rage <- 0; t <- 0
  next_mh <- runif(1, 0, p$mh_speed); next_oh <- runif(1, 0, p$oh_speed)
  bt_ready <- 0; ww_ready <- 0; gcd_ready <- 0
  flurry <- 0; hs_queued <- FALSE; in_execute <- FALSE
  hasted <- c(MH = FALSE, OH = FALSE)   # whether each hand's current swing timer was sped up by Flurry
  wf_ready <- 0                     # Windfury's internal cooldown
  rs_ready <- 0; rs_left <- 0; rs_end <- -Inf   # Reckless Swings: cooldown, charges left, and when they run out
  dw_end <- -Inf; dw_next <- Inf    # Deep Wounds: when the bleed ends, and when it next ticks
  crit <- p$crit - p$crit_suppression
  wasted <- 0; starved <- 0; last_t <- 0; generated <- 0
  spent <- c(bt = 0, ww = 0)        # rage spent on Bloodthirst and Whirlwind, after refunds
  n <- c(bt = 0, ww = 0, hs = 0, exec = 0, wf = 0, rs = 0)
  rs_gained <- 0                    # rage from Reckless Swings
  dmg <- c(white = 0, hs = 0, bt = 0, ww = 0, exec = 0, dw = 0)
  exec_rage <- numeric(0)   # rage spent on each Execute
  hs_t <- numeric(0)        # when each Heroic Strike went off
  tr <- if (trace) list() else NULL

  hand_mult <- function(hand) if (hand == "OH") 0.5 * p$oh_dmg_mult else 1
  base_dmg <- function(speed, hand, ap_bonus = 0) (wpn_dps * speed + (p$ap + ap_bonus) / 14 * speed) * p$armor * hand_mult(hand)
  add_rage <- function(x) {
    generated <<- generated + x   # all rage gained, including what the cap wastes
    over <- max(rage + x - p$rage_cap, 0)
    wasted <<- wasted + over
    rage <<- min(rage + x, p$rage_cap)
  }
  # An attack uses a Reckless Swings charge, if there's one left, for `mult` times its rage (0 for a charge used up
  # by a miss). Yellow attacks (Heroic Strike, Bloodthirst, Whirlwind) don't use one under `rs_white_only`.
  rs_hit <- function(mult = 1, yellow = FALSE) {
    if (yellow && p$rs_white_only) return(invisible(NULL))
    if (rs_left > 0 && t <= rs_end) {
      rs_left <<- rs_left - 1; rs_gained <<- rs_gained + p$rs_rage * mult; add_rage(p$rs_rage * mult)
    }
  }
  refund <- function(cost) { r <- p$refund * cost; rage <<- min(rage + r, p$rage_cap); r }
  # Any crit starts Flurry and restarts Deep Wounds (and its tick timer, as in WarriorSim).
  on_crit <- function() {
    flurry <<- p$flurry_charges
    if (p$deep_wounds > 0) { dw_end <<- t + 12; dw_next <<- t + 3 }
  }
  deep_wounds_ticks <- function(until) {
    while (dw_next <= min(until, dw_end)) {
      dmg["dw"] <<- dmg["dw"] + p$deep_wounds / 4 * (wpn_dps + p$ap / 14) * p$mh_speed   # a bleed: no armor
      dw_next <<- dw_next + 3
    }
  }
  # A yellow attack: one roll for miss / dodge, then a separate roll for crit.
  yellow <- function(d) {
    roll <- runif(1)
    if (roll < p$yellow_miss + p$dodge) return(0)
    if (runif(1) < crit) { on_crit(); return(d * p$crit_mult_yellow) }
    d
  }
  ww_hit <- function(hand, speed) (wpn_dps * speed + p$ap / 14 * p$wpn_norm) * p$armor * hand_mult(hand) * p$ww_dmg_mult

  # One swing: the queued Heroic Strike (main hand only), or a white hit. Returns TRUE if it landed, which
  # is what Windfury procs from. `ap_bonus` is Windfury's extra attack power.
  swing <- function(hand, ap_bonus = 0) {
    speed <- if (hand == "MH") p$mh_speed else p$oh_speed
    if (hand == "MH" && hs_queued) {
      hs_queued <<- FALSE
      if (rage >= p$hs_cost) {
        # Heroic Strike replaces the white swing: it costs rage, rolls as a yellow attack, and gives no rage.
        rage <<- rage - p$hs_cost; n["hs"] <<- n["hs"] + 1; hs_t <<- c(hs_t, t)
        d <- yellow(base_dmg(speed, hand, ap_bonus) + p$hs_bonus * p$armor)
        dmg["hs"] <<- dmg["hs"] + d
        if (d == 0) refund(p$hs_cost)
        if (d > 0 || !p$rs_hs_land) rs_hit(yellow = TRUE)                  # every cast uses a charge (wowsims)
        if (d > 0 && p$ubw_hs && runif(1) < p$ubw_chance) add_rage(p$ubw_rage)
        return(d > 0)
      }
    }
    miss <- if (hand == "OH") max((if (hs_queued && p$hs_oh_hit) p$yellow_miss else p$miss) - p$oh_hit_bonus, 0) else p$miss
    roll <- runif(1)
    if (roll < miss) { if (p$rs_miss) rs_hit(0); return(FALSE) }
    if (roll < miss + p$dodge) {
      if (p$rs_miss) rs_hit(0)
      if (p$dodge_rage > 0)
        add_rage(rage_fn(hand, p$dodge_rage * base_dmg(speed, hand, ap_bonus), speed) * (if (hand == "OH") p$oh_rage_mult else 1))
      return(FALSE)
    }
    is_glance <- roll < miss + p$dodge + p$glance
    is_crit <- !is_glance && runif(1) < crit / (1 - miss - p$dodge - p$glance)
    d <- base_dmg(speed, hand, ap_bonus) * (if (is_glance) p$glance_dmg else if (is_crit) 2 else 1)
    dmg["white"] <<- dmg["white"] + d
    add_rage(rage_fn(hand, d, speed) * (if (hand == "OH") p$oh_rage_mult else 1) * (if (is_crit) p$crit_rage_mult else 1) +
             (if (hasted[[hand]]) p$flurry_rage else 0))
    if (runif(1) < p$ubw_chance) add_rage(p$ubw_rage)
    rs_hit((if (is_crit && p$rs_crit) p$crit_rage_mult else 1) * (if (hand == "OH" && p$rs_oh) p$oh_rage_mult else 1))
    if (is_crit) on_crit()
    TRUE
  }
  # Windfury Totem: an extra main-hand swing (or the queued Heroic Strike) right away, which resets the
  # main-hand swing timer and can't proc Windfury again.
  windfury <- function() {
    if (!p$wf || t < wf_ready || runif(1) >= p$wf_chance) return(invisible(NULL))
    wf_ready <<- t + p$wf_icd; n["wf"] <<- n["wf"] + 1
    swing("MH", p$wf_ap)
    haste <- if (flurry > 0) 1 + p$flurry_haste else 1
    hasted[["MH"]] <<- flurry > 0
    if (flurry > 0 && p$wf_flurry) flurry <<- flurry - 1   # Forever: the strike uses no charge (wowsims)
    next_mh <<- t + p$mh_speed / (haste * p$extra_haste)
  }

  while (t < p$fight_len) {
    # Next event: a swing, an Anger Management tick, or the moment an ability comes off cooldown / off the
    # global cooldown. An ability that is ready but unaffordable is not an event.
    ability_t <- max(gcd_ready, min(bt_ready, ww_ready))
    tick_t <- if (p$anger_rps > 0) (floor(t * p$anger_rps + 1e-9) + 1) / p$anger_rps else Inf
    rs_t <- if (p$rs_rage > 0 && max(rs_ready, gcd_ready) > t) max(rs_ready, gcd_ready) else Inf
    t_new <- min(next_mh, next_oh, tick_t, rs_t, if (ability_t > t) ability_t else Inf)
    if (t_new > p$fight_len) break
    # Time spent with Bloodthirst ready but not enough rage to press it.
    if (bt_ready <= last_t && gcd_ready <= last_t && rage < p$bt_cost) starved <- starved + (t_new - last_t)
    t <- t_new; last_t <- t
    deep_wounds_ticks(t)
    if (abs(t - tick_t) < 1e-9) add_rage(1)   # Anger Management: 1 rage every 3 sec
    # Reckless Swings, whenever it and the global cooldown are ready; it takes a 1 sec global cooldown (wowsims)
    if (p$rs_rage > 0 && t >= rs_ready && t >= gcd_ready) {
      rs_left <- p$rs_charges; rs_end <- t + p$rs_dur; rs_ready <- t + p$rs_cd; n["rs"] <- n["rs"] + 1; gcd_ready <- t + p$rs_gcd
    }

    # Execute phase: Execute with all your rage whenever the global cooldown is free.
    in_execute <- !is.na(p$execute_at) && t >= p$execute_at
    if (in_execute && t >= gcd_ready && rage >= p$exec_cost) {
      used <- rage; rage <- 0; gcd_ready <- t + p$gcd; n["exec"] <- n["exec"] + 1
      exec_rage <- c(exec_rage, used)
      dmg["exec"] <- dmg["exec"] + yellow((p$exec_base + p$exec_per_rage * (used - p$exec_cost)) * p$armor)
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
        rage <- rage - p$bt_cost; spent["bt"] <- spent["bt"] + p$bt_cost; bt_ready <- t + p$bt_cd; gcd_ready <- t + p$gcd; n["bt"] <- n["bt"] + 1
        d <- yellow((p$bt_ap * p$ap + p$bt_flat) * p$armor)
        dmg["bt"] <- dmg["bt"] + d
        if (d == 0) spent["bt"] <- spent["bt"] - refund(p$bt_cost) else { if (p$rs_bt_ww) rs_hit(yellow = TRUE); windfury() }
      } else if (use == "ww") {
        rage <- rage - p$ww_cost; spent["ww"] <- spent["ww"] + p$ww_cost; ww_ready <- t + p$ww_cd; gcd_ready <- t + p$gcd; n["ww"] <- n["ww"] + 1
        d <- yellow(ww_hit("MH", p$mh_speed))
        dmg["ww"] <- dmg["ww"] + d
        if (p$ww_offhand) dmg["ww"] <- dmg["ww"] + yellow(ww_hit("OH", p$oh_speed))
        if (d > 0) { if (p$rs_bt_ww) rs_hit(yellow = TRUE); windfury() }
      }
    }
    # Heroic Strike is queued as soon as there's enough rage, and goes off on the next main-hand swing if
    # there's still enough to pay for it. In Classic, while it's queued, off-hand swings lose the dual wield miss
    # penalty (`hs_oh_hit`); Forever took that out on 1 Oct.
    if (!in_execute && !hs_queued && rage >= p$hs_threshold + p$hs_cost) hs_queued <- TRUE

    for (hand in c("MH", "OH")) {
      nxt <- if (hand == "MH") next_mh else next_oh
      if (nxt > t) next
      speed <- if (hand == "MH") p$mh_speed else p$oh_speed
      landed <- swing(hand)
      haste <- (if (flurry > 0) 1 + p$flurry_haste else 1) * p$extra_haste
      hasted[[hand]] <- flurry > 0
      if (flurry > 0) flurry <- flurry - 1
      if (hand == "MH") next_mh <- t + speed / haste else next_oh <- t + speed / haste
      if (hand == "MH" && landed) windfury()
    }
    if (trace) tr[[length(tr) + 1]] <- c(t = t, rage = rage)
  }
  deep_wounds_ticks(p$fight_len)

  per_min <- 60 / p$fight_len
  out <- tibble::tibble(bt_pm = n[["bt"]] * per_min, ww_pm = n[["ww"]] * per_min, hs_pm = n[["hs"]] * per_min,
                        wf_pm = n[["wf"]] * per_min, rs_rps = rs_gained / p$fight_len,
                        wasted_pm = wasted * per_min, starved_share = starved / p$fight_len,
                        rps = generated / p$fight_len,
                        spare_pm = (generated - sum(spent)) * per_min,   # rage left after Bloodthirst and Whirlwind
                        total_dps = sum(dmg) / p$fight_len,
                        dps_white = dmg[["white"]] / p$fight_len, dps_hs = dmg[["hs"]] / p$fight_len,
                        dps_bt = dmg[["bt"]] / p$fight_len, dps_ww = dmg[["ww"]] / p$fight_len,
                        dps_dw = dmg[["dw"]] / p$fight_len,
                        dps_exec = dmg[["exec"]] / p$fight_len, exec_n = n[["exec"]], exec_rage = list(exec_rage), hs_t = list(hs_t),
                        dpr_bt = if (spent[["bt"]] > 0) dmg[["bt"]] / spent[["bt"]] else NA_real_,
                        dpr_ww = if (spent[["ww"]] > 0) dmg[["ww"]] / spent[["ww"]] else NA_real_)
  if (trace) attr(out, "trace") <- do.call(rbind, tr)
  out
}
