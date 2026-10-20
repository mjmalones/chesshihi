# Chesshihi (Flutter)

iOS-oriented slice: board frame → FEN → Stockfish → optional spoken best move + explanation.

**Fair play:** analysis, training, and accessibility only — not live online engine assist.

## Features (PoC)

- Samples / Photos / **camera capture**
- **Side to move** control (White/Black) — Stockfish analyzes the active color in the FEN
- Eval + short **why this move** (score / mate / depth / main line)
- **Speak best move** toggle (off = on-screen only)
- **Live watch** (training/review): each new frame auto-analyzes. Continuous Chess.com screen capture (ReplayKit) is a later milestone. Vision is still stubbed for camera/Photos picks.

## Run / verify

```bash
flutter pub get
flutter analyze
flutter test
```

## IPA (requires macOS CI — not Linux)

See [../docs/ios-sideload.md](../docs/ios-sideload.md). Primary: Codemagic `ios-unsigned-ipa` → `chesshihi-unsigned.ipa` for your external signer.
