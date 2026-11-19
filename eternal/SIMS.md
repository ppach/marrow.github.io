# How the book's sims run

The book uses two simulators.

1. **wowsims** ([github.com/wowsims/forever](https://github.com/wowsims/forever)) is the community simulator. The
   book treats it as the source of truth for how today's game works. Where the book's text or its own model
   disagrees with wowsims, the book changes. A local clone lives at `C:\Users\pedro\src\wowsims-forever`, or wherever
   the `WOWSIMS_REPO` environment variable points.
2. **Our simulator** (`data/fight_sim.R`, `data/flurry.R`) is a simplified model. It runs what wowsims can't:
   Classic, the older Forever builds, the readings of a tooltip that turned out not to be the rule, and the
   rage-block formula. Its Forever rules follow wowsims (see the header of `fight_sim.R`). The text labels its
   numbers as our simulator's.

Which sim uses which simulator, and why: `wowsims-migration.md`.

## The book's warrior in wowsims

`book_wowsims(dps, ap, crit, hit)` in `data/wowsims.R` builds the warrior the book describes:

- level 60 human, Berserker Stance, the Forever 17/34/0 talents;
- custom fist weapons of exactly the book's DPS (2.7 and 2.0 speed, no stats, no racial weapon skill);
- `bonus_stats` set so wowsims' own character sheet shows the book's attack power, crit and hit. The rates are
  measured on the sheet, and the result is checked. Berserker Stance's 3% crit is allowed for;
- no buffs or consumables, and a level 63 boss whose armor leaves 75% of physical damage;
- the book's rotation, `data/wowsims/book.apl.siml`: Reckless Swings, Execute in the execute phase, Bloodthirst,
  Whirlwind, then Heroic Strike at 72 rage. Two variants exist: `book_ww_first.apl.siml` (Whirlwind first) and
  `white_only.apl.siml` (the Flurry check).

SIML can't express custom items, a random seed or the combat log. So R turns the SIML into the player's settings
(`wowsimcli siml parse -json`), wraps them in a full `RaidSimRequest` (as the CLI itself does), and adds those three
things.

## Running sims

| Function                            | What it does                                                                                       |
| ----------------------------------- | -------------------------------------------------------------------------------------------------- |
| `wowsims_ensure()`                  | Runs `data/wowsims_update.ps1` once per R session. Every wowsims call goes through it.             |
| `cached_wowsims(name, p)`           | One multi-iteration run, cached in `data/sim_cache/wowsims/name.rds`.                              |
| `wowsims_fights(name, setups, n)`   | `n` one-iteration fights per setup, on parallel workers. Fight *i* gets seed `seed0 + i` in every setup, so setups are paired. Each fight's combat log gives Heroic Strike times, rage per Execute and an approximate "Bloodthirst starved" share. Returns the columns of `fight_sim.R`'s `simulate_fight`, cached. |
| `wowsims_sheet(p)`                  | The character sheet wowsims computes (the `statsheet` helper).                                     |
| `wowsims_stamp(res)`                | "Simmed with wowsims forever @abc1234, 2026-11-19" for the text, linked to the commit.             |

A cached result is keyed on the full request (setup, rotation file, weapons, seed) and the wowsims commit. When
wowsims moves, every wowsims number in the book runs again on the next render, and the stamps in the text change
with them.

## Keeping wowsims current

`data/wowsims_update.ps1` runs these steps:

1. It runs `git fetch`. If `origin/master` moved, it fast-forwards the clone. Then it prints the commit range and
   the commits that touch `sim/warrior`, `sim/common/forever`, `sim/core` or `proto`.
2. If the binary isn't from the checked-out commit, it regenerates the protos and rebuilds `bin\wowsimcli.exe`. It
   also builds `bin\wowsimcli-statsheet.exe` (from `data/wowsims/statsheet`). A running binary is moved aside, not
   overwritten.
3. It writes `bin\wowsimcli.version.json` with the commit hash and date.

The script stops with an error in these cases: the fetch fails, the clone has local changes or commits, the pull is
not a fast-forward, or a build fails. After a failure, the version file still names the old commit. R refuses a
binary whose version file doesn't match the checkout, so the book never quietly uses a stale build.

## Refreshing the numbers

- **Normal render:** run `bookdown::render_book("index.Rmd")` or `Rscript deploy.R`. The render updates wowsims and
  re-runs only the sims whose inputs or wowsims commit changed. A full re-run of the wowsims sims takes about an hour
  on 12 workers. The biggest part is the 441-cell crit grid in Rage on Crit.
- **No network:** set `options(wowsims.offline = TRUE)` before you render.
- **Update wowsims by hand:** run `powershell -ExecutionPolicy Bypass -File data\wowsims_update.ps1` (add `-Force`
  to rebuild anyway).
- **Force every sim to run again:** delete `data/sim_cache/` (our simulator) or `data/sim_cache/wowsims/` (wowsims).
- **When wowsims changes a rule:** the numbers update by themselves, but the text and `fight_sim.R` don't. Read the
  "commits touching ..." list the update prints. If one changes a warrior or Forever rule, bring `fight_sim.R`'s
  Forever rules and the text in line with it.
