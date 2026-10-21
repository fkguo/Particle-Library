import 'package:flutter/widgets.dart';

import '../core/errors.dart';
import '../data/pdg_database.dart';
import '../data/review_annotation_notes.dart';
import '../data/pdg_repository.dart';
import '../data/snapshot_store.dart';
import '../data/sql_executor.dart';
import '../notes/notes.dart';
import '../search/search_service.dart';
import '../user/user_store.dart';
import 'app_scope.dart';
import 'settings_controller.dart';

class AppBootstrap {
  static Future<AppServices> load({
    SnapshotStore? snapshotStore,
    String? userStoreOverridePath,
    String? notesStoreOverridePath,
    bool openNotes = true,
  }) async {
    final watch = Stopwatch()..start();
    debugPrint('BOOT 0ms start');
    final userStoreFuture = UserStore.open(overridePath: userStoreOverridePath);
    // Notes are opened in parallel but their failure is contained: the PDG
    // snapshot must keep working even when the notes database cannot open.
    final notesFuture = openNotes
        ? _openNotes(notesStoreOverridePath)
        : Future.value(const _NotesOpenResult(store: null, error: null));
    PreparedSnapshot? prepared;
    SqlExecutor? executor;
    try {
      prepared = await (snapshotStore ?? SnapshotStore()).prepare();
      debugPrint('BOOT snapshot ${watch.elapsedMilliseconds}ms');
      executor = await IsolateSqlExecutor.open(prepared.path);
      debugPrint('BOOT sql isolate ${watch.elapsedMilliseconds}ms');
      final database = await PdgDatabase.open(
        executor,
        snapshotHash: prepared.sha256,
        validateSchema: true,
        verifyIntegrity: false,
      );
      debugPrint('BOOT pdg ${watch.elapsedMilliseconds}ms');
      final userStore = await userStoreFuture;
      debugPrint('BOOT user store ${watch.elapsedMilliseconds}ms');
      final notesResult = await notesFuture;
      debugPrint('BOOT notes open ${watch.elapsedMilliseconds}ms');
      // A notes database with a newer/foreign schema is not an app failure;
      // its error state is surfaced on the Notes page instead.
      var notesStore = notesResult.store;
      var notesError = notesResult.error;
      if (notesStore == null) {
        debugPrint('Notes unavailable: $notesError');
      } else {
        // Cleanup is a notes-only write. A locked/corrupt/full notes DB must
        // not turn a healthy PDG startup into an app failure.
        try {
          await notesStore.cleanupLegacyMeasurementMarkers();
          await ReviewAnnotationNotes.ensureMigrated(notesStore);
          debugPrint('BOOT notes migrate ${watch.elapsedMilliseconds}ms');
        } catch (error) {
          debugPrint('Notes cleanup failed; disabling notes: $error');
          notesError = error;
          await notesStore.close();
          notesStore = null;
        }
      }
      final settings = SettingsController(
        userStore,
        systemLocale: WidgetsBinding.instance.platformDispatcher.locale,
      );
      debugPrint('BOOT total ${watch.elapsedMilliseconds}ms');
      final notesChanges = ValueNotifier<int>(0);
      return AppServices(
        database: database,
        repository: PdgRepository(database),
        search: SearchService(
          database,
          notes: notesStore,
          notesChanges: notesChanges,
          language: settings.language,
        ),
        userStore: userStore,
        settings: settings,
        snapshotHash: prepared.sha256,
        snapshotPath: prepared.path,
        copiedFromBundle: prepared.copiedFromBundle,
        notes: notesStore,
        notesError: notesError,
        notesChanges: notesChanges,
      );
    } catch (error) {
      final notesResult = await notesFuture;
      await notesResult.store?.close();
      await executor?.dispose();
      if (error is AppException) rethrow;
      throw AppException(AppErrorCode.queryFailed, '应用启动失败。', detail: '$error');
    }
  }

  static Future<_NotesOpenResult> _openNotes(String? overridePath) async {
    try {
      final store = await NotesStore.open(overridePath: overridePath);
      return _NotesOpenResult(store: store, error: null);
    } catch (error) {
      return _NotesOpenResult(store: null, error: error);
    }
  }
}

class _NotesOpenResult {
  const _NotesOpenResult({required this.store, required this.error});

  final NotesStore? store;
  final Object? error;
}
