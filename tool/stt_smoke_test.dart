// Standalone HTTPS integration test; no API key, provider calls or Flutter engine.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:first_flutter/stt_client.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class LocalTls extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback = (cert, host, port) => host == '127.0.0.1';
}

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('stt-test-');
  HttpServer? server;
  final oldOverrides = HttpOverrides.current;
  try {
    final cert = '${temp.path}/cert.pem';
    final key = '${temp.path}/key.pem';
    final generated = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      key,
      '-out',
      cert,
      '-days',
      '1',
      '-subj',
      '/CN=localhost',
    ]);
    check(generated.exitCode == 0, 'Test TLS certificate generation failed');
    final context = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key);
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    HttpOverrides.global = LocalTls();
    final uploads = <List<int>>[];
    final contentTypes = <String>[];
    final auth = <String?>[];
    var status = 200;
    Object response = {'text': '안녕하세요. STT 테스트입니다.'};
    server.listen((request) async {
      uploads.add(
        await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
      );
      contentTypes.add(request.headers.value('content-type')!);
      auth.add(request.headers.value('authorization'));
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    final client = SttClient();
    final endpoint = 'https://127.0.0.1:${server.port}/v1/audio/transcriptions';
    final audio = Uint8List.fromList([82, 73, 70, 70, 0, 128, 255, 13, 10]);
    final result = await client.transcribe(audio, endpoint, 'test-only-token');
    check(
      result.transcript == '안녕하세요. STT 테스트입니다.',
      'Transcript not preserved',
    );
    check(result.model == 'whisper-large-v3-turbo', 'Wrong model');
    check(auth.single == 'Bearer test-only-token', 'Missing authorization');
    final boundary = contentTypes.single.split('boundary=').last;
    final body = latin1.decode(uploads.single);
    check(body.startsWith('--$boundary\r\n'), 'Missing boundary');
    check(
      body.contains('name="model"\r\n\r\nwhisper-large-v3-turbo'),
      'Missing model field',
    );
    check(
      body.contains('name="language"\r\n\r\nko'),
      'Missing Korean language',
    );
    check(
      body.contains('name="response_format"\r\n\r\njson'),
      'Missing response format',
    );
    check(
      body.contains(
        'filename="recording.wav"\r\nContent-Type: audio/wav\r\n\r\n${latin1.decode(audio)}\r\n--$boundary--\r\n',
      ),
      'WAV bytes corrupted',
    );
    response = {'text': ''};
    final empty = await client.transcribe(
      audio,
      endpoint,
      '',
      model: 'custom-stt',
      language: '',
    );
    check(
      empty.transcript.isEmpty && empty.model == 'custom-stt',
      'Empty result handling',
    );
    check(
      !latin1.decode(uploads.last).contains('name="language"'),
      'Auto language should omit field',
    );
    check(auth.last == null, 'Unexpected authorization');
    for (final code in [401, 403, 404, 429, 500]) {
      status = code;
      try {
        await client.transcribe(audio, endpoint, '');
        throw StateError('HTTP $code was accepted');
      } on FormatException catch (e) {
        check(e.message.contains('HTTP $code'), 'Lost HTTP status');
      }
    }
    status = 200;
    response = {'caption_ko': 'invalid contract'};
    try {
      await client.transcribe(audio, endpoint, '');
      throw StateError('Malformed result accepted');
    } on FormatException {
      /* expected */
    }
    final before = uploads.length;
    for (final url in ['http://example.com/stt', SttClient.defaultEndpoint]) {
      try {
        await client.transcribe(audio, url, '');
        throw StateError('Invalid config accepted');
      } on FormatException {
        /* expected */
      }
    }
    check(uploads.length == before, 'Invalid config triggered request');
    stdout.writeln(
      'PASS: HTTPS multipart WAV, auth, language, model, response, empty text, error and config handling',
    );
  } finally {
    HttpOverrides.global = oldOverrides;
    await server?.close(force: true);
    await temp.delete(recursive: true);
  }
}
