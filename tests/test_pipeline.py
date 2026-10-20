"""Smoke tests for vision → FEN → Stockfish."""

from __future__ import annotations

from pathlib import Path

import chess
import pytest

from chesshihi.engine.stockfish import StockfishEngine, find_stockfish
from chesshihi.render import ensure_sample_assets, render_board
from chesshihi.vision.template_matcher import TemplateMatcherRecognizer

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"

START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"
ITALIAN = "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R"
ENDGAME = "8/8/8/3k4/8/8/4K3/7Q"


@pytest.fixture(scope="module")
def assets() -> Path:
    ensure_sample_assets(ASSETS)
    return ASSETS


def test_recognize_starting_position(assets: Path) -> None:
    recognizer = TemplateMatcherRecognizer(assets / "templates", castling="KQkq")
    result = recognizer.recognize(assets / "samples" / "starting_position.png")
    placement = result.fen.split()[0]
    assert placement == START
    assert result.confidence > 0.7


def test_recognize_italian(assets: Path) -> None:
    recognizer = TemplateMatcherRecognizer(assets / "templates", castling="KQkq")
    result = recognizer.recognize(assets / "samples" / "italian_game.png")
    assert result.fen.split()[0] == ITALIAN


def test_recognize_endgame(assets: Path) -> None:
    recognizer = TemplateMatcherRecognizer(assets / "templates", castling="-")
    result = recognizer.recognize(assets / "samples" / "kings_queen_endgame.png")
    assert result.fen.split()[0] == ENDGAME


def test_recognize_roundtrip_custom(assets: Path, tmp_path: Path) -> None:
    fen_placement = "8/8/8/3k4/8/8/4K3/7Q"
    img = render_board(fen_placement, side_to_move="w")
    path = tmp_path / "custom.png"
    img.save(path)
    recognizer = TemplateMatcherRecognizer(
        assets / "templates", side_to_move="w", castling="-"
    )
    result = recognizer.recognize(path)
    assert result.fen.split()[0] == fen_placement


def test_stockfish_best_move() -> None:
    try:
        find_stockfish()
    except FileNotFoundError:
        pytest.skip("Stockfish not installed")
    engine = StockfishEngine()
    fen = f"{START} w KQkq - 0 1"
    result = engine.analyze(fen, depth=8)
    board = chess.Board(fen)
    assert chess.Move.from_uci(result.best_move_uci) in board.legal_moves
    assert result.best_move_san
