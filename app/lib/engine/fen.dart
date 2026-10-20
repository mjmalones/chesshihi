/// Minimal FEN helpers (side-to-move + display). Full chess rules live in Stockfish.
library;

class FenPosition {
  const FenPosition(this.fen);

  final String fen;

  List<String> get _parts => fen.trim().split(RegExp(r'\s+'));

  /// `'w'` or `'b'`. Defaults to white if the FEN is malformed.
  String get sideToMove {
    final parts = _parts;
    if (parts.length < 2) return 'w';
    final s = parts[1].toLowerCase();
    return s == 'b' ? 'b' : 'w';
  }

  bool get isWhiteToMove => sideToMove == 'w';

  String get sideToMoveLabel => isWhiteToMove ? 'White to move' : 'Black to move';

  /// Replace the side-to-move field. Other fields are preserved when present.
  String withSideToMove(String side) {
    final s = side.toLowerCase() == 'b' ? 'b' : 'w';
    final parts = List<String>.from(_parts);
    if (parts.isEmpty) {
      return BoardDefaults.emptyFenWithSide(s);
    }
    if (parts.length == 1) {
      return '${parts[0]} $s - - 0 1';
    }
    parts[1] = s;
    // FEN after a side flip is no longer "after the opponent's last move" in
    // the EP/halfmove sense, but Stockfish still analyzes the set-to-move.
    return parts.join(' ');
  }

  FenPosition copyWithSide(String side) => FenPosition(withSideToMove(side));
}

class BoardDefaults {
  static String emptyFenWithSide(String side) =>
      '8/8/8/8/8/8/8/8 $side - - 0 1';
}
