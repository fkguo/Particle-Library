#!/usr/bin/env python3
"""Parser tests for the pdgLive particle-status patch.

Run with:
    python3 tool/test_fetch_pdg_particle_status.py
"""

from __future__ import annotations

import importlib.util
import pathlib
import sqlite3
import unittest

MODULE_PATH = pathlib.Path(__file__).with_name("fetch_pdg_particle_status.py")
SPEC = importlib.util.spec_from_file_location("fetch_pdg_particle_status", MODULE_PATH)
assert SPEC and SPEC.loader
STATUS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STATUS)


def page(*rows: str) -> str:
    return "<html><body>" + "".join(rows) + "</body></html>"


def row(pdgid: str, cells: str) -> str:
    return (
        '<div class="list-group-item1">'
        f'<a href="./Particle.action?init=0&node={pdgid}&home=BXXX005">'
        "<table><tr>"
        f"{cells}"
        "</tr></table></a></div>"
    )


class ParseGroupTest(unittest.TestCase):
    def test_baryon_stars_are_read_from_the_last_cell(self) -> None:
        rows = STATUS.parse_group(
            page(
                row(
                    "B018",
                    "<td>${{\\mathit N}{(1700)}}$</td>"
                    "<td>$3/2^{- }$</td><td>***</td>",
                )
            )
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["pdgid"], "B018")
        self.assertEqual(rows[0]["stars"], 3)
        self.assertFalse(rows[0]["established"])
        self.assertIn(r"\mathit N", str(rows[0]["name"]))
        self.assertEqual(rows[0]["jp"], "$3/2^{- }$")

    def test_meson_bullet_is_established_not_a_star_rating(self) -> None:
        rows = STATUS.parse_group(
            page(
                row(
                    "S008",
                    '<td><font class="d">•</font></td>'
                    "<td>${{\\mathit \\pi}^{\\pm}}$</td>"
                    "<td>$1^-(0^{-})$</td><td></td>",
                )
            )
        )
        self.assertEqual(len(rows), 1)
        self.assertIsNone(rows[0]["stars"])
        self.assertTrue(rows[0]["established"])
        self.assertIn(r"\mathit \pi", str(rows[0]["name"]))
        self.assertEqual(rows[0]["jp"], "$1^-(0^{-})$")

    def test_a_row_without_a_published_mark_is_still_recorded(self) -> None:
        rows = STATUS.parse_group(
            page(
                row(
                    "B128",
                    "<td>${{\\mathit N}}(\\sim{}$3000 Region) Partial-Wave Analyses</td>"
                    "<td></td><td></td>",
                )
            )
        )
        self.assertEqual(len(rows), 1)
        self.assertIsNone(rows[0]["stars"])
        self.assertFalse(rows[0]["established"])


class StoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.store = sqlite3.connect(":memory:")
        STATUS.prepare(self.store)

    def tearDown(self) -> None:
        self.store.close()

    def test_validate_group_page_rejects_an_error_page(self) -> None:
        with self.assertRaises(ValueError):
            STATUS.validate_group_page(
                "<div>404 - We're sorry, the page you are looking for "
                "does not exist.</div>"
            )
        # An empty but real group page (CDXX/CNXX) is accepted.
        STATUS.validate_group_page("<div>pdgLive Home > BARYONS</div>")

    def test_scan_conflicts_detects_a_different_group(self) -> None:
        self.store.execute(
            "INSERT INTO pdg_particle_status_scan"
            "(pdgid, group_node, name, jp, stars, established, source) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            ("B018", "BXXX005", "N(1700)", "3/2-", 3, 0, "source"),
        )
        self.assertEqual(STATUS.scan_conflicts(self.store, ["B018"], "BXXX005"), [])
        self.assertEqual(
            STATUS.scan_conflicts(self.store, ["B018"], "BXXX010"),
            [("B018", "BXXX005")],
        )

    def test_rebuild_status_uses_only_marked_scan_rows(self) -> None:
        self.store.executemany(
            "INSERT INTO pdg_particle_status_scan"
            "(pdgid, group_node, name, jp, stars, established, source) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            [
                ("B018", "BXXX005", "N(1700)", "3/2-", 3, 0, "source"),
                ("S008", "MXXX005", "pi+", "1-(0-)", None, 1, "source"),
                ("B128", "BXXX005", "N(~3000)", "", None, 0, "source"),
            ],
        )
        STATUS.rebuild_status(self.store)
        rows = {
            row[0]: (row[1], row[2])
            for row in self.store.execute(
                "SELECT pdgid, stars, established FROM pdg_particle_status"
            )
        }
        self.assertEqual(rows, {"B018": (3, 0), "S008": (None, 1)})


if __name__ == "__main__":
    unittest.main()
