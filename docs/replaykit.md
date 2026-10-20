# Chesshihi — ReplayKit screen capture

**Fair play:** analysis, training, and accessibility only. Chesshihi does **not** silently capture Chess.com. The user must start **Screen Recording** from Control Center and explicitly pick **Chesshihi**. Do not use for live online engine assist.

## What shipped

| Piece | Location | Role |
|-------|----------|------|
| Broadcast Upload Extension | `app/ios/BroadcastUploadExtension/` | Receives ReplayKit sample buffers; writes latest JPEG + status into App Group |
| Shared constants | `app/ios/Shared/BroadcastShared.swift` | App Group id, keys, throttle interval (compiled into app + extension) |
| Host bridge | `app/ios/Runner/ReplayKitBridge.swift` | Method channel `chesshihi/replaykit` → `getState` / `clearState` |
| Flutter poller + UI | `app/lib/capture/`, `app/lib/main.dart` | Instructions, connection status, throttle / identical-frame skip → existing analyze path |

Vision runs the on-device **template-matching** pipeline (same as Photos/camera/samples) → real FEN when a board is found, or a clear error when not. See [vision.md](vision.md). Frames still feed preview → recognize → Stockfish → optional TTS.

## App Group / entitlements

| Item | Value |
|------|--------|
| App Group | `group.com.chesshihi.chesshihi` |
| Host app bundle id | `com.chesshihi.chesshihi` |
| Extension bundle id | `com.chesshihi.chesshihi.BroadcastUploadExtension` |
| Host entitlements | `app/ios/Runner/Runner.entitlements` |
| Extension entitlements | `app/ios/BroadcastUploadExtension/BroadcastUploadExtension.entitlements` |

Shared container file: `latest_frame.jpg`  
Shared `UserDefaults(suiteName:)` keys: `broadcastStatus`, `latestFramePath`, `updatedAtMs`, `contentHash`, `frameCount`.

### Unsigned IPA (`--no-codesign`)

Codemagic / `flutter build ipa --no-codesign` can still **compile and embed** `BroadcastUploadExtension.appex` inside `Runner.app/PlugIns/`. App Groups **do not work at runtime** until a signer attaches provisioning that includes:

1. The **host app** id + App Group `group.com.chesshihi.chesshihi`
2. The **extension** id + the **same** App Group
3. Both binaries re-signed (and the IPA’s embedded.mobileprovision / entitlements updated as your tool requires)

If the App Group is missing after sideload, the UI status will show App Group / broadcast errors and no frames will appear.

## Karl’s signer checklist

1. Build Codemagic workflow **`ios-unsigned-ipa`** on this branch → `chesshihi-unsigned.ipa`.
2. Confirm the IPA contains:
   - `Payload/Runner.app`
   - `Payload/Runner.app/PlugIns/BroadcastUploadExtension.appex`
3. Sign **both** the app and the appex with profiles that include App Group `group.com.chesshihi.chesshihi`.
4. Install on device.
5. First launch: open Chesshihi, read the Screen capture section, enable **Watch broadcast frames**.

## Device test steps (after sideload)

1. Open **Chesshihi**. Confirm fair-play banner and **Screen capture (ReplayKit)** section.
2. Turn on **Watch broadcast frames** (also enables Live watch).
3. Open **Control Center** → long-press **Screen Recording**.
4. Select **Chesshihi** as the broadcast destination → **Start Broadcast**.
5. Switch to a board you want to **review / train** (not for live rated assist).
6. Return to Chesshihi: status should show broadcasting; preview updates when frames change; recognized FEN (or a board-not-found error) + analyze when Live watch is on and recognition succeeds.
7. Stop broadcast from the status bar / Control Center → status becomes finished / idle.

Identical frames are skipped (extension hash + host `FrameIngestPolicy`). Writes are throttled (~2 fps max).

## Info.plist notes

- Extension `CFBundleDisplayName` = **Chesshihi** (name shown in the broadcast picker).
- `NSExtensionPointIdentifier` = `com.apple.broadcast-services-upload`
- `RPBroadcastProcessMode` = `RPBroadcastProcessModeSampleBuffer`
- Host still has Photos / Camera usage strings for the non-ReplayKit paths.

## Related

- Vision / FEN limits: [vision.md](vision.md)
- Sideload / Codemagic: [ios-sideload.md](ios-sideload.md)
- Flutter app notes: [../app/README.md](../app/README.md)
