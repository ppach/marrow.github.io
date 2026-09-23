"""Find combat logs posted to magey/forever-warrior discussions that are not in logs/metadata.yaml yet.

For each new log: download it to logs/incoming/, print the post text (for the metadata), and
print what the log itself says (build, warriors present, their GUIDs and levels).
Run from eternal/data:  python fetch_logs.py            (list + download new logs)
                        python fetch_logs.py --list     (list only, no download)
Uses the GitHub API through gh (one call for all posts, with the raw post markdown) when gh is
logged in, and falls back to scraping the public discussion pages otherwise.
"""
import html
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
from collections import Counter

import yaml

from parse_log import split

REPO = "https://github.com/magey/forever-warrior"
INCOMING = os.path.join("logs", "incoming")
# Spells only a warrior casts, to tell warriors apart from the other players in the log
WARRIOR_SPELLS = {"Heroic Strike", "Charge", "Bloodrage", "Battle Shout", "Rend", "Sunder Armor",
                  "Overpower", "Hamstring", "Execute", "Bloodthirst", "Whirlwind", "Mortal Strike",
                  "Cleave", "Thunder Clap", "Revenge", "Shield Block", "Victory Rush"}


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "marrow-compendium-log-fetcher"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", errors="replace")


GH = shutil.which("gh") or r"C:\Program Files\GitHub CLI\gh.exe"
QUERY = """query($cursor: String) {
  repository(owner: "magey", name: "forever-warrior") {
    discussions(first: 50, after: $cursor, orderBy: {field: CREATED_AT, direction: ASC}) {
      pageInfo { hasNextPage endCursor }
      nodes { number title body category { name } }
    }
  }
}"""


def gh_posts():
    """All Logs discussions via the GitHub API: {number: (title, body markdown, attachment URLs)}.
    Returns None when gh is missing or not logged in, so the caller can fall back to the web pages."""
    if not os.path.exists(GH):
        return None
    out, cursor = {}, None
    while True:
        args = [GH, "api", "graphql", "-f", f"query={QUERY}"] + (["-f", f"cursor={cursor}"] if cursor else [])
        r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8")
        if r.returncode != 0:
            print(f"(gh unavailable, using web pages: {r.stderr.strip()[:120]})")
            return None
        d = json.loads(r.stdout)["data"]["repository"]["discussions"]
        for n in d["nodes"]:
            if n["category"]["name"] == "Logs":
                files = sorted(set(re.findall(r"https://github\.com/user-attachments/files/\d+/[^\s)\"']+\.txt", n["body"])))
                out[n["number"]] = (n["title"], n["body"].strip(), files)
        if not d["pageInfo"]["hasNextPage"]:
            return out
        cursor = d["pageInfo"]["endCursor"]


def discussions():
    page = get(f"{REPO}/discussions?discussions_q=category%3ALogs")
    return sorted({int(n) for n in re.findall(r"/magey/forever-warrior/discussions/(\d+)", page)})


def post(number):
    page = get(f"{REPO}/discussions/{number}")
    title = re.search(r"<title>(.*?)</title>", page, re.S)
    title = html.unescape(title.group(1)).split(" · ")[0].strip() if title else ""
    body = re.search(r'class="[^"]*js-comment-body[^"]*"[^>]*>(.*?)</td>', page, re.S)
    text = ""
    if body:
        text = re.sub(r"<br\s*/?>|</p>|</li>|</pre>", "\n", body.group(1))
        text = html.unescape(re.sub(r"<[^>]+>", "", text))
        text = re.sub(r"\n{3,}", "\n\n", text).strip()
    files = sorted(set(re.findall(r"https://github\.com/user-attachments/files/\d+/[^\"'<>\s]+\.txt", page)))
    return title, text, files


def describe(path):
    """What the log itself says: header, and every warrior with GUID, level and event count."""
    header, found = "", Counter()
    levels = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "  " not in line:
                continue
            if "COMBAT_LOG_VERSION" in line:
                header = line.split("  ", 1)[1].strip()
            if "SPELL_CAST_SUCCESS,Player-" not in line:
                continue
            try:
                _, f = split(line)
            except Exception:
                continue
            if f[10] in WARRIOR_SPELLS:
                found[(f[1], f[2])] += 1
                levels.setdefault(f[1], Counter())[f[30]] += 1
    return header, [(g, n, c, dict(levels[g])) for (g, n), c in found.most_common()]


def main():
    known = yaml.safe_load(open(os.path.join("logs", "metadata.yaml"))) or []
    known_sources = {m.get("source") for m in known}
    known_attachments = {m.get("attachment") for m in known}
    list_only = "--list" in sys.argv
    os.makedirs(INCOMING, exist_ok=True)

    posts = gh_posts()
    for n in (sorted(posts) if posts is not None else discussions()):
        url = f"{REPO}/discussions/{n}"
        title, text, files = posts[n] if posts is not None else post(n)
        new = [f for f in files if f not in known_attachments]
        if not files:
            continue
        status = "NEW" if url not in known_sources and new else ("partly new" if new else "known")
        print(f"\n#{n} [{status}] {title}\n  {url}")
        for f in files:
            print(f"  attachment: {f}{'' if f in new else '  (already in metadata)'}")
        if not new:
            continue
        print("  --- post text ---")
        print("  " + text.replace("\n", "\n  "))
        if list_only:
            continue
        for f in new:
            dest = os.path.join(INCOMING, f"d{n}_" + f.rsplit("/", 1)[1])
            if not os.path.exists(dest):
                urllib.request.urlretrieve(f, dest)
            header, warriors = describe(dest)
            print(f"  downloaded: {dest} ({os.path.getsize(dest) / 1e6:.1f} MB)")
            print(f"  header: {header}")
            for guid, name, count, lv in warriors:
                print(f"  warrior: {name}  guid={guid}  casts={count}  levels={lv}")


if __name__ == "__main__":
    main()
