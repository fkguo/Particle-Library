class ReviewEntry {
  const ReviewEntry(this.title, this.file);

  final String title;
  final String file;

  String get url => 'https://pdg.lbl.gov/2026/reviews/$file';
}

class ReviewGroup {
  const ReviewGroup(this.titleZh, this.titleEn, this.entries);

  final String titleZh;
  final String titleEn;
  final List<ReviewEntry> entries;
}

const reviewEdition = '2026';

const reviewGroups = <ReviewGroup>[
  ReviewGroup(
    '导论、历史图与在线信息',
    'Introduction, History plots, Online information',
    [
      ReviewEntry('Introduction', 'rpp2026-rev-rpp-intro.pdf'),
      ReviewEntry('Highlights', 'rpp2026-rev-highlights.pdf'),
      ReviewEntry('History plots', 'rpp2026-rev-history-plots.pdf'),
      ReviewEntry(
        'Online particle physics information',
        'rpp2026-rev-online-hep-info.pdf',
      ),
    ],
  ),
  ReviewGroup(
    '常数、单位与原子核性质',
    'Constants, Units, Atomic and Nuclear Properties',
    [
      ReviewEntry('Physical constants', 'rpp2026-rev-phys-constants.pdf'),
      ReviewEntry(
        'Astrophysical constants',
        'rpp2026-rev-astrophysical-constants.pdf',
      ),
      ReviewEntry(
        'International system of units (SI)',
        'rpp2026-rev-si-units.pdf',
      ),
      ReviewEntry(
        'Periodic table of the elements',
        'rpp2026-rev-periodic-table.pdf',
      ),
      ReviewEntry(
        'Electronic structure of the elements',
        'rpp2026-rev-elements-electronic-struct.pdf',
      ),
      ReviewEntry(
        'Atomic and nuclear properties of materials',
        'rpp2026-rev-atomic-nuclear-prop.pdf',
      ),
      ReviewEntry(
        'Electromagnetic relations',
        'rpp2026-rev-electromag-relations.pdf',
      ),
      ReviewEntry(
        'Naming scheme for hadrons',
        'rpp2026-rev-naming-scheme-hadrons.pdf',
      ),
    ],
  ),
  ReviewGroup('标准模型及相关', 'Standard Model and Related Topics', [
    ReviewEntry('Quantum chromodynamics', 'rpp2026-rev-qcd.pdf'),
    ReviewEntry(
      'Electroweak model and constraints on new physics',
      'rpp2026-rev-standard-model.pdf',
    ),
    ReviewEntry(
      'Higgs boson physics, status of',
      'rpp2026-rev-higgs-boson.pdf',
    ),
    ReviewEntry('CKM quark-mixing matrix', 'rpp2026-rev-ckm-matrix.pdf'),
    ReviewEntry(
      'CP violation in the quark sector',
      'rpp2026-rev-cp-violation.pdf',
    ),
    ReviewEntry(
      'Neutrino masses, mixing, and oscillations',
      'rpp2026-rev-neutrino-mixing.pdf',
    ),
    ReviewEntry('Quark model', 'rpp2026-rev-quark-model.pdf'),
    ReviewEntry(
      'Heavy-quark and soft-collinear effective theory',
      'rpp2026-rev-heavy-quark-eff-th.pdf',
    ),
    ReviewEntry(
      'Lattice quantum chromodynamics',
      'rpp2026-rev-lattice-qcd.pdf',
    ),
    ReviewEntry('Structure functions', 'rpp2026-rev-structure-functions.pdf'),
    ReviewEntry(
      'Fragmentation functions in e+ e-, ep, and pp collisions',
      'rpp2026-rev-frag-functions.pdf',
    ),
    ReviewEntry(
      'High energy soft QCD and diffraction',
      'rpp2026-rev-soft-qcd.pdf',
    ),
    ReviewEntry(
      'Tests of conservation laws',
      'rpp2026-rev-conservation-laws.pdf',
    ),
  ]),
  ReviewGroup('天体物理与宇宙学', 'Astrophysics and Cosmology', [
    ReviewEntry(
      'Experimental tests of gravitational theory',
      'rpp2026-rev-gravity-tests.pdf',
    ),
    ReviewEntry('Big-Bang cosmology', 'rpp2026-rev-bbang-cosmology.pdf'),
    ReviewEntry('Inflation', 'rpp2026-rev-inflation.pdf'),
    ReviewEntry(
      'Big-Bang nucleosynthesis',
      'rpp2026-rev-bbang-nucleosynthesis.pdf',
    ),
    ReviewEntry(
      'Cosmological parameters',
      'rpp2026-rev-cosmological-parameters.pdf',
    ),
    ReviewEntry(
      'Neutrinos in cosmology',
      'rpp2026-rev-neutrinos-in-cosmology.pdf',
    ),
    ReviewEntry('Dark matter', 'rpp2026-rev-dark-matter.pdf'),
    ReviewEntry('Dark energy', 'rpp2026-rev-dark-energy.pdf'),
    ReviewEntry(
      'Cosmic microwave background',
      'rpp2026-rev-cosmic-microwave-background.pdf',
    ),
    ReviewEntry('Cosmic rays', 'rpp2026-rev-cosmic-rays.pdf'),
  ]),
  ReviewGroup('实验方法与对撞机', 'Experimental Methods and Colliders', [
    ReviewEntry(
      'Accelerator physics of colliders',
      'rpp2026-rev-accel-phys-colliders.pdf',
    ),
    ReviewEntry(
      'High-energy collider parameters',
      'rpp2026-rev-hep-collider-params.pdf',
    ),
    ReviewEntry(
      'Neutrino beam lines at High-energy proton synchrotrons',
      'rpp2026-rev-nu-beams-parameters.pdf',
    ),
    ReviewEntry(
      'Passage of particles through matter',
      'rpp2026-rev-passage-particles-matter.pdf',
    ),
    ReviewEntry(
      'Particle detectors at accelerators',
      'rpp2026-rev-particle-detectors-accel.pdf',
    ),
    ReviewEntry(
      'Particle detectors for non-accelerator physics',
      'rpp2026-rev-particle-detectors-non-accel.pdf',
    ),
    ReviewEntry(
      'Radioactivity and radiation protection',
      'rpp2026-rev-radioactivity.pdf',
    ),
    ReviewEntry(
      'Commonly used radioactive sources',
      'rpp2026-rev-commonly-used-radioactive-sources.pdf',
    ),
  ]),
  ReviewGroup('数学工具', 'Mathematical Tools', [
    ReviewEntry('Probability', 'rpp2026-rev-probability.pdf'),
    ReviewEntry('Statistics', 'rpp2026-rev-statistics.pdf'),
    ReviewEntry('Machine Learning', 'rpp2026-rev-machine-learning.pdf'),
    ReviewEntry(
      'Monte Carlo techniques',
      'rpp2026-rev-monte-carlo-techniques.pdf',
    ),
    ReviewEntry('Monte Carlo event generators', 'rpp2026-rev-mc-event-gen.pdf'),
    ReviewEntry(
      'Monte Carlo neutrino generators',
      'rpp2026-rev-mc-nu-event-gen.pdf',
    ),
    ReviewEntry(
      'Monte Carlo particle numbering scheme',
      'rpp2026-rev-monte-carlo-numbering.pdf',
    ),
    ReviewEntry(
      'Clebsch-Gordan coeff., sph. harmonics, and d functions',
      'rpp2026-rev-clebsch-gordan-coefs.pdf',
    ),
    ReviewEntry(
      'SU(3) isoscalar factors and representation matrices',
      'rpp2026-rev-su3-isoscalar-factors.pdf',
    ),
    ReviewEntry(
      'SU(n) multiplets and Young diagrams',
      'rpp2026-rev-young-diagrams.pdf',
    ),
  ]),
  ReviewGroup('运动学、截面公式与图表', 'Kinematics, Cross-Section Formulae, and Plots', [
    ReviewEntry('Kinematics', 'rpp2026-rev-kinematics.pdf'),
    ReviewEntry('Resonances', 'rpp2026-rev-resonances.pdf'),
    ReviewEntry(
      'Cross-section formulae for specific processes',
      'rpp2026-rev-cross-section-formulae.pdf',
    ),
    ReviewEntry(
      'Neutrino cross section measurements',
      'rpp2026-rev-nu-cross-sections.pdf',
    ),
    ReviewEntry(
      'Plots of cross sections and related quantities',
      'rpp2026-rev-cross-section-plots.pdf',
    ),
  ]),
  ReviewGroup('规范玻色子', 'Gauge Bosons', [
    ReviewEntry('Mass and width of the W boson', 'rpp2026-rev-w-mass.pdf'),
    ReviewEntry(
      'Extraction of triple gauge couplings (TGC\'s)',
      'rpp2026-rev-triple-gauge-couplings.pdf',
    ),
    ReviewEntry(
      'Anomalous W/Z quartic couplings (QGCs)',
      'rpp2026-rev-wz-quartic-couplings.pdf',
    ),
    ReviewEntry('Z boson', 'rpp2026-rev-z-boson.pdf'),
    ReviewEntry(
      'Anomalous Z Z gamma, Z gamma gamma, and Z Z V couplings',
      'rpp2026-rev-anomalous-z-couplings.pdf',
    ),
  ]),
  ReviewGroup('带电轻子', 'Charged Leptons', [
    ReviewEntry(
      'Muon anomalous magnetic moment',
      'rpp2026-rev-g-2-muon-anom-mag-moment.pdf',
    ),
    ReviewEntry('Muon decay parameters', 'rpp2026-rev-muon-decay-params.pdf'),
    ReviewEntry(
      'tau branching fractions',
      'rpp2026-rev-tau-branching-fractions.pdf',
    ),
    ReviewEntry(
      'tau-lepton decay parameters',
      'rpp2026-rev-tau-lepton-decay-param.pdf',
    ),
  ]),
  ReviewGroup('中微子', 'Neutrinos', [
    ReviewEntry(
      'Number of light neutrino types from collider experiments',
      'rpp2026-rev-light-neutrino-types.pdf',
    ),
    ReviewEntry('Neutrino properties', 'rpp2026-rev-intro-neutrino-prop.pdf'),
    ReviewEntry(
      'Sum of neutrino masses',
      'rpp2026-rev-sum-neutrino-masses.pdf',
    ),
    ReviewEntry(
      'Introductory text to neutrino mixing',
      'rpp2026-rev-neutrino-prop-intro.pdf',
    ),
  ]),
  ReviewGroup('夸克', 'Quarks', [
    ReviewEntry('Quark masses', 'rpp2026-rev-quark-masses.pdf'),
    ReviewEntry('Top quark', 'rpp2026-rev-top-quark.pdf'),
    ReviewEntry('Free quark searches', 'rpp2026-rev-free-quark-searches.pdf'),
  ]),
  ReviewGroup('介子', 'Mesons', [
    ReviewEntry(
      'Form factors for semileptonic kaon, radiative pion and kaon decays',
      'rpp2026-rev-form-factors-radiative-pik-decays.pdf',
    ),
    ReviewEntry(
      'Spectroscopy of Light Meson Resonances',
      'rpp2026-rev-light-mesons-spectroscopy.pdf',
    ),
    ReviewEntry('Scalar mesons below 1 GeV', 'rpp2026-rev-scalar-mesons.pdf'),
    ReviewEntry('Charged kaon mass', 'rpp2026-rev-charged-kaon-mass.pdf'),
    ReviewEntry('Rare kaon decays', 'rpp2026-rev-rare-kaon-decays.pdf'),
    ReviewEntry(
      'Dalitz plot parameters for K --> 3 pi decays',
      'rpp2026-rev-dalitz-params-k3pi-decays.pdf',
    ),
    ReviewEntry(
      'CPT invariance tests in neutral kaon decay',
      'rpp2026-rev-cpt-invariance-tests.pdf',
    ),
    ReviewEntry(
      'CP -violation in K S -> 3pi',
      'rpp2026-rev-cp-viol-k0s3pi.pdf',
    ),
    ReviewEntry(
      'V(ud), V(us), Cabibbo angle, and CKM unitarity',
      'rpp2026-rev-vud-vus.pdf',
    ),
    ReviewEntry(
      'CP -violation in K L decays',
      'rpp2026-rev-cp-viol-kl-decays.pdf',
    ),
    ReviewEntry(
      'Delta S = Delta Q in K0 decays',
      'rpp2026-rev-ds-equal-dq-in-K0-decays.pdf',
    ),
    ReviewEntry(
      'K*(892) masses and mass differences',
      'rpp2026-rev-k892-mass.pdf',
    ),
    ReviewEntry(
      'Review of multibody charm analyses',
      'rpp2026-rev-d-meson-dalitz-plot-analyses.pdf',
    ),
    ReviewEntry(r'$D_0$–$\bar{D}_0$ mixing', 'rpp2026-rev-d-dbar-mixing.pdf'),
    ReviewEntry(
      'Leptonic decays of charged pseudoscalar mesons',
      'rpp2026-rev-pseudoscalar-meson-decay-cons.pdf',
    ),
    ReviewEntry(
      'Production and decay of b-flavored hadrons',
      'rpp2026-rev-b-meson-prod-decay.pdf',
    ),
    ReviewEntry('Heavy Flavor Averaging Group', 'rpp2026-rev-hflav.pdf'),
    ReviewEntry(
      'Polarization in B decays',
      'rpp2026-rev-b-decays-polarization.pdf',
    ),
    ReviewEntry(r'$B_0$–$\bar{B}_0$ mixing', 'rpp2026-rev-b-bar-mixing.pdf'),
    ReviewEntry(
      'Semileptonic B-hadron decays, determination of V(cb), V(ub)',
      'rpp2026-rev-vcb-vub.pdf',
    ),
    ReviewEntry(
      'CKM angles from B hadrons, Determination of',
      'rpp2026-rev-ckm-angles.pdf',
    ),
    ReviewEntry(
      'Spectroscopy of mesons containing two heavy quarks',
      'rpp2026-rev-heavy-quarkonium-spectroscopy.pdf',
    ),
    ReviewEntry('Charmonium system', 'rpp2026-rev-charmonium.pdf'),
    ReviewEntry(
      'Branching ratios of psi(2S), chi_c(0,1,2) and eta_c(1S)',
      'rpp2026-rev-psi-chi-branching-ratios.pdf',
    ),
    ReviewEntry('Bottomonium system', 'rpp2026-rev-bottomonium.pdf'),
    ReviewEntry(
      'Width determination of the upsilon states',
      'rpp2026-rev-upsilon-states-width.pdf',
    ),
    ReviewEntry('Heavy non q-qbar mesons', 'rpp2026-rev-non-qqbar-mesons.pdf'),
  ]),
  ReviewGroup('重子', 'Baryons', [
    ReviewEntry(
      'Baryon decay parameters',
      'rpp2026-rev-baryon-semileptonic-decay.pdf',
    ),
    ReviewEntry('N and Delta resonances', 'rpp2026-rev-n-delta-resonances.pdf'),
    ReviewEntry(
      'Lambda and Sigma resonances',
      'rpp2026-rev-lambda-sigma-resonances.pdf',
    ),
    ReviewEntry(
      'Pole structure of the Lambda(1405) region',
      'rpp2026-rev-lam-1405-pole-struct.pdf',
    ),
    ReviewEntry(
      'Radiative hyperon decays',
      'rpp2026-rev-radiative-hyperon-decays.pdf',
    ),
    ReviewEntry('Xi and Omega resonances', 'rpp2026-rev-xi-resonances.pdf'),
    ReviewEntry('Pentaquarks', 'rpp2026-rev-pentaquarks.pdf'),
  ]),
  ReviewGroup('假想粒子与概念', 'Hypothetical Particles and Concepts', [
    ReviewEntry(
      'Extra dimensions searches',
      'rpp2026-rev-extra-dimensions.pdf',
    ),
    ReviewEntry('W\'-boson searches', 'rpp2026-rev-wprime-searches.pdf'),
    ReviewEntry('Z\'-boson searches', 'rpp2026-rev-zprime-searches.pdf'),
    ReviewEntry('Supersymmetry: theory', 'rpp2026-rev-susy-1-theory.pdf'),
    ReviewEntry(
      'Supersymmetry: experiment',
      'rpp2026-rev-susy-2-experiment.pdf',
    ),
    ReviewEntry(
      'Supersymmetric model assumptions',
      'rpp2026-rev-intro-susy-model.pdf',
    ),
    ReviewEntry(
      'Other particle searches',
      'rpp2026-rev-wimps-other-searches.pdf',
    ),
    ReviewEntry('Axions and other similar particles', 'rpp2026-rev-axions.pdf'),
    ReviewEntry(
      'Quark and lepton compositeness, searches for',
      'rpp2026-rev-searches-quark-lep-compositeness.pdf',
    ),
    ReviewEntry(
      'Dynamical electroweak symmetry breaking: implications of the H(0)',
      'rpp2026-rev-technicolor.pdf',
    ),
    ReviewEntry('Grand unified theories', 'rpp2026-rev-guts.pdf'),
    ReviewEntry('Leptoquarks', 'rpp2026-rev-leptoquark-quantum-numbers.pdf'),
    ReviewEntry('Magnetic monopoles', 'rpp2026-rev-mag-monopole-searches.pdf'),
  ]),
];

ReviewEntry? reviewEntryForFile(String file) {
  final name = file.trim();
  if (name.isEmpty) return null;
  for (final group in reviewGroups) {
    for (final entry in group.entries) {
      if (entry.file == name) return entry;
    }
  }
  return null;
}
