"""Rage analysis of the posted WoW: Forever logs, driven by logs/metadata.yaml.

Writes derived CSVs to derived/ and prints a summary. Run from this directory:
    python analyze.py
"""
import csv
import os
import statistics as st
from collections import Counter, defaultdict

import yaml

from parse_log import parse

MAX_GAP = 2.0      # seconds between snapshots; longer gaps may hide decay
RAGE_CAP = 1000    # tenths


def snapshots(rows):
    return [r for r in rows if r.get("info_is_player") and r.get("ptype") == "1"]


def after(s):
    # rage after the event: cast snapshots are taken before the cost is paid
    return s["rage"] - (s["cost"] if s["event"] == "SPELL_CAST_SUCCESS" else 0)


def analyze(meta):
    rows = parse(os.path.join("logs", meta["file"]), meta["player_guid"])
    snaps = snapshots(rows)
    levels = Counter(r["level"] for r in snaps)
    idx = {id(r): i for i, r in enumerate(rows)}

    swings, taken, misses = [], [], []
    for p, s in zip(snaps, snaps[1:]):
        if s["t"] - p["t"] > MAX_GAP:
            continue
        gain = s["rage"] - after(p)
        between = rows[idx[id(p)] + 1: idx[id(s)]]
        if s["event"] == "SWING_DAMAGE" and s["src"]:
            swings.append({"t": s["t"], "level": s["level"], "damage": s["amount"], "crit": s["crit"],
                           "glancing": s["glancing"], "ap": s["ap"], "gain": gain, "capped": s["rage"] >= RAGE_CAP})
        elif s["dst"] and not s["src"] and s["event"] in ("SWING_DAMAGE_LANDED", "SPELL_DAMAGE", "RANGE_DAMAGE"):
            if s["rage"] < RAGE_CAP and not any(b["src"] and b["event"].startswith("SWING") for b in between):
                taken.append({"level": s["level"], "damage": s["amount"], "maxhp": s["maxhp"], "gain": gain})
        own_miss = [b for b in between if b["event"] == "SWING_MISSED" and b["src"]]
        if len(own_miss) == 1 and not s["src"] and s["rage"] < RAGE_CAP and \
                not any(b["src"] and b["event"] == "SWING_DAMAGE" for b in between):
            misses.append({"miss": own_miss[0]["miss"], "gain": gain})

    energize = Counter((r["spell"], r["amount"]) for r in rows
                       if r["event"].endswith("ENERGIZE") and r["dst"] and r.get("energize_type") == "1")
    # Unbridled Wrath procs per landed white hit (procs at the rage cap still log, with 0 rage).
    landed_white = sum(1 for r in rows if r["event"] == "SWING_DAMAGE" and r["src"])
    ubw_procs = sum(1 for r in rows if r["event"] == "SPELL_ENERGIZE" and r["dst"] and r["spell"] == "Unbridled Wrath")
    # Level check: the level the log gives the player, against the level of the mobs they hit.
    # (SWING_DAMAGE_LANDED carries the target's advanced block, so its level field is the mob's.)
    mob_levels = [int(r["raw"][9 + 18]) for r in rows if r["event"] == "SWING_DAMAGE_LANDED" and r["src"]
                  and r["raw"][9].startswith("Creature")]
    procs = {"landed_white": landed_white, "ubw_procs": ubw_procs,
             "ubw_rank": (meta.get("talents") or {}).get("unbridled_wrath"),
             "log_level": levels.most_common(1)[0][0] if levels else None,
             "posted_level": meta.get("level_posted"),
             "mob_level_median": st.median(mob_levels) if mob_levels else None}
    return rows, levels, swings, taken, misses, energize, procs


def clusters(swings):
    """Group uncapped swing gains into clusters (values within 2 tenths) and time each cluster's swings."""
    vals = sorted(Counter(s["gain"] for s in swings if not s["capped"]).items())
    groups = []
    for v, n in vals:
        if groups and v - groups[-1]["max"] <= 2:
            g = groups[-1]
            g["max"], g["n"], g["sum"] = v, g["n"] + n, g["sum"] + v * n
        else:
            groups.append({"min": v, "max": v, "n": n, "sum": v * n})
    out = []
    for g in groups:
        if g["n"] < 10:
            continue
        mem = [s for s in swings if not s["capped"] and g["min"] <= s["gain"] <= g["max"]]
        gaps = [b["t"] - a["t"] for a, b in zip(mem, mem[1:]) if b["t"] - a["t"] < 5]
        dmg = [s["damage"] for s in mem]
        crit = [s["gain"] for s in mem if s["crit"]]
        norm = [s["gain"] for s in mem if not s["crit"]]
        out.append({"mean_gain": g["sum"] / g["n"] / 10, "n": g["n"],
                    "swing_interval_median": st.median(gaps) if gaps else None,
                    "damage_min": min(dmg), "damage_max": max(dmg),
                    "corr_damage": st.correlation(dmg, [s["gain"] for s in mem]) if len(set(dmg)) > 1 and len({s['gain'] for s in mem}) > 1 else 0.0,
                    "mean_gain_crit": st.mean(crit) / 10 if crit else None,
                    "mean_gain_noncrit": st.mean(norm) / 10 if norm else None})
    return out


def check(meta, rows, levels, cl):
    """Compare a log with its posted metadata. Returns warnings; an empty list means consistent."""
    warn = []
    if not levels:
        warn.append(f"no rage snapshots for {meta['player_guid']}: wrong GUID, or not a warrior")
        return warn
    speeds = [w["speed"] for w in meta["equipped_weapons"]]
    for c in cl:
        iv = c["swing_interval_median"]
        if iv is None or not any(abs(iv - s) / s <= 0.05 for s in speeds):
            warn.append(f"swing group +{c['mean_gain']:.2f} rage has interval {iv}s, matching no posted "
                        f"speed {speeds}: haste, a weapon swap, or wrong metadata")
    if len(cl) > len(speeds):
        warn.append(f"{len(cl)} swing groups for {len(speeds)} weapon(s): likely a hand or weapon swap mid-log")
    if len(levels) > 1:
        warn.append(f"level changes during the log: {dict(levels)}")
    return warn


def main():
    metas = yaml.safe_load(open("logs/metadata.yaml"))
    os.makedirs("derived", exist_ok=True)
    all_sw, all_tk, all_cl, all_mi, all_en, all_pr = [], [], [], [], [], []
    for m in metas:
        rows, levels, swings, taken, misses, energize, procs = analyze(m)
        all_pr.append({"file": m["file"], "character": m["character_name"], "setup": m["setup"], **procs})
        weapons = ", ".join(f"{w['slot']} {w['name']} {w['speed']}" for w in m["equipped_weapons"])
        print(f"\n== {m['file']}  ({m['character_name']}, build {m['beta_build']}, {m['setup']})")
        print(f"   weapons: {weapons}")
        print(f"   levels in log: {dict(levels)}")
        cl = clusters(swings)
        for w in check(m, rows, levels, cl):
            print(f"   WARNING: {w}")
        capped = sum(s["capped"] for s in swings)
        print(f"   white swings: {len(swings)} ({capped} at the rage cap, excluded)")
        for c in cl:
            print(f"   +{c['mean_gain']:.2f} rage  n={c['n']:<4} swing interval ~{c['swing_interval_median']:.2f}s  "
                  f"dmg {c['damage_min']}-{c['damage_max']} corr={c['corr_damage']:+.2f}  "
                  f"crit {c['mean_gain_crit']} vs non-crit {c['mean_gain_noncrit']:.2f}")
            all_cl.append({"file": m["file"], "character": m["character_name"], "setup": m["setup"], **c})
        if taken:
            k = sum(t["gain"] for t in taken) / sum(t["damage"] for t in taken) / 10
            print(f"   damage taken: n={len(taken)}  rage per point of damage = {k:.4f}")
        mc = defaultdict(list)
        for x in misses:
            mc[x["miss"]].append(x["gain"])
        print("   own swing misses -> rage:", {k: f"{st.mean(v)/10:.2f} (n={len(v)})" for k, v in mc.items()})
        print("   energize:", dict(energize))
        for s in swings:
            all_sw.append({"file": m["file"], "character": m["character_name"], "setup": m["setup"], **s})
        for t in taken:
            all_tk.append({"file": m["file"], "character": m["character_name"], **t})
        for k, v in mc.items():
            all_mi.append({"file": m["file"], "miss": k, "n": len(v), "mean_gain": st.mean(v) / 10})
        for (spell, amt), n in energize.items():
            all_en.append({"file": m["file"], "spell": spell, "amount": amt, "n": n})

    for name, data in [("swings", all_sw), ("taken", all_tk), ("swing_clusters", all_cl),
                       ("misses", all_mi), ("energize", all_en), ("procs", all_pr)]:
        with open(f"derived/{name}.csv", "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(data[0].keys()))
            w.writeheader()
            w.writerows(data)


if __name__ == "__main__":
    main()
