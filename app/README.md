# Chesshihi (Flutter)

iOS-oriented slice: board screenshot → FEN → Stockfish → spoken best move.

**Fair play:** analysis, training, and accessibility only — not live online engine assist.

## Run / verify

```bash
flutter pub get
flutter analyze
flutter test
```

## IPA (requires macOS CI — not Linux)

See [../docs/ios-sideload.md](../docs/ios-sideload.md). Primary: Codemagic `ios-unsigned-ipa` → `chesshihi-unsigned.ipa` for your external signer.
