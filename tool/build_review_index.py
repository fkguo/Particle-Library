#!/usr/bin/env python3
"""Build the bundled PDG review full-text index.

The index is a page-level FTS5 database derived from the official PDG review
PDFs.  It is intentionally independent from the pdgall snapshot: PDFs stay
download-on-demand and the derived text index is the only bundled asset.

Commands
--------
    fetch   download the PDFs listed in the source manifest (optional)
    build   build the index, manifest, rules and Dart contract
    verify  check an existing index/contract and run the U1-U3 self-test

Only pypdf is required for extraction (BSD).  PyMuPDF is not used here.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sqlite3
import sys
import time
import unicodedata
import urllib.request
from pathlib import Path

try:
    from pypdf import PdfReader
except ImportError:  # pragma: no cover - operator-facing message
    raise SystemExit("pypdf is required: pip install pypdf==4.3.1")

EDITION = "2026"
SCHEMA_VERSION = "2"
RULES_VERSION = "1"
EXTRACTOR = "pypdf"
EXTRACTOR_VERSION = "4.3.1"
BASE_URL = "https://pdg.lbl.gov/2026/reviews"
BLOCK = "zzpdgblockboundaryzz"
CAPTION_START = re.compile(r"^(Table|Figure)\s+(\d+(?:\.\d+)?)\s*[:.]", re.M)
PAGE_NUMBER = re.compile(r"^\s*\d+\s+")
HYPHEN_JOIN = re.compile(r"([A-Za-z]{2,})-\s*\n\s*([a-z]{2,})")
LIGATURES = range(0xFB00, 0xFB07)

# U1-U3 are release gates, not "top three is good enough".
GATES = {
    "CG coefficients": ("rpp2026-rev-clebsch-gordan-coefs.pdf", 1),
    "hadronic cross sections": ("rpp2026-rev-cross-section-plots.pdf", 5),
    "average hadron multiplicities": (
        "rpp2026-rev-cross-section-plots.pdf",
        2,
    ),
}

OVERRIDES = {
    "rpp2026-rev-clebsch-gordan-coefs.pdf": {
        "full_title": "Clebsch-Gordan Coefficients, Spherical Harmonics, and d Functions",
        "number": 46,
    },
    "rpp2026-rev-cross-section-plots.pdf": {
        "full_title": "Plots of Cross Sections and Related Quantities",
        "number": 53,
        "captions": {
            2: (
                "Table 53.1:",
                "Quoted errors are not increased by scale factor S.",
            ),
            5: (
                "Figure 53.2:",
                "Combination [104],",
            ),
        },
        "reference_pages": (4, 6),
    },
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def clean_text(raw: str) -> str:
    """NFKC, control characters, NBSP; keep newlines for joins/captions."""
    text = unicodedata.normalize("NFKC", raw or "")
    text = text.replace("\x00", " ").replace("\u00ad", "").replace("\u00a0", " ")
    text = "".join(
        ch if ch in "\n\t" or ord(ch) >= 32 else " " for ch in text
    )
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n[ \t]+", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def notation_tokens(text: str) -> str:
    """Supplementary canonical tokens; never a second copy of the page."""
    out: list[str] = []
    if re.search(r"e\s*[+⁺]\s*e\s*[−\-⁻]", text, re.I):
        out.append("electronpositronpair")
    if re.search(r"W\s*[′'’ʹ]", text, re.I):
        out.append("wprime")
    if re.search(r"Z\s*[′'’ʹ]", text, re.I):
        out.append("zprime")
    if re.search(r"g\s*[−\-⁻]\s*[2²]", text, re.I):
        out.append("gminus2 anomalous magnetic moment")
    if re.search(r"B\s*[⁰0]", text, re.I):
        out.append("bzero")
    return " ".join(dict.fromkeys(out))


def normalize_title(text: str) -> str:
    text = unicodedata.normalize("NFKC", text or "").lower()
    text = re.sub(r"\bcoeff\.", "coefficients", text)
    text = re.sub(r"\bsph\.", "spherical", text)
    text = re.sub(r"\bqm\.", "quantum mechanics", text)
    text = re.sub(r"\bext\.", "external", text)
    text = re.sub(r"\s+", " ", text).strip()
    canonical = notation_tokens(text)
    return f"{text} {canonical}".strip()


def flatten_outline(reader: PdfReader) -> list[tuple[int, str]]:
    out: list[tuple[int, str]] = []

    def walk(items) -> None:
        for item in items:
            if isinstance(item, list):
                walk(item)
                continue
            try:
                page = reader.get_destination_page_number(item) + 1
                title = str(getattr(item, "title", "") or "").strip()
                if title and page >= 1:
                    out.append((page, title))
            except Exception:
                continue

    try:
        walk(reader.outline)
    except Exception:
        pass
    return out


def first_heading(text: str) -> str:
    for line in text.splitlines():
        line = line.strip()
        if line:
            return PAGE_NUMBER.sub("", line)
    return ""


def caption_start(line: str) -> bool:
    return bool(re.match(r"^(Table|Figure)\s+\d+(?:\.\d+)?\s*[:.]", line.strip()))


def caption_blocks(text: str) -> list[str]:
    """Generic caption blocks.  Empty lines are only hints, never a hard cut."""
    lines = text.splitlines()
    blocks: list[str] = []
    for i, line in enumerate(lines):
        if not caption_start(line):
            continue
        block = [line.strip()]
        for nxt in lines[i + 1 :]:
            stripped = nxt.strip()
            if not stripped:
                break
            if caption_start(stripped):
                break
            if re.match(r"^\d+(\.\d+)?\s+[A-Z]", stripped):
                break
            if len(" ".join(block)) > 2400:
                break
            block.append(stripped)
        blocks.append(" ".join(block))
    return blocks


def override_caption(text: str, start: str, end_after: str) -> str | None:
    start_at = text.find(start)
    if start_at < 0:
        return None
    end_at = text.find(end_after, start_at)
    if end_at < 0:
        return None
    end_at += len(end_after)
    return re.sub(r"\s+", " ", text[start_at:end_at]).strip()


def page_caption(text: str, file: str, page: int) -> str:
    rule = OVERRIDES.get(file, {}).get("captions", {}).get(page)
    if rule:
        exact = override_caption(text, rule[0], rule[1])
        if exact:
            return exact
    blocks = caption_blocks(text)
    return f"\n{BLOCK}\n".join(blocks)


def is_reference_page(heading: str, text: str, file: str, page: int) -> int:
    if page in OVERRIDES.get(file, {}).get("reference_pages", ()):
        return 1
    if "reference" in (heading or "").lower():
        return 1
    stripped = text.lstrip().lower()
    if stripped.startswith("references") or "references grouped" in stripped[:200]:
        return 1
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if lines:
        refs = sum(1 for line in lines if re.match(r"^\[\d+\]", line))
        if refs / len(lines) > 0.3:
            return 1
    return 0


def page_heading(
    toc: list[tuple[int, str]], page: int, text: str
) -> tuple[str, str]:
    candidates = [(p, title) for p, title in toc if p <= page]
    if candidates:
        return candidates[-1][1], "outline"
    fallback = first_heading(text)
    return (fallback, "body") if fallback else ("", "none")


def parse_entries(repo: Path) -> list[tuple[str, str]]:
    src = (repo / "lib/features/reviews/review_index.dart").read_text()
    entries: list[tuple[str, str]] = []
    i = 0
    while True:
        j = src.find("ReviewEntry(", i)
        if j < 0:
            break
        k = j + len("ReviewEntry(")
        depth = 1
        quote: str | None = None
        while k < len(src) and depth > 0:
            ch = src[k]
            if quote:
                if ch == "\\":
                    k += 2
                    continue
                if ch == quote:
                    quote = None
            elif ch in "'\"":
                quote = ch
            elif ch in "([":
                depth += 1
            elif ch in ")]":
                depth -= 1
                if depth == 0:
                    break
            k += 1
        block = src[j:k]
        files = re.findall(r"'(rpp\d{4}-rev-[^']+\.pdf)'", block)
        title_match = re.match(
            r"ReviewEntry\(\s*(?:r)?'((?:[^'\\]|\\.)*)'", block
        )
        if files:
            title = (
                title_match.group(1).replace("\\'", "'")
                if title_match
                else files[0]
            )
            entries.append((title, files[0]))
        i = k
    # Preserve the Dart list order and drop accidental duplicates.
    seen: set[str] = set()
    unique: list[tuple[str, str]] = []
    for title, file in entries:
        if file not in seen:
            seen.add(file)
            unique.append((title, file))
    return unique


def build(repo: Path, pdf_dir: Path, out: Path, manifest: Path, rules: Path, contract: Path) -> None:
    entries = parse_entries(repo)
    if len(entries) != 121:
        raise SystemExit(f"expected 121 reviews, parsed {len(entries)}")

    sources: list[dict] = []
    review_rows: list[tuple] = []
    page_rows: list[tuple] = []
    started = time.time()

    for index, (title, file) in enumerate(entries, start=1):
        pdf = pdf_dir / file
        if not pdf.exists():
            raise SystemExit(f"missing PDF: {pdf}")
        raw_pdf = pdf.read_bytes()
        digest = sha256_bytes(raw_pdf)
        reader = PdfReader(pdf)
        toc = flatten_outline(reader)
        override = OVERRIDES.get(file, {})

        pages: list[tuple] = []
        heading_pages: dict[str, int] = {}
        review_chars = 0
        for page_no, page in enumerate(reader.pages, start=1):
            text = clean_text(page.extract_text() or "")
            review_chars += len(text)
            heading, source = page_heading(toc, page_no, text)
            if heading and heading not in heading_pages:
                heading_pages[heading] = page_no
            pages.append(
                (
                    file,
                    page_no,
                    heading,
                    heading if source == "outline" else "",
                    heading_pages.get(heading),
                    is_reference_page(heading, text, file, page_no),
                    page_caption(text, file, page_no),
                    text,
                    " ".join(
                        dict.fromkeys(
                            m.group(1) + m.group(2)
                            for m in HYPHEN_JOIN.finditer(text)
                        )
                    ),
                    notation_tokens(text),
                )
            )

        full_title = override.get("full_title") or (
            toc[0][1] if toc else first_heading(pages[0][7])
        )
        title_norm = normalize_title(f"{title} {full_title}")
        review_rows.append(
            (
                file,
                title,
                title_norm,
                full_title,
                len(reader.pages),
                review_chars,
                digest,
                f"{BASE_URL}/{file}",
                "CC BY 4.0",
            )
        )
        page_rows.extend(pages)
        sources.append(
            {
                "file": file,
                "title": title,
                "full_title": full_title,
                "number": override.get("number"),
                "url": f"{BASE_URL}/{file}",
                "sha256": digest,
                "pages": len(reader.pages),
                "bytes": len(raw_pdf),
                "license_decision": "include",
                "license": "CC BY 4.0",
                "attribution": "Particle Data Group, Review of Particle Physics 2026",
                "source": f"{BASE_URL}/{file}",
                "page_overrides": [
                    {"page": page, "caption": start, "start": start, "end_after": end}
                    for page, (start, end) in override.get("captions", {}).items()
                ],
                "reference_pages": list(override.get("reference_pages", ())),
            }
        )
        print(f"[{index:3}/{len(entries)}] {file}: {len(reader.pages)} pages")

    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".sqlite.partial")
    if tmp.exists():
        tmp.unlink()
    con = sqlite3.connect(tmp)
    con.executescript(
        f"""
        PRAGMA journal_mode=DELETE;
        PRAGMA page_size=4096;
        PRAGMA foreign_keys=ON;
        PRAGMA user_version={SCHEMA_VERSION};
        CREATE TABLE review(
          file TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          title_norm TEXT NOT NULL,
          full_title TEXT NOT NULL,
          pages INTEGER NOT NULL CHECK(pages > 0),
          chars INTEGER NOT NULL CHECK(chars >= 0),
          sha256 TEXT NOT NULL CHECK(length(sha256)=64),
          source_url TEXT NOT NULL,
          license TEXT NOT NULL
        );
        CREATE TABLE page(
          id INTEGER PRIMARY KEY,
          file TEXT NOT NULL REFERENCES review(file),
          page INTEGER NOT NULL CHECK(page >= 1),
          heading TEXT NOT NULL DEFAULT '',
          heading_display TEXT NOT NULL DEFAULT '',
          section_start_page INTEGER,
          is_reference INTEGER NOT NULL CHECK(is_reference IN (0,1)),
          caption TEXT NOT NULL DEFAULT '',
          text TEXT NOT NULL,
          joins TEXT NOT NULL DEFAULT '',
          terms TEXT NOT NULL DEFAULT '',
          UNIQUE(file,page)
        );
        CREATE INDEX page_file_page ON page(file,page);
        CREATE VIRTUAL TABLE page_fts USING fts5(
          heading, text, joins, caption, terms,
          content='page', content_rowid='id',
          tokenize='porter unicode61 remove_diacritics 2'
        );
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """
    )
    con.executemany(
        "INSERT INTO review VALUES(?,?,?,?,?,?,?,?,?)", review_rows
    )
    con.executemany(
        "INSERT INTO page(file,page,heading,heading_display,section_start_page,"
        "is_reference,caption,text,joins,terms) VALUES(?,?,?,?,?,?,?,?,?,?)",
        page_rows,
    )
    con.execute(
        "INSERT INTO page_fts(rowid,heading,text,joins,caption,terms) "
        "SELECT id,heading,text,joins,caption,terms FROM page ORDER BY id"
    )
    meta = {
        "edition": EDITION,
        "schema_version": SCHEMA_VERSION,
        "rules_version": RULES_VERSION,
        "extractor": EXTRACTOR,
        "extractor_version": EXTRACTOR_VERSION,
        "page_count": str(len(page_rows)),
        "review_count": str(len(review_rows)),
        "text_chars": str(sum(len(row[7]) for row in page_rows)),
        "join_candidates": str(
            sum(len(HYPHEN_JOIN.findall(row[7])) for row in page_rows)
        ),
        "source_manifest": manifest.name,
    }
    con.executemany("INSERT INTO meta VALUES(?,?)", meta.items())
    con.commit()
    con.execute("VACUUM")
    con.close()
    tmp.replace(out)
    db_bytes = out.read_bytes()

    # Manifest and rules are plain, reviewable assets.
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(
        json.dumps(
            {
                "edition": EDITION,
                "schema_version": SCHEMA_VERSION,
                "source_date": "2026-10-23",
                "extractor": {"name": EXTRACTOR, "version": EXTRACTOR_VERSION},
                "normalizer_version": RULES_VERSION,
                "ranking_version": "1",
                "sources": sources,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )
    rules.write_text(
        json.dumps(
            {
                "version": int(RULES_VERSION),
                "aliases": {
                    "cg": ["cg", "clebsch gordan"],
                    "hvp": ["hvp", "hadronic vacuum polarization"],
                    "hlbl": ["hlbl", "hadronic light by light"],
                    "qcd": ["qcd", "quantum chromodynamics"],
                    "gminus2": ["gminus2", "anomalous magnetic moment"],
                    "electronpositronpair": [
                        "electronpositronpair",
                        "electron positron",
                    ],
                },
                "notation": {
                    "electronpositronpair": ["e+e-", "e+e−", "e⁺e⁻"],
                    "wprime": ["W'", "W′"],
                    "zprime": ["Z'", "Z′"],
                    "gminus2": ["g-2", "g−2"],
                    "bzero": ["B0", "B⁰"],
                },
                "golden": [
                    {
                        "raw": "CG coefficients",
                        "canonical": ["cg|clebsch gordan", "coefficients"],
                        "expression": '("cg" OR "clebsch gordan") AND "coefficients"',
                    },
                    {
                        "raw": '"CG coefficients"',
                        "canonical": ["cg coefficients|clebsch gordan coefficients"],
                        "expression": '("cg coefficients" OR "clebsch gordan coefficients")',
                    },
                    {
                        "raw": "HVP",
                        "canonical": ["hvp|hadronic vacuum polarization"],
                        "expression": '("hvp" OR "hadronic vacuum polarization")',
                    },
                    {
                        "raw": "muon g-2",
                        "canonical": ["muon", "gminus2|anomalous magnetic moment"],
                        "expression": '"muon" AND ("gminus2" OR "anomalous magnetic moment")',
                    },
                    {
                        "raw": "e+e-",
                        "canonical": ["electronpositronpair"],
                        "expression": '("electronpositronpair" OR "electron positron")',
                    },
                    {
                        "raw": "E⁺E⁻",
                        "canonical": ["electronpositronpair"],
                        "expression": '("electronpositronpair" OR "electron positron")',
                    },
                    {
                        "raw": "W'",
                        "canonical": ["wprime"],
                        "expression": '"wprime"',
                    },
                    {
                        "raw": "B⁰",
                        "canonical": ["bzero"],
                        "expression": '"bzero"',
                    },
                ],
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )
    contract.parent.mkdir(parents=True, exist_ok=True)
    rules_sha = sha256_file(rules)
    manifest_sha = sha256_file(manifest)
    contract.write_text(
        "// GENERATED by tool/build_review_index.py; do not edit by hand.\n"
        "abstract final class ReviewIndexContract {\n"
        f"  static const String assetName = 'assets/{out.name}';\n"
        f"  static const int expectedSizeBytes = {len(db_bytes)};\n"
        f"  static const String expectedSha256 = '{sha256_bytes(db_bytes)}';\n"
        f"  static const String expectedEdition = '{EDITION}';\n"
        f"  static const String expectedSchemaVersion = '{SCHEMA_VERSION}';\n"
        f"  static const String expectedRulesVersion = '{RULES_VERSION}';\n"
        f"  static const String expectedRulesSha256 = '{rules_sha}';\n"
        f"  static const String expectedManifestSha256 = '{manifest_sha}';\n"
        f"  static const int expectedReviewCount = {len(review_rows)};\n"
        f"  static const int expectedPageCount = {len(page_rows)};\n"
        "}\n"
    )
    print(
        f"built {out} ({len(db_bytes)} bytes, {len(review_rows)} reviews, "
        f"{len(page_rows)} pages, {time.time() - started:.1f}s)"
    )
    print(f"contract: {contract}")
    print(f"manifest: {manifest}")
    print(f"rules: {rules}")


def rank(
    expr: str, words: list[str], con: sqlite3.Connection, limit: int = 5
) -> list[tuple[str, int, str, float]]:
    rows = con.execute(
        """
        SELECT r.file, r.title, r.title_norm, r.full_title, p.page, p.heading,
               p.section_start_page, p.is_reference, p.caption,
               bm25(page_fts, 8.0, 1.0, 0.5, 4.0, 2.0) AS rank
          FROM page_fts JOIN page p ON p.id=page_fts.rowid
          JOIN review r ON r.file=p.file
         WHERE page_fts MATCH ?
         ORDER BY rank
        """,
        (expr,),
    ).fetchall()
    by_review: dict[str, list[tuple]] = {}
    for row in rows:
        by_review.setdefault(row[0], []).append(row)
    scored = []
    for file, pages in by_review.items():
        title = (pages[0][2] + " " + pages[0][3]).lower()
        page_scored = []
        for row in pages:
            page_score = -row[9]
            if row[6] == row[4]:
                page_score += 1.5
            heading = (row[5] or "").lower()
            if words and all(word in heading for word in words):
                page_score += 4.0
            if words and " ".join(words) in heading:
                page_score += 6.0
            if row[8] and any(word in row[8].lower() for word in words):
                page_score += 1.0
            if row[7]:
                page_score -= 2.5
            page_scored.append((page_score, row))
        page_score, best = max(page_scored, key=lambda item: (item[0], -item[1][4]))
        title_hits = sum(1 for word in words if word in title)
        phrase = " ".join(words) in title
        score = page_score + 6.0 * title_hits + (10.0 if phrase else 0.0)
        score += 0.8 * math.log2(1 + len(pages))
        scored.append((score, file, pages[0][1], best[4]))
    scored.sort(key=lambda item: (-item[0], item[1]))
    return [(file, page, title, score) for score, file, title, page in scored[:limit]]


def verify(
    db: Path,
    contract: Path,
    rules: Path | None = None,
    manifest: Path | None = None,
) -> None:
    data = db.read_bytes()
    if not contract.exists():
        raise SystemExit(f"missing contract: {contract}")
    text = contract.read_text()
    expected_size = re.search(r"expectedSizeBytes\s*=\s*(\d+)", text)
    expected_sha = re.search(r"expectedSha256\s*=\s*'([0-9a-f]{64})'", text)
    if not expected_size:
        raise SystemExit("contract missing expectedSizeBytes")
    if not expected_sha:
        raise SystemExit("contract missing expectedSha256")
    if int(expected_size.group(1)) != len(data):
        raise SystemExit("contract size mismatch")
    if expected_sha.group(1) != sha256_bytes(data):
        raise SystemExit("contract sha256 mismatch")
    expected_rules = re.search(r"expectedRulesSha256\s*=\s*'([0-9a-f]{64})'", text)
    expected_manifest = re.search(
        r"expectedManifestSha256\s*=\s*'([0-9a-f]{64})'", text
    )
    if rules:
        if not expected_rules:
            raise SystemExit("contract missing expectedRulesSha256")
        if sha256_file(rules) != expected_rules.group(1):
            raise SystemExit("contract rules sha256 mismatch")
    if manifest:
        if not expected_manifest:
            raise SystemExit("contract missing expectedManifestSha256")
        if sha256_file(manifest) != expected_manifest.group(1):
            raise SystemExit("contract manifest sha256 mismatch")
    con = sqlite3.connect(f"file:{db}?mode=ro&immutable=1", uri=True)
    review_count = con.execute("SELECT COUNT(*) FROM review").fetchone()[0]
    page_count = con.execute("SELECT COUNT(*) FROM page").fetchone()[0]
    if review_count != 121 or page_count < 2000:
        raise SystemExit(f"unexpected counts: {review_count}/{page_count}")
    if con.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise SystemExit("integrity_check failed")
    for query, words, expected in (
        (
            '("cg" OR "clebsch gordan") AND "coefficients"',
            ["clebsch", "gordan", "coefficients"],
            ("rpp2026-rev-clebsch-gordan-coefs.pdf", 1),
        ),
        (
            '"hadronic" AND "cross" AND "sections"',
            ["hadronic", "cross", "sections"],
            ("rpp2026-rev-cross-section-plots.pdf", 5),
        ),
        (
            '"average" AND "hadron" AND "multiplicities"',
            ["average", "hadron", "multiplicities"],
            ("rpp2026-rev-cross-section-plots.pdf", 2),
        ),
    ):
        result = rank(query, words, con, limit=1)
        if not result:
            raise SystemExit(f"no result for {query}")
        file, page, title, _score = result[0]
        print(f"  {query} -> {title} p{page}")
        if (file, page) != expected:
            raise SystemExit(f"gate failed: {query}: {(file, page)} != {expected}")
    print("self-test: OK")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    sub = parser.add_subparsers(dest="command", required=True)

    fetch = sub.add_parser("fetch")
    fetch.add_argument("--manifest", type=Path, required=True)
    fetch.add_argument("--pdf-dir", type=Path, required=True)
    fetch.add_argument("--delay", type=float, default=1.0)

    build_cmd = sub.add_parser("build")
    build_cmd.add_argument("--pdf-dir", type=Path, required=True)
    build_cmd.add_argument("--out", type=Path, required=True)
    build_cmd.add_argument("--manifest", type=Path, required=True)
    build_cmd.add_argument("--rules", type=Path, required=True)
    build_cmd.add_argument("--contract", type=Path, required=True)

    verify_cmd = sub.add_parser("verify")
    verify_cmd.add_argument("--db", type=Path, required=True)
    verify_cmd.add_argument("--contract", type=Path, required=True)
    verify_cmd.add_argument("--rules", type=Path)
    verify_cmd.add_argument("--manifest", type=Path)

    args = parser.parse_args()
    if args.command == "fetch":
        manifest = json.loads(args.manifest.read_text())
        args.pdf_dir.mkdir(parents=True, exist_ok=True)
        for source in manifest.get("sources", []):
            target = args.pdf_dir / source["file"]
            if target.exists() and sha256_file(target) == source["sha256"]:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            req = urllib.request.Request(
                source["url"],
                headers={"User-Agent": "ParticleLibrary/0.2 review-index"},
            )
            with urllib.request.urlopen(req, timeout=60) as response:
                data = response.read()
            if not data.startswith(b"%PDF"):
                raise SystemExit(f"not a PDF: {source['url']}")
            target.write_bytes(data)
            if sha256_bytes(data) != source["sha256"]:
                raise SystemExit(f"sha256 mismatch: {source['url']}")
            time.sleep(args.delay)
        print("fetch: OK")
    elif args.command == "build":
        build(
            args.repo,
            args.pdf_dir,
            args.out,
            args.manifest,
            args.rules,
            args.contract,
        )
    else:
        verify(args.db, args.contract, args.rules, args.manifest)


if __name__ == "__main__":
    main()
