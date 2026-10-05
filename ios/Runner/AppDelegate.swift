import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioBridge: SoundAudioBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "sound_notes/audio", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    let bridge = SoundAudioBridge()
    audioBridge = bridge
    channel.setMethodCallHandler { call, result in
      bridge.handle(call, result: result)
    }
  }
}

private final class SoundAudioBridge: NSObject, AVAudioRecorderDelegate {
  private var recorder: AVAudioRecorder?
  private var fileURL: URL?
  private var failure: String?
  private var starting = false
  private var generation = 0

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(interrupted), name: AVAudioSession.interruptionNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification,
      object: nil)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      guard !starting, recorder == nil else {
        result(FlutterError(code: "busy", message: "이미 녹음 중입니다.", details: nil))
        return
      }
      starting = true
      generation += 1
      let current = generation
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        DispatchQueue.main.async {
          guard current == self.generation else {
            result(FlutterError(code: "cancelled", message: "녹음이 취소되었습니다.", details: nil))
            return
          }
          self.starting = false
          guard granted else {
            result(FlutterError(code: "permission", message: "설정에서 소리노트의 마이크 접근을 허용해주세요.", details: nil))
            return
          }
          guard UIApplication.shared.applicationState == .active else {
            result(FlutterError(code: "inactive", message: "앱으로 돌아와 다시 녹음해주세요.", details: nil))
            return
          }
          do {
            self.failure = nil
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
              .appendingPathComponent("sound-note-\(UUID().uuidString).wav")
            self.fileURL = url
            let recorder = try AVAudioRecorder(url: url, settings: [
              AVFormatIDKey: kAudioFormatLinearPCM,
              AVSampleRateKey: 16000.0,
              AVNumberOfChannelsKey: 1,
              AVLinearPCMBitDepthKey: 16,
              AVLinearPCMIsFloatKey: false,
              AVLinearPCMIsBigEndianKey: false,
            ])
            self.recorder = recorder
            recorder.delegate = self
            guard recorder.record(forDuration: 15) else {
              throw NSError(domain: "SoundNotes", code: 1)
            }
            result(nil)
          } catch {
            self.cleanup()
            result(FlutterError(code: "recording", message: "마이크를 시작할 수 없습니다. 다시 시도해주세요.", details: nil))
          }
        }
      }
    case "stop":
      recorder?.stop()
      defer { cleanup() }
      if let failure = failure {
        result(FlutterError(code: "interrupted", message: failure, details: nil))
        return
      }
      guard let url = fileURL, let data = try? Data(contentsOf: url), data.count > 44 else {
        result(FlutterError(code: "empty", message: "녹음된 소리가 없습니다. 다시 녹음해주세요.", details: nil))
        return
      }
      result(FlutterStandardTypedData(bytes: data))
    case "cancel":
      generation += 1
      starting = false
      cleanup()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func interrupted(_ notification: Notification) {
    guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      raw == AVAudioSession.InterruptionType.began.rawValue, recorder != nil else { return }
    failure = "전화 또는 다른 오디오 사용으로 녹음이 중단되었습니다. 다시 녹음해주세요."
    recorder?.stop()
  }

  @objc private func backgrounded() {
    recorder?.stop()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
    failure = "오디오 저장 중 오류가 발생했습니다. 다시 녹음해주세요."
  }

  private func cleanup() {
    recorder?.stop()
    recorder = nil
    if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    fileURL = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
