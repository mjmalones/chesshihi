import 'package:chesshihi/capture/replaykit_service.dart';
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
    await tester.scrollUntilVisible(
      find.text('Screen capture (ReplayKit)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Screen capture (ReplayKit)'), findsOneWidget);
    expect(find.textContaining('Control Center'), findsWidgets);
    expect(find.textContaining('cannot silently capture'), findsOneWidget);
  });

  test('FrameIngestPolicy skips identical and too-soon frames', () {
    const policy = FrameIngestPolicy(minInterval: Duration(milliseconds: 500));
    final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
    expect(
      policy.shouldIngest(
        candidateHash: 'abc',
        lastHash: null,
        lastIngestAt: null,
        now: t0,
      ),
      isTrue,
    );
    expect(
      policy.shouldIngest(
        candidateHash: 'abc',
        lastHash: 'abc',
        lastIngestAt: t0,
        now: t0.add(const Duration(seconds: 2)),
      ),
      isFalse,
    );
    expect(
      policy.shouldIngest(
        candidateHash: 'def',
        lastHash: 'abc',
        lastIngestAt: t0,
        now: t0.add(const Duration(milliseconds: 100)),
      ),
      isFalse,
    );
    expect(
      policy.shouldIngest(
        candidateHash: 'def',
        lastHash: 'abc',
        lastIngestAt: t0,
        now: t0.add(const Duration(milliseconds: 500)),
      ),
      isTrue,
    );
  });

  test('BroadcastState parses App Group payload', () {
    final state = BroadcastState.fromMap({
      'available': true,
      'appGroupReady': true,
      'status': 'started',
      'framePath': '/tmp/latest_frame.jpg',
      'updatedAtMs': 123,
      'contentHash': 'deadbeef',
      'frameCount': 4,
      'appGroupId': 'group.com.chesshihi.chesshihi',
    });
    expect(state.isBroadcasting, isTrue);
    expect(state.status.label, contains('Broadcasting'));
    expect(state.frameCount, 4);
    expect(state.appGroupId, 'group.com.chesshihi.chesshihi');
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
