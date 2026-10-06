import 'package:flutter/services.dart';

import 'stt_client.dart';
export 'stt_client.dart';

class SoundService extends SttClient {
  static const channel = MethodChannel('sound_notes/audio');
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
