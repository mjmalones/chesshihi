"""OpenCV template-matching board recognizer (PoC; replaceable with ML later)."""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np

from chesshihi.pieces import ALL_PIECES, DARK_SQ, LIGHT_SQ, placement_from_rows
from chesshihi.vision.base import BoardRecognizer, RecognitionResult


def _bgr(color: tuple[int, int, int]) -> np.ndarray:
    r, g, b = color
    return np.array([b, g, r], dtype=np.float32)


class TemplateMatcherRecognizer(BoardRecognizer):
    """
    Locate the board via color clustering / largest square region, split into
    64 cells, and classify each with normalized cross-correlation against
    shipped piece templates.
    """

    def __init__(
        self,
        templates_dir: Path | str,
        *,
        side_to_move: str = "w",
        castling: str = "KQkq",
        ep_square: str = "-",
        halfmove: int = 0,
        fullmove: int = 1,
        match_threshold: float = 0.45,
    ) -> None:
        self.templates_dir = Path(templates_dir)
        self.side_to_move = side_to_move
        self.castling = castling
        self.ep_square = ep_square
        self.halfmove = halfmove
        self.fullmove = fullmove
        self.match_threshold = match_threshold
        # label → {"light": gray, "dark": gray}
        self._templates = self._load_templates()

    def _load_templates(self) -> dict[str, dict[str, np.ndarray]]:
        """Map label → {light|dark → grayscale template}."""
        loaded: dict[str, dict[str, np.ndarray]] = {"": {}}
        for piece in ALL_PIECES:
            loaded[piece] = {}
        for path in sorted(self.templates_dir.glob("*.png")):
            stem = path.stem  # e.g. wK_light, bN_dark, empty_dark
            img = cv2.imread(str(path), cv2.IMREAD_COLOR)
            if img is None:
                continue
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            if stem.startswith("empty_"):
                shade = stem.split("_", 1)[1]
                loaded[""][shade] = gray
            else:
                prefix, shade = stem.split("_", 1)
                # prefix is wK / bP → FEN letter K / p
                if len(prefix) != 2 or prefix[0] not in "wb":
                    continue
                piece = prefix[1] if prefix[0] == "w" else prefix[1].lower()
                if piece in loaded:
                    loaded[piece][shade] = gray
        if not any(loaded[p] for p in ALL_PIECES):
            raise FileNotFoundError(f"No piece templates found in {self.templates_dir}")
        return loaded

    def recognize(self, image: np.ndarray | Path | str) -> RecognitionResult:
        bgr = self._load_image(image)
        x, y, w, h = self._find_board(bgr)
        board = bgr[y : y + h, x : x + w]
        labels, score = self._classify_board(board)
        placement = placement_from_rows(labels)
        fen = (
            f"{placement} {self.side_to_move} {self.castling} "
            f"{self.ep_square} {self.halfmove} {self.fullmove}"
        )
        return RecognitionResult(
            fen=fen,
            board_bbox=(x, y, w, h),
            square_labels=labels,
            confidence=score,
            extras={"backend": "opencv_template_match"},
        )

    @staticmethod
    def _load_image(image: np.ndarray | Path | str) -> np.ndarray:
        if isinstance(image, np.ndarray):
            return image
        path = Path(image)
        bgr = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if bgr is None:
            raise FileNotFoundError(f"Could not read image: {path}")
        return bgr

    def _find_board(self, bgr: np.ndarray) -> tuple[int, int, int, int]:
        """Find the largest region matching chess-square colors, else inset heuristic."""
        light = _bgr(LIGHT_SQ)
        dark = _bgr(DARK_SQ)
        pixels = bgr.astype(np.float32)
        d_light = np.linalg.norm(pixels - light, axis=2)
        d_dark = np.linalg.norm(pixels - dark, axis=2)
        mask = ((d_light < 45) | (d_dark < 45)).astype(np.uint8) * 255

        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)

        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        best: tuple[int, int, int, int] | None = None
        best_area = 0
        for cnt in contours:
            x, y, w, h = cv2.boundingRect(cnt)
            area = w * h
            aspect = w / max(h, 1)
            if area > best_area and 0.85 <= aspect <= 1.15 and w >= 64 and h >= 64:
                best = (x, y, w, h)
                best_area = area

        if best is not None:
            return best

        # Fallback: assume board is centered square with margin.
        H, W = bgr.shape[:2]
        side = int(min(W, H) * 0.82)
        x = (W - side) // 2
        y = (H - side) // 2
        return x, y, side, side

    def _classify_board(self, board: np.ndarray) -> tuple[list[list[str]], float]:
        h, w = board.shape[:2]
        cell_h, cell_w = h / 8.0, w / 8.0
        labels: list[list[str]] = []
        scores: list[float] = []
        for rank in range(8):
            row: list[str] = []
            for file in range(8):
                y0 = int(round(rank * cell_h))
                x0 = int(round(file * cell_w))
                y1 = int(round((rank + 1) * cell_h))
                x1 = int(round((file + 1) * cell_w))
                cell = board[y0:y1, x0:x1]
                label, sc = self._classify_cell(cell)
                row.append(label)
                scores.append(sc)
            labels.append(row)
        return labels, float(np.mean(scores)) if scores else 0.0

    def _square_shade(self, cell_bgr: np.ndarray) -> str:
        """Guess light vs dark square from mean color distance to palette."""
        mean = cell_bgr.reshape(-1, 3).mean(axis=0).astype(np.float32)
        d_light = float(np.linalg.norm(mean - _bgr(LIGHT_SQ)))
        d_dark = float(np.linalg.norm(mean - _bgr(DARK_SQ)))
        return "light" if d_light <= d_dark else "dark"

    def _classify_cell(self, cell_bgr: np.ndarray) -> tuple[str, float]:
        gray = cv2.cvtColor(cell_bgr, cv2.COLOR_BGR2GRAY)
        # Flat cells are empty (templates and renderer share solid square fills).
        if float(gray.std()) < 12.0:
            return "", 1.0

        shade = self._square_shade(cell_bgr)
        best_label = ""
        best_score = -1.0
        for label, by_shade in self._templates.items():
            if label == "":
                continue
            tmpl = by_shade.get(shade)
            if tmpl is None and by_shade:
                tmpl = next(iter(by_shade.values()))
            if tmpl is None:
                continue
            score = self._ncc(gray, tmpl)
            if score > best_score:
                best_score = score
                best_label = label
        if best_score < self.match_threshold:
            return "", best_score
        return best_label, best_score

    @staticmethod
    def _ncc(cell: np.ndarray, tmpl: np.ndarray) -> float:
        """Normalized correlation; resize template to cell size."""
        th, tw = cell.shape[:2]
        if th < 8 or tw < 8:
            return -1.0
        resized = cv2.resize(tmpl, (tw, th), interpolation=cv2.INTER_AREA)
        # Prefer matchTemplate on a slightly padded cell when sizes equal — use corrcoef.
        a = cell.astype(np.float32).ravel()
        b = resized.astype(np.float32).ravel()
        a -= a.mean()
        b -= b.mean()
        denom = float(np.linalg.norm(a) * np.linalg.norm(b))
        if denom < 1e-6:
            return 0.0
        return float(np.dot(a, b) / denom)
