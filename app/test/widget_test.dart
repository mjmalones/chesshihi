import 'package:chesshihi/engine/fen.dart';
import 'package:chesshihi/engine/stockfish_service.dart';
import 'package:chesshihi/fair_play.dart';
import 'package:chesshihi/main.dart';
import 'package:chesshihi/vision/board_recognizer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows fair-play banner and brand', (tester) async {
    await tester.pumpWidget(const ChesshihiApp());
    await tester.pumpAndSettle();

    expect(find.text('Chesshihi'), findsOneWidget);
    expect(find.textContaining('not for live online'), findsWidgets);
    expect(find.text(fairPlayBanner), findsOneWidget);

    // ListView builds lazily — scroll to controls below the fold.
    await tester.scrollUntilVisible(
      find.text('Side to move'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Side to move'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Speak best move'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Speak best move'), findsOneWidget);
  });

  test('sample assets map to known FENs', () {
    final r = BoardRecognizer();
    final start = r.recognize(assetPath: 'assets/samples/starting_position.png');
    expect(start.fen, BoardRecognizer.startingFen);
    expect(start.isStub, isFalse);
    expect(FenPosition(start.fen).isWhiteToMove, isTrue);

    final italian = r.recognize(assetPath: 'assets/samples/italian_game.png');
    expect(italian.fen, BoardRecognizer.italianFen);
    expect(FenPosition(italian.fen).isWhiteToMove, isFalse);

    final stub = r.recognize(pickedLabel: 'photo.jpg');
    expect(stub.isStub, isTrue);
  });

  test('FenPosition can flip side to move', () {
    final start = FenPosition(BoardRecognizer.startingFen);
    expect(start.sideToMove, 'w');
    final black = FenPosition(start.withSideToMove('b'));
    expect(black.sideToMove, 'b');
    expect(black.sideToMoveLabel, 'Black to move');
    // Piece placement unchanged.
    expect(black.fen.split(' ').first, start.fen.split(' ').first);
  });

  test('Stockfish info parse + explanation mention side to move', () {
    const line =
        'info depth 12 score cp 34 nodes 1000 nps 1000 pv e2e4 e7e5 g1f3';
    final info = StockfishInfo.tryParse(line);
    expect(info, isNotNull);
    expect(info!.depth, 12);
    expect(info.scoreCp, 34);
    expect(info.pvUci.first, 'e2e4');

    final text = ExplainMove.compose(
      fen: BoardRecognizer.startingFen,
      bestMoveUci: 'e2e4',
      scoreCp: 34,
      mateIn: null,
      depth: 12,
      pvUci: info.pvUci,
      stub: false,
    );
    expect(text.toLowerCase(), contains('white to move'));
    expect(text, contains('e2e4'));
    expect(text, contains('depth 12'));
  });

  test('desktop analyze stub respects black to move', () async {
    final engine = StockfishService();
    final blackFen =
        FenPosition(BoardRecognizer.startingFen).withSideToMove('b');
    final result = await engine.analyze(blackFen);
    expect(result.stub, isTrue);
    expect(result.bestMoveUci, 'e7e5');
    expect(result.explanation.toLowerCase(), contains('black to move'));
    engine.dispose();
  });
}
