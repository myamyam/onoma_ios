/// Text-only contract: no visual styling or haptic events are required.
class NonspeechCue {
  const NonspeechCue(this.time, this.end, this.text);
  final double time, end;
  final String text;
}

class NonspeechTranscription {
  const NonspeechTranscription(this.duration, this.model, this.captions);
  final double duration;
  final String model;
  final List<NonspeechCue> captions;
  String get text => captions.map((cue) => cue.text).join(' ');

  factory NonspeechTranscription.fromJson(dynamic value) {
    double number(dynamic v) {
      if (v is! num || !v.isFinite) {
        throw const FormatException('소리 전사 응답의 시간 형식이 올바르지 않습니다.');
      }
      return v.toDouble();
    }

    if (value is! Map ||
        value['version'] != 1 ||
        value['mode'] != 'transcription' ||
        value['model'] is! String ||
        value['captions'] is! List) {
      throw const FormatException('소리 전사 응답 형식이 올바르지 않습니다.');
    }
    final duration = number(value['duration']);
    final raw = value['captions'] as List;
    if (duration <= 0 || duration > 15 || raw.isEmpty || raw.length > 2048) {
      throw const FormatException('소리 전사의 길이 또는 자막 개수가 올바르지 않습니다.');
    }
    final cues = <NonspeechCue>[];
    for (final item in raw) {
      if (item is! Map ||
          item['text'] is! String ||
          (item['text'] as String).trim().isEmpty) {
        throw const FormatException('소리 전사에 자막 텍스트가 없습니다.');
      }
      final time = number(item['time']), end = number(item['end']);
      if (time < 0 ||
          end < time ||
          end > duration ||
          (cues.isNotEmpty && time < cues.last.time)) {
        throw const FormatException('소리 전사의 시간 범위가 올바르지 않습니다.');
      }
      cues.add(NonspeechCue(time, end, item['text']));
    }
    return NonspeechTranscription(
      duration,
      value['model'],
      List.unmodifiable(cues),
    );
  }
}
