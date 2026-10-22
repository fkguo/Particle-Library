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
import json
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


INSPIRE_API = "https://inspirehep.net/api/literature/"


def inspire_reference(recid: int, timeout: int = 30, retries: int = 3) -> dict:
    """Fetch the bibliographic record for a summary citation from INSPIRE."""
    url = (
        f"{INSPIRE_API}{recid}?fields=titles,authors.full_name,"
        "publication_info,dois,arxiv_eprints"
    )
    last: Exception | None = None
    for attempt in range(retries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                payload = json.loads(response.read().decode("utf-8", "replace"))
            metadata = payload.get("metadata", {})
            titles = metadata.get("titles") or []
            title = titles[0].get("title", "") if titles else ""
            authors = [
                author.get("full_name", "")
                for author in (metadata.get("authors") or [])
                if author.get("full_name")
            ]
            publication = ""
            year = None
            pub_info = metadata.get("publication_info") or []
            if pub_info:
                first = pub_info[0]
                year = first.get("year")
                journal = first.get("journal_title", "")
                volume = first.get("journal_volume", "")
                page = first.get("page_start", "") or first.get("artid", "")
                publication = " ".join(
                    part for part in (journal, volume, page) if part
                )
            dois = metadata.get("dois") or []
            doi = dois[0].get("value", "") if dois else ""
            eprints = metadata.get("arxiv_eprints") or []
            arxiv_id = eprints[0].get("value", "") if eprints else ""
            return {
                "title": title,
                "authors": ", ".join(authors[:20]),
                "year": year,
                "publication": publication,
                "doi": doi,
                "arxiv_id": arxiv_id,
            }
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
            last = error
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"INSPIRE {recid}: {last}")


def inspire_cite_key(recid: int, timeout: int = 30, retries: int = 3) -> str:
    """Fetch the INSPIRE BibTeX entry and return its cite key."""
    url = f"{INSPIRE_API}{recid}?format=bibtex"
    last: Exception | None = None
    for attempt in range(retries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                bibtex = response.read().decode("utf-8", "replace")
            match = re.match(r"^\s*@[A-Za-z]+\s*\{\s*([^,\s]+)\s*,", bibtex)
            return match.group(1) if match else ""
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last = error
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"INSPIRE bibtex {recid}: {last}")


def local_reference_ids(snapshot: str) -> set[str]:
    with sqlite3.connect(snapshot) as connection:
        return {
            row[0]
            for row in connection.execute("SELECT document_id FROM pdgreference")
        }


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

    # Citation labels that are not in the official reference table need their
    # bibliographic data in the patch so the app can show an in-app page.
    wanted: dict[str, int] = {}
    for note in notes.values():
        for label, recid in note.get("citations", {}).items():
            wanted[label] = recid
    references: dict[str, dict] = {}
    for index, (label, recid) in enumerate(sorted(wanted.items()), 1):
        try:
            references[label] = {
                    "inspire_recid": recid,
                    "cite_key": inspire_cite_key(recid),
                    **inspire_reference(recid),
                }
        except Exception as error:  # noqa: BLE001
            print(f"[ref {index}/{len(wanted)}] {label}: FAILED {error}", file=sys.stderr)
            continue
        print(f"[ref {index}/{len(wanted)}] {label}: {references[label]['title'][:60]}")
        time.sleep(args.delay)

    tmp = args.out + ".tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    with sqlite3.connect(tmp) as store:
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
            CREATE TABLE pdg_note_references (
              document_id TEXT NOT NULL PRIMARY KEY,
              inspire_recid INTEGER,
              title TEXT,
              authors TEXT,
              year INTEGER,
              publication TEXT,
              doi TEXT,
              arxiv_id TEXT,
              cite_key TEXT
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
            "INSERT INTO pdg_note_references(document_id, inspire_recid, title, "
            "authors, year, publication, doi, arxiv_id, cite_key) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (
                    label,
                    reference.get("inspire_recid"),
                    reference.get("title"),
                    reference.get("authors"),
                    reference.get("year"),
                    reference.get("publication"),
                    reference.get("doi"),
                    reference.get("arxiv_id"),
                    reference.get("cite_key"),
                )
                for label, reference in sorted(references.items())
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
    os.replace(tmp, args.out)
    with_was = sum(1 for note in notes.values() if "was" in note)
    with_summary = sum(1 for note in notes.values() if "summary" in note)
    print(
        f"\n{len(notes)} entries ({with_was} with 'was', {with_summary} with a "
        f"summary); fetched {fetched}, failed {failed}; wrote {args.out}"
    )
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
