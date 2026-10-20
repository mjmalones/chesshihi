import CoreImage
import ReplayKit
import UIKit

/// ReplayKit Broadcast Upload Extension.
///
/// The user must start Screen Recording from Control Center and pick
/// **Chesshihi**. There is no silent capture of Chess.com (or any app).
/// Frames are written into the App Group shared container for the Flutter
/// host to poll — analysis / training / accessibility only.
class SampleHandler: RPBroadcastSampleHandler {
  private var lastWriteAt: Date = .distantPast
  private var lastContentHash: String?

  override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    BroadcastShared.writeStatus(.started)
  }

  override func broadcastPaused() {
    BroadcastShared.writeStatus(.paused)
  }

  override func broadcastResumed() {
    BroadcastShared.writeStatus(.started)
  }

  override func broadcastFinished() {
    BroadcastShared.writeStatus(.finished)
  }

  override func processSampleBuffer(
    _ sampleBuffer: CMSampleBuffer,
    with sampleBufferType: RPSampleBufferType
  ) {
    guard sampleBufferType == .video else { return }

    let now = Date()
    if now.timeIntervalSince(lastWriteAt)
      < BroadcastShared.minWriteIntervalSeconds
    {
      return
    }

    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }

    guard let jpeg = Self.jpegData(from: imageBuffer, maxWidth: 1280, quality: 0.55)
    else {
      return
    }

    let hash = Self.fastHash(jpeg)
    if hash == lastContentHash {
      // Identical frame — skip write and host re-analysis.
      return
    }

    guard let container = BroadcastShared.containerURL else {
      BroadcastShared.writeStatus(.error)
      return
    }

    let dest = container.appendingPathComponent(BroadcastShared.relativeFrameName)
    do {
      try jpeg.write(to: dest, options: .atomic)
      lastWriteAt = now
      lastContentHash = hash
      BroadcastShared.writeStatus(
        .started,
        framePath: dest.path,
        contentHash: hash,
        bumpFrameCount: true
      )
    } catch {
      BroadcastShared.writeStatus(.error)
    }
  }

  /// Downscale + JPEG encode a CVPixelBuffer for the shared container.
  private static func jpegData(
    from pixelBuffer: CVPixelBuffer,
    maxWidth: CGFloat,
    quality: CGFloat
  ) -> Data? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
      return nil
    }

    let width = CGFloat(cgImage.width)
    let height = CGFloat(cgImage.height)
    let scale = width > maxWidth ? maxWidth / width : 1.0
    let targetSize = CGSize(width: width * scale, height: height * scale)

    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let uiImage = renderer.image { _ in
      UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: targetSize))
    }
    return uiImage.jpegData(compressionQuality: quality)
  }

  /// Cheap content fingerprint so identical frames are skipped.
  private static func fastHash(_ data: Data) -> String {
    var hash: UInt64 = 5381
    // Sample up to 4 KiB spread across the buffer.
    let step = max(1, data.count / 4096)
    var i = 0
    while i < data.count {
      hash = ((hash << 5) &+ hash) &+ UInt64(data[i])
      i += step
    }
    hash ^= UInt64(data.count)
    return String(hash, radix: 16)
  }
}
