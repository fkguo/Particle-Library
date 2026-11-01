import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/pdg_notes.dart';
import 'ui.dart';

/// Compact status mark for a particle listing.
///
/// Baryon listings show their published 1-4 stars; meson listings show the
/// pdgLive established bullet. A listing with no published mark renders
/// nothing, so callers can place this unconditionally in a Wrap.
class ParticleStatusChip extends StatelessWidget {
  const ParticleStatusChip(this.status, {super.key});

  final PdgParticleStatus? status;

  @override
  Widget build(BuildContext context) {
    final value = status;
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final strings = AppScope.of(context).strings;
    final tooltip = <String>[
      if (value.stars != null) strings.particleStatusStars(value.stars!),
      if (value.established) strings.particleStatusEstablished,
    ].join(' · ');
    final strong = (value.stars ?? 0) >= 3 || value.established;
    return MetaChip(
      value.marker,
      tone: strong ? BadgeTone.accent : BadgeTone.neutral,
      tooltip: tooltip,
    );
  }
}
