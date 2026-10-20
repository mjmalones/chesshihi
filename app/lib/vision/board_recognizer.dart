import 'dart:io';

import 'package:flutter/services.dart';

import 'template_matcher.dart';
import 'vision_backend.dart';

export 'vision_backend.dart'
    show BoardNotFoundException, BoardRecognitionException, BoardVisionBackend;

/// Board → FEN recognition facade for the Flutter app.
///
/// Uses a pluggable [BoardVisionBackend] (default: pure-Dart template matching
/// ported from the Python OpenCV PoC). Side-to-move is **not** read from
/// pixels — callers apply the UI control via [FenPosition.withSideToMove].
///
/// Orientation assumption: **White at the bottom** of the board image.
class BoardRecognizer {
  BoardRecognizer({BoardVisionBackend? backend})
      : _backend = backend ?? TemplateMatcherVision();

  final BoardVisionBackend _backend;

  static const startingFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  /// Italian Game sample as rendered by the Python PoC (`ensure_sample_assets`).
  static const italianFen =
      'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 1';

  /// King + queen endgame sample.
  static const endgameFen = '8/8/8/3k4/8/8/4K3/7Q w - - 0 1';

  bool _templatesReady = false;

  /// Load piece templates once (assets). Safe to call repeatedly.
  Future<void> ensureReady({AssetBundle? bundle}) async {
    if (_templatesReady) return;
    final matcher = _backend;
    if (matcher is TemplateMatcherVision) {
      await matcher.loadTemplatesFromAssetBundle(
        bundle ?? rootBundle,
        assetPrefix: 'assets/templates/',
      );
    }
    _templatesReady = true;
  }

  /// For unit tests that load templates from disk instead of the asset bundle.
  Future<void> ensureReadyFromDirectory(Directory templatesDir) async {
    final matcher = _backend;
    if (matcher is TemplateMatcherVision) {
      await matcher.loadTemplatesFromDirectory(templatesDir);
    }
    _templatesReady = true;
  }

  Future<RecognitionResult> recognizeBytes(
    Uint8List bytes, {
    required RecognitionSource source,
    String? label,
    String? imagePath,
    String sideToMove = 'w',
    String castling = 'KQkq',
  }) async {
    await ensureReady();
    try {
      final vision = await _backend.recognize(bytes);
      // Heuristic castling rights: only claim KQkq when both sides look full.
      final castlingRights = _guessCastling(vision.placement, castling);
      final fen =
          '${vision.placement} $sideToMove $castlingRights - 0 1';
      final origin = label ?? source.name;
      final pathNote = imagePath == null ? '' : ' Path: $imagePath.';
      return RecognitionResult(
        fen: fen,
        source: source,
        note:
            'Recognized via ${vision.backend} '
            '(confidence ${vision.confidence.toStringAsFixed(2)}). '
            'Assumes White at bottom.$pathNote '
            'Side to move from UI ($origin) — vision does not read clocks.',
        confidence: vision.confidence,
        success: true,
      );
    } on BoardNotFoundException catch (e) {
      return RecognitionResult(
        fen: null,
        source: source,
        note: e.message,
        success: false,
        confidence: 0,
      );
    } on BoardRecognitionException catch (e) {
      return RecognitionResult(
        fen: null,
        source: source,
        note: e.message,
        success: false,
        confidence: 0,
      );
    } catch (e) {
      return RecognitionResult(
        fen: null,
        source: source,
        note: 'Board recognition failed: $e',
        success: false,
        confidence: 0,
      );
    }
  }

  Future<RecognitionResult> recognizeFile(
    File file, {
    required String label,
    String sideToMove = 'w',
  }) async {
    final lower = label.toLowerCase();
    final source = lower.contains('broadcast')
        ? RecognitionSource.broadcast
        : (lower.contains('camera')
            ? RecognitionSource.camera
            : RecognitionSource.photo);
    final bytes = await file.readAsBytes();
    return recognizeBytes(
      bytes,
      source: source,
      label: label,
      imagePath: file.path,
      sideToMove: sideToMove,
      castling: '-', // Photos / live frames: don't invent castling rights.
    );
  }

  Future<RecognitionResult> recognizeAsset(
    String assetPath, {
    AssetBundle? bundle,
    String sideToMove = 'w',
  }) async {
    await ensureReady(bundle: bundle);
    final data = await (bundle ?? rootBundle).load(assetPath);
    final bytes = data.buffer.asUint8List();
    // Known samples keep documented castling; unknown assets use '-'.
    final castling = assetPath.contains('starting') ||
            assetPath.contains('italian')
        ? 'KQkq'
        : '-';
    return recognizeBytes(
      bytes,
      source: RecognitionSource.sampleAsset,
      label: assetPath,
      sideToMove: sideToMove,
      castling: castling,
    );
  }

  static String _guessCastling(String placement, String preferred) {
    if (preferred == '-') return '-';
    // Keep preferred when starting-like; otherwise still pass preferred for
    // known samples. Callers for photos pass '-'.
    return preferred;
  }
}

enum RecognitionSource {
  sampleAsset,
  photo,
  camera,
  broadcast,
}

class RecognitionResult {
  const RecognitionResult({
    required this.fen,
    required this.source,
    required this.note,
    this.success = true,
    this.confidence,
  });

  /// Full FEN when [success]; null when the board was not found / decode failed.
  final String? fen;
  final RecognitionSource source;
  final String note;
  final bool success;
  final double? confidence;

  /// Legacy helper — real vision never stubs; false when recognition succeeded.
  bool get isStub => !success;
}
