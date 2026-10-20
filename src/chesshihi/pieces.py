"""FEN piece letters and drawing helpers for synthetic Chess.com-style boards."""

from __future__ import annotations

from typing import Iterable

# FEN letters → display names
PIECE_NAMES: dict[str, str] = {
    "K": "white_king",
    "Q": "white_queen",
    "R": "white_rook",
    "B": "white_bishop",
    "N": "white_knight",
    "P": "white_pawn",
    "k": "black_king",
    "q": "black_queen",
    "r": "black_rook",
    "b": "black_bishop",
    "n": "black_knight",
    "p": "black_pawn",
}

ALL_PIECES: tuple[str, ...] = tuple(PIECE_NAMES.keys())

# Chess.com-ish palette
LIGHT_SQ = (240, 217, 181)
DARK_SQ = (181, 136, 99)
BOARD_FRAME = (48, 46, 43)
BG = (32, 34, 37)


def is_white(piece: str) -> bool:
    return piece.isupper()


def fen_rows_from_placement(placement: str) -> list[list[str]]:
    """Expand FEN placement (e.g. rnbqkbnr/pppppppp/8/...) into 8×8 labels."""
    rows: list[list[str]] = []
    for rank in placement.split("/"):
        row: list[str] = []
        for ch in rank:
            if ch.isdigit():
                row.extend([""] * int(ch))
            else:
                row.append(ch)
        if len(row) != 8:
            raise ValueError(f"Invalid FEN rank: {rank!r}")
        rows.append(row)
    if len(rows) != 8:
        raise ValueError("FEN placement must have 8 ranks")
    return rows


def placement_from_rows(rows: Iterable[Iterable[str]]) -> str:
    """Collapse 8×8 labels into FEN placement (rank 8 → rank 1)."""
    parts: list[str] = []
    for row in rows:
        empty = 0
        buf: list[str] = []
        for cell in row:
            if not cell:
                empty += 1
            else:
                if empty:
                    buf.append(str(empty))
                    empty = 0
                buf.append(cell)
        if empty:
            buf.append(str(empty))
        parts.append("".join(buf))
    return "/".join(parts)
