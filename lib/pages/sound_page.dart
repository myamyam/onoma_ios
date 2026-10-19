import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sound_service.dart';
import '../services/mucap_client.dart';
import '../models/nonspeech_transcription.dart';
import '../services/haptic_service.dart';
import '../widgets/mucap_visualization.dart';

enum CaptureState { ready, starting, recording, stopping, transcribing }

class RecordingEntry {
  RecordingEntry(this.result, Uint8List audio)
    : audio = Uint8List.fromList(audio);
  MucapResult? multimodal;
  bool timelineExpanded = false;
  List<HapticEvent> get hapticEvents => multimodal?.events ?? const [];
  final NonspeechTranscription result;
  final Uint8List audio;
}

class SoundPage extends StatefulWidget {
  const SoundPage({super.key, this.service, this.client});
  final MucapClient? client;
  final SoundService? service;
  @override
  State<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<SoundPage> with WidgetsBindingObserver {
  late final _service = widget.service ?? SoundService();
  final _results = <RecordingEntry>[];
  final _haptics = HapticService();
  bool _hapticsSupported = false;
  bool _textOnly = false;
  bool _generatingOutputs = false;
  RecordingEntry? _playing;
  double _position = 0;
  Timer? _playbackTimer;
  bool _playbackBusy = false;
  int _playbackGeneration = 0;
  CaptureState _state = CaptureState.ready;
  int _seconds = 0;
  Timer? _timer;
  Uint8List? _audio;
  String? _error;
  bool get _busy => _state != CaptureState.ready || _playbackBusy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkHaptics());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.inactive) &&
        _state == CaptureState.recording) {
      unawaited(_stop());
    }
    if (state != AppLifecycleState.resumed && _playing != null) {
      unawaited(_stopPlayback().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_service.stopPlayback().catchError((Object _) {}));
    _playbackTimer?.cancel();
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
      await _stopPlayback();
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
    final audio = _audio!;
    final includeOutputs = !_textOnly;
    setState(() {
      _state = CaptureState.transcribing;
      _error = null;
    });
    try {
      await _stopPlayback();
      final result = await (widget.client ?? MucapClient()).transcribe(audio);
      if (mounted) {
        final entry = RecordingEntry(result, audio);
        setState(() => _results.insert(0, entry));
        if (includeOutputs) await _addOutputs(entry, alreadyBusy: true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) {
        setState(() {
          _state = CaptureState.ready;
        });
      }
    }
  }

  Future<void> _stopPlayback() async {
    _playbackGeneration++;
    _playbackTimer?.cancel();
    if (mounted) {
      setState(() {
        _playing = null;
        _position = 0;
      });
    }
    await _service.stopPlayback();
  }

  Future<void> _togglePlayback(RecordingEntry entry) async {
    if (_busy) return;
    final wasPlaying = identical(_playing, entry);
    setState(() {
      _playbackBusy = true;
      _error = null;
    });
    try {
      await _stopPlayback();
      if (!wasPlaying && mounted) {
        final generation = _playbackGeneration;
        setState(() => _playing = entry);
        if (entry.multimodal != null && _hapticsSupported) {
          await _service.playIntegrated(entry.audio, entry.hapticEvents);
        } else {
          await _service.play(entry.audio);
        }
        if (!mounted ||
            generation != _playbackGeneration ||
            !identical(_playing, entry)) {
          return;
        }
        _playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (
          _,
        ) async {
          try {
            final active = await _service.isPlaying();
            final position = await _service.position();
            if (mounted &&
                generation == _playbackGeneration &&
                identical(_playing, entry)) {
              setState(() => _position = active ? position : 0);
            }
            if (mounted &&
                generation == _playbackGeneration &&
                identical(_playing, entry) &&
                !active) {
              await _stopPlayback();
            }
          } catch (_) {
            if (mounted &&
                generation == _playbackGeneration &&
                identical(_playing, entry)) {
              await _stopPlayback().catchError((Object _) {});
              if (mounted) setState(() => _error = '통합 재생 상태를 확인하지 못했습니다.');
            }
          }
        });
      }
    } catch (error) {
      await _stopPlayback().catchError((Object _) {});
      if (mounted) {
        setState(() => _error = '재생에 실패했습니다: ${_message(error)}');
      }
    } finally {
      if (mounted) setState(() => _playbackBusy = false);
    }
  }

  Future<void> _checkHaptics() async {
    try {
      final supported = await _haptics.isSupported();
      if (mounted) setState(() => _hapticsSupported = supported);
    } catch (_) {
      // Audio playback remains available when haptics cannot initialize.
    }
  }

  Future<void> _addOutputs(
    RecordingEntry entry, {
    bool alreadyBusy = false,
  }) async {
    if ((!alreadyBusy && _busy) || entry.multimodal != null) return;
    setState(() {
      _generatingOutputs = true;
      _state = CaptureState.transcribing;
      _error = null;
    });
    try {
      await _stopPlayback();
      final result = await (widget.client ?? MucapClient()).enrich(
        entry.audio,
        entry.result,
      );
      if (mounted) setState(() => entry.multimodal = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = '전사 기록은 보관했습니다. 시각화·햅틱 생성 실패: ${_message(error)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _generatingOutputs = false;
          _state = CaptureState.ready;
        });
      }
    }
  }

  Future<void> _clearHistory() async {
    if (_busy) return;
    setState(() => _playbackBusy = true);
    try {
      await _stopPlayback();
      if (mounted) setState(_results.clear);
    } catch (_) {
      if (mounted) setState(() => _error = '재생을 중지하지 못했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _playbackBusy = false);
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
      CaptureState.ready => _audio == null ? '원하는 소리를 녹음하세요' : '녹음이 준비되었어요',
      CaptureState.starting => '마이크 준비 중',
      CaptureState.recording => '주변 소리를 듣고 있어요',
      CaptureState.stopping => '녹음 마무리 중',
      CaptureState.transcribing =>
        _generatingOutputs ? '전사 완료 · 시각화·햅틱 생성 중' : '소리를 텍스트로 옮기는 중',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter test')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('소리를 텍스트로', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 12),
              const Text('소리를 녹음하고 텍스트를 확인하세요.'),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('텍스트만 먼저 보기'),
                subtitle: Text(
                  _textOnly ? '필요할 때 시각화·햅틱을 추가로 생성합니다.' : '시각화·햅틱도 함께 생성합니다.',
                ),
                value: _textOnly,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _textOnly = value),
              ),
              const SizedBox(height: 20),
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
                        label: Text(recording ? '녹음 종료' : '녹음'),
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
                          icon: const Icon(Icons.text_fields),
                          label: Text(_textOnly ? '소리 전사' : '전사·시각화·햅틱 생성'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text('최대 15초 · 화면을 벗어나면 녹음 종료'),
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
                  ),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('오디오 기록', style: theme.textTheme.titleLarge),
                  ),
                  if (_results.isNotEmpty)
                    TextButton(
                      onPressed: _busy ? null : _clearHistory,
                      child: const Text('지우기'),
                    ),
                ],
              ),
              const Text('전사와 녹음은 앱 실행 중에만 보관됩니다.'),
              if (_results.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text('아직 기록이 없어요. 녹음 후 소리 전사를 눌러보세요.'),
                ),
              for (final entry in _results)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          entry.result.text,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${entry.result.model} · ${entry.result.duration.toStringAsFixed(1)}초',
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () => setState(
                            () => entry.timelineExpanded =
                                !entry.timelineExpanded,
                          ),
                          icon: Icon(
                            entry.timelineExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                          ),
                          label: const Text('timeline'),
                        ),
                        if (entry.timelineExpanded)
                          for (final cue in entry.result.captions)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '[${cue.time.toStringAsFixed(2)}–${cue.end.toStringAsFixed(2)}초] ${cue.text}',
                                style: TextStyle(
                                  fontWeight:
                                      identical(_playing, entry) &&
                                          cue.time <= _position &&
                                          _position < cue.end
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                        if (entry.multimodal != null) ...[
                          const SizedBox(height: 12),
                          MucapVisualization(
                            result: entry.multimodal!,
                            position: identical(_playing, entry)
                                ? _position
                                : 0,
                          ),
                          const SizedBox(height: 8),
                          if (!_hapticsSupported)
                            const Text('이 기기에서는 오디오와 시각화만 재생합니다.'),
                          if (_hapticsSupported && entry.hapticEvents.isEmpty)
                            const Text('이 녹음에는 재생할 진동이 없습니다.'),
                        ] else ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _addOutputs(entry),
                            icon: const Icon(Icons.graphic_eq),
                            label: const Text('시각화·햅틱 추가 생성'),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _togglePlayback(entry),
                          icon: Icon(
                            identical(_playing, entry)
                                ? Icons.stop
                                : Icons.play_arrow,
                          ),
                          label: Text(
                            identical(_playing, entry)
                                ? '재생 정지'
                                : entry.multimodal != null
                                ? '통합 재생'
                                : '녹음 듣기',
                          ),
                        ),
                      ],
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
