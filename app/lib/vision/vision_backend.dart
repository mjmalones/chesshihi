import 'dart:typed_data';

/// Pluggable pixels → board grid → piece classes interface.
///
/// Swap [TemplateMatcherVision] for an on-device ML backend later without
/// touching Stockfish, TTS, or the capture/analyze UI.
abstract class BoardVisionBackend {
  /// Locate an 8×8 board in [imageBytes] and classify pieces.
  ///
  /// Throws [BoardNotFoundException] when no plausible board ROI is found,
  /// or [BoardRecognitionException] when decode/classify fails hard.
  Future<VisionBoard> recognize(Uint8List imageBytes);
}

/// Raw vision output before FEN side-to-move / castling fields are applied.
class VisionBoard {
  const VisionBoard({
    required this.placement,
    required this.squareLabels,
    required this.confidence,
    required this.backend,
    this.boardBbox,
    this.extras = const {},
  });

  /// FEN piece-placement field only (rank 8 → rank 1).
  final String placement;

  /// 8×8 FEN letters or `''` for empty. Row 0 = rank 8.
  final List<List<String>> squareLabels;

  /// Mean per-square match score in \[0, 1\] (template NCC).
  final double confidence;

  /// Backend id, e.g. `dart_template_match`.
  final String backend;

  /// Board ROI in image coords: left, top, width, height.
  final ({int x, int y, int w, int h})? boardBbox;

  final Map<String, Object?> extras;
}

class BoardNotFoundException implements Exception {
  BoardNotFoundException([this.message = 'No chessboard found in the image.']);
  final String message;

  @override
  String toString() => message;
}

class BoardRecognitionException implements Exception {
  BoardRecognitionException(this.message);
  final String message;

  @override
  String toString() => message;
}
