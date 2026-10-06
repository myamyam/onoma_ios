import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sound_service.dart';
import 'stt_config.dart';

enum CaptureState { ready, starting, recording, stopping, transcribing }

class SoundPage extends StatefulWidget {
  const SoundPage({super.key});
  @override
  State<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<SoundPage> with WidgetsBindingObserver {
  final _service = SoundService();
  final _results = <SoundResult>[];
  CaptureState _state = CaptureState.ready;
  int _seconds = 0;
  Timer? _timer;
  Uint8List? _audio;
  String? _error;
  bool get _busy => _state != CaptureState.ready;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.inactive) &&
        _state == CaptureState.recording) {
      unawaited(_stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_service.cancel().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _state = CaptureState.starting;
      _error = null;
      _audio = null;
      _seconds = 0;
    });
    try {
      await _service.start();
      if (!mounted) return;
      setState(() => _state = CaptureState.recording);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= 15) unawaited(_stop());
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _state = CaptureState.ready;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _stop() async {
    if (_state != CaptureState.recording) return;
    _timer?.cancel();
    setState(() => _state = CaptureState.stopping);
    try {
      final audio = await _service.stop();
      if (mounted) {
        setState(() {
          _audio = audio;
          _state = CaptureState.ready;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _state = CaptureState.ready;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _transcribe() async {
    if (_audio == null || _busy) return;
    if (SttConfig.apiKey.trim().isEmpty) {
      setState(() => _error = '전사 서비스가 아직 준비되지 않았습니다. 개발자에게 문의해주세요.');
      return;
    }
    setState(() {
      _state = CaptureState.transcribing;
      _error = null;
    });
    try {
      final result = await _service.transcribe(
        _audio!,
        SttConfig.endpoint,
        SttConfig.apiKey,
        model: SttConfig.model,
        language: SttConfig.language,
      );
      if (mounted) setState(() => _results.insert(0, result));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _state = CaptureState.ready);
    }
  }

  String _message(Object error) => switch (error) {
    PlatformException e => e.message ?? '녹음에 실패했습니다.',
    MissingPluginException() => '실제 녹음은 iOS 또는 macOS 앱에서 사용할 수 있습니다.',
    FormatException e => e.message,
    TimeoutException() => '응답 시간이 초과되었습니다. 다시 시도해주세요.',
    _ => '연결에 실패했습니다. 네트워크와 API 설정을 확인해주세요.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recording = _state == CaptureState.recording;
    final status = switch (_state) {
      CaptureState.ready => _audio == null ? '주변의 소리를 담아보세요' : '녹음이 준비되었어요',
      CaptureState.starting => '마이크 준비 중',
      CaptureState.recording => '주변 소리를 듣고 있어요',
      CaptureState.stopping => '녹음 마무리 중',
      CaptureState.transcribing => 'STT 모델이 전사하는 중',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('소리노트'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 20),
            child: Chip(label: Text('TEST')),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '녹음하고, 텍스트로.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text('마이크로 녹음한 소리를 텍스트로 확인해보세요.'),
              const SizedBox(height: 24),
              const Text('전송 버튼을 누르면 녹음이 음성 인식 서버로 전송됩니다.'),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        recording ? Icons.graphic_eq : Icons.mic_none_rounded,
                        size: 56,
                        color: recording
                            ? Colors.redAccent
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(status, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        '${_seconds.toString().padLeft(2, '0')} / 15초',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: recording ? _stop : (_busy ? null : _start),
                        icon: Icon(recording ? Icons.stop : Icons.mic),
                        label: Text(recording ? '녹음 종료' : '마이크로 녹음'),
                      ),
                      if (_state == CaptureState.transcribing)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: LinearProgressIndicator(),
                        ),
                      if (_audio != null) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _transcribe,
                          icon: const Icon(Icons.upload_rounded),
                          label: const Text('STT 전송'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        '최대 15초 · 화면을 벗어나면 녹음 종료',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                    semanticsLabel: '오류: $_error',
                  ),
                ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text('전사 기록', style: theme.textTheme.titleLarge),
                  ),
                  if (_results.isNotEmpty)
                    TextButton(
                      onPressed: _busy ? null : () => setState(_results.clear),
                      child: const Text('지우기'),
                    ),
                ],
              ),
              const Text('이번 실행 중의 결과만 표시됩니다.'),
              const SizedBox(height: 12),
              if (_results.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    '아직 기록이 없어요.\n마이크로 녹음한 뒤 STT 전송을 눌러보세요.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final result in _results)
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const Icon(Icons.notes),
                    title: SelectableText(
                      result.transcript.trim().isEmpty
                          ? '모델이 전사 텍스트를 반환하지 않았습니다.'
                          : result.transcript,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${result.model} · STT 결과'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
