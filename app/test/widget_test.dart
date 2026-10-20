import 'package:chesshihi/fair_play.dart';
import 'package:chesshihi/main.dart';
import 'package:chesshihi/vision/board_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows fair-play banner and brand', (tester) async {
    await tester.pumpWidget(const ChesshihiApp());
    await tester.pumpAndSettle();

    expect(find.text('Chesshihi'), findsOneWidget);
    expect(find.textContaining('not for live online'), findsWidgets);
    expect(find.text(fairPlayBanner), findsOneWidget);
  });

  test('sample assets map to known FENs', () {
    final r = BoardRecognizer();
    final start = r.recognize(assetPath: 'assets/samples/starting_position.png');
    expect(start.fen, BoardRecognizer.startingFen);
    expect(start.isStub, isFalse);

    final italian = r.recognize(assetPath: 'assets/samples/italian_game.png');
    expect(italian.fen, BoardRecognizer.italianFen);

    final stub = r.recognize(pickedLabel: 'photo.jpg');
    expect(stub.isStub, isTrue);
  });
}
