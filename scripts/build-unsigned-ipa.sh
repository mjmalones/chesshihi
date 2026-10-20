#!/usr/bin/env bash
# Build an unsigned/ad-hoc .ipa for an external signer (Sideloadly, AltStore, etc.).
#
# REQUIRES macOS + Xcode. Linux/Windows cannot produce an iOS IPA — Flutter does
# not cross-compile iOS from non-macOS hosts. Prefer Codemagic / GitHub Actions
# macos runners (see docs/ios-sideload.md) if you have no Mac.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
IPA_NAME="${IPA_NAME:-chesshihi-unsigned.ipa}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this script must run on macOS (got $(uname -s))." >&2
  echo "Flutter cannot build iOS without macOS/Xcode." >&2
  echo "Use Codemagic (codemagic.yaml) or GitHub Actions (.github/workflows/ios-ipa.yml)." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "error: flutter not on PATH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
cd "$APP"

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build ipa --no-codesign"
# Produce an IPA without Apple signing; Karl’s external signer re-signs later.
flutter build ipa --no-codesign --export-method ad-hoc 2>/dev/null \
  || flutter build ipa --no-codesign

# Prefer Flutter’s packaged IPA if present.
BUILT_IPA="$(find build/ios/ipa -name '*.ipa' 2>/dev/null | head -1 || true)"
if [[ -n "${BUILT_IPA}" ]]; then
  cp -f "$BUILT_IPA" "$OUT_DIR/$IPA_NAME"
  echo "Wrote $OUT_DIR/$IPA_NAME (from flutter build ipa)"
  exit 0
fi

# Fallback: package Runner.app into Payload/*.ipa manually.
echo "==> flutter build ios --no-codesign (fallback package)"
flutter build ios --no-codesign --release

APP_PATH=""
for candidate in \
  build/ios/iphoneos/Runner.app \
  build/ios/Release-iphoneos/Runner.app
do
  if [[ -d "$candidate" ]]; then
    APP_PATH="$candidate"
    break
  fi
done

if [[ -z "$APP_PATH" ]]; then
  echo "error: Runner.app not found under build/ios/" >&2
  find build/ios -maxdepth 3 -name 'Runner.app' 2>/dev/null || true
  exit 1
fi

STAGE="$(mktemp -d)"
mkdir -p "$STAGE/Payload"
cp -R "$APP_PATH" "$STAGE/Payload/"
(
  cd "$STAGE"
  zip -qr "$OUT_DIR/$IPA_NAME" Payload
)
rm -rf "$STAGE"

echo "Wrote $OUT_DIR/$IPA_NAME (manual Payload zip)"
echo "Hand this file to your external signer (no Apple Developer paid account required for the build step)."
