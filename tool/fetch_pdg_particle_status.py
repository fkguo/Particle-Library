#!/usr/bin/env python3
"""Fetch pdgLive's particle-status marks into the pdgLive sidecar.

pdgLive's group pages publish two different marks:

* baryon pages print a 1-4 star rating after each state: ``***`` etc.;
* meson pages print a bullet ``•`` for established entries (and no star
  count).

The official PDG SQLite snapshot has no status column.  This script stores the
published marks in the existing pdgLive sidecar (``pdg_notes_2026.sqlite``),
next to the notes and review links, so the app keeps one derived pdgLive asset:

    pdg_particle_status(pdgid TEXT PRIMARY KEY, stars INTEGER, established INTEGER)

``stars`` is 1-4 on baryon pages; ``established`` is 1 for a meson-page bullet.
The official snapshot is never modified.  The flow follows
``tool/fetch_pdg_reviews.py``: a resumable scan table, ``--force`` to refresh,
and one derived asset written next to the bundled databases.

Usage:
    python3 tool/fetch_pdg_particle_status.py \
        --snapshot assets/pdgall-2026.0.sqlite \
        --out assets/pdg_notes_2026.sqlite [--delay 1.2] [--force]

    # Development: only one group page
    python3 tool/fetch_pdg_particle_status.py --group-node BXXX005
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from bs4 import BeautifulSoup

HOME = "https://pdglive.lbl.gov/"
GROUP = "https://pdglive.lbl.gov/ParticleGroup.action?init=0&node="
UA = "ParticleLibrary/0.2 (offline PDG reader; particle-status patch)"
STAR = re.compile(r"^\*{1,4}$")
GROUP_LINK = re.compile(
    r"ParticleGroup\.action\?init=0(?:&amp;|&)node=([A-Za-z0-9]+)"
)
NODE = re.compile(r"node=([A-Za-z0-9.]+)")


def fetch(url: str, timeout: int = 30, retries: int = 3) -> str:
    last: Exception | None = None
    for attempt in range(retries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read().decode("utf-8", "replace")
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last = error
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"{url}: {last}")


def group_nodes(home_html: str) -> list[str]:
    return sorted(set(GROUP_LINK.findall(home_html)))


def parse_group(html: str) -> list[dict[str, object]]:
    """Rows from one ParticleGroup page.

    A row is the linked table in div.list-group-item1. Baryon pages use
    [name, J^P, stars]; meson pages use [bullet, name, I^G(J^PC), empty].
    """
    soup = BeautifulSoup(html, "lxml")
    rows: list[dict[str, object]] = []
    for item in soup.find_all("div", class_="list-group-item1"):
        anchor = item.find("a", href=True)
        if anchor is None:
            continue
        node = NODE.search(anchor["href"])
        if node is None:
            continue
        pdgid = node.group(1)
        cells = [
            " ".join(cell.get_text(" ", strip=True).split())
            for cell in item.find_all("td")
        ]
        stars = None
        established = False
        for cell in cells:
            if STAR.fullmatch(cell):
                stars = len(cell)
            elif cell == "•":
                established = True
        name = next((cell for cell in cells if r"\mathit" in cell), "")
        if not name:
            name = next(
                (
                    cell
                    for cell in cells
                    if cell
                    and cell != "•"
                    and not STAR.fullmatch(cell)
                    and not ("^" in cell and "$" in cell)
                ),
                "",
            )
        jp = next(
            (
                cell
                for cell in cells
                if cell != name and "$" in cell and "^" in cell
            ),
            "",
        )
        rows.append(
            {
                "pdgid": pdgid,
                "stars": stars,
                "established": established,
                "name": name,
                "jp": jp,
            }
        )
    return rows


def snapshot_roots(snapshot: str) -> dict[str, str]:
    with sqlite3.connect(snapshot) as connection:
        return {
            row[0]: (row[1] or "")
            for row in connection.execute(
                "SELECT pdgid, description FROM pdgid WHERE parent_id IS NULL"
            )
        }


def snapshot_sha256(snapshot: str) -> str:
    digest = hashlib.sha256()
    with open(snapshot, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def prepare(store: sqlite3.Connection) -> None:
    store.execute(
        "CREATE TABLE IF NOT EXISTS pdg_particle_status ("
        "pdgid TEXT PRIMARY KEY, "
        "stars INTEGER CHECK (stars BETWEEN 1 AND 4), "
        "established INTEGER NOT NULL DEFAULT 0 "
        "CHECK (established IN (0, 1)))"
    )
    # Every scanned row is remembered, including pages that publish no mark.
    # That makes reruns cheap and keeps the coverage auditable.
    store.execute(
        "CREATE TABLE IF NOT EXISTS pdg_particle_status_scan ("
        "pdgid TEXT PRIMARY KEY, "
        "group_node TEXT NOT NULL, "
        "name TEXT, "
        "jp TEXT, "
        "stars INTEGER, "
        "established INTEGER NOT NULL DEFAULT 0, "
        "source TEXT NOT NULL)"
    )
    store.execute(
        "CREATE TABLE IF NOT EXISTS pdg_particle_status_info ("
        "key TEXT PRIMARY KEY, value TEXT)"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", default="assets/pdgall-2026.0.sqlite")
    parser.add_argument("--out", default="assets/pdg_notes_2026.sqlite")
    parser.add_argument("--delay", type=float, default=1.2)
    parser.add_argument("--force", action="store_true")
    parser.add_argument(
        "--group-node",
        action="append",
        metavar="NODE",
        help="Only scan this group page (repeatable; default: discover from the home page)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and report without writing the sidecar",
    )
    args = parser.parse_args()

    if not Path(args.snapshot).is_file():
        print(f"snapshot not found: {args.snapshot}", file=sys.stderr)
        return 2

    if args.group_node:
        nodes = sorted(set(args.group_node))
    else:
        try:
            nodes = group_nodes(fetch(HOME))
        except Exception as error:  # noqa: BLE001
            print(f"could not discover group pages: {error}", file=sys.stderr)
            return 1
    if not nodes:
        print("no pdgLive group pages found", file=sys.stderr)
        return 1

    roots = snapshot_roots(args.snapshot)
    store = sqlite3.connect(args.out)
    try:
        prepare(store)
        if args.force:
            store.execute("DELETE FROM pdg_particle_status")
            store.execute("DELETE FROM pdg_particle_status_scan")
            store.commit()
        done = set()
        if not args.force:
            done = {
                row[0]
                for row in store.execute("SELECT pdgid FROM pdg_particle_status_scan")
            }

        fetched = failed = seen = star_rows = dot_rows = 0
        for index, group in enumerate(nodes, 1):
            try:
                rows = parse_group(fetch(GROUP + group))
            except Exception as error:  # noqa: BLE001
                failed += 1
                print(f"[{index}/{len(nodes)}] {group}: FAILED {error}", file=sys.stderr)
                continue
            fetched += 1
            new_rows = 0
            group_stars = 0
            group_dots = 0
            for row in rows:
                pdgid = str(row["pdgid"])
                if pdgid not in roots:
                    print(
                        f"[{index}/{len(nodes)}] {group}: {pdgid} is not a root "
                        "identifier in the snapshot; skipped",
                        file=sys.stderr,
                    )
                    continue
                if pdgid in done:
                    continue
                stars = row["stars"]
                established = 1 if row["established"] else 0
                if not args.dry_run:
                    store.execute(
                        "INSERT OR REPLACE INTO pdg_particle_status_scan"
                        "(pdgid, group_node, name, jp, stars, established, source) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?)",
                        (
                            pdgid,
                            group,
                            row["name"],
                            row["jp"],
                            stars,
                            established,
                            f"{GROUP}{group}",
                        ),
                    )
                    if stars is not None or established:
                        store.execute(
                            "INSERT OR REPLACE INTO pdg_particle_status"
                            "(pdgid, stars, established) VALUES (?, ?, ?)",
                            (pdgid, stars, established),
                        )
                done.add(pdgid)
                new_rows += 1
                seen += 1
                if stars is not None:
                    group_stars += 1
                    star_rows += 1
                if established:
                    group_dots += 1
                    dot_rows += 1
            if not args.dry_run:
                store.commit()
            print(
                f"[{index}/{len(nodes)}] {group}: {len(rows)} rows, "
                f"{new_rows} new, {group_stars} stars, {group_dots} dots"
            )
            if index < len(nodes):
                time.sleep(max(0.0, args.delay))

        if not args.dry_run:
            info = {
                "edition": "2026",
                "source": "https://pdglive.lbl.gov/ParticleGroup.action",
                "generator": "tool/fetch_pdg_particle_status.py",
                "generated_at": datetime.now(timezone.utc)
                .replace(microsecond=0)
                .isoformat()
                .replace("+00:00", "Z"),
                "snapshot_sha256": snapshot_sha256(args.snapshot),
                "coverage": (
                    "pdgLive baryon group pages publish 1-4 star ratings; "
                    "meson group pages mark established entries with a bullet"
                ),
            }
            store.executemany(
                "INSERT OR REPLACE INTO pdg_particle_status_info(key, value) "
                "VALUES (?, ?)",
                info.items(),
            )
            store.commit()
        total = store.execute(
            "SELECT COUNT(*) FROM pdg_particle_status"
        ).fetchone()[0]
        scanned = store.execute(
            "SELECT COUNT(*) FROM pdg_particle_status_scan"
        ).fetchone()[0]
    finally:
        store.close()

    print(
        f"\n{total} status rows ({star_rows} star, {dot_rows} dot) across "
        f"{scanned} scanned listings after fetching {fetched} groups "
        f"(failed {failed})"
    )
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
