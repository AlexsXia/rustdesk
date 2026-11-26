import AVFoundation
import AVKit
import Flutter
import UIKit

/// Puts the remote screen into a system Picture-in-Picture window, so it keeps
/// floating above other apps while the session stays connected.
final class UuPipController: NSObject, AVPictureInPictureControllerDelegate,
  AVPictureInPictureSampleBufferPlaybackDelegate
{
  static let shared = UuPipController()

  private let displayLayer = AVSampleBufferDisplayLayer()
  private var pipController: AVPictureInPictureController?
  private weak var hostViewController: UIViewController?
  private var previousAudioCategory: AVAudioSession.Category?

  private override init() {
    super.init()
    displayLayer.videoGravity = .resizeAspect
    displayLayer.backgroundColor = UIColor.black.cgColor
  }

  static var isSupported: Bool {
    AVPictureInPictureController.isPictureInPictureSupported()
  }

  func configure(viewController: UIViewController) {
    hostViewController = viewController
  }

  func start() -> Bool {
    guard Self.isSupported else { return false }
    if let pipController = pipController, pipController.isPictureInPictureActive {
      return true
    }
    if displayLayer.superlayer == nil {
      guard let hostViewController = hostViewController,
        hostViewController.isViewLoaded
      else { return false }
      displayLayer.frame = CGRect(x: 0, y: 0, width: 4, height: 4)
      hostViewController.view.layer.insertSublayer(displayLayer, at: 0)
    }
    if pipController == nil {
      let source = AVPictureInPictureController.ContentSource(
        sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
      let controller = AVPictureInPictureController(contentSource: source)
      controller.delegate = self
      pipController = controller
    }
    activateAudioSession()
    pipController?.startPictureInPicture()
    return true
  }

  func stop() {
    guard let pipController = pipController,
      pipController.isPictureInPictureActive
    else { return }
    pipController.stopPictureInPicture()
  }

  /// `rgba` holds `width * height * 4` bytes in RGBA order, as Flutter encodes it.
  func pushFrame(rgba: Data, width: Int, height: Int) {
    guard width > 0, height > 0, rgba.count >= width * height * 4,
      let sampleBuffer = Self.makeSampleBuffer(
        rgba: rgba, width: width, height: height)
    else { return }
    if displayLayer.status == .failed {
      displayLayer.flush()
    }
    displayLayer.enqueue(sampleBuffer)
  }

  // The audio session keeps the app alive in the background next to the
  // Picture-in-Picture window; mixing avoids pausing the user's own music.
  private func activateAudioSession() {
    let session = AVAudioSession.sharedInstance()
    if previousAudioCategory == nil {
      previousAudioCategory = session.category
    }
    try? session.setCategory(
      .playback, mode: .moviePlayback, options: [.mixWithOthers])
    try? session.setActive(true)
  }

  private func deactivateAudioSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
    if let previous = previousAudioCategory {
      previousAudioCategory = nil
      try? session.setCategory(previous)
    }
  }

  private static func makeSampleBuffer(
    rgba: Data, width: Int, height: Int
  ) -> CMSampleBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attributes: [String: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
      attributes as CFDictionary, &pixelBuffer)
    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      return nil
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    rgba.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
      guard let source = bytes.baseAddress else { return }
      for y in 0..<height {
        let sourceRow = source.advanced(by: y * width * 4)
        let destinationRow = base.advanced(by: y * stride)
        for x in 0..<width {
          let offset = x * 4
          let r = sourceRow.load(fromByteOffset: offset, as: UInt8.self)
          let g = sourceRow.load(fromByteOffset: offset + 1, as: UInt8.self)
          let b = sourceRow.load(fromByteOffset: offset + 2, as: UInt8.self)
          destinationRow.storeBytes(of: b, toByteOffset: offset, as: UInt8.self)
          destinationRow.storeBytes(
            of: g, toByteOffset: offset + 1, as: UInt8.self)
          destinationRow.storeBytes(
            of: r, toByteOffset: offset + 2, as: UInt8.self)
          destinationRow.storeBytes(
            of: 255, toByteOffset: offset + 3, as: UInt8.self)
        }
      }
    }
    var formatDescription: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault, imageBuffer: buffer,
      formatDescriptionOut: &formatDescription)
    guard let format = formatDescription else { return nil }
    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 30),
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
      decodeTimeStamp: .invalid)
    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault, imageBuffer: buffer,
      formatDescription: format, sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer)
    guard let sampleBuffer = sampleBuffer else { return nil }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(
      sampleBuffer, createIfNecessary: true),
      CFArrayGetCount(attachments) > 0
    {
      let attachment = unsafeBitCast(
        CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(
        attachment,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately)
          .toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
    return sampleBuffer
  }

  // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {}

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    deactivateAudioSession()
    UuPipChannel.notify("closed")
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    deactivateAudioSession()
    NSLog("Picture in Picture failed to start: %@", error.localizedDescription)
    UuPipChannel.notify("failed")
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
      completionHandler: @escaping (Bool) -> Void
  ) {
    guard let windowScene = hostViewController?.viewIfLoaded?.window?
      .windowScene
    else {
      completionHandler(false)
      return
    }
    UIApplication.shared.requestSceneSessionActivation(
      windowScene.session, userActivity: nil, options: nil
    ) { _ in
      completionHandler(true)
    }
  }
}

/// Bridges the Picture-in-Picture controller to the Flutter side.
enum UuPipChannel {
  private static var channel: FlutterMethodChannel?

  static func register(
    messenger: FlutterBinaryMessenger, viewController: UIViewController
  ) {
    UuPipController.shared.configure(viewController: viewController)
    let channel = FlutterMethodChannel(name: "uu/pip", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSupported":
        result(UuPipController.isSupported)
      case "startPip":
        result(UuPipController.shared.start())
      case "stopPip":
        UuPipController.shared.stop()
        result(nil)
      case "pushFrame":
        guard let arguments = call.arguments as? [String: Any],
          let data = arguments["bytes"] as? FlutterStandardTypedData,
          let width = arguments["width"] as? Int,
          let height = arguments["height"] as? Int
        else {
          result(
            FlutterError(
              code: "bad_args", message: "pushFrame needs bytes/width/height",
              details: nil))
          return
        }
        UuPipController.shared.pushFrame(
          rgba: data.data, width: width, height: height)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func notify(_ reason: String) {
    DispatchQueue.main.async {
      channel?.invokeMethod("pipStopped", arguments: reason)
    }
  }
}
