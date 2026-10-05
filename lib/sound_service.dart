import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class SoundResult {
  const SoundResult(this.transcript, this.isDemo);
  final String transcript;
  final bool isDemo;

  static SoundResult fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['transcript_ko'] is! String ||
        (value['transcript_ko'] as String).trim().isEmpty) {
      throw const FormatException('응답에 transcript_ko 문자열이 필요합니다.');
    }
    return SoundResult((value['transcript_ko'] as String).trim(), false);
  }
}

class SoundService {
  // This is our backend contract, not a provider-standard transcription API.
  static const transcriptionInstructions =
      '오디오에 실제로 들리는 비음성 소리 자체를 한글 의성어로 전사하세요. '
      '소리의 발생 순서, 반복 횟수, 길이, 쉼을 최대한 보존하세요. '
      '예: 멍! 멍멍… 으르렁 / 끼이익… 쾅! / 톡… 톡톡… 쏴아아. '
      '예시는 출력 형식 안내이며 입력에 들리지 않는 소리를 추가하지 마세요. '
      '소리 분류명이나 소리의 원인·상황을 설명하는 문장을 출력하지 마세요. '
      '사람의 말은 받아쓰지 마세요. 무음은 [무음], 들리지만 전사할 수 없는 '
      '구간은 [전사 불확실]로 표시하세요. '
      '결과는 transcript_ko 문자열을 가진 JSON으로 반환하세요.';

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

  Future<SoundResult> transcribe(
    Uint8List audio,
    String endpoint,
    String token,
  ) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('올바른 HTTPS API 주소를 입력해주세요.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client.postUrl(uri);
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        if (token.trim().isNotEmpty) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${token.trim()}',
          );
        }
        request.write(
          jsonEncode({
            'audio_base64': base64Encode(audio),
            'mime_type': 'audio/wav',
            'language': 'ko',
            'task': 'non_speech_sound_transcription',
            'instructions': transcriptionInstructions,
          }),
        );
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw FormatException(
            'API 요청 실패 (${response.statusCode}). 주소와 인증 정보를 확인해주세요.',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 1024 * 1024) {
            throw const FormatException('API 응답이 너무 큽니다.');
          }
        }
        return SoundResult.fromJson(jsonDecode(utf8.decode(bytes)));
      })().timeout(const Duration(seconds: 45));
    } finally {
      client.close(force: true);
    }
  }
}
