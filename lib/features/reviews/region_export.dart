import 'dart:io';

/// Where "Export Markdown" writes the note text and its region screenshot.
///
/// [chosenPath] is what the save dialog returned. The extension is matched
/// without regard to case (a dialog can hand back `X.MD`), and an existing
/// image beside the chosen file is never overwritten: the screenshot gets the
/// next free `-N` suffix instead.
({String markdown, String image}) regionExportPaths(
  String chosenPath, {
  bool Function(String path)? exists,
}) {
  final taken = exists ?? (path) => File(path).existsSync();
  final stem = chosenPath.toLowerCase().endsWith('.md')
      ? chosenPath.substring(0, chosenPath.length - 3)
      : chosenPath;
  var image = '$stem.png';
  for (var n = 1; taken(image); n++) {
    image = '$stem-$n.png';
  }
  return (markdown: '$stem.md', image: image);
}

/// The Markdown body for an exported region: the screenshot, then the comment.
///
/// The image name is percent-encoded, parentheses included, so a space or
/// bracket in the file name cannot end the link early.
String regionMarkdown({required String imageName, required String comment}) {
  final target = Uri.encodeComponent(imageName)
      .replaceAll('(', '%28')
      .replaceAll(')', '%29');
  final body = StringBuffer('![Region]($target)\n');
  final text = comment.trim();
  if (text.isNotEmpty) {
    body
      ..writeln()
      ..writeln(text);
  }
  return body.toString();
}
