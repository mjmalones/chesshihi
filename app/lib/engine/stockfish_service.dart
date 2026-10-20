import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:stockfish/stockfish.dart';

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
    // Wait until ready (or timeout).
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
    int movetimeMs = 400,
  }) async {
    if (!isNativeAvailable) {
      return EngineResult(
        bestMoveUci: 'e2e4',
        bestMoveSpoken: 'e two to e four',
        fen: fen,
        stub: true,
        detail: 'Desktop stub — run on iOS for real Stockfish.',
      );
    }

    await ensureStarted();
    final engine = _engine!;
    final completer = Completer<EngineResult>();
    final buffer = <String>[];

    await _stdoutSub?.cancel();
    _stdoutSub = engine.stdout.listen((line) {
      buffer.add(line);
      if (line.startsWith('bestmove ')) {
        final parts = line.split(RegExp(r'\s+'));
        final uci = parts.length > 1 ? parts[1] : '(none)';
        if (!completer.isCompleted) {
          completer.complete(
            EngineResult(
              bestMoveUci: uci,
              bestMoveSpoken: speakUci(uci),
              fen: fen,
              stub: false,
              detail: buffer.where((l) => l.startsWith('info ')).isNotEmpty
                  ? buffer.lastWhere(
                      (l) => l.startsWith('info '),
                      orElse: () => line,
                    )
                  : line,
            ),
          );
        }
      }
    });

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
        detail: 'Stockfish did not return bestmove in time.',
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

class EngineResult {
  const EngineResult({
    required this.bestMoveUci,
    required this.bestMoveSpoken,
    required this.fen,
    required this.stub,
    required this.detail,
  });

  final String bestMoveUci;
  final String bestMoveSpoken;
  final String fen;
  final bool stub;
  final String detail;
}
