#!/usr/bin/env python3
r"""Fetch pdgLive decay-table columns into the notes sidecar.

PDG Live adds three columns that the downloadable snapshot does not carry:
the scale factor / confidence level, the decay momentum P(MeV/c), and the
table note (e.g. "the following branching fractions are our estimates").
This script walks every parent page that has pdgdecay rows and stores them in:

    pdg_decay_details(decay_pdgid TEXT PRIMARY KEY, parent_pdgid TEXT,
                      p_text TEXT, scale_cl TEXT, source TEXT)
    pdg_decay_notes(parent_pdgid TEXT PRIMARY KEY, note TEXT,
                    source TEXT)

Usage:
    python3 tool/fetch_pdg_decay_details.py \
        --snapshot assets/pdgall-2026.0.sqlite \
        --notes assets/pdg_notes_2026.sqlite --delay 0.2
"""

from __future__ import annotations

import argparse
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import parse_qs, urlparse

from bs4 import BeautifulSoup

BASE = "https://pdglive.lbl.gov/Particle.action?init=0&node="
UA = "ParticleLibrary/0.2 (offline PDG reader; decay-table extraction)"


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


def clean(fragment: str) -> str:
    soup = BeautifulSoup(fragment, "lxml")
    for br in soup.find_all("br"):
        br.replace_with("\n")
    return " ".join(soup.get_text(" ", strip=True).split())


def parents(snapshot: str) -> list[str]:
    with sqlite3.connect(snapshot) as db:
        rows = db.execute(
            """
            SELECT DISTINCT p.pdgid
              FROM pdgdecay d
              JOIN pdgid e ON e.id = d.pdgid_id
              JOIN pdgid p ON p.id = e.parent_id
             WHERE e.data_type LIKE 'BF%'
               AND p.parent_id IS NULL
             ORDER BY p.pdgid
            """
        ).fetchall()
    return [row[0] for row in rows]


def parse(html: str, parent: str) -> tuple[list[tuple[str, str, str, str]], str]:
    soup = BeautifulSoup(html, "lxml")
    table = None
    for candidate in soup.find_all("table"):
        text = " ".join(candidate.get_text(" ", strip=True).split())
        if "P(MeV/c)" in text and "DECAY MODES" not in text and "dectd1" in str(candidate):
            table = candidate
            break
    if table is None:
        return [], ""

    page_text = " ".join(soup.get_text(" ", strip=True).split())
    note = ""
    note_match = re.search(
        r"The following branching fractions[^.]*\.", page_text, re.I
    )
    if note_match:
        note = note_match.group(0).strip()

    rows: list[tuple[str, str, str, str]] = []
    for tr in table.find_all("tr"):
        cell = tr.find("td", class_="dectd1")
        if cell is None:
            continue
        anchor = cell.find("a", href=True)
        if anchor is None or "BranchingRatio.action" not in anchor["href"]:
            continue
        query = parse_qs(urlparse(anchor["href"]).query)
        desig = (query.get("desig") or [""])[0]
        if not desig:
            continue
        decay_pdgid = f"{parent}.{desig}"

        def value_of(class_name: str) -> str:
            node = cell.find("td", class_=class_name)
            return clean(str(node)) if node is not None else ""

        p_text = value_of("momt")
        scale_cl = value_of("scale")
        rows.append((decay_pdgid, parent, p_text, scale_cl))
    return rows, note


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", default="assets/pdgall-2026.0.sqlite")
    parser.add_argument("--notes", default="assets/pdg_notes_2026.sqlite")
    parser.add_argument("--delay", type=float, default=0.2)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    nodes = parents(args.snapshot)
    if args.limit:
        nodes = nodes[: args.limit]

    with sqlite3.connect(args.notes) as store:
        store.execute(
            "CREATE TABLE IF NOT EXISTS pdg_decay_details ("
            "decay_pdgid TEXT PRIMARY KEY, parent_pdgid TEXT NOT NULL, "
            "p_text TEXT NOT NULL, scale_cl TEXT NOT NULL, source TEXT NOT NULL)"
        )
        store.execute(
            "CREATE TABLE IF NOT EXISTS pdg_decay_notes ("
            "parent_pdgid TEXT PRIMARY KEY, note TEXT NOT NULL, "
            "source TEXT NOT NULL)"
        )
        done: set[str] = set()
        if not args.force:
            done = {
                row[0]
                for row in store.execute(
                    "SELECT DISTINCT parent_pdgid FROM pdg_decay_details"
                )
            }

    fetched = failed = 0
    store = sqlite3.connect(args.notes)
    try:
        for index, parent in enumerate(nodes, 1):
            if parent in done:
                continue
            source = BASE + parent
            try:
                rows, note = parse(fetch(parent), parent)
            except Exception as error:  # noqa: BLE001 - keep the run going
                failed += 1
                print(
                    f"[{index}/{len(nodes)}] {parent}: FAILED {error}",
                    file=sys.stderr,
                    flush=True,
                )
                continue
            fetched += 1
            for decay_pdgid, parent_pdgid, p_text, scale_cl in rows:
                store.execute(
                    "INSERT OR REPLACE INTO pdg_decay_details"
                    "(decay_pdgid, parent_pdgid, p_text, scale_cl, source) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (decay_pdgid, parent_pdgid, p_text, scale_cl, source),
                )
            store.execute(
                "INSERT OR REPLACE INTO pdg_decay_notes(parent_pdgid, note, source) "
                "VALUES (?, ?, ?)",
                (parent, note, source),
            )
            store.commit()
            print(
                f"[{index}/{len(nodes)}] {parent}: {len(rows)} decay rows",
                flush=True,
            )
            if index < len(nodes):
                time.sleep(max(0.0, args.delay))
    finally:
        store.close()

    print(f"fetched {fetched} parents, {failed} failed", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
