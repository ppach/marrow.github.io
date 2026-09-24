"""Turn the talentsforever.com data export into tidy warrior tables.

Source: https://talentsforever.com/data.json (CC BY 4.0, data from talentsforever.com), from the
WoW Forever beta client. Writes:
  warrior_talents.csv       one row per talent: Forever max-rank text, Classic text and status
  warrior_talent_ranks.csv  one row per talent rank (Forever tooltip text)
  warrior_abilities.csv     one row per trainer spell rank: Forever and Classic tooltips
Run from this directory: python extract.py
"""
import csv
import json

d = json.load(open("data.json", encoding="utf-8"))
talents, ranks = [], []
for tree in d["talents"]["Warrior"]["trees"]:
    for t in tree["talents"]:
        c = t.get("classic") or {}
        talents.append({"tree": tree["name"], "talent": t["name"], "row": t["row"], "col": t["col"],
                        "max_rank": t["max"], "classic_status": c.get("status", "new"),
                        "classic_tree": c.get("tree"), "classic_max_rank": c.get("max"),
                        "forever_max_rank_text": t["desc"][-1] if t["desc"] else "",
                        "classic_rank1_text": c.get("text", ""),
                        "ranks_confirmed": " ".join(map(str, t.get("confirmed", []))), "source": t.get("src")})
        for i, txt in enumerate(t["desc"], 1):
            ranks.append({"tree": tree["name"], "talent": t["name"], "rank": i, "text": txt,
                          "confirmed": i in t.get("confirmed", [])})
abilities = []
for k, v in d["spell_desc"].items():
    cls, spell, rank = k.split("|")
    if cls != "Warrior":
        continue
    cost = [x for pair in v.get("l", []) for x in pair if x]
    abilities.append({"spell": spell, "rank": rank, "learned": v.get("lv", ""), "cost_and_cooldown": "; ".join(cost),
                      "forever_text": v.get("d", ""), "classic_status": v.get("cs", ""),
                      "classic_text": v.get("cd", ""), "source": v.get("s", ""), "spell_id": v.get("id")})
for name, rows in [("warrior_talents", talents), ("warrior_talent_ranks", ranks), ("warrior_abilities", abilities)]:
    with open(f"{name}.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(name, len(rows))
print("data generated:", d["generated"])
