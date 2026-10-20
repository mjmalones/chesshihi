import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:image/image.dart' as img;

import 'vision_backend.dart';

/// Chess.com-ish square palette used by the Python PoC renderer.
const List<int> kLightSqRgb = [240, 217, 181];
const List<int> kDarkSqRgb = [181, 136, 99];

const List<String> kAllPieces = [
  'K',
  'Q',
  'R',
  'B',
  'N',
  'P',
  'k',
  'q',
  'r',
  'b',
  'n',
  'p',
];

/// Pure-Dart port of `src/chesshihi/vision/template_matcher.py`.
///
/// Uses `package:image` (no OpenCV / native FFI) so Codemagic unsigned IPA
/// and sideload signing stay unchanged — no new native deps.
///
/// Orientation: assumes **White at the bottom** of the board ROI (a1 =
/// bottom-left from White's perspective). Flip / Black-at-bottom is not
/// auto-detected; set Side to move in the UI separately (vision does not
/// read clocks).
class TemplateMatcherVision implements BoardVisionBackend {
  TemplateMatcherVision({
    this.matchThreshold = 0.45,
    this.colorDistance = 45.0,
    this.emptyStdDev = 12.0,
  });

  final double matchThreshold;
  final double colorDistance;
  final double emptyStdDev;

  /// label → shade (`light`/`dark`) → grayscale luminance bytes (row-major).
  Map<String, Map<String, _GrayImage>>? _templates;

  bool get isReady => _templates != null;

  /// Load piece templates from a directory (tests / tooling).
  Future<void> loadTemplatesFromDirectory(Directory dir) async {
    final loaded = <String, Map<String, _GrayImage>>{
      for (final p in kAllPieces) p: {},
      '': {},
    };
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.png')) {
        continue;
      }
      final bytes = await entity.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) continue;
      final stem = entity.uri.pathSegments.last.replaceAll('.png', '');
      _ingestTemplate(loaded, stem, decoded);
    }
    _ensureTemplates(loaded);
    _templates = loaded;
  }

  /// Load templates shipped as Flutter assets under [assetPrefix].
  Future<void> loadTemplatesFromAssetBundle(
    AssetBundle bundle, {
    String assetPrefix = 'assets/templates/',
  }) async {
    final loaded = <String, Map<String, _GrayImage>>{
      for (final p in kAllPieces) p: {},
      '': {},
    };
    const stems = <String>[
      'empty_light',
      'empty_dark',
      'wK_light',
      'wK_dark',
      'wQ_light',
      'wQ_dark',
      'wR_light',
      'wR_dark',
      'wB_light',
      'wB_dark',
      'wN_light',
      'wN_dark',
      'wP_light',
      'wP_dark',
      'bK_light',
      'bK_dark',
      'bQ_light',
      'bQ_dark',
      'bR_light',
      'bR_dark',
      'bB_light',
      'bB_dark',
      'bN_light',
      'bN_dark',
      'bP_light',
      'bP_dark',
    ];
    for (final stem in stems) {
      final key = '$assetPrefix$stem.png';
      final data = await bundle.load(key);
      final bytes = data.buffer.asUint8List();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw BoardRecognitionException('Could not decode template $key');
      }
      _ingestTemplate(loaded, stem, decoded);
    }
    _ensureTemplates(loaded);
    _templates = loaded;
  }

  static void _ingestTemplate(
    Map<String, Map<String, _GrayImage>> loaded,
    String stem,
    img.Image decoded,
  ) {
    final gray = _GrayImage.fromImage(decoded);
    if (stem.startsWith('empty_')) {
      final shade = stem.substring('empty_'.length);
      loaded['']![shade] = gray;
      return;
    }
    final parts = stem.split('_');
    if (parts.length < 2) return;
    final prefix = parts[0];
    final shade = parts.sublist(1).join('_');
    if (prefix.length != 2 || (prefix[0] != 'w' && prefix[0] != 'b')) return;
    final piece =
        prefix[0] == 'w' ? prefix[1].toUpperCase() : prefix[1].toLowerCase();
    if (!loaded.containsKey(piece)) return;
    loaded[piece]![shade] = gray;
  }

  static void _ensureTemplates(Map<String, Map<String, _GrayImage>> loaded) {
    final anyPiece = kAllPieces.any((p) => loaded[p]?.isNotEmpty ?? false);
    if (!anyPiece) {
      throw BoardRecognitionException('No piece templates loaded');
    }
  }

  @override
  Future<VisionBoard> recognize(Uint8List imageBytes) async {
    final templates = _templates;
    if (templates == null) {
      throw BoardRecognitionException(
        'Templates not loaded — call loadTemplatesFromAssetBundle first.',
      );
    }
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw BoardRecognitionException('Could not decode image bytes');
    }
    // Work in opaque RGB (drop alpha) for stable color distances.
    var rgb = decoded.numChannels == 3
        ? decoded
        : decoded.convert(numChannels: 3);

    // Latency: shrink huge ReplayKit / camera frames before ROI search.
    const maxSide = 960;
    final scale = math.max(rgb.width, rgb.height) > maxSide
        ? maxSide / math.max(rgb.width, rgb.height)
        : 1.0;
    if (scale < 1.0) {
      rgb = img.copyResize(
        rgb,
        width: (rgb.width * scale).round(),
        height: (rgb.height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }

    final bbox = _findBoard(rgb);
    if (bbox == null) {
      throw BoardNotFoundException(
        'No chessboard found (expected Chess.com-like light/dark squares, '
        'White at bottom). Themes, animations, and move highlights can hide '
        'the board from this template matcher.',
      );
    }

    final board = img.copyCrop(
      rgb,
      x: bbox.x,
      y: bbox.y,
      width: bbox.w,
      height: bbox.h,
    );
    final labelsAndScore = _classifyBoard(board, templates);
    final placement = placementFromRows(labelsAndScore.labels);

    return VisionBoard(
      placement: placement,
      squareLabels: labelsAndScore.labels,
      confidence: labelsAndScore.score,
      backend: 'dart_template_match',
      boardBbox: bbox,
      extras: const {
        'orientation': 'white_at_bottom',
        'sideToMove': 'not_detected_use_ui',
      },
    );
  }

  ({int x, int y, int w, int h})? _findBoard(img.Image bgrOrRgb) {
    final w = bgrOrRgb.width;
    final h = bgrOrRgb.height;
    if (w < 64 || h < 64) return null;

    // Mask pixels near the known light/dark square palette.
    final mask = List<bool>.filled(w * h, false);
    var matchCount = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = bgrOrRgb.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        final dLight = _colorDist(r, g, b, kLightSqRgb);
        final dDark = _colorDist(r, g, b, kDarkSqRgb);
        if (dLight < colorDistance || dDark < colorDistance) {
          mask[y * w + x] = true;
          matchCount++;
        }
      }
    }
    // Require a meaningful amount of Chess.com-like square color. Without it
    // we refuse rather than inventing a FEN from a centered crop of UI chrome.
    if (matchCount < 64 * 16) {
      return null;
    }

    // Light morphology: close gaps from pieces (3×3 dilate then erode).
    final closed = _morphClose(mask, w, h, radius: 3);

    // Bounding box of remaining mask; prefer nearly-square region.
    var minX = w;
    var minY = h;
    var maxX = 0;
    var maxY = 0;
    var on = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!closed[y * w + x]) continue;
        on++;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
    if (on < 64 * 16) return null;

    final bw = maxX - minX + 1;
    final bh = maxY - minY + 1;
    final aspect = bw / math.max(bh, 1);
    if (bw >= 64 && bh >= 64 && aspect >= 0.85 && aspect <= 1.15) {
      return (x: minX, y: minY, w: bw, h: bh);
    }
    // Mask found square colors but aspect is off (letterboxing) — centered crop.
    return _centeredSquare(w, h);
  }

  static ({int x, int y, int w, int h}) _centeredSquare(int w, int h) {
    final side = (math.min(w, h) * 0.82).round();
    final x = (w - side) ~/ 2;
    final y = (h - side) ~/ 2;
    return (x: x, y: y, w: side, h: side);
  }

  static List<bool> _morphClose(
    List<bool> mask,
    int w,
    int h, {
    required int radius,
  }) {
    final dil = _dilate(mask, w, h, radius);
    return _erode(dil, w, h, radius);
  }

  static List<bool> _dilate(List<bool> mask, int w, int h, int radius) {
    final out = List<bool>.filled(w * h, false);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var any = false;
        for (var dy = -radius; dy <= radius && !any; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            final xx = x + dx;
            final yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            if (mask[yy * w + xx]) {
              any = true;
              break;
            }
          }
        }
        out[y * w + x] = any;
      }
    }
    return out;
  }

  static List<bool> _erode(List<bool> mask, int w, int h, int radius) {
    final out = List<bool>.filled(w * h, false);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var all = true;
        for (var dy = -radius; dy <= radius && all; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            final xx = x + dx;
            final yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) {
              all = false;
              break;
            }
            if (!mask[yy * w + xx]) {
              all = false;
              break;
            }
          }
        }
        out[y * w + x] = all;
      }
    }
    return out;
  }

  ({List<List<String>> labels, double score}) _classifyBoard(
    img.Image board,
    Map<String, Map<String, _GrayImage>> templates,
  ) {
    final h = board.height;
    final w = board.width;
    final cellH = h / 8.0;
    final cellW = w / 8.0;
    final labels = <List<String>>[];
    final scores = <double>[];
    for (var rank = 0; rank < 8; rank++) {
      final row = <String>[];
      for (var file = 0; file < 8; file++) {
        final y0 = (rank * cellH).round();
        final x0 = (file * cellW).round();
        final y1 = ((rank + 1) * cellH).round();
        final x1 = ((file + 1) * cellW).round();
        final cell = img.copyCrop(
          board,
          x: x0,
          y: y0,
          width: math.max(1, x1 - x0),
          height: math.max(1, y1 - y0),
        );
        final classified = _classifyCell(cell, templates);
        row.add(classified.label);
        scores.add(classified.score);
      }
      labels.add(row);
    }
    final mean =
        scores.isEmpty ? 0.0 : scores.reduce((a, b) => a + b) / scores.length;
    return (labels: labels, score: mean);
  }

  ({String label, double score}) _classifyCell(
    img.Image cell,
    Map<String, Map<String, _GrayImage>> templates,
  ) {
    final gray = _GrayImage.fromImage(cell);
    if (gray.stdDev() < emptyStdDev) {
      return (label: '', score: 1.0);
    }
    final shade = _squareShade(cell);
    var bestLabel = '';
    var bestScore = -1.0;
    for (final label in kAllPieces) {
      final byShade = templates[label];
      if (byShade == null || byShade.isEmpty) continue;
      var tmpl = byShade[shade];
      tmpl ??= byShade.values.first;
      final score = _ncc(gray, tmpl);
      if (score > bestScore) {
        bestScore = score;
        bestLabel = label;
      }
    }
    if (bestScore < matchThreshold) {
      return (label: '', score: bestScore);
    }
    return (label: bestLabel, score: bestScore);
  }

  String _squareShade(img.Image cell) {
    var rSum = 0.0;
    var gSum = 0.0;
    var bSum = 0.0;
    final n = cell.width * cell.height;
    for (var y = 0; y < cell.height; y++) {
      for (var x = 0; x < cell.width; x++) {
        final p = cell.getPixel(x, y);
        rSum += p.r.toDouble();
        gSum += p.g.toDouble();
        bSum += p.b.toDouble();
      }
    }
    final r = rSum / n;
    final g = gSum / n;
    final b = bSum / n;
    final dLight = _colorDist(r, g, b, kLightSqRgb);
    final dDark = _colorDist(r, g, b, kDarkSqRgb);
    return dLight <= dDark ? 'light' : 'dark';
  }

  static double _colorDist(double r, double g, double b, List<int> rgb) {
    final dr = r - rgb[0];
    final dg = g - rgb[1];
    final db = b - rgb[2];
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  static double _ncc(_GrayImage cell, _GrayImage tmpl) {
    final th = cell.height;
    final tw = cell.width;
    if (th < 8 || tw < 8) return -1.0;
    final resized = tmpl.resized(tw, th);
    final a = cell.pixels;
    final b = resized.pixels;
    final n = a.length;
    var meanA = 0.0;
    var meanB = 0.0;
    for (var i = 0; i < n; i++) {
      meanA += a[i];
      meanB += b[i];
    }
    meanA /= n;
    meanB /= n;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < n; i++) {
      final da = a[i] - meanA;
      final db = b[i] - meanB;
      dot += da * db;
      normA += da * da;
      normB += db * db;
    }
    final denom = math.sqrt(normA * normB);
    if (denom < 1e-6) return 0.0;
    return dot / denom;
  }
}

/// Collapse 8×8 labels into FEN placement (rank 8 → rank 1).
String placementFromRows(List<List<String>> rows) {
  final parts = <String>[];
  for (final row in rows) {
    var empty = 0;
    final buf = StringBuffer();
    for (final cell in row) {
      if (cell.isEmpty) {
        empty++;
      } else {
        if (empty > 0) {
          buf.write(empty);
          empty = 0;
        }
        buf.write(cell);
      }
    }
    if (empty > 0) buf.write(empty);
    parts.add(buf.toString());
  }
  return parts.join('/');
}

class _GrayImage {
  _GrayImage(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Float64List pixels;

  factory _GrayImage.fromImage(img.Image image) {
    final w = image.width;
    final h = image.height;
    final pixels = Float64List(w * h);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        // Rec. 601 luminance.
        pixels[i++] =
            0.299 * p.r.toDouble() + 0.587 * p.g.toDouble() + 0.114 * p.b.toDouble();
      }
    }
    return _GrayImage(w, h, pixels);
  }

  double stdDev() {
    if (pixels.isEmpty) return 0.0;
    var mean = 0.0;
    for (final v in pixels) {
      mean += v;
    }
    mean /= pixels.length;
    var acc = 0.0;
    for (final v in pixels) {
      final d = v - mean;
      acc += d * d;
    }
    return math.sqrt(acc / pixels.length);
  }

  _GrayImage resized(int tw, int th) {
    if (tw == width && th == height) return this;
    // Area-style average resample (good enough for NCC templates).
    final out = Float64List(tw * th);
    for (var y = 0; y < th; y++) {
      final y0 = (y * height / th).floor();
      final y1 = math.min(height, ((y + 1) * height / th).ceil());
      for (var x = 0; x < tw; x++) {
        final x0 = (x * width / tw).floor();
        final x1 = math.min(width, ((x + 1) * width / tw).ceil());
        var sum = 0.0;
        var count = 0;
        for (var yy = y0; yy < math.max(y0 + 1, y1); yy++) {
          for (var xx = x0; xx < math.max(x0 + 1, x1); xx++) {
            sum += pixels[yy * width + xx];
            count++;
          }
        }
        out[y * tw + x] = count == 0 ? 0.0 : sum / count;
      }
    }
    return _GrayImage(tw, th, out);
  }
}
