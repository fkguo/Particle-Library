#!/usr/bin/env python3
"""Fetch hadron-group headers from pdgLive into the notes sidecar.

PDG Live puts a group header (quantum-number line plus valence-quark content)
above each hadron summary table.  Those headers are not part of the official
snapshot.  They are stored in the generated ``pdg_notes`` asset:

    pdg_group_headers(node TEXT PRIMARY KEY, title TEXT NOT NULL,
                      content TEXT NOT NULL, source TEXT NOT NULL)

The title/content strings keep pdgLive's ``$...$`` math delimiters so the app's
existing DescriptionText renderer can typeset them.

Usage:
    python3 tool/fetch_pdg_group_headers.py \
        --notes assets/pdg_notes_2026.sqlite --delay 1.0
"""

from __future__ import annotations

import argparse
import sqlite3
import time
import urllib.error
import urllib.request

from bs4 import BeautifulSoup

GROUP_URL = "https://pdglive.lbl.gov/ParticleGroup.action?init=0&node="
UA = "ParticleLibrary/0.2 (offline PDG reader; group-header extraction)"

# The nodes are the hadron groups linked from pdgLive's Viewer.action page.
# Keys are the app's stable CatalogGroupKind names.
GROUPS: dict[str, str] = {
    "mesonLight": "MXXX005",
    "mesonStrange": "MXXX020",
    "mesonCharmed": "MXXX035",
    "mesonCharmedStrange": "MXXX040",
    "mesonBottom": "MXXX045",
    "mesonBottomStrange": "MXXX046",
    "mesonBottomCharmed": "MXXX049",
    "mesonCCbar": "MXXX025",
    "mesonBBbar": "MXXX030",
    "mesonOther": "MXXX050",
    "baryonN": "BXXX005",
    "baryonDelta": "BXXX010",
    "baryonLambda": "BXXX020",
    "baryonSigma": "BXXX025",
    "baryonXi": "BXXX030",
    "baryonOmega": "BXXX035",
    "baryonCharmed": "BXXX040",
    "baryonDoublyCharmed": "BXXX043",
    "baryonBottom": "BXXX045",
    "baryonExotic": "BXXX012",
}


def fetch(node: str, timeout: int = 30, retries: int = 3) -> str:
    last: Exception | None = None
    for attempt in range(retries):
        try:
            request = urllib.request.Request(
                GROUP_URL + node, headers={"User-Agent": UA}
            )
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


def parse_header(html: str) -> tuple[str, str]:
    soup = BeautifulSoup(html, "lxml")
    for table in soup.find_all("table"):
        heading = table.find("h4")
        if heading is None:
            continue
        title = " ".join(heading.get_text(" ", strip=True).split())
        rows = table.find_all("tr")
        content_parts: list[str] = []
        for row in rows[1:]:
            text = clean(str(row))
            if text:
                content_parts.append(text)
        return title, " ".join(content_parts)
    raise RuntimeError("no group header table")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--notes", default="assets/pdg_notes_2026.sqlite")
    parser.add_argument("--delay", type=float, default=1.0)
    args = parser.parse_args()

    rows: list[tuple[str, str, str, str]] = []
    for index, (kind, node) in enumerate(GROUPS.items(), 1):
        html = fetch(node)
        title, content = parse_header(html)
        source = GROUP_URL + node
        rows.append((node, title, content, source))
        print(f"[{index}/{len(GROUPS)}] {kind} / {node}: {title[:80]}")
        if index < len(GROUPS):
            time.sleep(max(0.0, args.delay))

    with sqlite3.connect(args.notes) as store:
        store.execute(
            "CREATE TABLE IF NOT EXISTS pdg_group_headers ("
            "node TEXT PRIMARY KEY, title TEXT NOT NULL, "
            "content TEXT NOT NULL, source TEXT NOT NULL)"
        )
        store.executemany(
            "INSERT OR REPLACE INTO pdg_group_headers"
            "(node, title, content, source) VALUES (?, ?, ?, ?)",
            rows,
        )
        total = store.execute("SELECT COUNT(*) FROM pdg_group_headers").fetchone()[0]
    print(f"stored {total} group headers in {args.notes}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
