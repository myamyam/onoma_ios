import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sound_service.dart';

enum CaptureState { ready, starting, recording, stopping, transcribing }

class SoundPage extends StatefulWidget {
  const SoundPage({super.key});
  @override
  State<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<SoundPage> with WidgetsBindingObserver {
  final _service = SoundService();
  final _endpoint = TextEditingController();
  final _token = TextEditingController();
  final _results = <SoundResult>[];
  CaptureState _state = CaptureState.ready;
  bool _demo = true;
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
    _endpoint.dispose();
    _token.dispose();
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
    setState(() {
      _state = CaptureState.transcribing;
      _error = null;
    });
    try {
      final result = await _service.transcribe(
        _audio!,
        _endpoint.text,
        _token.text,
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

  void _sample(String transcript) {
    setState(() {
      _error = null;
      _results.insert(0, SoundResult(transcript, true));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recording = _state == CaptureState.recording;
    final status = switch (_state) {
      CaptureState.ready => _audio == null ? '주변의 소리를 담아보세요' : '녹음이 준비되었어요',
      CaptureState.starting => '마이크 준비 중',
      CaptureState.recording => '주변 소리를 듣고 있어요',
      CaptureState.stopping => '녹음 마무리 중',
      CaptureState.transcribing => '들리는 소리를 한글로 전사하는 중',
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
                '들리는 소리 그대로',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text('멍! 멍멍… 끼이익… 쾅! 소리의 순서와 반복을 글자로 담아요.'),
              const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('샘플 체험'),
                    icon: Icon(Icons.science_outlined),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('실제 API'),
                    icon: Icon(Icons.cloud_outlined),
                  ),
                ],
                selected: {_demo},
                onSelectionChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _demo = value.first;
                        _error = null;
                      }),
              ),
              const SizedBox(height: 16),
              if (_demo) ...[
                const Text('미리 작성한 전사 예시입니다. 실제 오디오를 듣고 전사한 결과가 아닙니다.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.graphic_eq),
                      label: const Text('예시 1'),
                      onPressed: () => _sample('멍! 멍멍… 으르렁'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.graphic_eq),
                      label: const Text('예시 2'),
                      onPressed: () => _sample('톡… 톡톡… 쏴아아'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.graphic_eq),
                      label: const Text('예시 3'),
                      onPressed: () => _sample('끼이익… 쾅!'),
                    ),
                  ],
                ),
              ] else ...[
                const Text('녹음 후 전송 버튼을 누르면 아래 API로 오디오를 보냅니다.'),
                const SizedBox(height: 12),
                TextField(
                  controller: _endpoint,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'API 주소 (HTTPS)',
                    hintText: 'https://your-server.com/transcribe-sound',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _token,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '테스트용 Bearer 토큰 (선택)',
                  ),
                ),
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
                          onPressed: recording
                              ? _stop
                              : (_busy ? null : _start),
                          icon: Icon(recording ? Icons.stop : Icons.mic),
                          label: Text(recording ? '녹음 종료' : '소리 녹음'),
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
                            label: const Text('API로 전송 · 소리 전사'),
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
              ],
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
                    '아직 기록이 없어요.\n샘플을 선택하거나 주변 소리를 녹음해보세요.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final result in _results)
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Icon(
                      result.isDemo ? Icons.science_outlined : Icons.graphic_eq,
                    ),
                    title: Text(result.transcript),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        result.isDemo ? '샘플 · 실제 전사 아님' : 'API 전사 결과',
                      ),
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
