#!/usr/bin/env python3
"""Derive explicit links from the pdgLive summary prose.

pdgLive summaries often say "See the review on ..." or "See also <particle>",
but the HTML has no anchors for those targets.  This offline pass reads the
already-fetched summaries and writes two patch tables into the same sidecar:

    pdg_note_reviews(pdgid, file)                  review title in the summary
    pdg_note_see_also(pdgid, target, label, math)  See-also particle; ``math``
                                                   is the raw LaTeX fragment

The review file is matched against review_sources_2026.json.  A title only
counts when the summary contains the word "review" next to it, so historical
phrases such as "Before our 2012 Review" do not create a 2026 review link.
A small alias table covers pdgLive shorthands ("non-q qbar states",
"Quark and Lepton Compositeness") that do not repeat the article title.

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
TITLE_QUOTES = str.maketrans(
    {"\u201c": '"', "\u201d": '"', "\u2018": "'", "\u2019": "'"}
)

# pdgLive shorthands for reviews whose article title is longer/different.
REVIEW_ALIASES: dict[str, str] = {
    "nonqqbarstates": "rpp2026-rev-non-qqbar-mesons.pdf",
    "quarkandleptoncompositeness": "rpp2026-rev-searches-quark-lep-compositeness.pdf",
    "neutrinomassmixingoscillations": "rpp2026-rev-neutrino-mixing.pdf",
    "neutrinomassesmixingoscillations": "rpp2026-rev-neutrino-mixing.pdf",
    "neutrinomassmixingandoscillations": "rpp2026-rev-neutrino-mixing.pdf",
    "neutrinomassesmixingandoscillations": "rpp2026-rev-neutrino-mixing.pdf",
}

# Historical pdgLive names that no longer equal a 2026 root description.
SEE_ALSO_ALIASES: dict[str, str] = {
    "pc4380": "B171",
    "pc4450": "B172",
}

GENERIC_TITLES = {
    "overview",
    "highlights",
    "contents",
    "introduction",
    "list of reviews",
}


def key(value: str) -> str:
    """A comparison key for a particle name or review title."""
    text = value.translate(TITLE_QUOTES).lower()
    text = re.sub(r"\\overline\{\\mathit\s+([A-Za-z])\}", r"\1bar", text)
    text = re.sub(r"\\overline\{([^{}]+)\}", r"\1bar", text)
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


def loose_key(value: str) -> str:
    """Remove punctuation as well, so ``chi_c(0,1,2)`` meets ``chi_c0,1,2``."""
    return re.sub(r"[^a-z0-9]+", "", key(value))


def snapshot_names(snapshot: str) -> tuple[dict[str, tuple[str, str]], dict[str, str]]:
    """loose name -> (root pdgid, label), plus root descriptions by pdgid."""
    with sqlite3.connect(snapshot) as connection:
        roots = {
            row[0]: (row[1] or "")
            for row in connection.execute(
                "SELECT pdgid, description FROM pdgid WHERE parent_id IS NULL"
            )
        }
        candidates: dict[str, set[str]] = {}
        for pdgid, description in roots.items():
            candidates.setdefault(loose_key(description), set()).add(pdgid)
        for pdgid, name in connection.execute("SELECT pdgid, name FROM pdgparticle"):
            if pdgid in roots:
                candidates.setdefault(loose_key(name), set()).add(pdgid)
    names = {
        name_key: (next(iter(ids)), roots[next(iter(ids))])
        for name_key, ids in candidates.items()
        if len(ids) == 1
    }
    return names, roots


def review_titles(path: str) -> list[tuple[str, str, str]]:
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)
    titles: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str]] = set()
    for source in payload.get("sources", []):
        file = source.get("file")
        if not file:
            continue
        for title in {source.get("title") or "", source.get("full_title") or ""}:
            title_key = loose_key(title)
            if (
                len(title_key) < 6
                or len(title.split()) < 2
                or not any(char.isalpha() for char in title)
                or title_key in GENERIC_TITLES
                or (title_key, file) in seen
            ):
                continue
            seen.add((title_key, file))
            titles.append((title_key, file, title))
    return titles


def review_links(
    summary: str, titles: list[tuple[str, str, str]]
) -> list[tuple[str, str]]:
    summary_key = loose_key(summary)
    found: dict[str, str] = {}

    def near_review(position: int, length: int) -> bool:
        window = summary_key[max(0, position - 160) : position + length + 80]
        return "review" in window

    for title_key, file, title in titles:
        position = summary_key.find(title_key)
        if position >= 0 and near_review(position, len(title_key)):
            found[file] = title
    for alias, file in REVIEW_ALIASES.items():
        position = summary_key.find(alias)
        if position >= 0 and near_review(position, len(alias)):
            found[file] = alias
    return list(found.items())


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


def see_also_links(
    pdgid: str,
    summary: str,
    names: dict[str, tuple[str, str]],
    roots: dict[str, str],
) -> list[tuple[str, str, str]]:
    result: list[tuple[str, str, str]] = []
    for fragment in see_also_fragments(summary):
        match = MATH.search(fragment)
        math = match.group(1) if match else ""
        candidate = math or fragment
        candidate_key = loose_key(candidate)
        target = SEE_ALSO_ALIASES.get(candidate_key)
        label = roots.get(target, "") if target else ""
        if target is None:
            hit = names.get(candidate_key)
            if hit is not None:
                target, label = hit
        if target is not None and target != pdgid:
            result.append((target, label or target, math))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--notes", default="assets/pdg_notes_2026.sqlite")
    parser.add_argument("--snapshot", default="assets/pdgall-2026.0.sqlite")
    parser.add_argument("--reviews", default="assets/review_sources_2026.json")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    names, roots = snapshot_names(args.snapshot)
    titles = review_titles(args.reviews)
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
            "label TEXT NOT NULL, math TEXT NOT NULL DEFAULT '', "
            "PRIMARY KEY (pdgid, target_pdgid))"
        )
        columns = {
            row[1] for row in store.execute("PRAGMA table_info(pdg_note_see_also)")
        }
        if "math" not in columns:
            store.execute(
                "ALTER TABLE pdg_note_see_also "
                "ADD COLUMN math TEXT NOT NULL DEFAULT ''"
            )
        rows = list(
            store.execute(
                "SELECT pdgid, summary FROM pdg_notes WHERE summary IS NOT NULL"
            )
        )
        review_hits = see_also_hits = 0
        for pdgid, summary in rows:
            summary = summary or ""
            matched_reviews = review_links(summary, titles)
            see_also = see_also_links(pdgid, summary, names, roots)
            if not args.dry_run:
                for file, _title in matched_reviews:
                    store.execute(
                        "INSERT OR REPLACE INTO pdg_note_reviews(pdgid, file) "
                        "VALUES (?, ?)",
                        (pdgid, file),
                    )
                for target, label, math in see_also:
                    store.execute(
                        "INSERT OR REPLACE INTO pdg_note_see_also"
                        "(pdgid, target_pdgid, label, math) "
                        "VALUES (?, ?, ?, ?)",
                        (pdgid, target, label, math),
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
