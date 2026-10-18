import 'dart:convert';
import 'dart:io';

/// Bounded diagnostics: only provider error text, never the request or API key.
Future<String> apiErrorDetail(
  HttpClientResponse response, {
  String secret = '',
}) async {
  final bytes = <int>[];
  await for (final chunk in response) {
    bytes.addAll(chunk.take(8192 - bytes.length));
    if (bytes.length >= 8192) break;
  }
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) return '';
    final error = decoded['error'];
    final message = error is String
        ? error
        : error is Map
        ? error['message']
        : null;
    if (message is! String) return '';
    var safe = message.replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (secret.isNotEmpty) safe = safe.replaceAll(secret, '[hidden]');
    safe = safe.replaceAll(RegExp(r'(?:sk-|gsk_)[A-Za-z0-9_-]+'), '[hidden]');
    return safe.length > 400 ? safe.substring(0, 400) : safe;
  } catch (_) {
    return '';
  }
}
