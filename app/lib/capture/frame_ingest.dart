import 'dart:io';

import '../vision/board_recognizer.dart';

/// Shared ingest path for Photos / camera / ReplayKit frames.
///
/// Runs on-device template-matching vision → FEN. Callers apply side-to-move
/// and feed [RecognitionResult] into the existing Stockfish analyze path.
class FrameIngest {
  FrameIngest({BoardRecognizer? recognizer})
      : _recognizer = recognizer ?? BoardRecognizer();

  final BoardRecognizer _recognizer;

  Future<RecognitionResult> recognizeFile(
    File file, {
    required String label,
    String sideToMove = 'w',
  }) {
    return _recognizer.recognizeFile(
      file,
      label: label,
      sideToMove: sideToMove,
    );
  }
}
