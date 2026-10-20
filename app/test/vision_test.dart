import 'dart:io';
import 'dart:typed_data';

import 'package:chesshihi/vision/board_recognizer.dart';
import 'package:chesshihi/vision/template_matcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late TemplateMatcherVision matcher;

  setUpAll(() async {
    matcher = TemplateMatcherVision();
    final dir = Directory('assets/templates');
    expect(dir.existsSync(), isTrue, reason: 'templates must be in app/assets');
    await matcher.loadTemplatesFromDirectory(dir);
  });

  test('recognizes starting position sample', () async {
    final bytes =
        await File('assets/samples/starting_position.png').readAsBytes();
    final board = await matcher.recognize(Uint8List.fromList(bytes));
    expect(board.placement, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR');
    expect(board.confidence, greaterThan(0.7));
    expect(board.backend, 'dart_template_match');
    expect(board.extras['orientation'], 'white_at_bottom');
  });

  test('recognizes Italian Game sample', () async {
    final bytes =
        await File('assets/samples/italian_game.png').readAsBytes();
    final board = await matcher.recognize(Uint8List.fromList(bytes));
    expect(
      board.placement,
      'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R',
    );
  });

  test('recognizes kings+queen endgame sample', () async {
    final bytes =
        await File('assets/samples/kings_queen_endgame.png').readAsBytes();
    final board = await matcher.recognize(Uint8List.fromList(bytes));
    expect(board.placement, '8/8/8/3k4/8/8/4K3/7Q');
  });

  test('BoardRecognizer facade builds FEN and reports failure clearly', () async {
    final recognizer = BoardRecognizer(backend: matcher);
    await recognizer.ensureReadyFromDirectory(Directory('assets/templates'));

    final ok = await recognizer.recognizeBytes(
      await File('assets/samples/starting_position.png').readAsBytes(),
      source: RecognitionSource.sampleAsset,
      sideToMove: 'b',
    );
    expect(ok.success, isTrue);
    expect(ok.fen, startsWith('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b '));
    expect(ok.isStub, isFalse);

    // No Chess.com-like square colors → clear board-not-found error.
    final blank = img.Image(width: 200, height: 200);
    img.fill(blank, color: img.ColorRgb8(10, 20, 30));
    final fail = await recognizer.recognizeBytes(
      Uint8List.fromList(img.encodePng(blank)),
      source: RecognitionSource.photo,
    );
    expect(fail.success, isFalse);
    expect(fail.fen, isNull);
    expect(fail.note.toLowerCase(), contains('board'));
  });

  test('placementFromRows round-trips empty and pieces', () {
    expect(
      placementFromRows([
        for (var r = 0; r < 8; r++) [for (var f = 0; f < 8; f++) ''],
      ]),
      '8/8/8/8/8/8/8/8',
    );
  });
}
