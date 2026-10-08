import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:first_flutter/main.dart';
import 'package:first_flutter/sound_page.dart';
import 'package:first_flutter/stt_config.dart';
import 'package:first_flutter/sound_service.dart';

class FakeTranscriptionService extends SoundService {
  @override
  Future<SoundResult> transcribe(
    Uint8List audio,
    String endpoint,
    String token, {
    String model = 'test',
    String language = 'ko',
  }) async {
    return SoundResult('녹음 ${audio.first}', model);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SoundService.channel, null);
  });

  testWidgets('API 입력란 없이 녹음 화면 표시', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('샘플 체험'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('API 키 / Bearer 토큰'), findsNothing);
    await tester.scrollUntilVisible(find.text('마이크로 녹음'), 300);
    expect(find.text('마이크로 녹음'), findsOneWidget);
  });

  testWidgets('권한 거부 안내 및 재시도', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SoundService.channel, (call) async {
          if (call.method == 'start') {
            throw PlatformException(
              code: 'permission',
              message: '마이크 권한이 필요합니다.',
            );
          }
          return null;
        });
    await tester.pumpWidget(const MyApp());
    await tester.scrollUntilVisible(find.text('마이크로 녹음'), 300);
    await tester.tap(find.text('마이크로 녹음'));
    await tester.pumpAndSettle();
    expect(find.text('마이크 권한이 필요합니다.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '마이크로 녹음'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('15초 녹음 종료 후 전송 대기, 키 누락 안내', (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SoundService.channel, (call) async {
          calls.add(call.method);
          return call.method == 'stop' ? Uint8List.fromList([1, 2, 3]) : null;
        });
    await tester.pumpWidget(const MyApp());
    await tester.scrollUntilVisible(find.text('마이크로 녹음'), 300);
    await tester.tap(find.text('마이크로 녹음'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call == 'stop').length, 1);
    await tester.ensureVisible(find.text('STT 전송'));
    await tester.tap(find.text('STT 전송'));
    await tester.pumpAndSettle();
    expect(find.text('전사 서비스가 아직 준비되지 않았습니다. 개발자에게 문의해주세요.'), findsOneWidget);
  });
  testWidgets('각 전사 기록의 원본을 재생하고 완료·삭제 시 정지', (tester) async {
    final previousKey = SttConfig.apiKey;
    SttConfig.apiKey = 'test-only';
    addTearDown(() => SttConfig.apiKey = previousKey);
    var recording = 0;
    var playing = false;
    final played = <List<int>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SoundService.channel, (call) async {
          switch (call.method) {
            case 'stop':
              return Uint8List.fromList([++recording, 2, 3]);
            case 'play':
              played.add(List<int>.from(call.arguments as Uint8List));
              playing = true;
              return null;
            case 'stopPlayback':
              playing = false;
              return null;
            case 'isPlaying':
              return playing;
            default:
              return null;
          }
        });
    await tester.pumpWidget(
      MaterialApp(home: SoundPage(service: FakeTranscriptionService())),
    );
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.text('마이크로 녹음'));
      await tester.tap(find.text('마이크로 녹음'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('녹음 종료'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('STT 전송'));
      await tester.tap(find.text('STT 전송'));
      await tester.pumpAndSettle();
    }
    final firstRecord = find.ancestor(
      of: find.text('녹음 1'),
      matching: find.byType(Card),
    );
    final playFirst = find.descendant(
      of: firstRecord,
      matching: find.text('녹음 듣기'),
    );
    await tester.ensureVisible(playFirst);
    await tester.tap(playFirst);
    await tester.pumpAndSettle();
    expect(played.single, [1, 2, 3]);
    expect(find.text('재생 정지'), findsOneWidget);
    playing = false; // Native player finished.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('재생 정지'), findsNothing);
    await tester.tap(playFirst);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('지우기'));
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    expect(playing, false);
    expect(find.text('녹음 듣기'), findsNothing);
  });
}
