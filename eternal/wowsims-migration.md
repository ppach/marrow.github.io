# Moving the book's sims to wowsims

Started 18 Nov 2026 against wowsims forever @1381c2b (2026-11-19). **The book treats wowsims as the source of truth
for today's game:** where the book disagreed with it, the book changed. How the sims run: `SIMS.md`.

Categories:

- **(a)** wowsims can run it for today's game, so it's simmed in wowsims.
- **(b)** Classic, an older build, a hypothetical, or the analytical formula. It stays on our simulator (a simplified
  model whose Forever rules follow wowsims), and the text says so.
- **(c)** not moved yet.

## Every sim in the book

| #  | Chapter, chunk                                   | What it simulates                                            | Now        | Notes |
| -- | ------------------------------------------------ | ------------------------------------------------------------ | ---------- | ----- |
| 1  | 01 Rage                                          | Log analysis only                                            | n/a        | No sims. |
| 2  | 02 `ladder()` and its figures                    | The rage-block formula, both games                           | (b)        | The analytical model. Its Forever rules follow wowsims. |
| 3  | 02 `scaling_fights` (formula check, Fig. scaling-dps) | Fights across a weapon-DPS grid, both games             | (b) + check | Our simulator for the sweep. The check table has a wowsims column at every phase (`scaling_phases`). |
| 4  | 02 `scaling_windfury`                            | Windfury Totem on and off                                    | (a) / (b)  | Forever in wowsims, Classic in our simulator. |
| 5  | 02 Reckless Swings table                         | Reckless Swings on and off at each phase                     | (a)        | wowsims, paired seeds. |
| 6  | 02 `scaling_reckless_rules`                      | Readings of the tooltip                                      | (b)        | Now "how much the charge rule matters": wowsims' measured rule against the old assumption and other readings. |
| 7  | 03 `crit_grid`                                   | v0, v1, v2, Classic                                          | (b)        | Historical and Classic. The attack table follows wowsims (crit suppression, glancing). |
| 8  | 03 `crit_sheet`                                  | Our model against Bored's spreadsheet                        | (b)        | Keeps the spreadsheet's own assumptions on purpose. |
| 9  | 03 `crit_grid_now`, today's Forever              | Rage, damage and Heroic Strike waits over AP × crit × hit    | (a)        | wowsims, 441 cells × 30 ten-minute fights. The waits come from each fight's combat log. |
| 10 | 03 `crit_grid_now`, no crit bonus                | A rule that doesn't exist                                    | (b)        | Our simulator. |
| 11 | 04 `flurry_check`                                | Markov chain against a simulation                            | (a)        | wowsims, white swings only, Flurry 3/3 against 0/3. The chain uses wowsims' measured crit per swing. |
| 12 | 04 `haste_windows`                               | Swing-window combinatorics                                   | n/a        | Not a fight sim. |
| 13 | 04 `haste_fights`                                | Extra haste at phase 2                                       | (c)        | Still our simulator (labelled). Possible next step: wowsims `haste_rating`, 41 steps × 300 fights. |
| 14 | 04 Flurry tables                                 | `flurry_stats` analytics                                     | (b)        | Analytical. |
| 15 | 05 `abilities_casts`                             | Single casts, both games                                     | (b)        | |
| 16 | 05 `abilities_fights`                            | Bloodthirst and Whirlwind over whole fights                  | (a) / (b)  | Forever in wowsims (500 fights a phase, so the "middle 90%" bands still work), Classic in our simulator. |
| 17 | 05 `abilities_priority`                          | Whirlwind first or Bloodthirst first                         | (a) / (b)  | Forever in wowsims, fight for fight on the same seeds. |
| 18 | 05 `abilities_execute`                           | Execute phase, Improved Execute 0/2 and 2/2                  | (a) / (b)  | Forever in wowsims. The rage per Execute comes from the combat logs. |
| 19 | 06 Known Bugs                                    | Constants only                                               | n/a        | BUG-1's fix confirmed by wowsims' logs (58.8%). |
| 20 | 07 crit rework                                   | v0, v1, v2                                                   | (b)        | |
| 21 | 07 `abilities_fights_oct` + `ww_cmp`             | The 1 Oct build against today's                              | (b)        | Both sides in our simulator (`ability_sims_r`), so the comparison is like for like. |
| 22 | archive/*                                        | Classic tests, proposals                                     | (b)        | Not rendered. Unchanged. |

## Where the book disagreed with wowsims, and what changed

| Rule | The book had | wowsims (source) | Change |
| ---- | ------------ | ---------------- | ------ |
| Unbridled Wrath rate | Tooltip 60%, BUG-1 fixed | 60%; logs 58.8% (EV-0148) | None needed. BUG-1 now cites the logs. |
| What rolls Unbridled Wrath | Landed white hits only | Also Heroic Strike and Windfury Totem's strike (EV-0148) | `ubw_hs`; text in 02 and 06. |
| Reckless Swings charges | Landed white swings, Heroic Strike, Bloodthirst, Whirlwind | Landed white swings, Windfury's strike, every Heroic Strike cast; not Bloodthirst or Whirlwind (EV-0138) | New default in `fight_sim.R`; 02 section rewritten. |
| Reckless Swings global cooldown | None (assumed) | 1 sec | `rs_gcd`; 02 text. |
| Windfury's strike and Flurry | Uses a charge | Uses none (EV-0138, EV-0140) | `wf_flurry`; 02 text. |
| Whirlwind cost | 22 (Raging Blows) | 25: Raging Blows isn't in the launch tree | `ww_cost = 25` (22 stays for the 1 Oct build); 02, 03, 05 text. |
| Glancing blow damage | 65% | 70% in Forever | `glance_dmg = 0.70` for Forever; 03 text. |
| Heroic Strike | Rank 9, +157 | Rank 8, +138 (measured from the log) | `hs_bonus = 138` for Forever. |
| Crit suppression (Rage on Crit) | None (Bored's spreadsheet) | 4.8% against a level 63 boss | 03's attack table and text. |
| Rage per swing, crit ×2, no rage from dodges or Heroic Strike, Flurry 30%, Bloodthirst 45% AP + 48, Improved Whirlwind 8 sec / +30%, 80% refund, Execute 15 rage per point | | Same | Agrees. |

## Still open

- Row 13 (haste in fights) is the last (c).
- A full re-run of the wowsims sims takes about an hour. Results are cached per wowsims commit.
