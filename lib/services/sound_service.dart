import 'package:flutter/services.dart';

import 'haptic_service.dart';

class SoundService {
  static const channel = MethodChannel('sound_notes/audio');
  Future<void> play(Uint8List audio) =>
      channel.invokeMethod<void>('play', audio);
  Future<void> playIntegrated(Uint8List audio, List<HapticEvent> events) =>
      channel.invokeMethod<void>('playIntegrated', {
        'audio': audio,
        'events': events.map((event) => event.toMap()).toList(),
      });
  Future<void> stopPlayback() => channel.invokeMethod<void>('stopPlayback');
  Future<bool> isPlaying() async =>
      await channel.invokeMethod<bool>('isPlaying') ?? false;
  Future<double> position() async =>
      await channel.invokeMethod<double>('position') ?? 0;
  Future<void> start() => channel.invokeMethod<void>('start');
  Future<void> cancel() => channel.invokeMethod<void>('cancel');
  Future<Uint8List> stop() async {
    final bytes = await channel.invokeMethod<Uint8List>('stop');
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('녹음된 오디오가 없습니다. 다시 녹음해주세요.');
    }
    return bytes;
  }
}
