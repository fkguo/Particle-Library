/// Build identification injected with `--dart-define` by the release/build
/// scripts. Empty for ordinary `flutter run`/`flutter test` builds.
const String buildStamp = String.fromEnvironment('PDG_BUILD_STAMP');

/// Short commit hash injected alongside [buildStamp].
const String buildCommit = String.fromEnvironment('PDG_BUILD_COMMIT');

/// Human-readable build label, e.g. `10-22 09:30 (a584be0)`.
String get buildLabel {
  if (buildStamp.isEmpty) return '';
  if (buildCommit.isEmpty) return buildStamp;
  return '$buildStamp ($buildCommit)';
}
