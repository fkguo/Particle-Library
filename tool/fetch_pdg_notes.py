#!/usr/bin/env python3
"""Fetch pdgLive particle-page notes that are not in the PDG database.

pdgLive shows two pieces of prose that the downloadable SQLite database and
the REST API do not contain:

* a ``was <old name>`` line (renamed particles), and
* the short summary paragraph under the header.

Both live only in the pdgLive HTML.  This script walks every root identifier of
the bundled snapshot, extracts them and writes a small SQLite asset that the app
ships next to the official database:

    pdg_notes(pdgid TEXT PRIMARY KEY, was TEXT, summary TEXT)
    pdg_notes_info(key TEXT PRIMARY KEY, value TEXT)

The official snapshot is never modified, so its pinned SHA-256 stays valid.

Yearly procedure (after the PDG edition update, June/July):

    python3 tool/fetch_pdg_notes.py \
        --snapshot assets/pdgall-2027.0.sqlite \
        --out assets/pdg_notes_2027.sqlite --edition 2027
    # update lib/data/pdg_notes.dart to point at the new asset, rebuild

The script is resumable (rows already in --out are kept unless --force) and
prints a summary at the end.  Please keep the delay at >= 1 s; pdgLive is a
shared service.
"""

from __future__ import annotations

import argparse
import os
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from datetime import date

from bs4 import BeautifulSoup

BASE = "https://pdglive.lbl.gov/Particle.action?init=0&node="
UA = "ParticleLibrary/0.2 (offline PDG reader; one-time summary extraction)"


def fetch(node: str, timeout: int = 30, retries: int = 3) -> str:
    last: Exception | None = None
    for attempt in range(retries):
        try:
            request = urllib.request.Request(BASE + node, headers={"User-Agent": UA})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read().decode("utf-8", "replace")
        except (urllib.error.URLError, TimeoutError, OSError) as error:  # noqa: PERF203
            last = error
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"{node}: {last}")


def clean(fragment: str) -> str:
    soup = BeautifulSoup(fragment, "lxml")
    for br in soup.find_all("br"):
        br.replace_with("\n")
    return " ".join(soup.get_text(" ", strip=True).split())


def parse(html: str) -> dict[str, object]:
    note: dict[str, object] = {}
    was = re.search(r"<br>\s*was\s*(.*?)\s*<div class=\"minor_headerX\"", html, re.S)
    if was:
        value = clean(was.group(1))
        if value:
            note["was"] = value
    summary_div = BeautifulSoup(html, "lxml").find("div", id="minor_headerX")
    if summary_div is not None:
        citations: dict[str, int] = {}
        for anchor in summary_div.find_all("a", href=True):
            match = re.search(r"inspirehep\.net/literature/(\d+)", anchor["href"])
            label = " ".join(anchor.get_text(" ", strip=True).split())
            if label and match:
                citations[label] = int(match.group(1))
        for br in summary_div.find_all("br"):
            br.replace_with("\n")
        summary = " ".join(summary_div.get_text(" ", strip=True).split())
        if summary:
            note["summary"] = summary
        if citations:
            note["citations"] = citations
    return note


def roots(snapshot: str) -> list[str]:
    with sqlite3.connect(snapshot) as connection:
        rows = connection.execute(
            "SELECT pdgid FROM pdgid WHERE parent_id IS NULL ORDER BY pdgid"
        ).fetchall()
    return [row[0] for row in rows]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", default="assets/pdgall-2026.0.sqlite")
    parser.add_argument("--out", default="assets/pdg_notes_2026.sqlite")
    parser.add_argument("--edition", default="2026")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--delay", type=float, default=1.0)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    nodes = roots(args.snapshot)
    if args.limit:
        nodes = nodes[: args.limit]

    existing: dict[str, dict[str, str]] = {}
    if os.path.exists(args.out):
        with sqlite3.connect(args.out) as store:
            try:
                rows = store.execute("SELECT pdgid, was, summary FROM pdg_notes")
            except sqlite3.Error:
                rows = []
            for pdgid, was, summary in rows:
                existing[pdgid] = {
                    key: value
                    for key, value in (("was", was), ("summary", summary))
                    if value
                }
            try:
                for pdgid, label, recid in store.execute(
                    "SELECT pdgid, label, inspire_recid FROM pdg_note_citations"
                ):
                    existing.setdefault(pdgid, {}).setdefault(
                        "citations", {}
                    )[label] = recid
            except sqlite3.Error:
                pass

    notes = dict(existing)
    fetched = failed = 0
    for index, node in enumerate(nodes, 1):
        if node in notes and not args.force:
            continue
        try:
            note = parse(fetch(node))
        except Exception as error:  # noqa: BLE001 - keep the run going
            failed += 1
            print(f"[{index}/{len(nodes)}] {node}: FAILED {error}", file=sys.stderr)
            continue
        fetched += 1
        if note:
            notes[node] = note
        print(f"[{index}/{len(nodes)}] {node}: {', '.join(sorted(note)) or '-'}")
        if index < len(nodes):
            time.sleep(args.delay)

    if os.path.exists(args.out):
        os.remove(args.out)
    with sqlite3.connect(args.out) as store:
        store.executescript(
            """
            CREATE TABLE pdg_notes (
              pdgid TEXT NOT NULL PRIMARY KEY,
              was TEXT,
              summary TEXT
            );
            CREATE TABLE pdg_notes_info (
              key TEXT NOT NULL PRIMARY KEY,
              value TEXT NOT NULL
            );
            CREATE TABLE pdg_note_citations (
              pdgid TEXT NOT NULL,
              label TEXT NOT NULL,
              inspire_recid INTEGER,
              PRIMARY KEY (pdgid, label)
            );
            """
        )
        store.executemany(
            "INSERT INTO pdg_notes(pdgid, was, summary) VALUES (?, ?, ?)",
            [
                (pdgid, note.get("was"), note.get("summary"))
                for pdgid, note in sorted(notes.items())
            ],
        )
        store.executemany(
            "INSERT INTO pdg_note_citations(pdgid, label, inspire_recid) "
            "VALUES (?, ?, ?)",
            [
                (pdgid, label, recid)
                for pdgid, note in sorted(notes.items())
                for label, recid in sorted(note.get("citations", {}).items())
            ],
        )
        store.executemany(
            "INSERT INTO pdg_notes_info(key, value) VALUES (?, ?)",
            [
                ("edition", args.edition),
                ("generated", date.today().isoformat()),
                ("source", BASE + "<pdgid>"),
                ("count", str(len(notes))),
            ],
        )
    with_was = sum(1 for note in notes.values() if "was" in note)
    with_summary = sum(1 for note in notes.values() if "summary" in note)
    print(
        f"\n{len(notes)} entries ({with_was} with 'was', {with_summary} with a "
        f"summary); fetched {fetched}, failed {failed}; wrote {args.out}"
    )
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
