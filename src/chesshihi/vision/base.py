"""Abstract vision interface — swap template matching for ML later without touching CLI/engine."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np


@dataclass
class RecognitionResult:
    """Output of a board recognizer."""

    fen: str
    board_bbox: tuple[int, int, int, int]  # x, y, w, h in image coords
    square_labels: list[list[str]]  # 8×8 FEN piece letters or "" for empty
    confidence: float = 0.0
    extras: dict[str, Any] = field(default_factory=dict)


class BoardRecognizer(ABC):
    """Pixels → FEN. Implementations must not depend on Stockfish."""

    @abstractmethod
    def recognize(self, image: np.ndarray | Path | str) -> RecognitionResult:
        """Locate the 8×8 board, classify pieces, return FEN (placement + side to move)."""
