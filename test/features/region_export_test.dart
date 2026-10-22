import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/features/reviews/region_export.dart';

void main() {
  group('regionExportPaths', () {
    test('puts the image beside the chosen Markdown file', () {
      final paths = regionExportPaths('/tmp/note.md', exists: (_) => false);
      expect(paths.markdown, '/tmp/note.md');
      expect(paths.image, '/tmp/note.png');
    });

    test('an upper-case extension never makes the image share the file', () {
      final paths = regionExportPaths('/tmp/NOTE.MD', exists: (_) => false);
      expect(paths.markdown, '/tmp/NOTE.md');
      expect(paths.image, '/tmp/NOTE.png');
      expect(paths.image, isNot(paths.markdown));
    });

    test('a name without extension gains .md', () {
      final paths = regionExportPaths('/tmp/note', exists: (_) => false);
      expect(paths.markdown, '/tmp/note.md');
      expect(paths.image, '/tmp/note.png');
    });

    test('an existing image is not overwritten', () {
      final taken = {'/tmp/note.png', '/tmp/note-1.png'};
      final paths = regionExportPaths('/tmp/note.md', exists: taken.contains);
      expect(paths.image, '/tmp/note-2.png');
      expect(paths.markdown, '/tmp/note.md');
    });
  });

  group('regionMarkdown', () {
    test('links the image and appends the comment', () {
      expect(
        regionMarkdown(imageName: 'a.png', comment: ' my comment \n'),
        '![Region](a.png)\n\nmy comment\n',
      );
    });

    test('escapes characters that would end the link', () {
      final text = regionMarkdown(imageName: 'my (note) 1.png', comment: '');
      expect(text, '![Region](my%20%28note%29%201.png)\n');
    });
  });
}
