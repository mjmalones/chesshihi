/// Board → FEN recognition.
///
/// TODO: Port the Python OpenCV template-matcher PoC
/// (`src/chesshihi/vision/template_matcher.py`) to Dart FFI / on-device ML.
/// Until then, known sample assets map to canned FENs; Photos picks use a
/// placeholder FEN so Stockfish + speech can still be exercised end-to-end.
class BoardRecognizer {
  static const startingFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  /// Italian Game sample from the Python PoC renderer.
  static const italianFen =
      'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 4';

  /// Placeholder when a real photo is selected — replace after vision port.
  static const placeholderFen =
      'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2';

  RecognitionResult recognize({
    String? assetPath,
    String? pickedLabel,
  }) {
    if (assetPath != null) {
      if (assetPath.contains('italian')) {
        return RecognitionResult(
          fen: italianFen,
          source: RecognitionSource.sampleAsset,
          note: 'Sample asset (Italian Game) — canned FEN from Python PoC.',
        );
      }
      if (assetPath.contains('starting')) {
        return RecognitionResult(
          fen: startingFen,
          source: RecognitionSource.sampleAsset,
          note: 'Sample asset (starting position) — canned FEN.',
        );
      }
    }

    return RecognitionResult(
      fen: placeholderFen,
      source: RecognitionSource.stub,
      note:
          'Stub FEN for Photos pick. TODO: port OpenCV PoC / on-device vision '
          'so this becomes a real recognition result.',
    );
  }
}

enum RecognitionSource { sampleAsset, stub }

class RecognitionResult {
  const RecognitionResult({
    required this.fen,
    required this.source,
    required this.note,
  });

  final String fen;
  final RecognitionSource source;
  final String note;

  bool get isStub => source == RecognitionSource.stub;
}
