import 'package:chess/chess.dart';

/// Convert a UCI principal variation to SAN when the FEN is legal enough.
///
/// Falls back to the original UCI tokens for any move that cannot be applied
/// (illegal / incomplete FEN). Never invents commentary — only notation.
class SanLine {
  const SanLine._(this.moves, {required this.usedSan});

  final List<String> moves;
  final bool usedSan;

  String get joined => moves.join(' ');

  /// Best-effort UCI → SAN along [pvUci] from [fen].
  static SanLine fromPv({
    required String fen,
    required List<String> pvUci,
  }) {
    if (pvUci.isEmpty) {
      return const SanLine._([], usedSan: false);
    }

    final board = Chess();
    final loaded = board.load(fen, check_validity: false);
    if (!loaded) {
      return SanLine._(List<String>.from(pvUci), usedSan: false);
    }

    final out = <String>[];
    var allSan = true;

    for (var i = 0; i < pvUci.length; i++) {
      final uci = pvUci[i];
      final san = _uciToSanAndPlay(board, uci);
      if (san == null) {
        out.add(uci);
        allSan = false;
        out.addAll(pvUci.skip(i + 1));
        break;
      }
      out.add(san);
    }

    return SanLine._(out, usedSan: allSan && out.isNotEmpty);
  }

  /// Single UCI move → SAN, or null if not legal in [fen].
  static String? uciToSan(String fen, String uci) {
    final board = Chess();
    if (!board.load(fen, check_validity: false)) return null;
    return _uciToSanAndPlay(board, uci);
  }

  static String? _uciToSanAndPlay(Chess board, String uci) {
    if (uci == '(none)' || uci == '(timeout)' || uci == '0000') return null;
    if (uci.length < 4) return null;

    final from = uci.substring(0, 2);
    final to = uci.substring(2, 4);
    final promo = uci.length >= 5 ? uci[4].toLowerCase() : null;

    final legal = board.moves({'asObjects': true});
    Move? match;
    for (final raw in legal) {
      if (raw is! Move) continue;
      if (raw.fromAlgebraic != from || raw.toAlgebraic != to) continue;
      if (promo != null) {
        if (raw.promotion == null || raw.promotion!.name != promo) continue;
      }
      match = raw;
      break;
    }
    if (match == null) return null;

    final san = board.move_to_san(match);
    board.make_move(match);
    return san;
  }
}
