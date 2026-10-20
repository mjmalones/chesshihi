"""Minimal UCI client for Stockfish (or any UCI engine)."""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import chess
import chess.engine


DEFAULT_CANDIDATES = (
    "stockfish",
    "/usr/games/stockfish",
    "/usr/bin/stockfish",
    "/usr/local/bin/stockfish",
)


@dataclass
class AnalysisResult:
    fen: str
    best_move_uci: str
    best_move_san: str
    score_text: str
    depth: int | None
    movetime_ms: int | None
    engine_path: str


def find_stockfish(explicit: str | Path | None = None) -> str:
    if explicit:
        path = Path(explicit)
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
        which = shutil.which(str(explicit))
        if which:
            return which
        raise FileNotFoundError(f"Stockfish not found at {explicit}")

    env = os.environ.get("STOCKFISH_PATH")
    if env:
        return find_stockfish(env)

    for cand in DEFAULT_CANDIDATES:
        which = shutil.which(cand) if "/" not in cand else (cand if Path(cand).is_file() else None)
        if which and os.access(which, os.X_OK):
            return which
        if "/" in cand and Path(cand).is_file() and os.access(cand, os.X_OK):
            return cand
    raise FileNotFoundError(
        "Stockfish binary not found. Install it (e.g. `sudo apt install stockfish`) "
        "or set STOCKFISH_PATH / pass --stockfish."
    )


class StockfishEngine:
    def __init__(self, path: str | Path | None = None) -> None:
        self.path = find_stockfish(path)

    def analyze(
        self,
        fen: str,
        *,
        depth: int | None = None,
        movetime_ms: int | None = 500,
    ) -> AnalysisResult:
        board = chess.Board(fen)
        limit = (
            chess.engine.Limit(depth=depth)
            if depth is not None
            else chess.engine.Limit(time=(movetime_ms or 500) / 1000.0)
        )
        with chess.engine.SimpleEngine.popen_uci(self.path) as engine:
            info = engine.analyse(board, limit)
            # Also ask for a play move so we always get a concrete suggestion.
            result = engine.play(board, limit)

        move = result.move
        if move is None:
            raise RuntimeError("Engine returned no move (game over?)")

        score = info.get("score")
        score_text = "n/a"
        if score is not None:
            pov = score.white()
            if pov.is_mate():
                score_text = f"mate {pov.mate()}"
            else:
                cp = pov.score()
                score_text = f"{cp / 100:.2f} pawns" if cp is not None else "n/a"

        return AnalysisResult(
            fen=fen,
            best_move_uci=move.uci(),
            best_move_san=board.san(move),
            score_text=score_text,
            depth=depth,
            movetime_ms=None if depth is not None else (movetime_ms or 500),
            engine_path=self.path,
        )


def smoke_uci(path: str | None = None) -> str:
    """Return the engine's `id name` line for diagnostics."""
    engine_path = find_stockfish(path)
    proc = subprocess.Popen(
        [engine_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert proc.stdin and proc.stdout
    proc.stdin.write("uci\nquit\n")
    proc.stdin.flush()
    out, _ = proc.communicate(timeout=5)
    for line in out.splitlines():
        if line.startswith("id name"):
            return line
    return out.splitlines()[0] if out else engine_path
