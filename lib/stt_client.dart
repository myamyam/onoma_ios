import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class SoundResult {
  const SoundResult(this.transcript, this.model);
  final String transcript;
  final String model;

  static SoundResult fromJson(Object? value, String model) {
    if (value is! Map<String, dynamic> || value['text'] is! String) {
      throw const FormatException('STT 응답에 text 문자열이 없습니다. API 형식을 확인해주세요.');
    }
    // An empty transcript is a valid model result, not a network error.
    return SoundResult(value['text'] as String, model);
  }
}

class SttClient {
  static const defaultEndpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  Future<SoundResult> transcribe(
    Uint8List audio,
    String endpoint,
    String token, {
    String model = 'whisper-large-v3-turbo',
    String language = 'ko',
  }) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('올바른 HTTPS API 주소를 입력해주세요.');
    }
    if (model.trim().isEmpty) {
      throw const FormatException('모델 이름을 입력해주세요.');
    }
    if ((uri.host == 'api.openai.com' || uri.host == 'api.groq.com') &&
        token.trim().isEmpty) {
      throw const FormatException('API 키를 입력해주세요.');
    }
    if (audio.isEmpty) throw const FormatException('녹음된 오디오가 없습니다.');
    final boundary =
        'soundnotes-${List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}';
    final body = BytesBuilder();
    void field(String name, String value) {
      body.add(
        utf8.encode(
          '--$boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n$value\r\n',
        ),
      );
    }

    field('model', model.trim());
    field('response_format', 'json');
    if (language.isNotEmpty) field('language', language);
    body.add(
      utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="file"; filename="recording.wav"\r\nContent-Type: audio/wav\r\n\r\n',
      ),
    );
    body.add(audio);
    body.add(utf8.encode('\r\n--$boundary--\r\n'));
    final payload = body.takeBytes();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client.postUrl(uri);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'multipart/form-data; boundary=$boundary',
        );
        if (token.trim().isNotEmpty) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${token.trim()}',
          );
        }
        request.contentLength = payload.length;
        request.add(payload);
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final message = switch (response.statusCode) {
            401 || 403 => 'API 인증에 실패했습니다. 키와 모델 접근 권한을 확인해주세요.',
            404 => 'API 주소 또는 모델을 찾을 수 없습니다.',
            429 => '요청 한도 또는 API 사용 잔액을 확인해주세요.',
            >= 500 => 'STT 서버에 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
            _ => 'API가 요청을 거부했습니다. 모델과 오디오 업로드 형식을 확인해주세요.',
          };
          throw FormatException('$message (HTTP ${response.statusCode})');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 1024 * 1024) {
            throw const FormatException('API 응답이 너무 큽니다.');
          }
        }
        return SoundResult.fromJson(
          jsonDecode(utf8.decode(bytes)),
          model.trim(),
        );
      })().timeout(const Duration(seconds: 60));
    } finally {
      client.close(force: true);
    }
  }
}
