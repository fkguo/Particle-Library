import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/domain/labels.dart';
import 'package:pdgapp/domain/models.dart';
import 'package:pdgapp/data/pdg_database.dart';
import 'package:pdgapp/features/catalog/catalog_groups.dart';

Entry entry(String description, String flags, {String pdgid = 'X'}) => Entry({
  'id': description.hashCode,
  'pdgid': pdgid,
  'description': description,
  'flags': flags,
  'data_type': 'PART',
});

CatalogGroupKind? kind(String description, String flags) =>
    catalogGroupFor(entry(description, flags))?.kind;

void main() {
  test('section headings are grouped as quarkonium', () {
    expect(kind('Bottomonium', 'M'), CatalogGroupKind.mesonBBbar);
    expect(kind('Charmonium', 'M'), CatalogGroupKind.mesonCCbar);
  });

  test('mesons follow the PDG Live summary-table groups', () {
    expect(kind('pi0', 'M'), CatalogGroupKind.mesonLight);
    expect(kind('b_1(1235)', 'M'), CatalogGroupKind.mesonLight);
    expect(kind('K^*(892)', 'M'), CatalogGroupKind.mesonStrange);
    expect(kind('D^*(2010)+-', 'M'), CatalogGroupKind.mesonCharmed);
    expect(kind('D_s3^*(2860)+-', 'M'), CatalogGroupKind.mesonCharmedStrange);
    expect(kind('B^+-', 'M'), CatalogGroupKind.mesonBottom);
    expect(kind('B_s^()0', 'M'), CatalogGroupKind.mesonBottomStrange);
    expect(kind('B_c()+', 'M'), CatalogGroupKind.mesonBottomCharmed);
    expect(kind('eta_c(1S)', 'M'), CatalogGroupKind.mesonCCbar);
    expect(kind('Upsilon(1S)', 'M'), CatalogGroupKind.mesonBBbar);
    expect(kind('X(2370)', 'M'), CatalogGroupKind.mesonOther);
  });

  test('baryons follow the PDG Live summary-table groups', () {
    expect(kind('N(1440)', 'B'), CatalogGroupKind.baryonN);
    expect(kind('Delta(1232)', 'B'), CatalogGroupKind.baryonDelta);
    expect(kind('Lambda(1405)', 'B'), CatalogGroupKind.baryonLambda);
    expect(kind('Sigma(1385)', 'B'), CatalogGroupKind.baryonSigma);
    expect(kind('Xi(1530)', 'B'), CatalogGroupKind.baryonXi);
    expect(kind('Omega-', 'B'), CatalogGroupKind.baryonOmega);
    expect(kind('Lambda_c()+', 'B'), CatalogGroupKind.baryonCharmed);
    expect(kind('Xi_cc()+', 'B'), CatalogGroupKind.baryonDoublyCharmed);
    expect(kind('Lambda_b()0', 'B'), CatalogGroupKind.baryonBottom);
  });

  test('topic-only roots follow their category but stay out of subgroups', () {
    final vcb = CatalogRoot(
      entry('V(cb) and V(ub) CKM Matrix Elements', 'M'),
      0,
      0,
    );
    final spectroscopy = CatalogRoot(
      entry('Heavy Quarkonium Spectroscopy', 'M'),
      0,
      0,
    );
    // Category comes from the flags, exactly as the entry page shows it.
    expect(catalogCategoryForRoot(vcb), ParticleCategory.meson);
    expect(catalogCategoryForRoot(spectroscopy), ParticleCategory.meson);
    // Without particle identities they never join a meson/baryon subgroup.
    expect(catalogGroupForRoot(vcb), isNull);
    expect(catalogGroupForRoot(spectroscopy), isNull);

    final pi0 = CatalogRoot(entry('pi0', 'M'), 1, 1);
    expect(catalogCategoryForRoot(pi0), ParticleCategory.meson);
    expect(catalogGroupForRoot(pi0)?.kind, CatalogGroupKind.mesonLight);
  });

  test('PDG Live topic nodes link to their exact review', () {
    expect(
      entryReviewFiles['M209'],
      contains('rpp2026-rev-heavy-quarkonium-spectroscopy.pdf'),
    );
    expect(entryReviewFiles['S052'], contains('rpp2026-rev-vcb-vub.pdf'));
    expect(
      entryReviewFiles['S056'],
      contains('rpp2026-rev-zprime-searches.pdf'),
    );
  });

  test('charmonium and bottomonium labels carry explicit math', () {
    final mesons = catalogGroups(ParticleCategory.meson);
    final cc = mesons.firstWhere(
      (group) => group.kind == CatalogGroupKind.mesonCCbar,
    );
    final bb = mesons.firstWhere(
      (group) => group.kind == CatalogGroupKind.mesonBBbar,
    );
    expect(cc.label(TextLang.en), contains(r'$c\bar{c}$'));
    expect(bb.label(TextLang.en), contains(r'$b\bar{b}$'));
  });

  test('category review buttons use exact PDG Live review sets', () {
    expect(
      categoryReviewFiles[ParticleCategory.gaugeHiggs],
      contains('rpp2026-rev-w-mass.pdf'),
    );
    expect(
      categoryReviewFiles[ParticleCategory.meson],
      contains('rpp2026-rev-heavy-quarkonium-spectroscopy.pdf'),
    );
    expect(
      categoryReviewFiles[ParticleCategory.baryon],
      contains('rpp2026-rev-pentaquarks.pdf'),
    );
    expect(
      categoryReviewFiles[ParticleCategory.search],
      contains('rpp2026-rev-wimps-other-searches.pdf'),
    );
  });

  test('group lists are only exposed for mesons and baryons', () {
    expect(catalogGroups(ParticleCategory.meson).length, 10);
    expect(catalogGroups(ParticleCategory.baryon).length, 10);
    expect(catalogGroups(ParticleCategory.lepton), isEmpty);
  });

  test('sections without particle identities still follow their flags', () {
    // These roots have no particle rows; their flags still name the category.
    expect(
      catalogCategoryForRoot(CatalogRoot(entry('Neutrino Properties', 'L'), 12, 0)),
      ParticleCategory.lepton,
    );
    expect(
      catalogCategoryForRoot(CatalogRoot(entry('Extra Dimensions', 'S'), 8, 0)),
      ParticleCategory.search,
    );
    expect(
      catalogCategoryForRoot(CatalogRoot(entry('Charmonium', 'M'), 0, 0)),
      ParticleCategory.meson,
    );
    // Only a root without any category flag is uncategorised.
    expect(
      catalogCategoryForRoot(CatalogRoot(entry('Miscellaneous', ''), 2, 0)),
      ParticleCategory.unknown,
    );
  });

  test('CKM matrix elements follow PDG Live and sit under Quarks', () {
    final ckm = CatalogRoot(
      entry('V(cb) and V(ub) CKM Matrix Elements', 'M', pdgid: 'S052'),
      0,
      0,
    );
    expect(catalogCategoryForRoot(ckm), ParticleCategory.quark);
    // The override is keyed by PDG ID, not by the description.
    final other = CatalogRoot(
      entry('V(cb) and V(ub) CKM Matrix Elements', 'M'),
      0,
      0,
    );
    expect(catalogCategoryForRoot(other), ParticleCategory.meson);
  });
}
