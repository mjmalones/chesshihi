# Chesshihi

**Fair play:** Chesshihi is for **post-game analysis, training, and accessibility** (e.g. spoken recommendations for visually impaired players). It is **not** for live online engine assistance. Chess.com Fair Play prohibits engine help during live games — do not use this tool to hide or enable assistance in rated/casual online play.

Two slices live in this repo:

| Slice | Path | What it does |
|-------|------|----------------|
| Python vision PoC | `src/chesshihi/` | Screenshot → OpenCV FEN → system Stockfish (Linux) |
| Flutter iOS app | `app/` | Photos/sample/ReplayKit board → on-device vision → FEN → Stockfish → TTS |

## Hard constraint: no Linux → IPA

**Flutter cannot build iOS without macOS + Xcode.** Linux/Windows Flutter will not emit an `.ipa`. Karl has **no Mac**, so the supported path is **cloud macOS CI** that produces an **unsigned IPA** for his external signer (Sideloadly / AltStore / etc.). No Apple Developer paid account is required for the build step.

→ Full steps: **[docs/ios-sideload.md](docs/ios-sideload.md)** · ReplayKit: **[docs/replaykit.md](docs/replaykit.md)** · Vision: **[docs/vision.md](docs/vision.md)**

### Get an IPA for your signer (primary: Codemagic)

1. Connect this repo to [Codemagic](https://codemagic.io) (free account is enough).
2. Use in-repo [`codemagic.yaml`](codemagic.yaml) workflow **`ios-unsigned-ipa`**.
3. Start a build → download artifact **`chesshihi-unsigned.ipa`**.
4. Re-sign / sideload with your own signer.

Alternate (if the repo is on GitHub): [`.github/workflows/ios-ipa.yml`](.github/workflows/ios-ipa.yml) on `macos-latest` → artifact `chesshihi-unsigned.ipa`.

Local Mac helper (optional, not required): `./scripts/build-unsigned-ipa.sh` → `dist/chesshihi-unsigned.ipa` (exits on Linux by design).

---

## Flutter iOS app (`app/`)

Minimal device slice:

- Pick a board screenshot from Photos, use shipped sample assets, or **ReplayKit** broadcast (Control Center → Screen Recording → Chesshihi)
- **On-device vision** (pure-Dart template matching, same concepts as the Python OpenCV PoC) → real FEN, or a clear error if no board is found
- Assumes **White at bottom**; set **Side to move** in the UI (vision does not read clocks)
- Run on-device Stockfish (`stockfish` Flutter package) and **speak** the best move (`flutter_tts`)
- Fair-play banner in the UI — no silent Chess.com capture
- **No new native deps** for vision (no OpenCV iOS) — Codemagic unsigned IPA / NNUE script unchanged

### Develop / verify on Linux

```bash
cd app
flutter pub get
flutter analyze
flutter test
```

`flutter build ios` / `flutter build ipa` **will fail on Linux** — expected. Use Codemagic or GitHub Actions for the IPA.

### How iOS shares FEN + engine with the Python PoC later

| Python PoC | Flutter / iOS |
|------------|----------------|
| `vision/template_matcher.py` | `app/lib/vision/template_matcher.dart` (pure Dart; pluggable for ML later) |
| Same FEN string | Same FEN string to Stockfish UCI |
| System Stockfish UCI | `stockfish` package (iOS/Android FFI) |
| CLI print | TTS + Semantics announcements |

Keep the Python PoC for Linux smoke tests; the Flutter app runs the Dart port on device.

---

## Python vision PoC (`src/chesshihi/`)

Static pipeline: **board screenshot → FEN → Stockfish best move**.

### Requirements

- Python 3.11+
- [uv](https://docs.astral.sh/uv/) (recommended) or pip
- Stockfish binary (`sudo apt install stockfish` — often `/usr/games/stockfish`)

### Install & run

```bash
uv sync
uv run chesshihi prepare-assets
uv run chesshihi doctor
uv run chesshihi analyze
uv run chesshihi analyze assets/samples/italian_game.png --movetime 500
uv run pytest -q
```

---

## Layout

```
app/                      # Flutter Chesshihi (iOS + Android targets)
docs/ios-sideload.md      # Unsigned IPA via Codemagic / GHA (no local Mac)
docs/replaykit.md         # Broadcast capture + signer checklist
docs/vision.md            # Pixels → FEN: capabilities & limits
codemagic.yaml            # Primary cloud macOS IPA workflow
.github/workflows/ios-ipa.yml
scripts/build-unsigned-ipa.sh
scripts/ensure-stockfish-nnue.sh  # NNUE nets for iOS Release/archive (stockfish 1.8.x)
src/chesshihi/            # Python OpenCV → FEN → Stockfish PoC
assets/                   # Shared sample boards + templates (PoC)
```
