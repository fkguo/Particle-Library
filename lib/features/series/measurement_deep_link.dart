import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../domain/models.dart';
import '../common/async_view.dart';
import '../common/page.dart';
import '../common/ui.dart';
import '../entry/entry_route_page.dart';
import 'measurement_card.dart';

/// A direct route to one measurement, used by Evidence rows and captured
/// source links. It never guesses: a missing measurement shows the series-page
/// fallback instead.
class MeasurementDeepLinkPage extends StatefulWidget {
  const MeasurementDeepLinkPage({
    super.key,
    required this.pdgid,
    required this.measurementId,
  });

  final String pdgid;
  final int measurementId;

  @override
  State<MeasurementDeepLinkPage> createState() =>
      _MeasurementDeepLinkPageState();
}

class _MeasurementDeepLinkPageState extends State<MeasurementDeepLinkPage> {
  Future<MeasurementBundle?>? _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _future = _load();
  }

  Future<MeasurementBundle?> _load() async {
    final bundle = await AppScope.of(context).database
        .measurementById(widget.measurementId);
    if (bundle == null || bundle.measurement.pdgid != widget.pdgid) {
      return null;
    }
    return bundle;
  }

  void _retry() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    return PageScaffold(
      title: Text(
        widget.pdgid,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: strings.measurementNumber(widget.measurementId),
      actions: [
        IconButton(
          tooltip: strings.commonBack,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, size: 20),
        ),
      ],
      body: FutureBuilder<MeasurementBundle?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(Insets.l),
              child: LoadingPanel(compact: true),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(Insets.l),
              child: ErrorPanel(
                error: snapshot.error!,
                compact: true,
                onRetry: _retry,
              ),
            );
          }
          final bundle = snapshot.data;
          if (bundle == null) {
            return Padding(
              padding: const EdgeInsets.all(Insets.l),
              child: EmptyPanel(
                message: strings.notesEvidenceMissingSource,
                icon: Icons.search_off,
                action: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EntryRoutePage(pdgid: widget.pdgid),
                    ),
                  ),
                  child: Text(strings.commonDetails),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: Insets.xxl),
            children: [
              MeasurementCard(bundle: bundle, seriesLabel: widget.pdgid),
            ],
          );
        },
      ),
    );
  }
}
