# Chesshihi — unsigned IPA for sideload (no Mac required locally)

**Hard constraint:** Flutter **cannot** build iOS binaries on Linux or Windows. There is no cross-compile path. A **macOS + Xcode** environment is always required to produce a `.ipa`. If you have no Mac, use **cloud macOS CI** below.

This path does **not** need an Apple Developer paid account. Build unsigned / no-codesign, then re-sign with your own signer (Sideloadly, AltStore, TrollStore, etc.).

Fair play: Chesshihi is for **analysis, training, and accessibility** only — not live online engine assist.

## Primary path: Codemagic (recommended, minimal setup)

In-repo config: [`codemagic.yaml`](../codemagic.yaml) → workflow `ios-unsigned-ipa`.

1. Create a free account at [codemagic.io](https://codemagic.io) and **connect [mjmalones/chesshihi](https://github.com/mjmalones/chesshihi)**.
2. Codemagic should detect `codemagic.yaml`. Select workflow **Chesshihi unsigned IPA** / `ios-unsigned-ipa`.
3. Start a build (manual is fine).
4. When green, download the artifact **`chesshihi-unsigned.ipa`**.
5. Feed that `.ipa` to your signer and install on device.

What the workflow runs (conceptually):

```bash
cd app && flutter pub get
./scripts/ensure-stockfish-nnue.sh   # Stockfish NNUE nets (required for iOS Release)
cd app && flutter build ipa --no-codesign
# fallback if needed: flutter build ios --no-codesign + zip Payload/Runner.app → .ipa
```

### Stockfish NNUE prerequisite

The `stockfish` Flutter plugin (1.8.x) embeds two neural-net eval files at compile time via `incbin`:

- `nn-c288c895ea92.nnue` (~104 MB)
- `nn-37f18f62d772.nnue` (~3.4 MB)

Debug builds find them under the pod’s `Stockfish/src` (`-I`). **Release / archive builds use `-flto=full`**, so the linker resolves `.incbin` against `ios/Pods/` instead — without the files there you get `Could not find incbin file 'nn-….nnue'`.

`scripts/ensure-stockfish-nnue.sh` (wired into Codemagic, GitHub Actions, and `build-unsigned-ipa.sh`) downloads the nets into the plugin, patches the podspec to also copy them into `${PODS_ROOT}`, and stages copies under `app/ios/`. Nets are **not** committed (too large); CI always fetches them. See [ArjanAswal/Stockfish#57](https://github.com/ArjanAswal/Stockfish/issues/57).

## Alternate path: GitHub Actions `macos-latest`

In-repo config: [`.github/workflows/ios-ipa.yml`](../.github/workflows/ios-ipa.yml).

Use this if the repo (or a mirror) is on GitHub:

1. Push this branch / merge to a GitHub remote that has Actions enabled.
2. Actions → **iOS unsigned IPA** → **Run workflow**.
3. Download artifact **`chesshihi-unsigned-ipa`** → `chesshihi-unsigned.ipa`.
4. Re-sign with your signer.

Origin-only remotes will not run this YAML until mirrored to GitHub; prefer Codemagic in that case.

## Optional: script on a Mac (not required)

If you ever have macOS + Xcode locally:

```bash
./scripts/build-unsigned-ipa.sh
# → dist/chesshihi-unsigned.ipa
# (runs ensure-stockfish-nnue.sh after pub get)
```

On Linux/Windows the IPA script **exits with an error** and points you at CI — by design. You can still run `./scripts/ensure-stockfish-nnue.sh` on Linux after `flutter pub get` to verify NNUE download + podspec patch.

## After you have the IPA

1. Open Sideloadly / AltStore / your preferred tool.
2. Select `chesshihi-unsigned.ipa`.
3. Sign with your certificate / Apple ID / device provisioning as your tool requires.
4. Install on the iPhone.

No paid Apple Developer Program membership is required for the **build** step documented here; your signer’s own requirements still apply for install.

## Verify the Flutter app without an IPA (Linux)

```bash
cd app
flutter pub get
flutter analyze
flutter test
```

`flutter build ios` / `flutter build ipa` will fail on Linux — expected.
