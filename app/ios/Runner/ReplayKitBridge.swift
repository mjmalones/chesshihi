import Flutter
import Foundation

/// Method channel bridge: Flutter polls App Group state written by the
/// Broadcast Upload Extension. Channel: `chesshihi/replaykit`.
enum ReplayKitBridge {
  static let channelName = "chesshihi/replaykit"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getState":
        result(BroadcastShared.readState())
      case "clearState":
        BroadcastShared.clearState()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
