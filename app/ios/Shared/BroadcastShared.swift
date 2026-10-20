import Foundation

/// Constants shared by the Flutter host (Runner) and the ReplayKit
/// Broadcast Upload Extension. Keep both targets compiling this file.
enum BroadcastShared {
  /// App Group — must match Runner.entitlements and
  /// BroadcastUploadExtension.entitlements. Karl’s signer must include this
  /// App Group on **both** the app and the extension profiles.
  static let appGroupId = "group.com.chesshihi.chesshihi"

  static let statusKey = "broadcastStatus"
  static let framePathKey = "latestFramePath"
  static let updatedAtKey = "updatedAtMs"
  static let contentHashKey = "contentHash"
  static let frameCountKey = "frameCount"
  static let relativeFrameName = "latest_frame.jpg"

  /// Minimum interval between frame writes from the extension (throttle).
  static let minWriteIntervalSeconds: TimeInterval = 0.5

  enum Status: String {
    case idle
    case started
    case paused
    case finished
    case error
  }

  static var containerURL: URL? {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    )
  }

  static var defaults: UserDefaults? {
    UserDefaults(suiteName: appGroupId)
  }

  static func writeStatus(
    _ status: Status,
    framePath: String? = nil,
    contentHash: String? = nil,
    bumpFrameCount: Bool = false
  ) {
    guard let defaults else { return }
    defaults.set(status.rawValue, forKey: statusKey)
    defaults.set(Int(Date().timeIntervalSince1970 * 1000), forKey: updatedAtKey)
    if let framePath {
      defaults.set(framePath, forKey: framePathKey)
    }
    if let contentHash {
      defaults.set(contentHash, forKey: contentHashKey)
    }
    if bumpFrameCount {
      let n = defaults.integer(forKey: frameCountKey) + 1
      defaults.set(n, forKey: frameCountKey)
    }
    defaults.synchronize()
  }

  static func readState() -> [String: Any] {
    guard let defaults else {
      return [
        "available": false,
        "status": Status.idle.rawValue,
        "appGroupReady": false,
      ]
    }
    let containerReady = containerURL != nil
    return [
      "available": true,
      "appGroupReady": containerReady,
      "status": (defaults.string(forKey: statusKey) ?? Status.idle.rawValue),
      "framePath": defaults.string(forKey: framePathKey) as Any,
      "updatedAtMs": defaults.object(forKey: updatedAtKey) as Any,
      "contentHash": defaults.string(forKey: contentHashKey) as Any,
      "frameCount": defaults.integer(forKey: frameCountKey),
      "appGroupId": appGroupId,
    ]
  }

  static func clearState() {
    guard let defaults else { return }
    defaults.removeObject(forKey: statusKey)
    defaults.removeObject(forKey: framePathKey)
    defaults.removeObject(forKey: updatedAtKey)
    defaults.removeObject(forKey: contentHashKey)
    defaults.removeObject(forKey: frameCountKey)
    defaults.synchronize()
    if let url = containerURL?.appendingPathComponent(relativeFrameName) {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
