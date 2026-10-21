import AVFoundation
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var audioBridge: MacSoundAudioBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let bridge = MacSoundAudioBridge()
    audioBridge = bridge
    let channel = FlutterMethodChannel(
      name: "sound_notes/audio", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      bridge.handle(call, result: result)
    }
    title = "소리노트"
    minSize = NSSize(width: 420, height: 600)
    setContentSize(NSSize(width: 720, height: 860))
    center()

    super.awakeFromNib()
  }
}

private final class MacSoundAudioBridge: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
  private var player: AVAudioPlayer?
  private var recorder: AVAudioRecorder?
  private var fileURL: URL?
  private var failure: String?
  private var pendingStop: FlutterResult?
  private var starting = false
  private var generation = 0

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(backgrounded), name: NSApplication.didResignActiveNotification,
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
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async {
          guard current == self.generation else {
            result(FlutterError(code: "cancelled", message: "녹음이 취소되었습니다.", details: nil))
            return
          }
          self.starting = false
          guard granted else {
            result(FlutterError(code: "permission", message: "시스템 설정 → 개인정보 보호 및 보안 → 마이크에서 이 앱의 접근을 허용해주세요.", details: nil))
            return
          }
          guard NSApp.isActive else {
            result(FlutterError(code: "inactive", message: "앱으로 돌아와 다시 녹음해주세요.", details: nil))
            return
          }
          do {
            self.failure = nil
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
      guard pendingStop == nil else {
        result(FlutterError(code: "busy", message: "녹음을 저장하는 중입니다.", details: nil))
        return
      }
      pendingStop = result
      if let recorder = recorder, recorder.isRecording {
        // AVAudioRecorder finalizes the WAV header before its finish callback.
        recorder.stop()
      } else {
        finishRecordingRead()
      }
    case "cancel":
      stopPlayback()
      generation += 1
      starting = false
      cleanup()
      result(nil)
    case "play":
      guard !starting, recorder == nil,
        let audio = call.arguments as? FlutterStandardTypedData else {
        result(FlutterError(code: "playback", message: "녹음을 재생할 수 없습니다.", details: nil))
        return
      }
      stopPlayback()
      do {
        let player = try AVAudioPlayer(data: audio.data)
        self.player = player
        player.delegate = self
        guard player.play() else { throw NSError(domain: "SoundNotes", code: 2) }
        result(nil)
      } catch {
        stopPlayback()
        result(FlutterError(code: "playback", message: "녹음 재생에 실패했습니다.", details: nil))
      }
    case "stopPlayback":
      stopPlayback()
      result(nil)
    case "position":
      result(player?.currentTime ?? 0.0)
    case "isPlaying":
      result(player?.isPlaying ?? false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func backgrounded() {
    stopPlayback()
    recorder?.stop()
  }

  func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
    DispatchQueue.main.async {
      guard self.recorder === recorder else { return }
      if !flag && self.failure == nil {
        self.failure = "녹음 파일을 완성하지 못했습니다. 다시 녹음해주세요."
      }
      if self.pendingStop != nil { self.finishRecordingRead() }
    }
  }

  private func finishRecordingRead() {
    guard let result = pendingStop else { return }
    pendingStop = nil
    defer { cleanup() }
    if let failure = failure {
      result(FlutterError(code: "interrupted", message: failure, details: nil))
      return
    }
    do {
      guard let url = fileURL else { throw NSError(domain: "SoundNotes", code: 4) }
      let audio = try AVAudioFile(forReading: url)
      guard audio.length > 0 else {
        result(FlutterError(code: "empty",
          message: "마이크에서 오디오가 저장되지 않았습니다. 연결된 오디오 장치와 마이크 권한을 확인하고 다시 녹음해주세요.",
          details: nil))
        return
      }
      let data = try Data(contentsOf: url)
      result(FlutterStandardTypedData(bytes: data))
    } catch {
      result(FlutterError(code: "recording", message: "녹음 파일을 읽지 못했습니다. 다시 녹음해주세요.", details: nil))
    }
  }

  func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
    failure = "오디오 저장 중 오류가 발생했습니다. 다시 녹음해주세요."
    if pendingStop != nil { finishRecordingRead() }
  }

  private func stopPlayback() {
    player?.stop()
    player = nil
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
    let waiting = pendingStop
    pendingStop = nil
    waiting?(FlutterError(code: "cancelled", message: "녹음 저장이 취소되었습니다.", details: nil))
    recorder?.stop()
    recorder = nil
    if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    fileURL = nil
  }
}
