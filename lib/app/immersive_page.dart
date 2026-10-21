/// Marker for a page that wants the app's global top bar and bottom
/// navigation hidden while it is the top route of a tab, or the full-screen
/// detail pane on narrow layouts.
abstract interface class ImmersivePage {}

/// Marker for a page that implements its own text selection and must not
/// inherit the app-wide [SelectionArea].
abstract interface class NoGlobalSelection {}
