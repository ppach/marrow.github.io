"""Parse a WoW: Forever combat log into a per-player rage timeline.

Advanced-log field layout (build 1.60.1, COMBAT_LOG_VERSION 22), 0-based after the timestamp:
  0 event | 1-4 source guid/name/flags/raidflags | 5-8 dest guid/name/flags/raidflags
  SPELL_* events then carry 9 spellId, 10 spellName, 11 school; SWING_* events do not,
  so the advanced block starts at 12 for SPELL_* and at 9 for SWING_*.
  Advanced block (offset a): a+0 infoGUID, a+1 ownerGUID, a+2 curHP, a+3 maxHP, a+4 AP,
  a+5 SP, a+6 armor, a+7..a+9 (absorb + 2 unknown), a+10 powerType, a+11 curPower,
  a+12 maxPower, a+13 powerCost, a+14 posX, a+15 posY, a+16 mapID, a+17 facing, a+18 level.
  Suffix starts at a+19.
  Multi-power units report "1|4"-style lists; the first entry is the primary power.
Power values are in tenths (rage 1000 = 100.0).
"""
import csv
import io
import sys

ADV_LEN = 19


def split(line):
    ts, rest = line.rstrip("\n").split("  ", 1)
    return ts, next(csv.reader(io.StringIO(rest)))


def ts_seconds(ts):
    # "9/23/2026 10:49:08.889-7"
    t = ts.split(" ")[1].rsplit("-", 1)[0]
    h, m, s = t.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def first(v):
    return v.split("|")[0]


def adv_offset(event):
    if event.startswith("SWING_"):
        return 9
    if event.startswith(("SPELL_", "RANGE_", "DAMAGE_SHIELD")):
        return 12
    return None


def parse(path, player_guid):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "  " not in line or player_guid not in line:
                continue
            try:
                ts, f = split(line)
            except Exception:
                continue
            ev = f[0]
            a = adv_offset(ev)
            if ev in ("SWING_MISSED", "SPELL_MISSED", "RANGE_MISSED"):
                a = 9 if ev == "SWING_MISSED" else 12
                t = ts_seconds(ts)
                rows.append({"t": t, "event": ev, "src": f[1] == player_guid, "dst": f[5] == player_guid,
                             "spell": f[10] if a == 12 else "Melee", "info_is_player": False,
                             "miss": f[a], "raw": f})
                continue
            if a is None or len(f) < a + ADV_LEN:
                continue
            t = ts_seconds(ts)
            src, dst = f[1], f[5]
            row = {"t": t, "event": ev, "src": src == player_guid, "dst": dst == player_guid,
                   "spell": f[10] if a == 12 else "Melee", "info_is_player": f[a] == player_guid}
            if row["info_is_player"]:
                row["ptype"] = first(f[a + 10])
                row["rage"] = int(first(f[a + 11]))
                row["cost"] = int(first(f[a + 13])) if f[a + 13] not in ("", "nil") else 0
                row["level"] = int(f[a + 18])
                row["ap"] = int(f[a + 4])
                row["hp"] = int(f[a + 2])
                row["maxhp"] = int(f[a + 3])
            s = a + ADV_LEN
            if ev in ("SWING_DAMAGE", "SWING_DAMAGE_LANDED", "SPELL_DAMAGE", "RANGE_DAMAGE"):
                row["amount"] = int(f[s])
                row["crit"] = f[s + 7] == "1"
                row["glancing"] = f[s + 8] == "1"
            elif ev in ("SPELL_ENERGIZE", "SPELL_PERIODIC_ENERGIZE"):
                row["amount"] = float(f[s])
                row["energize_type"] = f[s + 2]
            row["raw"] = f
            rows.append(row)
    return rows


if __name__ == "__main__":
    path, guid = sys.argv[1], sys.argv[2]
    rows = parse(path, guid)
    for r in rows[:60]:
        print(r)
