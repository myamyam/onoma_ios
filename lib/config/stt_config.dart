import 'dart:convert';

import 'package:flutter/services.dart';

/// Local developer configuration, bundled for development testing only.
/// Never display or log the API key or the raw configuration file.
class SttConfig {
  static String endpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';
  static String apiKey = '';
  static String model = 'whisper-large-v3-turbo';
  static String language = 'ko';
  static String? loadError;

  static Future<void> load() async {
    apiKey = '';
    loadError = null;
    try {
      final value = jsonDecode(
        await rootBundle.loadString('config/stt.local.json'),
      );
      if (value is! Map<String, dynamic>) throw const FormatException();
      for (final key in [
        'STT_API_URL',
        'STT_API_KEY',
        'STT_MODEL',
        'STT_LANGUAGE',
      ]) {
        if (value[key] is! String) throw const FormatException();
      }
      endpoint = (value['STT_API_URL'] as String).trim();
      model = (value['STT_MODEL'] as String).trim();
      language = (value['STT_LANGUAGE'] as String).trim();
      apiKey = (value['STT_API_KEY'] as String).trim();
    } catch (_) {
      loadError = '전사 서비스 설정을 불러오지 못했습니다. 개발자에게 문의해주세요.';
    }
  }
}
