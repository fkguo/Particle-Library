# Third-party notices

Last reviewed: 2026-10-22

Particle Library's application code is licensed under the Mozilla Public
License 2.0 (MPL-2.0) in [LICENSE](LICENSE). That license does **not** apply to
the PDG data, the PDG review PDFs, or third-party packages. Their terms are summarized below.

## PDG data snapshot

The bundled `assets/pdgall-2026.0.sqlite` snapshot contains data from the
Particle Data Group (PDG), *Review of Particle Physics*, 2026 edition:

> F. Takahashi et al. (Particle Data Group), Int. J. Mod. Phys. A **41**,
> 2630011 (2026).

PDG data is distributed under the **Creative Commons Attribution 4.0
International (CC BY 4.0)** license. Attribution must be retained when the
snapshot or substantial portions of it are redistributed. This project is not
an official PDG application.

- PDG: <https://pdg.lbl.gov/>
- CC BY 4.0: <https://creativecommons.org/licenses/by/4.0/>

## PDG review PDFs

PDG review PDFs are **not bundled** with the app. The app downloads them from
the official PDG website only when the user requests an individual review or
the explicit "cache all" action. Those PDFs remain subject to PDG's terms and
attribution requirements; downloading or caching them does not relicense
them. The PDF files are stored locally for reading and are not redistributed
by this repository.

## Direct Dart/Flutter dependencies

The following direct dependencies retain their own licenses. The complete
transitive license texts are included in the Flutter license registry and in
the generated macOS application's `NOTICES.Z`.

| Package | License |
|---|---|
| Flutter / Dart SDK | BSD-3-Clause |
| `path_provider` | BSD-3-Clause |
| `url_launcher` | BSD-3-Clause |
| `crypto` | BSD-3-Clause |
| `sqlite3` | MIT |
| `sqlite3_flutter_libs` | MIT |
| `flutter_math_fork` | Apache-2.0 |
| `pdfrx` / `pdfrx_engine` | MIT |
| `pdfium` / `pdfium_flutter` | BSD-3-Clause / MIT |
| `flutter_svg` | MIT |
| `file_selector` | BSD-3-Clause |
| `archive` | MIT |
| `html` | MIT |
| SQLite (via `sqlite3`, `sqlite3_flutter_libs`) | Public domain / MIT |
| KaTeX fonts bundled by `flutter_math_fork` | MIT |

Package source and license files are available from <https://pub.dev/> and the
respective upstream repositories.

## Icons and brand artwork

The Particle Library owl artwork and in-app BrandMark were created for this
project and are included under the MPL-2.0 above. No third-party character
asset is included.

## INSPIRE name and mark

The in-app “iN” monogram is an original outline mark used to identify the
external INSPIRE-HEP service. No official INSPIRE logo is bundled, and this
project is not endorsed by INSPIRE or CERN.
