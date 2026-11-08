#!/usr/bin/env python3
"""Builds the nhentai tag list the app uses for tag suggestions.

Reads every tag type from nhentai's API v2 (tags/<type>?page=N&per_page=100)
and writes a compact JSON file:

    {"version": 1, "updated": "<UTC time>",
     "types": ["parody", "character", ...],
     "tags": [[id, name, count, type_index], ...]}   # most used first

Only the standard library is used. Run by .github/workflows/nhentai-tags.yml.
"""
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

API = "https://nhentai.net/api/v2/"
TYPES = ["parody", "character", "tag", "artist", "group", "language", "category"]
USER_AGENT = "Boorusphere/tag-list (+https://github.com/Schw1/boorusphere-ios)"
DELAY = 1.5  # seconds between requests; nhentai rate-limits busy clients (429)
MIN_TAGS = 50_000  # a run with fewer tags is treated as broken


def get(path: str) -> dict:
    for attempt in range(8):
        req = urllib.request.Request(
            API + path,
            headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as res:
                return json.load(res)
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504):
                wait = min(60, 2 ** attempt)
                print(f"  HTTP {e.code} for {path}, retrying in {wait}s")
                time.sleep(wait)
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            wait = min(60, 2 ** attempt)
            print(f"  {e} for {path}, retrying in {wait}s")
            time.sleep(wait)
    raise RuntimeError(f"giving up on {path}")


def tags_of(type_name: str):
    page = 1
    while True:
        data = get(f"tags/{type_name}?page={page}&per_page=100")
        for tag in data.get("result", []):
            yield tag
        pages = int(data.get("num_pages") or 1)
        if page % 50 == 0 or page == pages:
            print(f"{type_name}: page {page}/{pages}")
        if page >= pages:
            return
        page += 1
        time.sleep(DELAY)


def main(out: str) -> None:
    rows = {}
    for index, type_name in enumerate(TYPES):
        for tag in tags_of(type_name):
            try:
                tag_id = int(tag["id"])
                name = str(tag["name"]).strip()
                count = int(tag.get("count") or 0)
            except (KeyError, TypeError, ValueError):
                continue
            if name:
                rows[tag_id] = [tag_id, name, count, index]
        time.sleep(DELAY)

    if len(rows) < MIN_TAGS:
        sys.exit(f"only {len(rows)} tags, expected at least {MIN_TAGS}; not writing")

    tags = sorted(rows.values(), key=lambda r: (-r[2], r[0]))
    result = {
        "version": 1,
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "types": TYPES,
        "tags": tags,
    }
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, separators=(",", ":"))
    print(f"wrote {len(tags)} tags to {out}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "nhentai-tags.json")
