# Warrior talents: reference data

Our reference for what every warrior talent does in WoW: Forever, and how it differs from Classic.
Check here before assuming a talent's value, tree or requirement.

**Source:** [talentsforever.com](https://talentsforever.com) data export (`data.json`, CC BY 4.0, credit the site
with a link), read from the beta client (build 1.60.1.69876, export dated 2026-09-20). Rebuild the tables with
`python extract.py` after downloading a fresh `data.json` (it isn't committed).

| File | What's in it |
|---|---|
| `warrior_talents.csv` | One row per talent: tree, row, column, max rank, Forever max-rank tooltip, Classic **rank 1** tooltip and status (same / changed / new / moved) |
| `warrior_talent_ranks.csv` | Every rank's Forever tooltip, and whether the site read it verbatim from the client |
| `warrior_abilities.csv` | Every trainer spell rank: cost, cooldown, Forever and Classic tooltips |

The Classic text is rank 1 only (for example, Flurry shows 10%, when 5/5 was 30%), so work out Classic max ranks by hand.

## Talent rules

- **Points:** 1 point per level from level 10, so **51 at level 60**.
- **Rows:** a row opens once the tree has 5 points per row above it: row 2 needs 5 points in that tree, row 3 needs 10, and so on (row 7 needs 30).
- **Arrows:** some talents need the talent above them maxed first.
- **Trees matter:** a talent can only be taken with enough points in *its own* tree, so a build's reachable talents depend on where the points go.

## Tree layout

Row / column positions, max rank in brackets. **New** = not in Classic.

| Row (points needed) | Arms | Fury | Protection |
|---|---|---|---|
| 1 (0) | Improved Heroic Strike (3), Deflection (5), Improved Rend (3) | Booming Voice (5), Cruelty (5) | Shield Specialization (5), Anticipation (5) |
| 2 (5) | Improved Charge (2), Improved Tactical Mastery (5), Improved Overpower (2) | Iron Will (5), Unbridled Wrath (5) | Improved Bloodrage (2), Toughness (5), Improved Thunder Clap (3) |
| 3 (10) | Anger Management (1), Deep Wounds (3) | Improved Cleave (3), Piercing Howl (1), Blood Craze (3), **Boundless Rage (3)** | Last Stand (1), **Master of Defense (2)**, Improved Revenge (3), Defiance (3) |
| 4 (15) | **Spearing Strike (1)**, Two-Handed Weapon Specialization (3), Impale (2) | Dual Wield Specialization (5), **Raging Blows (1)**, Enrage (5), Improved Execute (2) | Improved Sunder Armor (3), Improved Disarm (3), **Vanguard (1)** |
| 5 (20) | **Bloodthrill (5)**, Sweeping Strikes (1), **Weaponmaster (5)** | **Precision (3)**, Death Wish (1), Improved Intercept (2) | Improved Shield Wall (2), Concussion Blow (1), Improved Shield Bash (2), **Bastion (5)** |
| 6 (25) | Improved Slam (2), Improved Hamstring (3) | Improved Berserker Rage (2), Flurry (5) | **Focused Rage (3)** |
| 7 (30) | Mortal Strike (1) | Bloodthirst (1) | Shield Slam (1) |

## What the beta's level cap lets us test

At level 20 there are 11 points, so rows 1 to 3 of one tree are reachable:

- **Testable now:** Cruelty, Unbridled Wrath, Improved Heroic Strike, Improved Rend, Improved Charge, Improved Tactical Mastery, and in row 3, Anger Management (1 rage every 3 sec in combat), Boundless Rage (+30 max rage), Deep Wounds, Blood Craze, Master of Defense, Improved Bloodrage.
- **Needs level 24+ (15 points in the tree):** Dual Wield Specialization, Raging Blows, Enrage, Impale, Two-Handed Weapon Specialization.
- **Needs level 34+ (25 points):** Flurry.
