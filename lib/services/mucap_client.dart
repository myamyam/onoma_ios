import '../utils/api_error.dart';
import '../models/mucap_visual_style.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'haptic_service.dart';
import '../models/nonspeech_transcription.dart';

class CaptionCue {
  const CaptionCue(
    this.time,
    this.end,
    this.text,
    this.pitch,
    this.size, {
    this.visual,
  });
  final CueVisual? visual;
  final double time, end, pitch, size;
  final String text;
}

class MucapResult {
  const MucapResult(this.duration, this.model, this.captions, this.events);
  final double duration;
  final String model;
  final List<CaptionCue> captions;
  final List<HapticEvent> events;

  factory MucapResult.fromJson(dynamic value) {
    double number(dynamic v) {
      if (v is! num || !v.isFinite) {
        throw const FormatException('MuCap 응답에 올바른 숫자가 필요합니다.');
      }
      return v.toDouble();
    }

    if (value is! Map ||
        value['version'] != 1 ||
        value['model'] is! String ||
        value['captions'] is! List ||
        value['events'] is! List) {
      throw const FormatException('MuCap 응답 형식이 올바르지 않습니다.');
    }
    final duration = number(value['duration']);
    if (duration <= 0 || duration > 15) {
      throw const FormatException('MuCap 오디오는 최대 15초입니다.');
    }
    final captions = <CaptionCue>[];
    for (final item in value['captions']) {
      if (item is! Map || item['text'] is! String) {
        throw const FormatException('자막 형식이 올바르지 않습니다.');
      }
      final t = number(item['time']), end = number(item['end']);
      final pitch = number(item['pitch']), size = number(item['size']);
      if (t < 0 ||
          end < t ||
          end > duration ||
          pitch < 0 ||
          pitch > 1 ||
          size < 8 ||
          size > 120 ||
          (captions.isNotEmpty && t < captions.last.time)) {
        throw const FormatException('자막 시간 또는 스타일 범위가 올바르지 않습니다.');
      }
      captions.add(
        CaptionCue(
          t,
          end,
          item['text'],
          pitch,
          size,
          visual: item['visual'] == null
              ? null
              : CueVisual.fromJson(item['visual'], item['text']),
        ),
      );
    }
    if (captions.isEmpty ||
        captions.length > 2048 ||
        value['events'].length > 256) {
      throw const FormatException('MuCap 이벤트 개수가 올바르지 않습니다.');
    }
    final events = <HapticEvent>[];
    for (final item in value['events']) {
      if (item is! Map) throw const FormatException('햅틱 형식 오류');
      final event = HapticEvent(
        time: number(item['time']),
        duration: number(item['duration']),
        intensity: number(item['intensity']),
        sharpness: number(item['sharpness']),
      );
      event.toMap();
      if (event.time + event.duration > duration + 0.001) {
        throw const FormatException('햅틱이 녹음 길이를 초과했습니다.');
      }
      events.add(event);
    }
    return MucapResult(
      duration,
      value['model'],
      List.unmodifiable(captions),
      List.unmodifiable(events),
    );
  }
}

class MucapClient {
  static const endpoint = String.fromEnvironment('MUCAP_API_URL');

  Future<MucapResult> analyze(Uint8List audio) async =>
      MucapResult.fromJson(await _request(audio, 'analyze'));

  Future<NonspeechTranscription> transcribe(Uint8List audio) async =>
      NonspeechTranscription.fromJson(await _request(audio, 'transcribe'));

  Future<MucapResult> enrich(
    Uint8List audio,
    NonspeechTranscription transcript,
  ) async {
    final payload = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'audio': base64Encode(audio),
          'model': transcript.model,
          'captions': transcript.captions
              .map(
                (cue) => {'time': cue.time, 'end': cue.end, 'text': cue.text},
              )
              .toList(),
        }),
      ),
    );
    return MucapResult.fromJson(await _request(payload, 'outputs', json: true));
  }

  Future<dynamic> _request(
    Uint8List audio,
    String operation, {
    bool json = false,
  }) async {
    final configured = Uri.tryParse(endpoint);
    final uri = configured?.replace(
      path: configured.path.replaceFirst(
        RegExp(r'/(analyze|transcribe|outputs)/?$'),
        '/$operation',
      ),
    );
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('MuCap 서버 주소를 설정해주세요.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client.postUrl(uri);
        request.followRedirects = false;
        request.headers.contentType = json
            ? ContentType.json
            : ContentType('audio', 'wav');
        request.contentLength = audio.length;
        request.add(audio);
        final response = await request.close();
        if (response.statusCode != 200) {
          final detail = await apiErrorDetail(response);
          throw FormatException(
            'MuCap 요청 오류 (HTTP ${response.statusCode})${detail.isEmpty ? '' : ': $detail'}',
          );
        }
        final bytes = BytesBuilder();
        await for (final chunk in response) {
          bytes.add(chunk);
          if (bytes.length > 2 * 1024 * 1024) {
            throw const FormatException('MuCap 응답이 너무 큽니다.');
          }
        }
        return jsonDecode(utf8.decode(bytes.takeBytes()));
      })().timeout(const Duration(minutes: 10));
    } on SocketException {
      throw FormatException(
        'MuCap 서버(${uri.host}:${uri.port})에 연결하지 못했습니다. 서버 실행, 같은 Wi-Fi 연결, iPhone의 로컬 네트워크 권한을 확인해주세요.',
      );
    } finally {
      client.close(force: true);
    }
  }
}
