# Chesshihi (Flutter)

iOS-oriented slice: board frame → FEN → Stockfish → optional spoken best move + explanation.

**Fair play:** analysis, training, and accessibility only — not live online engine assist.

## Features (PoC)

- Samples / Photos / **camera capture**
- **Side to move** control (White/Black) — Stockfish analyzes the active color in the FEN
- Eval + short **why this move** (score / mate / depth / main line)
- **Speak best move** toggle (off = on-screen only)
- **Live watch** (training/review): each new frame auto-analyzes
- **ReplayKit screen capture**: user starts Screen Recording from Control Center and picks Chesshihi; frames land in an App Group and feed the analyze path (throttled / identical-frame skip). Vision is still stubbed for camera/Photos/broadcast frames.

## Run / verify

```bash
flutter pub get
flutter analyze
flutter test
```

## IPA (requires macOS CI — not Linux)

See [../docs/ios-sideload.md](../docs/ios-sideload.md). Primary: Codemagic `ios-unsigned-ipa` → `chesshihi-unsigned.ipa` for your external signer.

ReplayKit / App Groups / signer checklist: [../docs/replaykit.md](../docs/replaykit.md).
