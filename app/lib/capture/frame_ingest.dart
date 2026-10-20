import 'dart:io';

import '../vision/board_recognizer.dart';

/// Shared ingest path for Photos / camera / ReplayKit frames.
///
/// Vision may still return a stub FEN; callers apply side-to-move and feed
/// [RecognitionResult] into the existing Stockfish analyze path.
class FrameIngest {
  FrameIngest({BoardRecognizer? recognizer})
      : _recognizer = recognizer ?? BoardRecognizer();

  final BoardRecognizer _recognizer;

  RecognitionResult recognizeFile(File file, {required String label}) {
    return _recognizer.recognize(
      pickedLabel: label,
      imagePath: file.path,
    );
  }
}
