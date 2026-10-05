import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:first_flutter/main.dart';
import 'package:first_flutter/sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SoundService.channel, null);
  });

  testWidgets('샘플은 실제 전사와 구분되며 기록을 지울 수 있다', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('예시 1'));
    await tester.pumpAndSettle();
    expect(find.text('멍! 멍멍… 으르렁'), findsOneWidget);
    expect(find.text('샘플 · 실제 전사 아님'), findsOneWidget);
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    expect(find.text('샘플 · 실제 전사 아님'), findsNothing);
  });

  testWidgets('권한 거부 후 다시 녹음할 수 있다', (tester) async {
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
    await tester.tap(find.text('실제 API'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('소리 녹음'));
    await tester.tap(find.text('소리 녹음'));
    await tester.pumpAndSettle();
    expect(find.text('마이크 권한이 필요합니다.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '소리 녹음'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('15초 후 녹음을 종료하고 명시적 전송을 기다린다', (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SoundService.channel, (call) async {
          calls.add(call.method);
          return call.method == 'stop' ? Uint8List.fromList([1, 2, 3]) : null;
        });
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('실제 API'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('소리 녹음'));
    await tester.tap(find.text('소리 녹음'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call == 'stop').length, 1);
    expect(find.text('API로 전송 · 소리 전사'), findsOneWidget);
    expect(find.text('API 전사 결과'), findsNothing);
    await tester.ensureVisible(find.text('API로 전송 · 소리 전사'));
    await tester.tap(find.text('API로 전송 · 소리 전사'));
    await tester.pumpAndSettle();
    expect(find.text('올바른 HTTPS API 주소를 입력해주세요.'), findsOneWidget);
  });

  test('API 응답 검증 및 샘플 표시 구분', () {
    final result = SoundResult.fromJson({'transcript_ko': '  끼이익… 쾅!  '});
    expect(result.transcript, '끼이익… 쾅!');
    expect(result.isDemo, false);
    for (final value in [
      null,
      {},
      {'transcript_ko': ''},
      {'transcript_ko': 3},
      {'caption_ko': '문이 닫히는 소리'},
    ]) {
      expect(() => SoundResult.fromJson(value), throwsFormatException);
    }
  });
}
