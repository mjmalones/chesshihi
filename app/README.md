# Chesshihi (Flutter)

iOS-oriented slice: board frame → **vision → FEN** → Stockfish → optional spoken best move + explanation.

**Fair play:** analysis, training, and accessibility only — not live online engine assist.

## Features (PoC)

- Samples / Photos / **camera capture** / **ReplayKit** frames
- On-device **template-matching vision** (pure Dart, no OpenCV native dep) → real FEN
- Clear error when no board is found
- **Side to move** control (White/Black) — Stockfish analyzes the active color; vision does not read clocks
- Orientation: **White at bottom** (see [../docs/vision.md](../docs/vision.md))
- Eval + short **why this move** (score / mate / depth / main line)
- **Speak best move** toggle (off = on-screen only)
- **Live watch** (training/review): each new frame auto-analyzes when recognition succeeds
- **ReplayKit screen capture**: Control Center → Screen Recording → Chesshihi

## Run / verify

```bash
flutter pub get
flutter analyze
flutter test
```

Vision-only:

```bash
flutter test test/vision_test.dart
```

## IPA (requires macOS CI — not Linux)

See [../docs/ios-sideload.md](../docs/ios-sideload.md). Primary: Codemagic `ios-unsigned-ipa` → `chesshihi-unsigned.ipa` for your external signer.

ReplayKit / App Groups / signer checklist: [../docs/replaykit.md](../docs/replaykit.md).

Vision limits (themes, highlights, animations): [../docs/vision.md](../docs/vision.md).
