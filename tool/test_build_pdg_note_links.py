#!/usr/bin/env python3
"""Parser tests for the pdgLive summary-link builder.

Run with:
    python3 tool/test_build_pdg_note_links.py
"""

from __future__ import annotations

import importlib.util
import json
import pathlib
import tempfile
import unittest

MODULE_PATH = pathlib.Path(__file__).with_name("build_pdg_note_links.py")
SPEC = importlib.util.spec_from_file_location("build_pdg_note_links", MODULE_PATH)
assert SPEC and SPEC.loader
LINKS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LINKS)


class KeyTest(unittest.TestCase):
    def test_particle_latex_normalizes_to_the_snapshot_spelling(self) -> None:
        self.assertEqual(
            LINKS.key(r"{{\mathit \pi}_{{{1}}}{(1600)}}"), "pi1(1600)"
        )
        self.assertEqual(LINKS.key(r"\Lambda_b^0"), "lambdab0")

    def test_review_title_whitespace_and_quotes_are_ignored(self) -> None:
        self.assertEqual(
            LINKS.key('"Spectroscopy of Light Meson Resonances"'),
            "spectroscopyoflightmesonresonances",
        )


class SummaryTest(unittest.TestCase):
    def test_see_also_fragment_extracts_the_math_target(self) -> None:
        summary = (
            "Coupled channel analyses favor one state. "
            "See the review on \"Spectroscopy of Light Meson Resonances\". "
            "See also ${{\\mathit \\pi}_{{{1}}}{(1600)}}$."
        )
        fragments = LINKS.see_also_fragments(summary)
        self.assertEqual(len(fragments), 1)
        self.assertIn(r"\pi", fragments[0])

    def test_citation_clauses_are_not_treated_as_particles(self) -> None:
        self.assertEqual(
            LINKS.see_also_fragments(
                "See also HEMINGWAY 1975 and the ${{\\mathit \\pi}_{{{1}}}{(1600)}}$."
            ),
            [r"${{\mathit \pi}_{{{1}}}{(1600)}}$"],
        )

    def test_review_shorthand_alias_matches(self) -> None:
        links = LINKS.review_links(
            "See the review on non-q qbar states.", []
        )
        self.assertEqual(
            links, [("rpp2026-rev-non-qqbar-mesons.pdf", "nonqqbarstates")]
        )

    def test_historical_particle_name_maps_to_current_root(self) -> None:
        math = r"{{\mathit P}_{{{c}}}{(4450)}^{+}}"
        links = LINKS.see_also_links(
            "B171",
            f"See also the ${math}$.",
            {},
            {"B171": "P_c_cbar(4380)+", "B172": "P_c_cbar(4457)+"},
        )
        self.assertEqual(
            links, [("B172", "P_c_cbar(4457)+", math)]
        )


class ReviewTitleTest(unittest.TestCase):
    def test_short_section_headings_are_not_article_titles(self) -> None:
        payload = {
            "sources": [
                {"title": "Overview", "full_title": "Overview", "file": "a.pdf"},
                {"title": "7", "full_title": "7", "file": "b.pdf"},
                {
                    "title": "Spectroscopy of Light Meson Resonances",
                    "full_title": "Spectroscopy of Light Meson Resonances",
                    "file": "c.pdf",
                },
            ]
        }
        with tempfile.NamedTemporaryFile(
            "w", suffix=".json", delete=False
        ) as handle:
            json.dump(payload, handle)
            path = handle.name
        try:
            titles = LINKS.review_titles(path)
        finally:
            pathlib.Path(path).unlink()
        self.assertEqual(
            [(title, file) for _, file, title in titles],
            [("Spectroscopy of Light Meson Resonances", "c.pdf")],
        )


if __name__ == "__main__":
    unittest.main()
