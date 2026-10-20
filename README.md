# Chesshihi

**Fair play:** Chesshihi is for **post-game analysis, training, and accessibility** (e.g. spoken recommendations for visually impaired players). It is **not** for live online engine assistance. Chess.com Fair Play prohibits engine help during live games — do not use this tool to hide or enable assistance in rated/casual online play.

Static PoC (Linux / cloud): **board screenshot → FEN → Stockfish best move**.

## What this slice does

1. Accepts a Chess.com-**style** board screenshot (synthetic samples ship in-repo — no Chess.com assets required).
2. Locates the 8×8 board and classifies pieces with **OpenCV template matching** (pluggable interface for later ML).
3. Runs **Stockfish** over UCI and prints the best move (depth or short movetime).
4. Documents how this maps to a future iOS app (ReplayKit → Vision/OpenCV → StockfishEmbedded → VoiceOver).

## Requirements

- Python 3.11+
- [uv](https://docs.astral.sh/uv/) (recommended) or pip
- Stockfish binary (`sudo apt install stockfish` on Debian/Ubuntu — often at `/usr/games/stockfish`)

Optional: set `STOCKFISH_PATH` if the engine is not on `PATH`.

## Install

```bash
# from repo root
uv sync

# generate synthetic piece templates + sample boards (also done automatically on first run)
uv run chesshihi prepare-assets

# confirm Stockfish + assets
uv run chesshihi doctor
```

With pip:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .
python scripts/generate_assets.py
```

## Run

Analyze the shipped starting-position sample:

```bash
uv run chesshihi analyze
```

Analyze the Italian Game sample (richer position):

```bash
uv run chesshihi analyze assets/samples/italian_game.png --movetime 500
```

Vision only (print FEN):

```bash
uv run chesshihi recognize assets/samples/starting_position.png
```

Skip vision and feed a FEN:

```bash
uv run chesshihi analyze --fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" --depth 12
```

Example output (exact move may vary by Stockfish version / time):

```
Fair play: Chesshihi is for analysis, training, and accessibility only — not live online engine assist.
image:      assets/samples/starting_position.png
confidence: 0.99
FEN:        rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
best move:  e4 (e2e4)
score:      0.28 pawns
movetime:   500 ms
engine:     /usr/games/stockfish
```

## Project layout

```
src/chesshihi/
  cli.py                 # entrypoint
  render.py              # synthetic board + template generation
  vision/
    base.py              # BoardRecognizer protocol (swap in ML later)
    template_matcher.py  # OpenCV PoC backend
  engine/stockfish.py    # UCI via python-chess
assets/
  templates/             # piece / empty square PNGs
  samples/               # starting_position.png, italian_game.png
```

## PoC → future iOS

| PoC (this repo) | iOS direction |
|-----------------|---------------|
| Static PNG input | ReplayKit broadcast extension (user starts capture from Control Center) |
| OpenCV template matching | Same pipeline on-device, and/or Vision / Core ML classifier |
| System Stockfish UCI | StockfishEmbedded / Multi-Stockfish Swift packages |
| CLI print | `UIAccessibility` announcements + `AVSpeechSynthesizer` |
| Fair-play banner in CLI | Transparent App Store copy; optional live-game detection → disable recommendations |

Latency target later: vision on board ROI only; Stockfish short `movetime` (≤500ms) for interactive feel.

## Tests

```bash
uv run pytest -q
```

## Risks / known PoC limits

- **Piece sets**: templates match the synthetic renderer. Real Chess.com themes, 2D/3D pieces, or custom sets need new templates or an ML classifier.
- **Animations / highlights**: move flashes, arrows, and last-move highlights can confuse matching.
- **Perspective / crop**: heavy UI chrome, partial boards, or extreme skew are not handled.
- **Side to move / castling / EP**: inferred only from CLI flags (defaults: White to move, `KQkq`) — screenshot alone does not encode clock/side reliably.
- **Orientation**: assumes White at bottom (Chess.com default for White).
- **Not production vision**: template matching is a deliberate PoC stand-in for on-device ML.

## License / ethics

Use only for analysis, coaching, and accessibility. Do not integrate or market this as a live-game cheating aid.
