#!/usr/bin/env python3
"""Derive explicit links from the pdgLive summary prose.

pdgLive summaries often say "See the review on ..." or "See also <particle>",
but the HTML has no anchors for those targets.  This offline pass reads the
already-fetched summaries and writes two patch tables into the same sidecar:

    pdg_note_reviews(pdgid, file)        review title mentioned by the summary
    pdg_note_see_also(pdgid, target, label)

The review file is matched against review_sources_2026.json.  The "See also"
particle is matched by a conservative LaTeX-to-name key against the root
descriptions and particle names in the official snapshot; only unique matches
are written.  Unmatched prose is left alone.

Usage:
    python3 tool/build_pdg_note_links.py \
        --notes assets/pdg_notes_2026.sqlite \
        --snapshot assets/pdgall-2026.0.sqlite \
        --reviews assets/review_sources_2026.json [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys

# LaTeX command -> plain name used by the PDG snapshot descriptions.
GREEK = {
    "alpha": "alpha",
    "beta": "beta",
    "gamma": "gamma",
    "delta": "delta",
    "epsilon": "epsilon",
    "zeta": "zeta",
    "eta": "eta",
    "theta": "theta",
    "iota": "iota",
    "kappa": "kappa",
    "lambda": "lambda",
    "mu": "mu",
    "nu": "nu",
    "xi": "xi",
    "pi": "pi",
    "rho": "rho",
    "sigma": "sigma",
    "tau": "tau",
    "upsilon": "upsilon",
    "phi": "phi",
    "chi": "chi",
    "psi": "psi",
    "omega": "omega",
    "Delta": "Delta",
    "Lambda": "Lambda",
    "Sigma": "Sigma",
    "Xi": "Xi",
    "Omega": "Omega",
    "Upsilon": "Upsilon",
    "Phi": "Phi",
    "Chi": "Chi",
    "Psi": "Psi",
}

SEE_ALSO = re.compile(r"(?i)see also\s+(?:the\s+)?(.+?)(?:\.\s|\.$|$)")
MATH = re.compile(r"\$(.+?)\$")
CITATION = re.compile(r"\b[A-Z][A-Z0-9&.\-]{2,}\s+\d{4}[A-Z]?\b")
TITLE_QUOTES = str.maketrans({"\u201c": '"', "\u201d": '"', "\u2018": "'", "\u2019": "'"})


def key(value: str) -> str:
    """A conservative comparison key for a particle name or review title."""
    text = value.translate(TITLE_QUOTES).lower()
    text = re.sub(r"\\(?:mathit|mathrm|text|mathcal|mathsf)\s*", "", text)
    text = text.replace("\\,", "").replace("\\!", "").replace("\\;", "")
    text = text.replace("{", "").replace("}", "").replace("$", "")
    text = re.sub(
        r"\\([A-Za-z]+)",
        lambda match: GREEK.get(match.group(1), match.group(1)),
        text,
    )
    text = text.replace("\\", "")
    text = text.replace("^", "").replace("_", "").replace("()", "")
    text = re.sub(r"[\s`\"']+", "", text)
    return text


def snapshot_names(snapshot: str) -> dict[str, tuple[str, str]]:
    """key(name) -> (root pdgid, display label), only for unique matches."""
    with sqlite3.connect(snapshot) as connection:
        roots = {
            row[0]: (row[1] or "")
            for row in connection.execute(
                "SELECT pdgid, description FROM pdgid WHERE parent_id IS NULL"
            )
        }
        candidates: dict[str, set[str]] = {}
        for pdgid, description in roots.items():
            candidates.setdefault(key(description), set()).add(pdgid)
        for pdgid, name in connection.execute(
            "SELECT pdgid, name FROM pdgparticle"
        ):
            if pdgid in roots:
                candidates.setdefault(key(name), set()).add(pdgid)
    return {
        name_key: (next(iter(ids)), roots[next(iter(ids))])
        for name_key, ids in candidates.items()
        if len(ids) == 1
    }


def review_titles(path: str) -> list[tuple[str, str]]:
    payload = json.load(open(path, encoding="utf-8"))
    titles: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for source in payload.get("sources", []):
        file = source.get("file")
        if not file:
            continue
        for title in {source.get("title") or "", source.get("full_title") or ""}:
            # The source JSON also contains front matter and one-word section
            # headings ("7", "Overview", "Top quark"). Matching those against a
            # long summary would create false review links; keep only titles
            # substantial enough to be an article title.
            title_key = key(title)
            if (
                len(title_key) < 12
                or len(title.split()) < 2
                or not any(char.isalpha() for char in title)
                or (title_key, file) in seen
            ):
                continue
            seen.add((title_key, file))
            titles.append((title, file))
    return titles


def see_also_fragments(summary: str) -> list[str]:
    fragments: list[str] = []
    for match in SEE_ALSO.finditer(summary):
        clause = match.group(1).strip()
        for part in re.split(r",\s*|\s+and\s+", clause):
            part = part.strip().strip(" .,;:")
            part = re.sub(r"(?i)^the\s+", "", part)
            if not part or CITATION.search(part):
                continue
            fragments.append(part)
    return fragments


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--notes", default="assets/pdg_notes_2026.sqlite")
    parser.add_argument("--snapshot", default="assets/pdgall-2026.0.sqlite")
    parser.add_argument(
        "--reviews", default="assets/review_sources_2026.json"
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    names = snapshot_names(args.snapshot)
    titles = review_titles(args.reviews)
    title_keys = [(key(title), file, title) for title, file in titles if key(title)]
    store = sqlite3.connect(args.notes)
    try:
        store.execute(
            "CREATE TABLE IF NOT EXISTS pdg_note_reviews ("
            "pdgid TEXT NOT NULL, file TEXT NOT NULL,"
            "PRIMARY KEY (pdgid, file))"
        )
        store.execute(
            "CREATE TABLE IF NOT EXISTS pdg_note_see_also ("
            "pdgid TEXT NOT NULL, target_pdgid TEXT NOT NULL, "
            "label TEXT NOT NULL, PRIMARY KEY (pdgid, target_pdgid))"
        )
        rows = list(
            store.execute("SELECT pdgid, summary FROM pdg_notes WHERE summary IS NOT NULL")
        )
        review_hits = see_also_hits = 0
        for pdgid, summary in rows:
            summary = summary or ""
            summary_key = key(summary)
            matched_reviews = []
            for title_key, file, title in title_keys:
                if title_key and title_key in summary_key:
                    matched_reviews.append((file, title))
            see_also = []
            for fragment in see_also_fragments(summary):
                match = MATH.search(fragment)
                candidate = match.group(1) if match else fragment
                if "\\overline" in candidate:
                    continue
                hit = names.get(key(candidate))
                if hit is not None:
                    target, label = hit
                    if target != pdgid:
                        see_also.append((target, label))
            if not args.dry_run:
                for file, _title in matched_reviews:
                    store.execute(
                        "INSERT OR REPLACE INTO pdg_note_reviews(pdgid, file) "
                        "VALUES (?, ?)",
                        (pdgid, file),
                    )
                for target, label in see_also:
                    store.execute(
                        "INSERT OR REPLACE INTO pdg_note_see_also"
                        "(pdgid, target_pdgid, label) VALUES (?, ?, ?)",
                        (pdgid, target, label),
                    )
            review_hits += len(matched_reviews)
            see_also_hits += len(see_also)
        if not args.dry_run:
            store.commit()
    finally:
        store.close()

    print(
        f"{review_hits} summary review links, {see_also_hits} see-also links"
        + (" (dry run; no file written)" if args.dry_run else "")
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
