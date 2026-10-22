#!/usr/bin/env python3
"""Collect the review PDFs related to each particle node from pdgLive.

pdgLive's particle page lists the review articles that discuss that particle
(e.g. S010 -> Rare Kaon Decays, Charged Kaon Mass, Dalitz Plot Parameters).
The official database has no such mapping; this script stores it in the notes
sidecar as ``pdg_note_reviews(pdgid, file)`` so the app can open the related
reviews instead of the category's full list.

Usage:
    python3 tool/fetch_pdg_reviews.py --snapshot assets/pdgall-2026.0.sqlite \
        --out assets/pdg_notes_2026.sqlite [--delay 1.2] [--force]

The script is resumable: nodes already present in the table are skipped unless
--force is given.
"""

from __future__ import annotations

import argparse
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request

from bs4 import BeautifulSoup

BASE = "https://pdglive.lbl.gov/Particle.action?init=0&node="
UA = "ParticleLibrary/0.2 (offline PDG reader; related-review extraction)"

# Only the particle page's own review table has class="iframe"; the global
# Reviews drop-down uses class="dropdown-item iframe" and must be ignored.
REVIEW_LINK = re.compile(
    r'<a[^>]*class="iframe"[^>]*href="[^"]*?/reviews/'
    r'(rpp\d{4}-rev-[a-z0-9-]+\.pdf)"',
    re.I,
)


def fetch(node: str, timeout: int = 30, retries: int = 3) -> str:
    last: Exception | None = None
    for attempt in range(retries):
        try:
            request = urllib.request.Request(BASE + node, headers={"User-Agent": UA})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read().decode("utf-8", "replace")
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last = error
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"{node}: {last}")


def parse_reviews(html: str) -> list[str]:
    files = []
    for match in REVIEW_LINK.finditer(html):
        name = match.group(1)
        if name not in files:
            files.append(name)
    return files


def roots(snapshot: str) -> list[str]:
    with sqlite3.connect(snapshot) as connection:
        return [
            row[0]
            for row in connection.execute(
                "SELECT pdgid FROM pdgid WHERE parent_id IS NULL ORDER BY pdgid"
            )
        ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", default="assets/pdgall-2026.0.sqlite")
    parser.add_argument("--out", default="assets/pdg_notes_2026.sqlite")
    parser.add_argument("--delay", type=float, default=1.2)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    nodes = roots(args.snapshot)
    with sqlite3.connect(args.out) as store:
        store.execute(
            "CREATE TABLE IF NOT EXISTS pdg_note_reviews ("
            "pdgid TEXT NOT NULL, file TEXT NOT NULL,"
            "PRIMARY KEY (pdgid, file))"
        )
        # Remember every scanned node, including those with no related review,
        # so a rerun only retries missing nodes (or all with --force).
        store.execute("CREATE TABLE IF NOT EXISTS pdg_review_scan (pdgid TEXT PRIMARY KEY)")
        done = set()
        if not args.force:
            done = {row[0] for row in store.execute("SELECT pdgid FROM pdg_review_scan")}
            done |= {row[0] for row in store.execute("SELECT DISTINCT pdgid FROM pdg_note_reviews")}
        fetched = failed = 0
        for index, node in enumerate(nodes, 1):
            if node in done:
                continue
            try:
                files = parse_reviews(fetch(node))
            except Exception as error:  # noqa: BLE001
                failed += 1
                print(f"[{index}/{len(nodes)}] {node}: FAILED {error}", file=sys.stderr)
                continue
            fetched += 1
            store.execute("INSERT OR REPLACE INTO pdg_review_scan(pdgid) VALUES (?)", (node,))
            if files:
                store.executemany(
                    "INSERT OR REPLACE INTO pdg_note_reviews(pdgid, file) VALUES (?, ?)",
                    [(node, file) for file in files],
                )
            print(f"[{index}/{len(nodes)}] {node}: {len(files)} reviews")
            if index < len(nodes):
                time.sleep(args.delay)
        store.commit()
        total = store.execute("SELECT COUNT(*) FROM pdg_note_reviews").fetchone()[0]
    print(f"\n{total} review links after fetching {fetched} nodes (failed {failed})")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
