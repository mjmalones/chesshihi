"""Synthetic Chess.com-style board renderer + piece template generator (no Chess.com assets)."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from chesshihi.pieces import (
    ALL_PIECES,
    BG,
    BOARD_FRAME,
    DARK_SQ,
    LIGHT_SQ,
    fen_rows_from_placement,
    is_white,
)

DEFAULT_SQUARE = 80
DEFAULT_MARGIN = 48
PIECE_INSET = 4  # must match between board render and templates


def _fill_color(piece: str) -> tuple[int, int, int]:
    # Slightly cooler white / warmer black for contrast on both square colors.
    return (250, 250, 245) if is_white(piece) else (25, 25, 28)


def _stroke_color(piece: str) -> tuple[int, int, int]:
    return (35, 35, 40) if is_white(piece) else (230, 230, 225)


def draw_piece(draw: ImageDraw.ImageDraw, piece: str, box: tuple[int, int, int, int]) -> None:
    """Draw a simple distinctive silhouette for ``piece`` inside ``box`` (l,t,r,b)."""
    l, t, r, b = box
    w, h = r - l, b - t
    cx, cy = (l + r) / 2, (t + b) / 2
    fill, stroke = _fill_color(piece), _stroke_color(piece)
    kind = piece.upper()
    sw = max(2, w // 28)

    def oval(dx: float, dy: float, rw: float, rh: float) -> None:
        draw.ellipse(
            [cx + dx - rw, cy + dy - rh, cx + dx + rw, cy + dy + rh],
            fill=fill,
            outline=stroke,
            width=sw,
        )

    def poly(pts: list[tuple[float, float]]) -> None:
        draw.polygon([(cx + x, cy + y) for x, y in pts], fill=fill, outline=stroke)

    def rect(dx: float, dy: float, rw: float, rh: float) -> None:
        draw.rectangle(
            [cx + dx - rw, cy + dy - rh, cx + dx + rw, cy + dy + rh],
            fill=fill,
            outline=stroke,
            width=sw,
        )

    s = min(w, h) * 0.38

    if kind == "P":
        oval(0, -0.15 * s, 0.45 * s, 0.45 * s)
        poly([(-0.55 * s, 0.55 * s), (0.55 * s, 0.55 * s), (0.35 * s, 0.05 * s), (-0.35 * s, 0.05 * s)])
        rect(0, 0.72 * s, 0.65 * s, 0.12 * s)
    elif kind == "R":
        poly(
            [
                (-0.55 * s, 0.7 * s),
                (0.55 * s, 0.7 * s),
                (0.45 * s, -0.1 * s),
                (-0.45 * s, -0.1 * s),
            ]
        )
        for dx in (-0.5, -0.1, 0.3):
            rect(dx * s + 0.1 * s, -0.45 * s, 0.18 * s, 0.35 * s)
        rect(0, 0.85 * s, 0.7 * s, 0.12 * s)
    elif kind == "N":
        poly(
            [
                (-0.5 * s, 0.7 * s),
                (0.55 * s, 0.7 * s),
                (0.45 * s, 0.1 * s),
                (0.2 * s, -0.15 * s),
                (0.55 * s, -0.35 * s),
                (0.15 * s, -0.7 * s),
                (-0.15 * s, -0.35 * s),
                (-0.35 * s, -0.55 * s),
                (-0.55 * s, -0.1 * s),
                (-0.25 * s, 0.15 * s),
            ]
        )
        rect(0, 0.85 * s, 0.7 * s, 0.12 * s)
    elif kind == "B":
        poly([(0, -0.75 * s), (0.45 * s, 0.15 * s), (0.25 * s, 0.55 * s), (-0.25 * s, 0.55 * s), (-0.45 * s, 0.15 * s)])
        oval(0, -0.55 * s, 0.18 * s, 0.18 * s)
        rect(0, 0.75 * s, 0.65 * s, 0.12 * s)
    elif kind == "Q":
        poly(
            [
                (-0.55 * s, 0.55 * s),
                (0.55 * s, 0.55 * s),
                (0.4 * s, -0.05 * s),
                (0.55 * s, -0.55 * s),
                (0.2 * s, -0.2 * s),
                (0, -0.75 * s),
                (-0.2 * s, -0.2 * s),
                (-0.55 * s, -0.55 * s),
                (-0.4 * s, -0.05 * s),
            ]
        )
        oval(0, -0.85 * s, 0.12 * s, 0.12 * s)
        rect(0, 0.75 * s, 0.7 * s, 0.12 * s)
    elif kind == "K":
        rect(0, -0.15 * s, 0.12 * s, 0.55 * s)
        rect(0, -0.35 * s, 0.35 * s, 0.12 * s)
        poly([(-0.5 * s, 0.55 * s), (0.5 * s, 0.55 * s), (0.35 * s, -0.05 * s), (-0.35 * s, -0.05 * s)])
        rect(0, 0.75 * s, 0.7 * s, 0.12 * s)
    else:
        raise ValueError(f"Unknown piece: {piece}")


def _paint_square(
    draw: ImageDraw.ImageDraw,
    x0: int,
    y0: int,
    square: int,
    color: tuple[int, int, int],
    piece: str | None = None,
) -> None:
    draw.rectangle([x0, y0, x0 + square - 1, y0 + square - 1], fill=color)
    if piece:
        inset = PIECE_INSET
        draw_piece(draw, piece, (x0 + inset, y0 + inset, x0 + square - inset, y0 + square - inset))


def render_piece_on_square(
    piece: str,
    square_color: tuple[int, int, int],
    size: int = DEFAULT_SQUARE,
) -> Image.Image:
    img = Image.new("RGB", (size, size), square_color)
    draw = ImageDraw.Draw(img)
    _paint_square(draw, 0, 0, size, square_color, piece)
    return img


def render_empty_square(square_color: tuple[int, int, int], size: int = DEFAULT_SQUARE) -> Image.Image:
    return Image.new("RGB", (size, size), square_color)


def template_stem(piece: str) -> str:
    """macOS-safe template basename prefix, e.g. ``wK`` / ``bN`` (avoids ``K`` vs ``k``)."""
    side = "w" if is_white(piece) else "b"
    return f"{side}{piece.upper()}"


def write_templates(out_dir: Path, size: int = DEFAULT_SQUARE) -> None:
    """Write piece + empty templates with the same painter as sample screenshots."""
    out_dir.mkdir(parents=True, exist_ok=True)
    for piece in ALL_PIECES:
        stem = template_stem(piece)
        for name, color in (("light", LIGHT_SQ), ("dark", DARK_SQ)):
            render_piece_on_square(piece, color, size).save(out_dir / f"{stem}_{name}.png")
    for name, color in (("light", LIGHT_SQ), ("dark", DARK_SQ)):
        render_empty_square(color, size).save(out_dir / f"empty_{name}.png")


def render_board(
    fen_placement: str,
    *,
    square: int = DEFAULT_SQUARE,
    margin: int = DEFAULT_MARGIN,
    side_to_move: str = "w",
    flipped: bool = False,
) -> Image.Image:
    """
    Render a Chess.com-style board image from a FEN placement string.

    ``flipped`` shows Black's perspective (rank 1 at top). Coordinates for
    recognition always assume White at bottom unless flipped is set and
    communicated to the recognizer.
    """
    rows = fen_rows_from_placement(fen_placement)
    if flipped:
        rows = [list(reversed(r)) for r in reversed(rows)]

    board_px = square * 8
    canvas = Image.new("RGB", (board_px + 2 * margin, board_px + 2 * margin), BG)
    draw = ImageDraw.Draw(canvas)
    draw.rectangle(
        [margin - 6, margin - 6, margin + board_px + 5, margin + board_px + 5],
        fill=BOARD_FRAME,
    )

    for rank_i, row in enumerate(rows):
        for file_i, piece in enumerate(row):
            x0 = margin + file_i * square
            y0 = margin + rank_i * square
            is_light = (file_i + rank_i) % 2 == 0
            color = LIGHT_SQ if is_light else DARK_SQ
            _paint_square(draw, x0, y0, square, color, piece or None)

    # Tiny side-to-move indicator (does not affect recognition)
    stm_color = (245, 245, 240) if side_to_move == "w" else (30, 30, 30)
    draw.ellipse([12, 12, 36, 36], fill=stm_color, outline=(180, 180, 180))
    return canvas


def render_board_bgr(
    fen_placement: str,
    **kwargs,
) -> np.ndarray:
    """Same as ``render_board`` but as an OpenCV BGR ndarray."""
    import cv2

    rgb = np.asarray(render_board(fen_placement, **kwargs))
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)


def ensure_sample_assets(
    assets_root: Path,
    *,
    fen_placement: str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
    side_to_move: str = "w",
) -> tuple[Path, Path]:
    """Create templates + sample board screenshots."""
    templates = assets_root / "templates"
    samples = assets_root / "samples"
    samples.mkdir(parents=True, exist_ok=True)
    write_templates(templates)
    sample_path = samples / "starting_position.png"
    render_board(fen_placement, side_to_move=side_to_move).save(sample_path)
    mid = "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R"
    render_board(mid, side_to_move="w").save(samples / "italian_game.png")
    return sample_path, templates
