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
}
