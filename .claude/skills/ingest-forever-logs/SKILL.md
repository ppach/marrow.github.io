---
name: ingest-forever-logs
description: Find new WoW Forever combat logs posted to github.com/magey/forever-warrior/discussions, download them, record their posted metadata in eternal/data/logs/metadata.yaml, check them against that metadata, and fold them into the rage analysis and the Eternal book. Use when the user asks to check for new logs, pull or ingest logs, add a log, update the analysis with new data, or refresh the rage findings.
---

# Ingest new Forever combat logs

The Eternal compendium tests the Classic compendium's formulas (in `classic/`) against combat logs from the new game. Logs arrive as attachments on posts in the Logs category of https://github.com/magey/forever-warrior/discussions, with metadata the poster types in: character, build, weapons and speeds, weapon skill, hit and crit. That metadata drives the analysis, so it must be recorded faithfully.

All paths below are relative to `eternal/data/`. Python is at `C:/Users/pedro/AppData/Local/Programs/Python/Python311/python.exe` (the bare `python` in Git Bash is a Store stub). R is `C:/Program Files/R/R-4.4.1/bin/Rscript.exe`, and pandoc is in `C:/Users/pedro/AppData/Local/Pandoc`.

## Steps

1. **Find and download new logs.** Run `python fetch_logs.py`. It lists every Logs discussion, marks which attachments are already in `logs/metadata.yaml` (by the `attachment` URL), downloads new ones to `logs/incoming/`, and prints for each:
   - the post text, which holds the metadata
   - the log header (combat log version, build)
   - every warrior in the log, with GUID, level and cast count

   If nothing is new, say so and stop. Use `--list` to look without downloading.

   The script reads the posts through the GitHub API with `gh` (at `C:/Program Files/GitHub CLI/gh.exe`). That takes one call and returns the raw post markdown. If gh is not logged in, it prints `(gh unavailable ...)` and scrapes the public pages instead. The results are the same, only slower. Suggest `gh auth login` to the user if you see that line.

2. **Pick the right character.** A log often contains several warriors (for example, `ryqenz_zomdaya_uw_dw_092326.txt` also holds Shwn). Match the posted character name to a warrior's name in the log. Names in the log are `Name-Realm`, and the posted name can include a surname ("Siax Isanorc" is `Siax-ClassicBetaPvP2-`). If no warrior matches, or two could match, ask the user. Do not guess.

3. **Name and move the file.** Use `<character>_<zone>_<setup>_<MMDDYY>.txt`, all lower case, with `setup` as `dw`, `2h` or `1h_shield`. Use the poster's name as a prefix when it differs from the character (`ryqenz_zomdaya_...`). Move the file from `logs/incoming/` to `logs/`.

4. **Record the metadata.** Add an entry to `logs/metadata.yaml`, following the existing entries:
   - Copy what the poster wrote, even if it looks wrong. Put your doubts in `notes` or a comment, never in the value. For example, Siax posted 0% crit while the log shows crits.
   - Weapon order is main hand first. Weapon `type` comes from the post or the item name, and `speed` is required. If the post gives no speed, ask the user or the poster. The analysis cannot place swings without it.
   - `player_guid` comes from step 2. `source` is the discussion URL, and `attachment` is the file URL, which is what marks the log as ingested.
   - Level is not a metadata field. The analysis reads it from the log.
   - If the post lacks a required field (build, weapons, speeds), record what exists, add a `notes` line naming what is missing, and tell the user.

5. **Run the analysis and read the warnings.** Run `python analyze.py`. For each log it prints the rage-per-swing groups with their swing intervals, then `WARNING:` lines where the log and the metadata disagree:
   - a swing interval that matches no posted speed: haste, a weapon swap, or a wrong speed in the post
   - more swing groups than weapons: a hand or weapon swap mid-log (known for `ryqenz_zomdaya_uw_dw_092326.txt`)
   - no rage snapshots: wrong GUID, or the character is not a warrior
   - level changes during the log

   Investigate each warning in the log before accepting it, and record the outcome in the entry's `notes`. Do not edit the posted values to silence a warning.

6. **Check the new data against the current findings.** The current model (chapter `eternal/01-rage.Rmd`) is:

   > rage per white swing = rate × weapon speed, with rate ≈ 3.46 (main hand), 1.73 (off hand), 4.5 (two-hand), and no dependence on damage, crits, or level 13 to 16

   Say plainly whether the new log agrees. Pay most attention to anything the current data cannot answer, because that is where a new log adds the most:
   - a second two-hand speed (rate versus flat bonus)
   - levels above 16
   - other stances
   - a new build number

   A new build can change mechanics. Report findings per build, and never pool builds silently.

7. **Rebuild the book.** From `eternal/`, run:

   ```bash
   PATH="$PATH:/c/Users/pedro/AppData/Local/Pandoc" "/c/Program Files/R/R-4.4.1/bin/Rscript.exe" -e '.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths())); bookdown::render_book("index.Rmd", "bookdown::gitbook", quiet = TRUE)'
   ```

   The chapter reads `data/derived/*.csv` and `metadata.yaml`, so new logs appear in its tables and plots without code changes. Update the prose when the numbers or conclusions moved. Look at the rendered plots, not only the build status.

8. **Report, then ask before publishing.** Tell the user:
   - which logs you added
   - the warnings and what you found for each
   - whether the findings changed

   Commit and push (git identity `Marrow <marrowwar@gmail.com>`, no Claude co-author trailer) and redeploy (`Rscript deploy.R` from `eternal/`) only when the user says so.

## Log format notes

`data/parse_log.py` documents the field layout for build 1.60.1 (COMBAT_LOG_VERSION 22). If a new build changes the header or field count, parsing breaks quietly: swing groups vanish, or levels look wrong. In that case, re-check the layout against a known event before trusting any number. Charge's `SPELL_ENERGIZE` should show `9.0000` rage, and a `SPELL_CAST_SUCCESS` for Heroic Strike should show cost `150`.

Facts about the log that the analysis relies on:
- Rage appears in tenths (1000 = 100 rage).
- Each event records the unit's own rage after its effect, except `SPELL_CAST_SUCCESS`, which records it before the cost is paid.
- Swings made at 100 rage are excluded, since their gain is cut off by the cap.
