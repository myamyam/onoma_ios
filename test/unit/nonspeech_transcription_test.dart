import 'package:flutter_test/flutter_test.dart';
import 'package:first_flutter/models/nonspeech_transcription.dart';

void main() {
  Map<String, dynamic> payload() => {
    'version': 1,
    'mode': 'transcription',
    'duration': 1,
    'model': 'test',
    'captions': [
      {'time': 0, 'end': 1, 'text': '둥'},
    ],
  };
  test('text contract does not require haptics or visual fields', () {
    expect(NonspeechTranscription.fromJson(payload()).text, '둥');
  });
  test('rejects wrong mode and out-of-range timestamps', () {
    for (final value in [
      payload()..['mode'] = 'multimodal',
      payload()
        ..['captions'] = [
          {'time': 0, 'end': 2, 'text': '둥'},
        ],
    ]) {
      expect(
        () => NonspeechTranscription.fromJson(value),
        throwsFormatException,
      );
    }
  });
}
