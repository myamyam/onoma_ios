import 'package:flutter_test/flutter_test.dart';
import 'package:first_flutter/services/mucap_client.dart';

Map<String, Object> response() => {
  'version': 1,
  'duration': 1.0,
  'model': 'fixture',
  'captions': [
    {'time': 0, 'end': 1, 'text': '둥', 'pitch': .5, 'size': 26},
  ],
  'events': [
    {'time': 0, 'duration': .08, 'intensity': .7, 'sharpness': .3},
  ],
};

void main() {
  test('accepts timeline and silence without a fabricated vibration', () {
    final result = MucapResult.fromJson(response());
    expect(result.captions.single.text, '둥');
    expect(result.events.single.intensity, .7);
    expect(MucapResult.fromJson(response()..['events'] = []).events, isEmpty);
  });
  test(
    'rejects invalid times and nonfinite payloads before native playback',
    () {
      for (final value in [
        response()..['duration'] = 16,
        response()..['duration'] = double.nan,
        response()
          ..['events'] = [
            {'time': 1, 'duration': 1, 'intensity': .7, 'sharpness': .3},
          ],
        response()
          ..['captions'] = [
            {'time': 0, 'end': 2, 'text': '둥', 'pitch': .5, 'size': 26},
          ],
      ]) {
        expect(() => MucapResult.fromJson(value), throwsFormatException);
      }
    },
  );
}
