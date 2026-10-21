import '../../data/pdg_database.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';

/// Second-level catalog groups, following the PDG Live Summary Tables.
enum CatalogGroupKind {
  mesonLight,
  mesonStrange,
  mesonCharmed,
  mesonCharmedStrange,
  mesonBottom,
  mesonBottomStrange,
  mesonBottomCharmed,
  mesonCCbar,
  mesonBBbar,
  mesonOther,
  baryonN,
  baryonDelta,
  baryonLambda,
  baryonSigma,
  baryonXi,
  baryonOmega,
  baryonCharmed,
  baryonDoublyCharmed,
  baryonBottom,
  baryonOther,
}

class CatalogGroup {
  const CatalogGroup(this.kind, this.zh, this.en);

  final CatalogGroupKind kind;
  final String zh;
  final String en;

  String label(TextLang lang) => pick(lang, zh, en);
}

const _mesonGroups = <CatalogGroup>[
  CatalogGroup(CatalogGroupKind.mesonLight, '轻无味介子', 'Light unflavored'),
  CatalogGroup(CatalogGroupKind.mesonStrange, '奇异介子', 'Strange'),
  CatalogGroup(CatalogGroupKind.mesonCharmed, '粲介子', 'Charmed'),
  CatalogGroup(
    CatalogGroupKind.mesonCharmedStrange,
    '粲奇异介子',
    'Charmed, strange',
  ),
  CatalogGroup(CatalogGroupKind.mesonBottom, '底介子', 'Bottom'),
  CatalogGroup(CatalogGroupKind.mesonBottomStrange, '底奇异介子', 'Bottom, strange'),
  CatalogGroup(CatalogGroupKind.mesonBottomCharmed, '底粲介子', 'Bottom, charmed'),
  CatalogGroup(
    CatalogGroupKind.mesonCCbar,
    r'$c\bar{c}$（粲偶素）',
    r'$c\bar{c}$ (charmonium)',
  ),
  CatalogGroup(
    CatalogGroupKind.mesonBBbar,
    r'$b\bar{b}$（底偶素）',
    r'$b\bar{b}$ (bottomonium)',
  ),
  CatalogGroup(CatalogGroupKind.mesonOther, '其他介子', 'Other mesons'),
];

const _baryonGroups = <CatalogGroup>[
  CatalogGroup(CatalogGroupKind.baryonN, 'N', 'N'),
  CatalogGroup(CatalogGroupKind.baryonDelta, 'Δ', 'Delta'),
  CatalogGroup(CatalogGroupKind.baryonLambda, 'Λ', 'Lambda'),
  CatalogGroup(CatalogGroupKind.baryonSigma, 'Σ', 'Sigma'),
  CatalogGroup(CatalogGroupKind.baryonXi, 'Ξ', 'Xi'),
  CatalogGroup(CatalogGroupKind.baryonOmega, 'Ω', 'Omega'),
  CatalogGroup(CatalogGroupKind.baryonCharmed, '粲重子', 'Charmed'),
  CatalogGroup(CatalogGroupKind.baryonDoublyCharmed, '双粲重子', 'Doubly charmed'),
  CatalogGroup(CatalogGroupKind.baryonBottom, '底重子', 'Bottom'),
  CatalogGroup(CatalogGroupKind.baryonOther, '其他重子', 'Other baryons'),
];

List<CatalogGroup> catalogGroups(ParticleCategory category) =>
    switch (category) {
      ParticleCategory.meson => _mesonGroups,
      ParticleCategory.baryon => _baryonGroups,
      _ => const [],
    };

CatalogGroup? catalogGroupFor(Entry entry) {
  final category = categoryFromFlags(entry.flags)?.category;
  final desc = entry.description.trim();
  if (category == ParticleCategory.meson) {
    return _mesonGroup(desc);
  }
  if (category == ParticleCategory.baryon) {
    return _baryonGroup(desc);
  }
  return null;
}

CatalogGroup? _mesonGroup(String desc) {
  // Section headings are not particle names; match them before prefixes.
  if (desc == 'Charmonium') {
    return _group(CatalogGroupKind.mesonCCbar);
  }
  if (desc == 'Bottomonium') {
    return _group(CatalogGroupKind.mesonBBbar);
  }
  // Heavy-flavour subscripts precede the simpler D/B/K prefixes.
  if (desc.startsWith('D_s') || desc.startsWith('D_{s')) {
    return _group(CatalogGroupKind.mesonCharmedStrange);
  }
  if (desc.startsWith('D')) {
    return _group(CatalogGroupKind.mesonCharmed);
  }
  if (desc.startsWith('B_s') || desc.startsWith('B_{s')) {
    return _group(CatalogGroupKind.mesonBottomStrange);
  }
  if (desc.startsWith('B_c') || desc.startsWith('B_{c')) {
    return _group(CatalogGroupKind.mesonBottomCharmed);
  }
  if (desc.startsWith('B')) return _group(CatalogGroupKind.mesonBottom);
  if (desc.startsWith('K')) return _group(CatalogGroupKind.mesonStrange);

  if (desc.startsWith('eta_c') ||
      desc.startsWith('J/psi') ||
      desc.startsWith('psi') ||
      desc.startsWith('chi_c') ||
      desc.startsWith('h_c') ||
      desc.startsWith("psi'")) {
    return _group(CatalogGroupKind.mesonCCbar);
  }
  if (desc.startsWith('Upsilon') ||
      desc.startsWith('eta_b') ||
      desc.startsWith('chi_b') ||
      desc.startsWith('h_b')) {
    return _group(CatalogGroupKind.mesonBBbar);
  }
  if (desc.contains("psi's and chi's")) {
    return _group(CatalogGroupKind.mesonCCbar);
  }
  if (desc.toLowerCase().contains('b-flavored')) {
    return _group(CatalogGroupKind.mesonBottom);
  }

  const lightPrefixes = [
    'pi',
    'eta',
    'rho',
    'omega',
    'phi',
    'f_',
    'f(',
    'a_',
    'a(',
    'h_',
    'h(',
    'b_',
    'b(',
    'pi_',
    'eta_',
    'omega_',
    'rho_',
  ];
  if (lightPrefixes.any(desc.startsWith)) {
    return _group(CatalogGroupKind.mesonLight);
  }
  return _group(CatalogGroupKind.mesonOther);
}

CatalogGroup? _baryonGroup(String desc) {
  // Multi-heavy-flavour labels first.
  if (desc.startsWith('Xi_cc') || desc.startsWith('Xi_{cc')) {
    return _group(CatalogGroupKind.baryonDoublyCharmed);
  }
  if (desc.startsWith('Lambda_c') ||
      desc.startsWith('Sigma_c') ||
      desc.startsWith('Xi_c') ||
      desc.startsWith('Omega_c')) {
    return _group(CatalogGroupKind.baryonCharmed);
  }
  if (desc.startsWith('Lambda_b') ||
      desc.startsWith('Sigma_b') ||
      desc.startsWith('Xi_b') ||
      desc.startsWith('Omega_b')) {
    return _group(CatalogGroupKind.baryonBottom);
  }
  if (desc.startsWith('N')) return _group(CatalogGroupKind.baryonN);
  if (desc.startsWith('Delta')) return _group(CatalogGroupKind.baryonDelta);
  if (desc.startsWith('Lambda')) return _group(CatalogGroupKind.baryonLambda);
  if (desc.startsWith('Sigma')) return _group(CatalogGroupKind.baryonSigma);
  if (desc.startsWith('Xi')) return _group(CatalogGroupKind.baryonXi);
  if (desc.startsWith('Omega')) return _group(CatalogGroupKind.baryonOmega);
  return _group(CatalogGroupKind.baryonOther);
}

CatalogGroup _group(CatalogGroupKind kind) {
  for (final group in [..._mesonGroups, ..._baryonGroups]) {
    if (group.kind == kind) return group;
  }
  throw StateError('unknown catalog group $kind');
}

/// Topic/section roots have no particle identity row. PDG's flag column can
/// still say `M` (e.g. "V(cb) and V(ub) CKM Matrix Elements"), so particle
/// category membership requires an actual particle row.
/// PDG Live places a few topic tables in a different category than the
/// snapshot's category flag. Overrides are keyed by PDG ID so they stay
/// explicit and auditable.
const Map<String, ParticleCategory> catalogCategoryOverrides = {
  // CKM matrix elements are listed under Quarks on PDG Live; the snapshot
  // carries a meson flag on this row.
  'S052': ParticleCategory.quark,
};

ParticleCategory catalogCategoryForRoot(CatalogRoot root) {
  final override = catalogCategoryOverrides[root.entry.pdgid];
  if (override != null) return override;
  // The flags name the PDG category for every root, including sections that
  // have no particle identities of their own (Searches, Neutrino Properties,
  // ADMIXTURE sections). A particle-count guard used to send all of those to
  // "uncategorized", which emptied the Searches chip and hid real sections.
  return categoryFromFlags(root.entry.flags)?.category ??
      ParticleCategory.unknown;
}

CatalogGroup? catalogGroupForRoot(CatalogRoot root) {
  if (root.particleCount == 0) return null;
  return catalogGroupFor(root.entry);
}

/// Review PDFs shown by PDG Live's category-level "reviews" button.
const Map<ParticleCategory, List<String>> categoryReviewFiles = {
  ParticleCategory.gaugeHiggs: [
    'rpp2026-rev-w-mass.pdf',
    'rpp2026-rev-triple-gauge-couplings.pdf',
    'rpp2026-rev-wz-quartic-couplings.pdf',
    'rpp2026-rev-z-boson.pdf',
    'rpp2026-rev-anomalous-z-couplings.pdf',
    'rpp2026-rev-wprime-searches.pdf',
    'rpp2026-rev-zprime-searches.pdf',
    'rpp2026-rev-leptoquark-quantum-numbers.pdf',
    'rpp2026-rev-axions.pdf',
  ],
  ParticleCategory.lepton: [
    'rpp2026-rev-g-2-muon-anom-mag-moment.pdf',
    'rpp2026-rev-muon-decay-params.pdf',
    'rpp2026-rev-tau-branching-fractions.pdf',
    'rpp2026-rev-tau-lepton-decay-param.pdf',
    'rpp2026-rev-intro-neutrino-prop.pdf',
    'rpp2026-rev-sum-neutrino-masses.pdf',
    'rpp2026-rev-light-neutrino-types.pdf',
    'rpp2026-rev-neutrino-mixing.pdf',
    'rpp2026-rev-neutrino-prop-intro.pdf',
  ],
  ParticleCategory.quark: [
    'rpp2026-rev-quark-masses.pdf',
    'rpp2026-rev-top-quark.pdf',
    'rpp2026-rev-free-quark-searches.pdf',
  ],
  ParticleCategory.meson: [
    'rpp2026-rev-form-factors-radiative-pik-decays.pdf',
    'rpp2026-rev-scalar-mesons.pdf',
    'rpp2026-rev-light-mesons-spectroscopy.pdf',
    'rpp2026-rev-charged-kaon-mass.pdf',
    'rpp2026-rev-rare-kaon-decays.pdf',
    'rpp2026-rev-dalitz-params-k3pi-decays.pdf',
    'rpp2026-rev-cpt-invariance-tests.pdf',
    'rpp2026-rev-cp-viol-k0s3pi.pdf',
    'rpp2026-rev-vud-vus.pdf',
    'rpp2026-rev-cp-viol-kl-decays.pdf',
    'rpp2026-rev-ds-equal-dq-in-K0-decays.pdf',
    'rpp2026-rev-k892-mass.pdf',
    'rpp2026-rev-d-meson-dalitz-plot-analyses.pdf',
    'rpp2026-rev-d-dbar-mixing.pdf',
    'rpp2026-rev-pseudoscalar-meson-decay-cons.pdf',
    'rpp2026-rev-b-meson-prod-decay.pdf',
    'rpp2026-rev-hflav.pdf',
    'rpp2026-rev-b-decays-polarization.pdf',
    'rpp2026-rev-b-bar-mixing.pdf',
    'rpp2026-rev-vcb-vub.pdf',
    'rpp2026-rev-heavy-quarkonium-spectroscopy.pdf',
    'rpp2026-rev-charmonium.pdf',
    'rpp2026-rev-psi-chi-branching-ratios.pdf',
    'rpp2026-rev-upsilon-states-width.pdf',
    'rpp2026-rev-bottomonium.pdf',
  ],
  ParticleCategory.baryon: [
    'rpp2026-rev-baryon-semileptonic-decay.pdf',
    'rpp2026-rev-lam-1405-pole-struct.pdf',
    'rpp2026-rev-lambda-sigma-resonances.pdf',
    'rpp2026-rev-n-delta-resonances.pdf',
    'rpp2026-rev-pentaquarks.pdf',
    'rpp2026-rev-radiative-hyperon-decays.pdf',
    'rpp2026-rev-xi-resonances.pdf',
  ],
  ParticleCategory.search: [
    'rpp2026-rev-mag-monopole-searches.pdf',
    'rpp2026-rev-susy-1-theory.pdf',
    'rpp2026-rev-susy-2-experiment.pdf',
    'rpp2026-rev-intro-susy-model.pdf',
    'rpp2026-rev-technicolor.pdf',
    'rpp2026-rev-searches-quark-lep-compositeness.pdf',
    'rpp2026-rev-extra-dimensions.pdf',
    'rpp2026-rev-wimps-other-searches.pdf',
  ],
};

/// Exact review PDF linked by a PDG Live node. Kept separate from
/// [categoryReviewFiles] so a search/topic root is not mistaken for a particle
/// or duplicated as a separate review.
const Map<String, List<String>> entryReviewFiles = {
  'M209': ['rpp2026-rev-heavy-quarkonium-spectroscopy.pdf'],
  'S052': ['rpp2026-rev-vcb-vub.pdf'],
  'S056': [
    'rpp2026-rev-wprime-searches.pdf',
    'rpp2026-rev-zprime-searches.pdf',
  ],
  'S029': ['rpp2026-rev-axions.pdf'],
  'S043': [
    'rpp2026-rev-w-mass.pdf',
    'rpp2026-rev-triple-gauge-couplings.pdf',
    'rpp2026-rev-wz-quartic-couplings.pdf',
  ],
  'S044': ['rpp2026-rev-z-boson.pdf', 'rpp2026-rev-anomalous-z-couplings.pdf'],
  'S126': ['rpp2026-rev-higgs-boson.pdf'],
};
