#!/usr/bin/env bash
# Ensure Stockfish NNUE nets exist where the iOS pod expects them, and patch the
# stockfish 1.8.x podspec so Release+LTO builds can find them.
#
# Background (stockfish 1.8.0/1.8.1, Flutter iOS release):
#   The pod downloads nets into Stockfish/src (used via -I for Debug assemble).
#   Release uses -flto=full, so .incbin is resolved at link time against
#   ${PODS_ROOT} (app/ios/Pods) — not Stockfish/src — yielding:
#     Could not find incbin file 'nn-c288c895ea92.nnue'
#     Could not find incbin file 'nn-37f18f62d772.nnue'
#   See: https://github.com/ArjanAswal/Stockfish/issues/57
#
# Run after `flutter pub get` and before `flutter build ipa` / `pod install`.
# Safe to re-run (idempotent). Does not require macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP_DIR:-$ROOT/app}"

# Official Stockfish 18 default nets (must match evaluate.h in the package).
BIG_NNUE="nn-c288c895ea92.nnue"
SMALL_NNUE="nn-37f18f62d772.nnue"
NNUE_BASE_URL="${NNUE_BASE_URL:-https://tests.stockfishchess.org/api/nn}"

# Reject truncated / HTML error bodies (official sizes ~104MB / ~3.4MB).
BIG_MIN_BYTES=100000000
SMALL_MIN_BYTES=1000000

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

find_stockfish_ios_root() {
  local pkg_config="$APP/.dart_tool/package_config.json"
  if [[ -f "$pkg_config" ]]; then
    local uri
    uri="$(python3 - "$pkg_config" <<'PY'
import json, sys, urllib.parse, pathlib
cfg = json.load(open(sys.argv[1]))
for p in cfg.get("packages", []):
    if p.get("name") == "stockfish":
        root = urllib.parse.unquote(urllib.parse.urlparse(p["rootUri"]).path)
        path = pathlib.Path(root)
        if not path.is_absolute():
            path = (pathlib.Path(sys.argv[1]).parent / path).resolve()
        print(path)
        break
else:
    sys.exit(1)
PY
)" || true
    if [[ -n "${uri:-}" && -d "$uri/ios" ]]; then
      printf '%s\n' "$uri/ios"
      return 0
    fi
  fi

  local cache="${PUB_CACHE:-$HOME/.pub-cache}"
  local candidate
  for candidate in \
    "$cache/hosted/pub.dev"/stockfish-* \
    "$cache/hosted/pub.dartlang.org"/stockfish-*
  do
    if [[ -d "$candidate/ios/Stockfish/src" ]]; then
      printf '%s\n' "$candidate/ios"
      return 0
    fi
  done
  return 1
}

download_nnue() {
  local name="$1"
  local dest_dir="$2"
  local min_bytes="$3"
  local dest="$dest_dir/$name"
  mkdir -p "$dest_dir"

  if [[ -f "$dest" ]]; then
    local size
    size="$(wc -c <"$dest" | tr -d ' ')"
    if [[ "$size" -ge "$min_bytes" ]]; then
      log "$name already present (${size} bytes)"
      return 0
    fi
    log "$name present but too small (${size}B) — re-downloading"
    rm -f "$dest"
  fi

  log "Downloading $name → $dest_dir"
  local tmp
  tmp="$(mktemp "$dest_dir/.${name}.XXXXXX")"
  if ! curl --fail --location --retry 4 --retry-delay 2 \
      --connect-timeout 30 --max-time 600 \
      --output "$tmp" "$NNUE_BASE_URL/$name"; then
    rm -f "$tmp"
    die "failed to download $NNUE_BASE_URL/$name"
  fi
  local size
  size="$(wc -c <"$tmp" | tr -d ' ')"
  if [[ "$size" -lt "$min_bytes" ]]; then
    rm -f "$tmp"
    die "$name download too small (${size}B < ${min_bytes}B) — check network / URL"
  fi
  mv -f "$tmp" "$dest"
  log "Wrote $dest (${size} bytes)"
}

# Patch podspec script phases so each net is also copied to ${PODS_ROOT}
# (where Release LTO .incbin resolves). Idempotent.
patch_podspec() {
  local podspec="$1"
  [[ -f "$podspec" ]] || die "podspec not found: $podspec"

  if grep -q 'cmp -s.*PODS_ROOT\|PODS_ROOT}/nn-' "$podspec"; then
    log "podspec already patched for PODS_ROOT NNUE copy"
    return 0
  fi

  log "Patching $podspec (copy nets to \${PODS_ROOT} for Release LTO)"
  python3 - "$podspec" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()

def script_for(name: str) -> str:
    return (
        'cd \\"${PODS_TARGET_SRCROOT}/Stockfish/src\\" && '
        '{ [ -e \'' + name + '\' ] || curl --fail --location --retry 4 --remote-name '
        '\'https://tests.stockfishchess.org/api/nn/' + name + '\'; } && '
        '{ cmp -s \'' + name + '\' \\"${PODS_ROOT}/' + name + '\\" || '
        'cp \'' + name + '\' \\"${PODS_ROOT}/' + name + '\\"; }'
    )

def repl(match: re.Match) -> str:
    return f':script => "{script_for(match.group(1))}"'

new, n = re.subn(
    r':script => "cd \\"\$\{PODS_TARGET_SRCROOT\}/Stockfish/src\\" && \[ -e \'(nn-[^\'"]+\.nnue)\' \] \|\| curl[^"]+"',
    repl,
    text,
)
if n < 1:
    sys.stderr.write("error: could not patch stockfish.podspec script phases\n")
    sys.exit(1)
path.write_text(new)
print(f"patched {path} ({n} script phase(s))")
PY
}

stage_into_ios_dirs() {
  local src_dir="$1"
  local targets=()
  [[ -d "$APP/ios/Pods" ]] && targets+=("$APP/ios/Pods")
  targets+=("$APP/ios")

  local t name
  for t in "${targets[@]}"; do
    mkdir -p "$t"
    for name in "$BIG_NNUE" "$SMALL_NNUE"; do
      if [[ -f "$src_dir/$name" ]]; then
        if [[ ! -f "$t/$name" ]] || ! cmp -s "$src_dir/$name" "$t/$name"; then
          cp -f "$src_dir/$name" "$t/$name"
          log "Staged $name → $t/"
        fi
      fi
    done
  done
}

main() {
  [[ -d "$APP" ]] || die "Flutter app dir not found: $APP"
  log "Resolving stockfish iOS plugin root…"
  local ios_root
  ios_root="$(find_stockfish_ios_root)" \
    || die "stockfish package not found — run 'cd app && flutter pub get' first"

  local src="$ios_root/Stockfish/src"
  local podspec="$ios_root/stockfish.podspec"
  [[ -d "$src" ]] || die "Stockfish src missing under $ios_root"
  [[ -f "$podspec" ]] || die "stockfish.podspec missing under $ios_root"

  log "stockfish ios root: $ios_root"
  download_nnue "$BIG_NNUE" "$src" "$BIG_MIN_BYTES"
  download_nnue "$SMALL_NNUE" "$src" "$SMALL_MIN_BYTES"
  patch_podspec "$podspec"
  stage_into_ios_dirs "$src"
  log "Stockfish NNUE ready for iOS archive/release build"
}

main "$@"
