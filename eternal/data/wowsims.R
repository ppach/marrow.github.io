# The bridge from the book to wowsims (github.com/wowsims/forever), the community simulator for WoW: Forever. The
# book treats wowsims as the source of truth for how the game works today.
#
#   wowsims_ensure()            updates the wowsims clone and rebuilds wowsimcli if origin/master moved (once per R session)
#   book_wowsims(phase, ...)    the book's warrior as a wowsims setup: its weapons, attack power, crit and hit, talents
#                               and rotation (see "The book's warrior" below)
#   wowsims_run(p)              runs a setup and returns tidy results
#   cached_wowsims(name, p)     the same, saved in data/sim_cache/wowsims/ and re-run when the input or wowsims changes
#   wowsims_sheet(p)            the character sheet wowsims computes for a setup (attack power, crit, hit, ...)
#   wowsims_stamp(res)          "Simmed with wowsims forever @abc1234, 2026-11-18" for the text
#
# How a run works: the setup becomes a SIML file, `wowsimcli siml parse -json` turns it into the player's settings, and
# R wraps those in a RaidSimRequest (as the CLI itself does for a SIML file) with three things SIML can't say: the
# book's weapons as custom items (any DPS and speed, no stats), a fixed random seed, and, on request, the combat log
# of the first iteration. Each result carries the wowsims commit that produced it (`res$version`). A cached result is
# keyed on the request and the wowsims commit, so every cached number goes stale when wowsims changes.
# See SIMS.md for how the book's sims run and how to refresh them.

wowsims_repo <- function() normalizePath(Sys.getenv("WOWSIMS_REPO", "C:/Users/pedro/src/wowsims-forever"), "/", mustWork = FALSE)
wowsims_bin  <- function(name = "wowsimcli") file.path(wowsims_repo(), "bin", paste0(name, ".exe"))
.wowsims <- if (exists(".wowsims", inherits = FALSE) && is.environment(.wowsims)) .wowsims else new.env(parent = emptyenv())   # kept when sourced again
`%||%` <- function(a, b) if (is.null(a)) b else a
json_obj <- function(x = list()) if (length(x)) x else structure(list(), names = character(0))   # {} in JSON

# Run data/wowsims_update.ps1 (fetch, fast-forward, rebuild if needed), once per R session. With
# options(wowsims.offline = TRUE) it skips the fetch but still rebuilds a binary that doesn't match the checkout.
# Stops if the update or the build fails, or if the binary isn't from the checked-out commit.
wowsims_ensure <- function() {
  if (!is.null(.wowsims$version)) return(.wowsims$version)
  script <- normalizePath("data/wowsims_update.ps1", mustWork = TRUE)
  args <- c("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", shQuote(script), "-Repo", shQuote(wowsims_repo()))
  if (isTRUE(getOption("wowsims.offline"))) args <- c(args, "-Offline")
  status <- system2("powershell", args)
  if (!identical(status, 0L)) stop("wowsims update failed (see the messages above); not using a stale wowsimcli", call. = FALSE)
  v <- jsonlite::fromJSON(file.path(wowsims_repo(), "bin", "wowsimcli.version.json"))
  head <- system2("git", c("-C", shQuote(wowsims_repo()), "rev-parse", "HEAD"), stdout = TRUE)
  if (!identical(v$commit, head)) stop("wowsimcli was built from ", v$short, " but the clone is at ", substr(head, 1, 7), call. = FALSE)
  .wowsims$version <- v
  v
}

# ---- Setups ----------------------------------------------------------------------------------------------------------

# A setup is a list. Its fields, with the defaults below:
#   talents      the talent string (wowsims order). The default is the book's Forever 17/34/0.
#   apl          the rotation file, data/wowsims/book.apl.siml by default (the book's warrior; the site's fury rotation
#                is data/wowsims/fury.apl.siml)
#   settings     SIML settings lines (race, stance, ...)
#   weapons      list(mh = c(dps, speed), oh = c(dps, speed)): custom fist weapons with no stats, so no racial weapon
#                skill applies. NULL to use the `gear` slot rows instead.
#   gear         SIML slot rows, e.g. c(trinket1 = "hand_of_justice")
#   bonus_stats  named numbers for `bonus_stats(stats(...))`, e.g. c(attack_power = 600)
#   buffs, raid_buffs, debuffs, consumables   SIML flag lines
#   duration, execute   fight length (sec) and the share of it at the end that is the execute phase (0: none)
#   armor        the boss's armor. 1833 leaves 75% of physical damage at level 60, as the book assumes.
#   target_level the boss's level, 63 by default
#   iterations, seed, log   sim options; log = TRUE returns the first iteration's combat log too
wowsims_defaults <- list(
  spec = "dps_warrior",
  talents = "30303213002-450530005122100231",
  apl = "data/wowsims/book.apl.siml",
  settings = c("race human", "default_stance berserker", "distance_from_target 5"),
  weapons = NULL, gear = character(0), bonus_stats = numeric(0),
  buffs = character(0), raid_buffs = character(0), debuffs = character(0), consumables = character(0),
  duration = 180, execute = 0, armor = 1833, target_level = 63,
  iterations = 20000, seed = 1, log = FALSE
)

wowsims_siml <- function(p) {
  section <- function(name, lines) if (length(lines)) c("", paste0(name, ":"), paste0("  ", lines)) else character(0)
  gear <- c(if (length(p$gear)) sprintf("%-10s %s", names(p$gear), p$gear),
            if (length(p$bonus_stats)) sprintf("bonus_stats(stats(%s))", paste0(names(p$bonus_stats), "=", round(p$bonus_stats, 2), collapse = ", ")))
  if (!length(gear)) gear <- "bonus_stats(stats(attack_power=0))"   # an empty gear section reads as no gear section
  paste(c("siml 1", paste("spec", p$spec), sprintf('talents "%s"', p$talents),
          sprintf('use "%s"', normalizePath(p$apl, "/", mustWork = TRUE)),
          section("settings", p$settings), section("gear", gear), section("consumables", p$consumables),
          section("buffs", p$buffs), section("raid_buffs", p$raid_buffs), section("debuffs", p$debuffs)),
        collapse = "\n")
}

# The book's weapons as custom items: average damage = dps x speed, spread +-25% around it.
book_weapon <- function(id, dps, speed, hand) {
  avg <- dps * speed
  list(id = id, name = sprintf("Book %s %.1f DPS %.1f", hand, dps, speed), type = "ItemTypeWeapon",
       weaponType = "WeaponTypeFist", handType = "HandTypeOneHand", weaponSpeed = speed, quality = "ItemQualityEpic",
       scalingOptions = list(`0` = list(weaponDamageMin = avg * 0.75, weaponDamageMax = avg * 1.25, unroundedDps = dps)))
}

# The player's settings (IndividualSimSettings, as a list) for a setup, with the book's weapons in place.
wowsims_settings <- function(p) {
  p <- utils::modifyList(wowsims_defaults, p)
  dir <- tempfile("wowsims"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE))
  f <- file.path(dir, "in.siml"); writeLines(wowsims_siml(p), f, useBytes = TRUE)
  out <- suppressWarnings(system2(wowsims_bin(), c("siml", "parse", "-json", shQuote(f)), stdout = TRUE, stderr = TRUE))
  if (!is.null(attr(out, "status"))) stop("SIML did not load:\n", paste(out, collapse = "\n"), call. = FALSE)
  s <- jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)
  if (!is.null(p$weapons)) {
    items <- s$player$equipment$items %||% rep(list(json_obj()), 17)
    while (length(items) < 17) items <- c(items, list(json_obj()))
    mh <- book_weapon(990001L, p$weapons$mh[[1]], p$weapons$mh[[2]], "MH")
    oh <- book_weapon(990002L, p$weapons$oh[[1]], p$weapons$oh[[2]], "OH")
    items[[15]] <- list(id = mh$id); items[[16]] <- list(id = oh$id)
    s$player$equipment$items <- items
    s$player$database <- list(items = list(mh, oh))
  }
  list(settings = s, p = p)
}

# The RaidSimRequest for a setup: the player alone in the first of five parties, as the CLI builds it for a SIML file.
wowsims_request <- function(p) {
  w <- wowsims_settings(p); s <- w$settings; p <- w$p
  target <- list(id = 31146, name = "Raid Target", level = p$target_level, mobType = "MobTypeMechanical",
                 stats = as.list(replace(numeric(37), c(28, 15, 30) , c(p$armor, 320, 1428900))),
                 swingSpeed = 2, minBaseDamage = 2601, parryHaste = TRUE, canCrush = TRUE, damageSpread = 0.5)
  list(raid = list(parties = c(list(list(players = list(s$player), buffs = json_obj(s$partyBuffs))), rep(list(json_obj()), 4)),
                   buffs = json_obj(s$raidBuffs), debuffs = json_obj(s$debuffs)),
       encounter = list(duration = p$duration, durationVariation = 0, executeProportion20 = p$execute,
                        executeProportion35 = p$execute, targets = list(target)),
       simOptions = list(iterations = p$iterations, randomSeed = p$seed, debugFirstIteration = isTRUE(p$log)),
       type = "SimTypeIndividual")
}

# ---- Running ---------------------------------------------------------------------------------------------------------

# Run one setup. Returns a list: dps (mean, sd), per_second (dps, rage gained per second), actions (one row per action
# and hand: casts, hits, crits, misses, dodges, glances, damage, all per fight), rage (one row per rage source: rage per
# fight, positive for gains and negative for costs), log (the first iteration's combat log, if asked for), the setup
# and the wowsims version.
wowsims_run <- function(p = list()) {
  v <- wowsims_ensure()
  req <- wowsims_request(p); p <- utils::modifyList(wowsims_defaults, p)
  out <- wowsims_exec(req, p$duration, log = isTRUE(p$log))
  c(out, list(setup = p[setdiff(names(p), "log")], version = v))
}

# Run a RaidSimRequest (a list) and parse the result. Used by wowsims_run() and by the per-fight runs.
wowsims_exec <- function(req, duration, log = FALSE) {
  dir <- tempfile("wowsims"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE))
  infile <- file.path(dir, "request.json"); outfile <- file.path(dir, "out.json")
  writeLines(jsonlite::toJSON(req, auto_unbox = TRUE, digits = NA, null = "null"), infile, useBytes = TRUE)
  err <- suppressWarnings(system2(wowsims_bin(), c("sim", "--infile", shQuote(infile), "--outfile", shQuote(outfile)), stdout = TRUE, stderr = TRUE))
  if (!file.exists(outfile)) stop("wowsimcli failed:\n", paste(utils::tail(err, 20), collapse = "\n"), call. = FALSE)
  d <- jsonlite::fromJSON(outfile, simplifyVector = FALSE)
  if (length(d$error)) stop("wowsimcli: ", jsonlite::toJSON(d$error, auto_unbox = TRUE), call. = FALSE)
  n <- d$iterationsDone %||% req$simOptions$iterations
  pl <- d$raidMetrics$parties[[1]]$players[[1]]

  action_id <- function(id) if (!is.null(id$spellId)) as.character(id$spellId) else id$otherId %||% NA_character_
  hand <- function(tag) switch(as.character(tag %||% 0), `14` = "MH", `15` = "OH", NA_character_)
  num <- function(x) if (is.null(x)) 0 else as.numeric(x)
  actions <- purrr::map_dfr(pl$actions, function(a) {
    t <- if (length(a$targets)) a$targets[[1]] else list()
    tibble::tibble(id = action_id(a$id), tag = as.integer(a$id$tag %||% 0L), hand = hand(a$id$tag),
                   casts = num(t$casts) / n, hits = num(t$hits) / n,
                   crits = num(t$crits) / n, misses = num(t$misses) / n, dodges = num(t$dodges) / n,
                   glances = num(t$glances) / n, damage = num(t$damage) / n)
  })
  rage <- purrr::map_dfr(pl$resources, function(r) {
    if (!identical(r$type, "ResourceTypeRage")) return(NULL)
    tibble::tibble(id = action_id(r$id), tag = as.integer(r$id$tag %||% 0L), hand = hand(r$id$tag),
                   events = num(r$events) / n, rage = num(r$gain) / n, actual = num(r$actualGain %||% r$gain) / n)
  })
  rage <- wowsims_name(rage)
  list(dps = c(mean = pl$dps$avg, sd = pl$dps$stdev %||% NA_real_), iterations = n,
       per_second = c(dps = pl$dps$avg, rage = sum(rage$actual[rage$actual > 0]) / duration),
       actions = wowsims_name(actions), rage = rage, log = if (log) d$logs else NULL)
}

# ---- Fight by fight --------------------------------------------------------------------------------------------------

# One fight's numbers, in the columns the book's R model gives (data/fight_sim.R's simulate_fight), from a one-iteration
# result with its combat log: casts a minute, damage per second by source, rage per second, damage per rage of
# Bloodthirst and Whirlwind (after refunds), and from the log the time of every Heroic Strike and the rage each Execute
# spent. Abilities are looked up by name, so a rank change in wowsims needs a new name in wowsims_spell_names.
fight_summary <- function(res, duration, bt_cost = 30, refund = 0.8) {
  a <- res$actions; per_min <- 60 / duration
  dmg <- function(nm, tag = NULL) sum(a$damage[a$name %in% nm & (is.null(tag) | a$tag %in% tag)])
  casts <- function(nm, tag = 0L) sum(a$casts[a$name %in% nm & a$tag %in% tag])
  hs <- c("Heroic Strike", "Heroic Strike (rank 8)")
  bt <- a[a$name == "Bloodthirst", ]
  bt_spent <- sum(bt$casts) * bt_cost - refund * bt_cost * sum(bt$misses + bt$dodges)
  ww_spent <- -sum(res$rage$rage[res$rage$name == "Whirlwind"])
  ev <- if (!is.null(res$log)) wowsims_log_events(res$log) else list(hs_t = numeric(0), exec_rage = numeric(0), bt_t = numeric(0))
  # Bloodthirst starved (approximate): time Bloodthirst came back more than a global cooldown late, which in the book's
  # rotation means waiting for rage. NA without a log.
  starved <- if (is.null(res$log)) NA_real_ else sum(pmax(diff(ev$bt_t) - 6 - 1.5, 0)) / duration
  r <- res$rage
  tibble::tibble(
    bt_pm = casts("Bloodthirst") * per_min, ww_pm = casts("Whirlwind", 14L) * per_min, hs_pm = casts(hs) * per_min,
    rs_rps = sum(r$actual[r$name == "Reckless Swings"]) / duration,
    rps = sum(r$actual[r$actual > 0 & r$name != "Refund"]) / duration,
    total_dps = res$dps[["mean"]],
    dps_white = dmg("Melee") / duration, dps_hs = dmg(hs) / duration, dps_bt = dmg("Bloodthirst") / duration,
    dps_ww = dmg("Whirlwind") / duration, dps_dw = dmg("Deep Wounds") / duration, dps_exec = dmg("Execute") / duration,
    dps_wf = dmg("Windfury Totem strike") / duration,
    starved_share = starved,
    exec_n = casts("Execute"), exec_rage = list(ev$exec_rage), hs_t = list(ev$hs_t),
    dpr_bt = if (bt_spent > 0) dmg("Bloodthirst") / bt_spent else NA_real_,
    dpr_ww = if (ww_spent > 0) dmg("Whirlwind") / ww_spent else NA_real_)
}

# From a combat log: when each Heroic Strike went off (the swing, not the queueing), when each Bloodthirst was cast,
# and the rage each Execute spent (its cost plus the extra rage it uses up).
wowsims_log_events <- function(log) {
  lines <- strsplit(log, "\n", fixed = TRUE)[[1]]
  t_of <- function(x) as.numeric(sub("^\\[([0-9.]+)\\].*", "\\1", x))
  hs <- grep("Casting \\{SpellID: (11567|25286)\\} \\(Cost = [1-9]", lines, value = TRUE)
  bt <- grep("Casting \\{SpellID: 23894\\}", lines, value = TRUE)
  ex <- grep("Spent [0-9.]+ rage from \\{SpellID: 20662\\}", lines, value = TRUE)
  ex_amt <- as.numeric(sub(".*Spent ([0-9.]+) rage.*", "\\1", ex))
  list(hs_t = t_of(hs), bt_t = t_of(bt),
       exec_rage = if (length(ex)) unname(tapply(ex_amt, t_of(ex), sum)) else numeric(0))
}

# Fight by fight: every setup in `setups` (a named list) over `n` one-iteration fights, fight i with seed
# seed0 + i in every setup, so the setups are paired. Runs on `workers` R processes, and caches the result in
# data/sim_cache/wowsims/name.rds keyed on the requests and the wowsims commit. Returns one row per setup and fight
# (fight_summary's columns), plus the wowsims version as an attribute.
wowsims_fights <- function(name, setups, n, seed0 = 1000, log = TRUE,
                           workers = max(1, min(12, parallel::detectCores() - 2))) {
  v <- wowsims_ensure()
  reqs <- lapply(setups, wowsims_request)
  durs <- vapply(setups, function(p) utils::modifyList(wowsims_defaults, p)$duration, 0)
  key <- rlang::hash(list(reqs, n, seed0, log, v$commit, body(fight_summary), body(wowsims_log_events)))
  dir <- "data/sim_cache/wowsims"; dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(dir, paste0(name, ".rds"))
  if (file.exists(path)) {
    saved <- readRDS(path)
    if (identical(saved$key, key)) return(saved$value)
  }
  message("Running wowsims fight by fight: ", name, " @", v$short, " (", length(setups), " setups x ", n, " fights)")
  jobs <- expand.grid(fight = seq_len(n), setup = names(setups), stringsAsFactors = FALSE)
  cl <- parallel::makeCluster(workers); on.exit(parallel::stopCluster(cl))
  parallel::clusterCall(cl, setwd, getwd())
  parallel::clusterExport(cl, c("reqs", "durs", "seed0", "log", "v"), envir = environment())
  invisible(parallel::clusterEvalQ(cl, { source("data/wowsims.R"); .wowsims$version <- v; NULL }))
  rows <- parallel::parLapplyLB(cl, split(jobs, seq_len(nrow(jobs))), function(j) {
    req <- reqs[[j$setup]]
    req$simOptions <- list(iterations = 1, randomSeed = seed0 + j$fight, debugFirstIteration = log)
    res <- wowsims_exec(req, durs[[j$setup]], log = log)
    cbind(data.frame(setup = j$setup, fight = j$fight, stringsAsFactors = FALSE), fight_summary(res, durs[[j$setup]]))
  })
  value <- tibble::as_tibble(do.call(rbind, rows))
  attr(value, "version") <- v
  saveRDS(list(key = key, value = value), path)
  value
}

# Names for the warrior actions the book uses (spell ids from the wowsims result; other ids are kept as they are).
wowsims_spell_names <- c(
  OtherActionAttack = "Melee", `23894` = "Bloodthirst", `1680` = "Whirlwind", `25286` = "Heroic Strike",
  `11567` = "Heroic Strike (rank 8)", `20662` = "Execute", `10610` = "Windfury Totem strike",
  `12964` = "Unbridled Wrath", `1329554` = "Reckless Swings", `1329555` = "Reckless Swings (cast)",
  `12296` = "Anger Management", `29131` = "Bloodrage", `2687` = "Bloodrage (cast)", `18499` = "Berserker Rage",
  OtherActionRefund = "Refund", `12328` = "Death Wish", `7373` = "Hamstring", `11574` = "Rend",
  `11597` = "Sunder Armor", `11585` = "Overpower", `25289` = "Battle Shout", `11551` = "Battle Shout",
  `2457` = "Battle Stance", `2458` = "Berserker Stance", `12721` = "Deep Wounds", `412609` = "Deep Wounds"
)
wowsims_name <- function(df) {
  if (!nrow(df)) return(df)
  df$name <- unname(ifelse(df$id %in% names(wowsims_spell_names), wowsims_spell_names[df$id], df$id))
  df
}
# One action's row (summed over hands unless `hand` is given), as a named vector of its columns.
wowsims_action <- function(res, name, hand = NULL) {
  a <- res$actions[res$actions$name == name & (is.null(hand) | res$actions$hand %in% hand), ]
  colSums(a[, c("casts", "hits", "crits", "misses", "dodges", "glances", "damage")])
}

# ---- The character sheet ---------------------------------------------------------------------------------------------

# The sheet wowsims computes for a setup (data/wowsims/statsheet): a list of stats and pseudo-stats.
wowsims_sheet <- function(p = list()) {
  wowsims_ensure()
  s <- wowsims_settings(p)$settings
  out <- suppressWarnings(system2(wowsims_bin("wowsimcli-statsheet"), stdout = TRUE, stderr = TRUE,
                                  input = jsonlite::toJSON(s, auto_unbox = TRUE, digits = NA)))
  if (!is.null(attr(out, "status"))) stop("statsheet failed:\n", paste(out, collapse = "\n"), call. = FALSE)
  jsonlite::fromJSON(paste(out, collapse = "\n"))
}
# Attack power, melee crit (%) and melee hit (%) on the sheet.
sheet_numbers <- function(sh) c(ap = sh$stats$StatAttackPower, crit = sh$pseudo$PseudoStatMeleeCritPercent %||% 0,
                                hit = sh$pseudo$PseudoStatMeleeHitPercent %||% 0)

# ---- The book's warrior ----------------------------------------------------------------------------------------------

# The book's warrior in wowsims: level 60 human (fist weapons, so no racial weapon skill), Berserker Stance, the
# Forever 17/34/0 talents, a 2.7 and a 2.0 speed weapon of the same DPS, no buffs or consumables, a level 63 boss
# whose armor leaves 75% of physical damage, and the book's rotation. `bonus_stats` brings the warrior to the given
# attack power, crit (a share, as in the book: 0.28 is 28%) and hit from gear (a share). The book's crit is the crit
# you have in the fight; wowsims adds Berserker Stance's 3% when the fight starts, outside the sheet it computes, so
# the sheet is set 3% lower. Other fields of `p` are passed on (talents, raid_buffs, execute, ...).
book_wowsims <- function(dps, ap, crit, hit = 0.07, p = list(), stance_crit = 0.03) {
  base <- utils::modifyList(list(weapons = list(mh = c(dps, 2.7), oh = c(dps, 2.0))), p)
  base$bonus_stats <- c(p$bonus_stats, book_bonus_stats(base, ap, crit - stance_crit, hit))
  base
}
# The book's talent string with one Fury talent changed: `fury_pos` is its place in the Fury part of the string
# (wowsims' order, proto/warrior.proto), e.g. 10 for Reckless Swings, 17 for Flurry, 11 for Improved Execute.
book_talents <- function(fury_pos, rank, talents = wowsims_defaults$talents) {
  parts <- strsplit(talents, "-", fixed = TRUE)[[1]]
  f <- strsplit(parts[2], "")[[1]]; f[fury_pos] <- as.character(rank); parts[2] <- paste(f, collapse = "")
  paste(parts, collapse = "-")
}

# The bonus stats that bring a setup's sheet to `ap`, `crit` and `hit`. Rating per percent and attack power per point
# are measured on the sheet, not assumed; the result is checked, and it stops if the sheet misses by more than 0.5 AP
# or 0.01%.
book_bonus_stats <- function(p, ap, crit, hit) {
  key <- rlang::hash(list(p[c("talents", "settings", "weapons", "gear", "bonus_stats", "buffs", "raid_buffs", "debuffs")], wowsims_ensure()$commit))
  if (is.null(.wowsims$rates[[key]])) {
    s0 <- sheet_numbers(wowsims_sheet(p))
    probe <- function(stat, amount) sheet_numbers(wowsims_sheet(utils::modifyList(p, list(bonus_stats = c(p$bonus_stats, setNames(amount, stat))))))
    .wowsims$rates[[key]] <- list(s0 = s0, ap = (probe("attack_power", 100)["ap"] - s0["ap"]) / 100,
                                  crit = 140 / (probe("crit_rating", 140)["crit"] - s0["crit"]),
                                  hit = 100 / (probe("hit_rating", 100)["hit"] - s0["hit"]))
  }
  r <- .wowsims$rates[[key]]
  b <- c(attack_power = unname((ap - r$s0["ap"]) / r$ap), crit_rating = unname((crit * 100 - r$s0["crit"]) * r$crit),
         hit_rating = unname((hit * 100 - r$s0["hit"]) * r$hit))
  got <- sheet_numbers(wowsims_sheet(utils::modifyList(p, list(bonus_stats = c(p$bonus_stats, b)))))
  if (abs(got[["ap"]] - ap) > 0.5 || abs(got[["crit"]] - crit * 100) > 0.01 || abs(got[["hit"]] - hit * 100) > 0.01)
    stop(sprintf("sheet calibration missed: got %.1f AP, %.2f%% crit, %.2f%% hit for %.0f, %.2f, %.2f",
                 got[["ap"]], got[["crit"]], got[["hit"]], ap, crit * 100, hit * 100), call. = FALSE)
  b
}

# ---- Caching ---------------------------------------------------------------------------------------------------------

# cached_wowsims("name", setup) runs wowsims_run() and saves the result in data/sim_cache/wowsims/name.rds. It re-runs
# when the request (setup, rotation file, weapons, seed) or the wowsims commit changes.
cached_wowsims <- function(name, p = list()) {
  v <- wowsims_ensure()
  full <- utils::modifyList(wowsims_defaults, p)
  key <- rlang::hash(list(setup = full, siml = wowsims_siml(full), apl = readLines(full$apl), commit = v$commit))
  dir <- "data/sim_cache/wowsims"; dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(dir, paste0(name, ".rds"))
  if (file.exists(path)) {
    saved <- readRDS(path)
    if (identical(saved$key, key)) return(saved$value)
  }
  message("Running wowsims: ", name, " @", v$short)
  value <- wowsims_run(p)
  saveRDS(list(key = key, value = value), path)
  value
}

# "Simmed with wowsims forever @abc1234, 2026-11-18", from one result or a list of them (they should share a commit;
# if not, every commit is listed, which is a sign the cache needs a refresh).
wowsims_stamp <- function(res) {
  vs <- if (!is.null(res$version)) list(res$version) else lapply(res, `[[`, "version")
  # A result whose version was dropped (dplyr verbs drop attributes) is from this session's commit, since every cache
  # is keyed on it.
  vs <- lapply(if (length(vs)) vs else list(NULL), function(v) v %||% wowsims_ensure())
  vs <- unique(lapply(vs, function(v) v[c("short", "date")]))
  link <- function(v) sprintf("[wowsims forever \\@%s](https://github.com/wowsims/forever/commit/%s), %s", v$short, v$short, v$date)
  paste0("Simmed with ", paste(vapply(vs, link, ""), collapse = "; "))
}
