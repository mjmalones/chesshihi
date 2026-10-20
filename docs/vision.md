# Chesshihi — board vision (pixels → FEN)

**Fair play:** analysis, training, and accessibility only — not live online engine assist.

## What shipped

| Piece | Location | Role |
|-------|----------|------|
| Pluggable backend | `app/lib/vision/vision_backend.dart` | `BoardVisionBackend` — swap template matching for ML later |
| Dart template matcher | `app/lib/vision/template_matcher.dart` | Pure-Dart port of Python OpenCV PoC (`package:image`) |
| Facade | `app/lib/vision/board_recognizer.dart` | Loads templates, builds FEN, clear errors |
| Piece templates | `app/assets/templates/` | Same silhouettes as Python PoC / `assets/templates/` |
| Samples | `app/assets/samples/` | starting, Italian, K+Q endgame |

ReplayKit / Photos / camera frames all go through `FrameIngest` → recognizer → Stockfish. No stub FEN.

## Orientation & side to move

- Vision assumes **White at the bottom** of the board ROI (a1 bottom-left from White’s view).
- **Side to move is not read from pixels** (no clock/OCR). Use the in-app **Side to move** control before Analyze.
- Castling / en passant rights are not inferred from screenshots; samples may keep `KQkq`, live frames use `-`.

## What works (v1)

- Synthetic Chess.com-**like** boards that match the shipped palette + piece silhouettes (the sample assets).
- Screenshots / ReplayKit frames that still show the classic light/dark wood-ish squares close to `(240,217,181)` / `(181,136,99)` and piece shapes similar to the PoC templates.

## What is brittle / not supported yet

| Situation | Effect |
|-----------|--------|
| Alternate piece themes / 3D / neon | Mis-classify or empty squares |
| Strong move highlights / arrows / last-move overlays | Wrong piece or empty cell |
| Animating pieces mid-slide | Transient wrong FEN — ReplayKit already throttles / skips identical frames |
| Board flipped (Black at bottom) | Mirrored / inverted placement — flip the source or wait for orientation detection |
| Heavy letterboxing / multi-board UI | Board ROI miss → **“No chessboard found”** |
| Very dark / custom board colors | Color mask misses board → clear error |

When recognition fails, the UI shows the error and **disables Analyze** until a readable frame arrives.

## Native deps / IPA signing

**None new.** Vision is pure Dart (`image` package). Codemagic `ios-unsigned-ipa`, `ensure-stockfish-nnue.sh`, and ReplayKit appex embedding are unchanged. No OpenCV iOS / FFI for this path — Karl’s signer still only needs app + Broadcast Upload Extension + App Group.

## Verify

```bash
cd app
flutter pub get
flutter test test/vision_test.dart test/widget_test.dart
```

Python PoC (same samples):

```bash
uv run pytest -q
uv run chesshihi analyze assets/samples/kings_queen_endgame.png
```

## Related

- ReplayKit capture: [replaykit.md](replaykit.md)
- Sideload / Codemagic: [ios-sideload.md](ios-sideload.md)
