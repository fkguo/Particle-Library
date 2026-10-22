/// One CSV field, quoted, and made safe to open in a spreadsheet.
///
/// Excel and LibreOffice evaluate a cell that starts with `=`, `@`, `+` or `-`
/// (and a tab or carriage return) as a formula even when it is quoted, and the
/// text in these files can come from imported notes. Such a cell gets a leading
/// apostrophe, which spreadsheets treat as "this is text".
///
/// A cell that starts with `+` or `-` and holds only digits and the signs used
/// in measurement values (`-0.71 ± 0.96`, `+0.3 -0.2`, `1.2e-3`) is left as it
/// is: without letters it cannot call a function, and PDG values are often
/// negative.
String csvCell(String value) {
  final safe = _needsGuard(value) ? "'$value" : value;
  return '"${safe.replaceAll('"', '""')}"';
}

final RegExp _numericText = RegExp(r'^[+\-][0-9.,\s eE±+\-−×()^%/]*$');

bool _needsGuard(String value) {
  if (value.isEmpty) return false;
  switch (value[0]) {
    case '=':
    case '@':
    case '\t':
    case '\r':
      return true;
    case '+':
    case '-':
      return !_numericText.hasMatch(value);
  }
  return false;
}
