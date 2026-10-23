import 'package:flutter/widgets.dart';

import '../data/pdg_database.dart';
import '../data/pdg_repository.dart';
import '../notes/notes.dart';
import '../search/review_search_service.dart';
import '../search/search_service.dart';
import '../user/user_store.dart';
import 'app_strings.dart';
import 'settings_controller.dart';

class AppServices {
  AppServices({
    required this.database,
    required this.repository,
    required this.search,
    required this.userStore,
    required this.settings,
    required this.snapshotHash,
    required this.snapshotPath,
    required this.copiedFromBundle,
    this.reviewSearch,
    this.notes,
    this.notesError,
    ValueNotifier<int>? notesChanges,
    ValueNotifier<int>? homeRequests,
    ValueNotifier<int>? noteRequests,
  }) : notesChanges = notesChanges ?? ValueNotifier<int>(0),
       homeRequests = homeRequests ?? ValueNotifier<int>(0),
       noteRequests = noteRequests ?? ValueNotifier<int>(0);

  final PdgDatabase database;
  final PdgRepository repository;
  final SearchService search;
  final UserStore userStore;
  final SettingsController settings;
  final String snapshotHash;
  final String snapshotPath;
  final bool copiedFromBundle;

  /// Lazily opened full-text index for the PDG reviews; `null` when the
  /// feature is disabled (for example in a widget test).
  final ReviewSearchService? reviewSearch;

  /// The local notes database, or `null` when it could not be opened.
  ///
  /// A notes failure never prevents the PDG snapshot from being used; the
  /// error is kept in [notesError] for the Notes page and for diagnostics.
  final NotesStore? notes;

  /// The error that prevented [notes] from opening, if any.
  final Object? notesError;

  /// Bumped after every note create/update/delete so note counts, lists and
  /// backlinks can refresh without a global database query on each rebuild.
  final ValueNotifier<int> notesChanges;

  /// Bumped by the Home actions. HomePage listens and resets its nested
  /// detail navigator/search without rebuilding the whole shell.
  final ValueNotifier<int> homeRequests;

  /// Bumped by the ⌘N shortcut to start a new note on the Notes tab.
  final ValueNotifier<int> noteRequests;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found above this context');
    return scope!;
  }

  static AppScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>();

  PdgRepository get repository => services.repository;
  PdgDatabase get database => services.database;
  SearchService get search => services.search;
  UserStore get store => services.userStore;
  SettingsController get settings => services.settings;
  AppStrings get strings => services.settings.strings;
  String get snapshotHash => services.snapshotHash;

  /// Local notes storage; `null` when the notes database failed to open.
  ReviewSearchService? get reviewSearch => services.reviewSearch;
  NotesStore? get notes => services.notes;

  /// The notes open failure, if any (never a reason to hide PDG data).
  Object? get notesError => services.notesError;

  /// Refreshes note lists/counts after a write.
  ValueNotifier<int> get notesChanges => services.notesChanges;

  /// Requests a reset to the main search page.
  ValueNotifier<int> get homeRequests => services.homeRequests;
  ValueNotifier<int> get noteRequests => services.noteRequests;

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    // This widget is rebuilt by the settings controller. The controller is
    // mutable, so comparing the old and new service objects cannot detect a
    // change; notify dependents whenever a new AppScope is installed.
    return true;
  }
}
