import AVFoundation
import CoreHaptics
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioBridge: SoundAudioBridge?
  private var hapticBridge: SoundHapticBridge?

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
    let hapticChannel = FlutterMethodChannel(
      name: "sound_notes/haptics", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    let haptics = SoundHapticBridge()
    hapticBridge = haptics
    hapticChannel.setMethodCallHandler { call, result in
      haptics.handle(call, result: result)
    }
    let bridge = SoundAudioBridge(haptics: haptics)
    audioBridge = bridge
    channel.setMethodCallHandler { call, result in
      bridge.handle(call, result: result)
    }
  }
}

private final class SoundAudioBridge: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
  private var player: AVAudioPlayer?
  private let haptics: SoundHapticBridge
  private var scheduledAudioTime: TimeInterval?
  private var recorder: AVAudioRecorder?
  private var fileURL: URL?
  private var failure: String?
  private var starting = false
  private var generation = 0

  init(haptics: SoundHapticBridge) {
    self.haptics = haptics
    super.init()
    haptics.onInterrupted = { [weak self] in self?.stopPlayback() }
    NotificationCenter.default.addObserver(
      self, selector: #selector(stopPlayback), name: UIApplication.willResignActiveNotification,
      object: nil)
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
      stopPlayback()
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
      stopPlayback()
      generation += 1
      starting = false
      cleanup()
      result(nil)
    case "play", "playIntegrated":
      let args = call.arguments as? [String: Any]
      let audio = call.method == "playIntegrated"
        ? args?["audio"] as? FlutterStandardTypedData
        : call.arguments as? FlutterStandardTypedData
      guard !starting, recorder == nil, UIApplication.shared.applicationState == .active,
        let audio = audio else {
        result(FlutterError(code: "playback", message: "녹음을 재생할 수 없습니다.", details: nil))
        return
      }
      stopPlayback()
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        let player = try AVAudioPlayer(data: audio.data)
        self.player = player
        player.delegate = self
        guard player.prepareToPlay() else { throw NSError(domain: "SoundNotes", code: 2) }
        if call.method == "playIntegrated" {
          guard let events = args?["events"] as? [[String: Any]], events.count <= 256 else {
            throw NSError(domain: "SoundNotes", code: 3)
          }
          if !events.isEmpty {
            try haptics.prepare(events)
          }
          // Both clocks are sampled after decoding and engine warm-up. Schedule
          // 100 ms ahead, compensating for time spent between clock reads.
          let hostStart = ProcessInfo.processInfo.systemUptime + 0.1
          let audioTime = player.deviceCurrentTime + hostStart - ProcessInfo.processInfo.systemUptime
          if !events.isEmpty { try haptics.start(atHostTime: hostStart) }
          scheduledAudioTime = audioTime
          guard player.play(atTime: audioTime) else { throw NSError(domain: "SoundNotes", code: 2) }
        } else {
          guard player.play() else { throw NSError(domain: "SoundNotes", code: 2) }
        }
        result(nil)
      } catch {
        stopPlayback()
        result(FlutterError(code: "playback", message: "녹음 재생에 실패했습니다.", details: nil))
      }
    case "stopPlayback":
      stopPlayback()
      result(nil)
    case "position":
      result(isScheduled ? 0.0 : (player?.currentTime ?? 0.0))
    case "isPlaying":
      result(isScheduled || (player?.isPlaying ?? false))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func interrupted(_ notification: Notification) {
    guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      raw == AVAudioSession.InterruptionType.began.rawValue else { return }
    stopPlayback()
    guard recorder != nil else { return }
    failure = "전화 또는 다른 오디오 사용으로 녹음이 중단되었습니다. 다시 녹음해주세요."
    recorder?.stop()
  }

  @objc private func backgrounded() {
    stopPlayback()
    recorder?.stop()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
    failure = "오디오 저장 중 오류가 발생했습니다. 다시 녹음해주세요."
  }

  private var isScheduled: Bool {
    guard let player = player, let start = scheduledAudioTime else { return false }
    return player.deviceCurrentTime < start
  }

  @objc private func stopPlayback() {
    scheduledAudioTime = nil
    haptics.stop()
    player?.stop()
    player = nil
    if recorder == nil && !starting {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard self.player === player else { return }
    stopPlayback()
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    guard self.player === player else { return }
    stopPlayback()
  }

  private func cleanup() {
    recorder?.stop()
    recorder = nil
    if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    fileURL = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

// Receives pipeline events without depending on transcription or audio decoding.
private final class SoundHapticBridge: NSObject {
  var onInterrupted: (() -> Void)?
  private var engine: CHHapticEngine?
  private var player: CHHapticAdvancedPatternPlayer?
  private var playing = false
  private var generation = 0

  override init() {
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(stop),
      name: UIApplication.willResignActiveNotification, object: nil)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(CHHapticEngine.capabilitiesForHardware().supportsHaptics)
    case "isPlaying":
      result(playing)
    case "stop":
      stop()
      result(nil)
    case "play":
      guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
        result(FlutterError(code: "unsupported", message: "이 기기는 내장 햅틱 재생을 지원하지 않습니다.", details: nil))
        return
      }
      guard UIApplication.shared.applicationState == .active else {
        result(FlutterError(code: "inactive", message: "앱으로 돌아온 뒤 햅틱을 재생해주세요.", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
        let values = args["events"] as? [[String: Any]],
        !values.isEmpty, values.count <= 256 else {
        result(FlutterError(code: "pattern", message: "햅틱 패턴 형식이 올바르지 않습니다.", details: nil))
        return
      }
      do {
        try prepare(values)
        try start()
        result(nil)
      } catch {
        stop()
        result(FlutterError(code: "haptics", message: "햅틱을 재생하지 못했습니다. 다시 시도해주세요.", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }


  func prepare(_ values: [[String: Any]]) throws {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
      !values.isEmpty, values.count <= 256 else {
      throw NSError(domain: "SoundNotesHaptics", code: 3)
    }
    let events = try values.map { value -> CHHapticEvent in
      guard let time = value["time"] as? Double,
        let duration = value["duration"] as? Double,
        let intensity = value["intensity"] as? Double,
        let sharpness = value["sharpness"] as? Double,
        [time, duration, intensity, sharpness].allSatisfy({ $0.isFinite }),
        time >= 0, duration >= 0, time + duration <= 15,
        (0...1).contains(intensity), (0...1).contains(sharpness) else {
        throw NSError(domain: "SoundNotesHaptics", code: 1)
      }
      return CHHapticEvent(eventType: duration == 0 ? .hapticTransient : .hapticContinuous,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness))
        ], relativeTime: time, duration: duration)
    }
    stop()
    if engine == nil {
      let newEngine = try CHHapticEngine()
      newEngine.playsHapticsOnly = true
      newEngine.isAutoShutdownEnabled = true
      newEngine.stoppedHandler = { [weak self, weak newEngine] _ in
        DispatchQueue.main.async {
          guard let self = self, let source = newEngine, self.engine === source else { return }
          self.engineInterrupted()
        }
      }
      newEngine.resetHandler = { [weak self, weak newEngine] in
        DispatchQueue.main.async {
          guard let self = self, let source = newEngine, self.engine === source else { return }
          self.engineInterrupted()
        }
      }
      engine = newEngine
    }
    guard let engine = engine else { throw NSError(domain: "SoundNotesHaptics", code: 2) }
    try engine.start()
    let pattern = try CHHapticPattern(events: events, parameters: [])
    let newPlayer = try engine.makeAdvancedPlayer(with: pattern)
    let current = generation
    newPlayer.completionHandler = { [weak self] error in
      DispatchQueue.main.async {
        guard let self = self, self.generation == current else { return }
        if error != nil { self.engineInterrupted(); return }
        self.playing = false
        self.player = nil
      }
    }
    player = newPlayer
  }

  func start(atHostTime hostTime: TimeInterval? = nil) throws {
    guard let engine = engine, let player = player else {
      throw NSError(domain: "SoundNotesHaptics", code: 2)
    }
    let start = hostTime.map {
      engine.currentTime + max(0, $0 - ProcessInfo.processInfo.systemUptime)
    } ?? CHHapticTimeImmediate
    try player.start(atTime: start)
    playing = true
  }

  private func engineInterrupted() {
    let wasPlaying = playing
    stop()
    if wasPlaying { onInterrupted?() }
  }

  @objc func stop() {
    generation += 1
    try? player?.stop(atTime: CHHapticTimeImmediate)
    player = nil
    playing = false
    // Retire the engine before changing the audio session. Delayed callbacks
    // from a previous playback must not interrupt a newly scheduled playback.
    let oldEngine = engine
    engine = nil
    oldEngine?.stoppedHandler = { _ in }
    oldEngine?.resetHandler = {}
    oldEngine?.stop(completionHandler: nil)
  }
}
