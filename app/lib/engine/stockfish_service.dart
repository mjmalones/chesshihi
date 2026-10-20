import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:stockfish/stockfish.dart';

import 'fen.dart';

/// On-device Stockfish via the `stockfish` Flutter package (iOS / Android).
///
/// On desktop (Linux CI / local analyze) the native plugin is unavailable —
/// we return a deterministic stub move so UI + tests still run.
class StockfishService {
  Stockfish? _engine;
  StreamSubscription<String>? _stdoutSub;

  bool get isNativeAvailable =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<void> ensureStarted() async {
    if (!isNativeAvailable) return;
    if (_engine != null && _engine!.state.value == StockfishState.ready) {
      return;
    }
    _engine?.dispose();
    _engine = Stockfish();
    final ready = Completer<void>();
    void listener() {
      if (_engine?.state.value == StockfishState.ready && !ready.isCompleted) {
        ready.complete();
      }
    }

    _engine!.state.addListener(listener);
    await ready.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _engine!.state.removeListener(listener);
        throw StateError('Stockfish failed to become ready');
      },
    );
    _engine!.state.removeListener(listener);
  }

  /// Best move for [fen] using a short movetime (interactive feel).
  Future<EngineResult> analyze(
    String fen, {
    int movetimeMs = 800,
  }) async {
    final side = FenPosition(fen).sideToMoveLabel;

    if (!isNativeAvailable) {
      final uci = FenPosition(fen).isWhiteToMove ? 'e2e4' : 'e7e5';
      return EngineResult(
        bestMoveUci: uci,
        bestMoveSpoken: speakUci(uci),
        fen: fen,
        stub: true,
        detail: 'Desktop stub — run on iOS for real Stockfish.',
        scoreCp: FenPosition(fen).isWhiteToMove ? 25 : -25,
        mateIn: null,
        depth: 1,
        pvUci: [uci],
        explanation: ExplainMove.compose(
          fen: fen,
          bestMoveUci: uci,
          scoreCp: FenPosition(fen).isWhiteToMove ? 25 : -25,
          mateIn: null,
          depth: 1,
          pvUci: [uci],
          stub: true,
        ),
      );
    }

    await ensureStarted();
    final engine = _engine!;
    final completer = Completer<EngineResult>();
    final buffer = <String>[];
    StockfishInfo? bestInfo;

    await _stdoutSub?.cancel();
    _stdoutSub = engine.stdout.listen((line) {
      buffer.add(line);
      final info = StockfishInfo.tryParse(line);
      if (info != null && info.hasScore) {
        // Prefer deeper lines with a PV that starts with a move.
        if (bestInfo == null ||
            info.depth >= bestInfo!.depth ||
            (info.pvUci.isNotEmpty && bestInfo!.pvUci.isEmpty)) {
          bestInfo = info;
        }
      }
      if (line.startsWith('bestmove ')) {
        final parts = line.split(RegExp(r'\s+'));
        final uci = parts.length > 1 ? parts[1] : '(none)';
        final info = bestInfo;
        final pv = info != null && info.pvUci.isNotEmpty
            ? info.pvUci
            : (uci != '(none)' ? [uci] : <String>[]);
        if (!completer.isCompleted) {
          completer.complete(
            EngineResult(
              bestMoveUci: uci,
              bestMoveSpoken: speakUci(uci),
              fen: fen,
              stub: false,
              detail: info?.raw ?? line,
              scoreCp: info?.scoreCp,
              mateIn: info?.mateIn,
              depth: info?.depth,
              pvUci: pv,
              explanation: ExplainMove.compose(
                fen: fen,
                bestMoveUci: uci,
                scoreCp: info?.scoreCp,
                mateIn: info?.mateIn,
                depth: info?.depth,
                pvUci: pv,
                stub: false,
              ),
            ),
          );
        }
      }
    });

    // UCI: side-to-move is entirely determined by the FEN's active color field.
    engine.stdin = 'ucinewgame';
    engine.stdin = 'position fen $fen';
    engine.stdin = 'go movetime $movetimeMs';

    return completer.future.timeout(
      Duration(milliseconds: movetimeMs + 5000),
      onTimeout: () => EngineResult(
        bestMoveUci: '(timeout)',
        bestMoveSpoken: 'analysis timed out',
        fen: fen,
        stub: false,
        detail: 'Stockfish did not return bestmove in time ($side).',
        explanation:
            'Analysis timed out before Stockfish returned a best move for $side.',
      ),
    );
  }

  void dispose() {
    _stdoutSub?.cancel();
    _engine?.dispose();
    _engine = null;
  }

  /// Rough UCI → spoken English for TTS / VoiceOver.
  static String speakUci(String uci) {
    if (uci == '(none)' || uci == '0000' || uci == '(timeout)') {
      return 'no move';
    }
    if (uci.length < 4) return uci;
    final from = '${uci[0]} ${uci[1]}';
    final to = '${uci[2]} ${uci[3]}';
    var spoken = '$from to $to';
    if (uci.length >= 5) {
      const promo = {
        'q': 'queen',
        'r': 'rook',
        'b': 'bishop',
        'n': 'knight',
      };
      spoken += ', promoting to ${promo[uci[4].toLowerCase()] ?? uci[4]}';
    }
    return spoken;
  }
}

/// Parsed subset of a Stockfish `info …` line.
class StockfishInfo {
  const StockfishInfo({
    required this.raw,
    required this.depth,
    required this.scoreCp,
    required this.mateIn,
    required this.pvUci,
  });

  final String raw;
  final int depth;
  final int? scoreCp;
  final int? mateIn;
  final List<String> pvUci;

  bool get hasScore => scoreCp != null || mateIn != null;

  static StockfishInfo? tryParse(String line) {
    if (!line.startsWith('info ')) return null;
    final tokens = line.split(RegExp(r'\s+'));
    int depth = 0;
    int? scoreCp;
    int? mateIn;
    final pv = <String>[];

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t == 'depth' && i + 1 < tokens.length) {
        depth = int.tryParse(tokens[i + 1]) ?? depth;
      } else if (t == 'score' && i + 2 < tokens.length) {
        final kind = tokens[i + 1];
        final val = int.tryParse(tokens[i + 2]);
        if (val != null) {
          if (kind == 'cp') scoreCp = val;
          if (kind == 'mate') mateIn = val;
        }
      } else if (t == 'pv') {
        pv.addAll(tokens.sublist(i + 1).where((m) => m.length >= 4));
        break;
      }
    }

    if (scoreCp == null && mateIn == null && pv.isEmpty) return null;
    return StockfishInfo(
      raw: line,
      depth: depth,
      scoreCp: scoreCp,
      mateIn: mateIn,
      pvUci: pv,
    );
  }
}

class ExplainMove {
  /// Plain-language reason based on eval + PV (not full chess commentary).
  static String compose({
    required String fen,
    required String bestMoveUci,
    required int? scoreCp,
    required int? mateIn,
    required int? depth,
    required List<String> pvUci,
    required bool stub,
  }) {
    final pos = FenPosition(fen);
    final side = pos.sideToMoveLabel;
    final move = bestMoveUci == '(none)' || bestMoveUci == '(timeout)'
        ? 'no move'
        : bestMoveUci;

    if (bestMoveUci == '(timeout)') {
      return 'Analysis timed out before a recommendation for $side.';
    }
    if (bestMoveUci == '(none)' || bestMoveUci == '0000') {
      return 'Stockfish found no legal move for $side (checkmate or stalemate).';
    }

    final buf = StringBuffer();
    buf.write('For $side, Stockfish prefers $move');

    if (mateIn != null) {
      final n = mateIn.abs();
      if (mateIn > 0) {
        buf.write(' — forcing mate in $n');
      } else {
        buf.write(' — the only way to delay mate (mate in $n against us)');
      }
    } else if (scoreCp != null) {
      // UCI scores are from the side to move's perspective in Stockfish…
      // Actually classic Stockfish reports score from the side to move.
      // Positive = good for the side about to move.
      final pawns = (scoreCp / 100).toStringAsFixed(2);
      if (scoreCp >= 80) {
        buf.write(' — evaluation about +$pawns pawns in favor of the side to move');
      } else if (scoreCp <= -80) {
        buf.write(
          ' — still the best try; position is about ${pawns.replaceFirst('-', '−')} pawns against the side to move',
        );
      } else {
        buf.write(' — roughly equal (about $pawns pawns)');
      }
    }

    if (depth != null && depth > 0) {
      buf.write('. Searched to depth $depth');
    }

    if (pvUci.length > 1) {
      final preview = pvUci.take(6).join(' ');
      buf.write('. Main line: $preview');
    }

    buf.write('.');
    if (stub) {
      buf.write(' (Desktop stub — on iOS this uses real Stockfish eval.)');
    }
    return buf.toString();
  }
}

class EngineResult {
  const EngineResult({
    required this.bestMoveUci,
    required this.bestMoveSpoken,
    required this.fen,
    required this.stub,
    required this.detail,
    this.scoreCp,
    this.mateIn,
    this.depth,
    this.pvUci = const [],
    this.explanation = '',
  });

  final String bestMoveUci;
  final String bestMoveSpoken;
  final String fen;
  final bool stub;
  final String detail;
  final int? scoreCp;
  final int? mateIn;
  final int? depth;
  final List<String> pvUci;
  final String explanation;

  String get scoreLabel {
    if (mateIn != null) {
      return mateIn! > 0 ? 'Mate in ${mateIn!}' : 'Mated in ${mateIn!.abs()}';
    }
    if (scoreCp != null) {
      final p = (scoreCp! / 100).toStringAsFixed(2);
      return scoreCp! >= 0 ? '+$p' : p;
    }
    return '—';
  }
}
