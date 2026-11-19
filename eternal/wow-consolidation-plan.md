# Plan: put the WoW projects side by side under C:\Users\pedro\wow

Status: **done on 18 Nov 2026** (steps 1 to 7 below). The old folders are still in place as a fallback (step 8). One
change from the proposal: the site's fury rotation stayed in the gear sim, since the book doesn't use it, so nothing is
copied twice.

## Target layout

```
C:\Users\pedro\wow\                  (outside OneDrive)
  marrow.github.io\     git, today C:\Users\pedro\Documents\marrow.github.io (remote github.com/ppach/marrow.github.io)
  auction-watch\        new git repo, today C:\Users\pedro\OneDrive\Documentos\TSM Auction Watch
    tsm-dashboard\
    gear-sim\
  wowsims-forever\      git (a shallow clone of github.com/wowsims/forever), today C:\Users\pedro\src\wowsims-forever
  wow-sim-tools\        new, small: see below
```

**Is `wow-sim-tools` worth having? Yes, but small.** Both the book (R) and the gear sim (Python) need the same two
things: "update and rebuild wowsims first" and the fury rotation files. Today the update script lives in the book
(`eternal/data/wowsims_update.ps1`), and the rotation is copied in two places. `wow-sim-tools` would hold:

- `wowsims_update.ps1` (moved from the book), which also builds the `statsheet` helper
- `statsheet/` (today `eternal/data/wowsims/statsheet`): prints wowsims' character sheet for a setup. The gear sim
  could use it to show stats next to each swap.
- (not moved: the site's fury rotation stays in `gear-sim/`, the only user; the book's own rotations stay in the book)
- `siml.py`, the SIML builder and CLI runner pulled out of `gear-sim/sim_swaps.py`

The R bridge (`data/wowsims.R`) stays in the book. It would find the tools through a `WOW_SIM_TOOLS` environment
variable, defaulting to `..\..\wow-sim-tools` from `eternal\`. Rendering the book would then need that folder next to
the repo. If you'd rather keep the book self-contained, the alternative is to leave the script in the book and have
the gear sim call it there.

## Why not OneDrive

Git repos inside OneDrive get sync conflicts and locked files (`.git\index.lock`, `bin\wowsimcli.exe` while a sim
runs). Built output would also fill OneDrive: two 35 MB `wowsimcli` binaries, the Go and protoc output, and
`node_modules` if the wowsims UI is ever built. So everything goes to `C:\Users\pedro\wow`. Backup comes from git
remotes instead. For `auction-watch`, that means a **private** GitHub repo, since it holds your price alerts and
trading notes.

There's no `node_modules` anywhere today. There are only `__pycache__` folders (in `tsm-dashboard`, `gear-sim` and
`eternal\data`).

## Everything that hard-codes a current path

| Where                                                      | What it says today                                                                                                                         | Change after the move                                                                               |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| Windows task **TSM Auction Watch** (timed)                 | `pythonw.exe "...\OneDrive\Documentos\TSM Auction Watch\tsm-dashboard\build.py"`, working directory the same folder                       | Re-point the action and the working directory (`Set-ScheduledTask`)                                 |
| Windows task **TSM Price Alerts** (timed)                  | the same, for `alert.py`                                                                                                                   | The same                                                                                            |
| Windows task **TSM Dashboard Server** (at logon, **running now**) | the same, for `server.py`                                                                                                           | Stop it before the move, re-point it, start it                                                      |
| **market-trends-report**                                   | Not a Windows task. It's a Claude scheduled task: `~\.claude\scheduled-tasks\market-trends-report\SKILL.md` says "Work only inside the folder C:\Users\pedro\OneDrive\Documentos\TSM Auction Watch\tsm-dashboard". | Edit that line (and its working folder, if the scheduler stores one)                                |
| `tsm-dashboard\start-server.bat`, `update-dashboard.bat`, `farm-start.bat`, `farm-stop.bat` | `%~dp0`, and the task name "TSM Dashboard Server"                                                          | None. They're already relative.                                                                     |
| `tsm-dashboard\server.py`, `build.py`                      | Paths from `__file__`                                                                                                                      | None                                                                                                |
| `tsm-dashboard\build.py` (`--wow` default), `alert.py` (`APPDATA`), `farm.py` (`WOW`) | `C:\Games\World of Warcraft\_forever_`, the game and addon folder                                              | None, because the game doesn't move. Suggested: read it from one setting (an environment variable `WOW_DIR`) instead of three copies. |
| `gear-sim\sim_swaps.py`, `gear-sim\build_pool.py`          | `REPO = C:\Users\pedro\src\wowsims-forever`                                                                                                | `WOWSIMS_REPO` environment variable, defaulting to `..\..\wowsims-forever`                          |
| `gear-sim\prices.py`, `build_pool.py`, `report_data.py`    | `..\tsm-dashboard` (relative)                                                                                                              | None, while both stay inside `auction-watch`                                                        |
| `TSM Auction Watch\.claude\launch.json`                    | relative `tsm-dashboard`                                                                                                                   | None                                                                                                |
| Book: `eternal\data\wowsims.R`, `data\wowsims_update.ps1`  | Default `C:\Users\pedro\src\wowsims-forever`                                                                                               | New default, or set `WOWSIMS_REPO`                                                                  |
| Book: `deploy.R`, `eternal.Rproj`, `rsconnect\`            | Relative                                                                                                                                   | None                                                                                                |
| **Claude memory** (keyed on the folder path)               | `~\.claude\projects\C--Users-pedro-OneDrive-Documentos-TSM-Auction-Watch\memory\`: 6 files (`fury-gear-sim.md` names the wowsims path). `~\.claude\projects\C--Users-pedro-Documents-marrow-github-io\memory\` (1 memory). `...-marrow-github-io-eternal\` (no memory). | Copy each `memory\` folder to the new key (`C--Users-pedro-wow-auction-watch`, `C--Users-pedro-wow-marrow-github-io`). Update the path in `fury-gear-sim.md`. Old session transcripts stay where they are. |
| Desktop shortcuts and pinned items, if any                 | Not checked                                                                                                                                | Check by hand                                                                                       |

## What auction-watch's .gitignore should hold

Keep out of git (TSM history, saved variables, personal data, and generated or cached files):

```
# TSM data and anything derived from it
tsm-dashboard/history/          # 40 MB of TSM snapshots per realm
tsm-dashboard/daily.csv
tsm-dashboard/dashboard.html    # generated, embeds all the data
tsm-dashboard/alerts-state.json
tsm-dashboard/alerts.log
tsm-dashboard/farm_sessions.json
tsm-dashboard/names.json        # Wowhead name cache
tsm-dashboard/trends/*.json     # calls logs
# Saved variables / addon exports, never copied in
*.lua
# gear sim: your gear, bag and results
gear-sim/bag.json
gear-sim/my_gear.*
gear-sim/me_*.siml
gear-sim/*.result.json
gear-sim/pool.json
gear-sim/exalted.json
gear-sim/search_results*.json
gear-sim/shortlist.*
gear-sim/swaps.*
gear-sim/weights.json
gear-sim/report.html
gear-sim/report_data.json
*.log
*.out
__pycache__/
```

Commit: the `.py` and `.bat` files, `template.html`, `report_template.html`, the `*.apl.siml` files, and the
hand-made reference data (`categories.json`, `recipes.json`, `item_uses.json`, `supply_caps.json`, `nodes.json`).

**Your call:** `alerts.json` (your price alert list), `plan.json`, `categories.blocked`, `trends/*.md` (daily reports)
and `trends/WRITING_GUIDE.md`. They're personal, but small and useful to keep in a private repo.

In the book, the 19 R-model cache files (`eternal/data/sim_cache/`) are committed. Keep it that way, so a render works
without re-running everything, and commit `data/sim_cache/wowsims/` the same way.

## Steps, once you approve

1. Stop the three Windows tasks and any running `wowsimcli`. Close RStudio and editors on these folders.
2. Copy (not move) each folder to `C:\Users\pedro\wow\...` with `robocopy /E`, leaving out `__pycache__`.
3. In `auction-watch`: `git init`, add the `.gitignore` above, make the first commit, and create a private remote if
   you want one.
4. Create `wow-sim-tools`. Move the update script and the rotation files there. Point the book and the gear sim at it.
5. Update the paths in the table above. Re-register the three tasks. Edit the market-trends-report task.
6. Copy the Claude memory folders to their new keys.
7. Test: run each task once, open the dashboard, run `sim_swaps.py` on a small bag, render one book chapter.
8. Keep the old folders for a week, then delete them (after asking you).
