import 'package:flutter/services.dart';

/// Pipeline boundary: seconds, normalized intensity/sharpness, and event type.
class HapticEvent {
  const HapticEvent({
    required this.time,
    required this.duration,
    required this.intensity,
    required this.sharpness,
  });
  final double time;
  final double duration; // Zero is a transient tap; positive is continuous.
  final double intensity;
  final double sharpness;

  Map<String, double> toMap() {
    if (![time, duration, intensity, sharpness].every((v) => v.isFinite) ||
        time < 0 ||
        duration < 0 ||
        time + duration > 15 ||
        intensity < 0 ||
        intensity > 1 ||
        sharpness < 0 ||
        sharpness > 1) {
      throw const FormatException('햅틱 패턴의 시간 또는 강도 범위가 올바르지 않습니다.');
    }
    return {
      'time': time,
      'duration': duration,
      'intensity': intensity,
      'sharpness': sharpness,
    };
  }
}

class HapticService {
  static const channel = MethodChannel('sound_notes/haptics');
  // Hardware smoke test only. Not derived from the recorded audio.
  static const testPattern = [
    HapticEvent(time: 0, duration: 0, intensity: 0.5, sharpness: 0.5),
    HapticEvent(time: 0.35, duration: 0, intensity: 0.8, sharpness: 0.7),
    HapticEvent(time: 0.7, duration: 0.6, intensity: 0.6, sharpness: 0.3),
  ];

  Future<bool> isSupported() async {
    try {
      return await channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> play(List<HapticEvent> events) async {
    if (events.isEmpty || events.length > 256) {
      throw const FormatException('햅틱 이벤트는 1~256개여야 합니다.');
    }
    await channel.invokeMethod<void>('play', {
      'events': events.map((e) => e.toMap()).toList(),
    });
  }

  Future<void> stop() async {
    try {
      await channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // macOS and other platforms do not implement iPhone haptics.
    }
  }

  Future<bool> isPlaying() async =>
      await channel.invokeMethod<bool>('isPlaying') ?? false;
}
