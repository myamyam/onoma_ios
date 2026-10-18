import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:first_flutter/main.dart';
import 'package:first_flutter/services/haptic_service.dart';
import 'package:first_flutter/widgets/mucap_visualization.dart';
import 'package:first_flutter/pages/sound_page.dart';
import 'package:first_flutter/services/sound_service.dart';
import 'package:first_flutter/services/mucap_client.dart';
import 'package:first_flutter/models/nonspeech_transcription.dart';

class FakeMucapClient extends MucapClient {
  bool fail = false;
  bool failOutputs = false;
  int outputCalls = 0;
  final uploads = <Uint8List>[];
  @override
  Future<NonspeechTranscription> transcribe(Uint8List audio) async {
    uploads.add(audio);
    if (fail) throw const FormatException('전사 테스트 오류');
    return NonspeechTranscription(1, 'test', [
      NonspeechCue(0, 1, '둥${audio.first}'),
    ]);
  }

  @override
  Future<MucapResult> enrich(
    Uint8List audio,
    NonspeechTranscription transcript,
  ) async {
    outputCalls++;
    if (failOutputs) throw const FormatException('outputs failed');
    return MucapResult(
      transcript.duration,
      transcript.model,
      transcript.captions
          .map((cue) => CaptionCue(cue.time, cue.end, cue.text, .5, 26))
          .toList(),
      [const HapticEvent(time: 0, duration: .08, intensity: .5, sharpness: .5)],
    );
  }

  @override
  Future<MucapResult> analyze(Uint8List audio) =>
      throw StateError('Full pipeline must not run');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          HapticService.channel,
          (call) async =>
              call.method == 'isSupported' || call.method == 'isPlaying'
              ? false
              : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HapticService.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SoundService.channel, null);
  });

  testWidgets('전사 화면은 STT·시각화·햅틱 생성 없이 표시', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('STT 전송'), findsNothing);
    expect(find.text('MuCap 분석'), findsNothing);
    expect(find.text('햅틱 재생'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('마이크로 녹음'), findsOneWidget);
  });

  testWidgets('권한 거부 후 다시 녹음 가능', (tester) async {
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
    await tester.ensureVisible(find.text('마이크로 녹음'));
    await tester.pumpAndSettle();
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

  testWidgets('15초 종료 후 전사만 호출, 오류 재시도 및 원본 재생·삭제', (tester) async {
    final client = FakeMucapClient()..fail = true;
    var stopCount = 0;
    var playing = false;
    final played = <Uint8List>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SoundService.channel, (call) async {
          switch (call.method) {
            case 'stop':
              stopCount++;
              return Uint8List.fromList([7, 2, 3]);
            case 'play':
              played.add(call.arguments as Uint8List);
              playing = true;
              return null;
            case 'stopPlayback':
              playing = false;
              return null;
            case 'isPlaying':
              return playing;
            case 'position':
              return .2;
            default:
              return null;
          }
        });
    await tester.pumpWidget(MaterialApp(home: SoundPage(client: client)));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('마이크로 녹음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('마이크로 녹음'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(stopCount, 1);
    await tester.ensureVisible(find.text('소리 전사'));
    await tester.tap(find.text('소리 전사'));
    await tester.pumpAndSettle();
    expect(find.text('전사 테스트 오류'), findsOneWidget);
    client.fail = false;
    await tester.tap(find.text('소리 전사'));
    await tester.pumpAndSettle();
    expect(client.uploads.length, 2);
    expect(client.uploads.last, [7, 2, 3]);
    expect(find.text('둥7'), findsOneWidget);
    expect(find.text('[0.00–1.00초] 둥7'), findsOneWidget);
    expect(find.text('햅틱 재생'), findsNothing);
    await tester.ensureVisible(find.text('녹음 듣기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('녹음 듣기'));
    await tester.pumpAndSettle();
    expect(played.single, [7, 2, 3]);
    expect(find.text('재생 정지'), findsOneWidget);
    playing = false;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('재생 정지'), findsNothing);
    await tester.ensureVisible(find.text('지우기'));
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    expect(find.text('둥7'), findsNothing);
  });
  testWidgets('전사 결과를 유지하며 시각화·햅틱 실패 후 재시도', (tester) async {
    final client = FakeMucapClient()..failOutputs = true;
    final integrated = <Map<dynamic, dynamic>>[];
    var playing = false;
    var failPlayback = false;
    var stopCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HapticService.channel, (call) async {
          if (call.method == 'isSupported') return true;
          if (call.method == 'play') fail('Use one native integrated call');
          if (call.method == 'isPlaying') return false;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HapticService.channel, null),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SoundService.channel, (call) async {
          if (call.method == 'stop') return Uint8List.fromList([8, 2, 3]);
          if (call.method == 'playIntegrated') {
            integrated.add(call.arguments as Map);
            if (failPlayback) {
              throw PlatformException(code: 'playback', message: '통합 시작 실패');
            }
            playing = true;
          }
          if (call.method == 'stopPlayback') {
            stopCalls++;
            playing = false;
          }
          if (call.method == 'isPlaying') return playing;
          if (call.method == 'position') return .4;
          return null;
        });
    await tester.pumpWidget(MaterialApp(home: SoundPage(client: client)));
    await tester.ensureVisible(find.text('마이크로 녹음'));
    await tester.ensureVisible(find.text('마이크로 녹음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('마이크로 녹음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('녹음 종료'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('전사·시각화·햅틱 생성'));
    await tester.tap(find.text('전사·시각화·햅틱 생성'));
    await tester.pumpAndSettle();
    expect(client.uploads.length, 1);
    expect(client.outputCalls, 1);
    expect(find.text('둥8'), findsOneWidget);
    expect(find.textContaining('전사는 보관했습니다.'), findsOneWidget);
    client.failOutputs = false;
    await tester.ensureVisible(find.text('시각화·햅틱 추가 생성'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시각화·햅틱 추가 생성'));
    await tester.pumpAndSettle();
    expect(client.uploads.length, 1);
    expect(client.outputCalls, 2);
    expect(find.byType(MucapVisualization), findsOneWidget);
    expect(find.text('햅틱 재생'), findsNothing);
    await tester.ensureVisible(find.text('통합 재생'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('통합 재생'));
    await tester.pumpAndSettle();
    expect(integrated.single['audio'], [8, 2, 3]);
    expect((integrated.single['events'] as List).single['intensity'], .5);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<MucapVisualization>(find.byType(MucapVisualization))
          .position,
      .4,
    );
    final beforeStop = stopCalls;
    await tester.tap(find.text('재생 정지'));
    await tester.pumpAndSettle();
    expect(stopCalls, greaterThan(beforeStop));
    expect(playing, isFalse);
    expect(
      tester
          .widget<MucapVisualization>(find.byType(MucapVisualization))
          .position,
      0,
    );

    // Restart and stop both outputs when the app becomes inactive.
    await tester.tap(find.text('통합 재생'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(playing, isFalse);
    expect(find.text('재생 정지'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // A failed native start must clean up and allow retry.
    failPlayback = true;
    final beforeFailure = stopCalls;
    await tester.tap(find.text('통합 재생'));
    await tester.pumpAndSettle();
    expect(stopCalls, greaterThan(beforeFailure + 1));
    await tester.scrollUntilVisible(
      find.textContaining('통합 시작 실패'),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('통합 시작 실패'), findsOneWidget);
    expect(find.text('재생 정지'), findsNothing);
    failPlayback = false;
    await tester.ensureVisible(find.text('통합 재생'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('통합 재생'));
    await tester.pumpAndSettle();
    playing = false;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('재생 정지'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
