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


def validate_group_page(html: str, group: str) -> None:
    """Reject an error page served with HTTP 200 before it can erase a group."""
    soup = BeautifulSoup(html, "lxml")
    text = " ".join(soup.get_text(" ", strip=True).split())
    if "does not exist" in text or "404 -" in text:
        raise ValueError("pdgLive returned a 404 page")
    if f"home={group}" not in html and f"node={group}" not in html:
        raise ValueError(f"page does not identify group {group}")
    if (
        soup.find("div", class_="list-group-item1") is None
        and "pdgLive Home >" not in text
    ):
        raise ValueError("unrecognized pdgLive group page")


def filter_eligible(
    rows: list[dict[str, object]], roots: dict[str, str]
) -> list[dict[str, object]]:
    """Keep only rows whose pdgid is a root identifier in the snapshot."""
    return [row for row in rows if str(row["pdgid"]) in roots]


def replacement_allowed(
    previous: int,
    eligible: list[dict[str, object]],
    allow_empty: bool,
    force: bool,
) -> bool:
    """A previously populated group may only become empty with an override."""
    return previous == 0 or bool(eligible) or (allow_empty and force)


def move_conflicts(
    store: sqlite3.Connection, conflicts: list[tuple[str, str]]
) -> None:
    """Remove a conflicting row from its old group before reassigning it."""
    for pdgid, old_group in conflicts:
        store.execute(
            "DELETE FROM pdg_particle_status_scan "
            "WHERE pdgid = ? AND group_node = ?",
            (pdgid, old_group),
        )


def scan_conflicts(
    store: sqlite3.Connection, pdgids: list[str], group: str
) -> list[tuple[str, str]]:
    """Rows already attributed to a different group page."""
    if not pdgids:
        return []
    placeholders = ",".join("?" for _ in pdgids)
    return store.execute(
        f"SELECT pdgid, group_node FROM pdg_particle_status_scan "
        f"WHERE pdgid IN ({placeholders}) AND group_node != ?",
        [*pdgids, group],
    ).fetchall()


def rebuild_status(store: sqlite3.Connection) -> None:
    """Recompute the derived status table from the auditable scan table."""
    store.execute("DELETE FROM pdg_particle_status")
    store.execute(
        "INSERT INTO pdg_particle_status(pdgid, stars, established) "
        "SELECT pdgid, MAX(stars), MAX(established) "
        "FROM pdg_particle_status_scan "
        "WHERE stars IS NOT NULL OR established = 1 "
        "GROUP BY pdgid"
    )


def _has_scan_table(store: sqlite3.Connection) -> bool:
    return (
        store.execute(
            "SELECT 1 FROM sqlite_master "
            "WHERE type='table' AND name='pdg_particle_status_scan'"
        ).fetchone()
        is not None
    )


def _scanned_ids(store: sqlite3.Connection) -> set[str]:
    if not _has_scan_table(store):
        return set()
    return {
        row[0] for row in store.execute("SELECT pdgid FROM pdg_particle_status_scan")
    }


def group_scan_count(store: sqlite3.Connection, group: str) -> int:
    if not _has_scan_table(store):
        return 0
    return store.execute(
        "SELECT COUNT(*) FROM pdg_particle_status_scan WHERE group_node = ?",
        (group,),
    ).fetchone()[0]


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
    parser.add_argument(
        "--allow-empty",
        action="store_true",
        help=(
            "With --force, allow a previously populated group to become empty "
            "after you have verified that the removals are legitimate"
        ),
    )
    parser.add_argument(
        "--allow-move",
        action="store_true",
        help=(
            "With --force, move a pdgid that now appears in this group from its "
            "previous group instead of refusing the collision"
        ),
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
    out_path = Path(args.out)
    if args.dry_run:
        # A dry run must be strictly read-only: open the existing sidecar
        # read-only, or use an in-memory schema when it does not exist yet.
        if out_path.exists():
            store = sqlite3.connect(f"file:{out_path}?mode=ro", uri=True)
        else:
            store = sqlite3.connect(":memory:")
            prepare(store)
    else:
        store = sqlite3.connect(out_path)
        prepare(store)

    try:
        done = set() if args.force else _scanned_ids(store)
        fetched = failed = seen = star_rows = dot_rows = 0

        for index, group in enumerate(nodes, 1):
            try:
                html = fetch(GROUP + group)
                validate_group_page(html, group)
                rows = parse_group(html)
            except Exception as error:  # noqa: BLE001
                # Leave this group's previous scan rows (if any) untouched.
                failed += 1
                print(f"[{index}/{len(nodes)}] {group}: FAILED {error}", file=sys.stderr)
                continue

            eligible = filter_eligible(rows, roots)
            previous = group_scan_count(store, group)
            if not replacement_allowed(
                previous, eligible, args.allow_empty, args.force
            ):
                failed += 1
                print(
                    f"[{index}/{len(nodes)}] {group}: parsed no eligible rows "
                    f"but {previous} existing rows; use --force --allow-empty "
                    "after verifying the removals",
                    file=sys.stderr,
                )
                continue

            conflicts = scan_conflicts(
                store, [str(row["pdgid"]) for row in eligible], group
            )
            if conflicts and not (args.allow_move and args.force):
                failed += 1
                print(
                    f"[{index}/{len(nodes)}] {group}: COLLISION {conflicts}; "
                    "use --force --allow-move after checking the reassignment",
                    file=sys.stderr,
                )
                continue

            fetched += 1
            group_stars = sum(
                1 for row in eligible if row["stars"] is not None
            )
            group_dots = sum(1 for row in eligible if row["established"])

            if args.dry_run:
                group_seen = 0
                for row in eligible:
                    group_seen += 1
                    if row["stars"] is not None:
                        star_rows += 1
                    if row["established"]:
                        dot_rows += 1
                seen += group_seen
                suffix = (
                    f", {len(conflicts)} movable" if conflicts else ""
                )
                print(
                    f"[{index}/{len(nodes)}] {group}: {len(rows)} rows, "
                    f"{group_seen} eligible, {group_stars} stars, "
                    f"{group_dots} dots{suffix}"
                )
                if index < len(nodes):
                    time.sleep(max(0.0, args.delay))
                continue

            to_insert: list[tuple[object, ...]] = []
            for row in eligible:
                pdgid = str(row["pdgid"])
                if not args.force and pdgid in done:
                    continue
                to_insert.append(
                    (
                        pdgid,
                        group,
                        row["name"],
                        row["jp"],
                        row["stars"],
                        1 if row["established"] else 0,
                        f"{GROUP}{group}",
                    )
                )

            try:
                # Replace only this successfully fetched group. A later
                # network failure cannot delete another group's rows, and a
                # forced single-group refresh keeps the rest of the patch.
                # Rebuild the derived table in the same transaction so an
                # interruption cannot leave scan and status out of sync.
                with store:
                    if args.force:
                        store.execute(
                            "DELETE FROM pdg_particle_status_scan "
                            "WHERE group_node = ?",
                            (group,),
                        )
                    if conflicts:
                        move_conflicts(store, conflicts)
                    store.executemany(
                        "INSERT OR REPLACE INTO pdg_particle_status_scan"
                        "(pdgid, group_node, name, jp, stars, established, source) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?)",
                        to_insert,
                    )
                    rebuild_status(store)
            except sqlite3.Error as error:
                failed += 1
                print(
                    f"[{index}/{len(nodes)}] {group}: WRITE FAILED {error}",
                    file=sys.stderr,
                )
                continue

            for row in to_insert:
                done.add(str(row[0]))
            seen += len(to_insert)
            star_rows += group_stars
            dot_rows += group_dots
            print(
                f"[{index}/{len(nodes)}] {group}: {len(rows)} rows, "
                f"{len(to_insert)} new, {group_stars} stars, {group_dots} dots"
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
            with store:
                store.executemany(
                    "INSERT OR REPLACE INTO pdg_particle_status_info(key, value) "
                    "VALUES (?, ?)",
                    info.items(),
                )
            total = store.execute(
                "SELECT COUNT(*) FROM pdg_particle_status"
            ).fetchone()[0]
            total_stars = store.execute(
                "SELECT COUNT(*) FROM pdg_particle_status WHERE stars IS NOT NULL"
            ).fetchone()[0]
            total_dots = store.execute(
                "SELECT COUNT(*) FROM pdg_particle_status WHERE established = 1"
            ).fetchone()[0]
            scanned = store.execute(
                "SELECT COUNT(*) FROM pdg_particle_status_scan"
            ).fetchone()[0]
        else:
            total = 0
            total_stars = 0
            total_dots = 0
            scanned = 0
    finally:
        store.close()

    if args.dry_run:
        print(
            f"\nDRY RUN: {star_rows} stars and {dot_rows} dots across "
            f"{seen} valid listings; no file was written"
        )
    else:
        print(
            f"\n{total} status rows ({total_stars} star, {total_dots} dot) across "
            f"{scanned} scanned listings after fetching {fetched} groups "
            f"(failed {failed})"
        )
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
