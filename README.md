# 소리노트 — 비음성 소리의 한글 전사 테스트

목표는 **들리는 소리 자체를 한글 의성어로 전사**하는 것입니다. 소리의 순서, 반복, 길이와 쉼을 표현합니다.

- 전사 예시: `멍! 멍멍… 으르렁`, `끼이익… 쾅!`, `톡… 톡톡… 쏴아아`
- 분류명(`개 짖음`)이나 상황 설명(`개가 짖고 있습니다`)은 목표 출력이 아닙니다.
- 정해진 분류 결과를 의성어로 치환하지 않고 입력 오디오에서 전사해야 합니다.

## 현재 구현 범위

iOS·macOS 녹음, API 전송, 전사 결과 표시 및 샘플 UI를 구현했습니다. **실제 오디오를 한글로 전사하는 모델/백엔드는 아직 연결되지 않았습니다.** 요청의 task 이름과 지침만으로 모델 기능이 생기지는 않습니다. 아래는 이 앱에서 정의한 임시 계약이며 특정 제공자의 표준 API가 아닙니다.

## 실행

```sh
flutter pub get
flutter run
```

맥에서 실행하려면 `flutter run -d macos`를 사용합니다. `샘플 체험`은 API 없이 확인할 수 있습니다. `실제 API`에서 녹음을 시작하면 마이크 권한을 요청합니다. 다른 앱으로 전환하면 녹음이 종료됩니다.

독립 실행 앱 빌드: `flutter build macos --debug`. 실행: `open build/macos/Build/Products/Debug/first_flutter.app`.

iPhone 또는 iOS 시뮬레이터에서도 실행할 수 있습니다. 실제 마이크 입력 검증은 iPhone에서 진행하세요.

- **샘플 체험:** 예시 1~3으로 미리 작성된 전사 텍스트를 표시합니다. 마이크나 모델을 사용하지 않습니다.
- **실제 API:** HTTPS 주소와 필요한 경우 테스트용 Bearer 토큰 입력 → 최대 15초 녹음 → 종료 → `API로 전송 · 소리 전사`.
- 기록·토큰·녹음은 영구 저장하지 않습니다. 녹음 임시 파일은 읽기/취소 후 삭제합니다.
- 백그라운드 이동 시 녹음 종료. 전화 등 오디오 인터럽트 발생 시 다시 녹음하도록 안내합니다.

## 임시 API 계약

요청: `POST`, `Content-Type: application/json`, 선택적 `Authorization: Bearer ...`

```json
{
  "audio_base64": "<WAV 파일의 Base64>",
  "mime_type": "audio/wav",
  "language": "ko",
  "task": "non_speech_sound_transcription",
  "instructions": "<SoundService.transcriptionInstructions의 전사 지침>"
}
```

전사 지침은 들리는 비음성 소리를 한글 의성어로 옮기고 순서·반복·길이·쉼을 보존하도록 요청합니다. 분류명과 상황 설명, 사람의 말 받아쓰기, 들리지 않는 소리의 추가는 제외합니다. 무음은 `[무음]`, 전사할 수 없는 구간은 `[전사 불확실]`로 요청합니다.

오디오: 16 kHz, mono, 16-bit PCM WAV, 최대 15초.

성공 응답: HTTP 2xx

```json
{"transcript_ko": "끼이익… 쾅!"}
```

기존 `caption_ko` 응답은 받지 않습니다. 앱은 응답 구조를 검사하지만 문자열이 실제 소리와 일치하는지는 자동 검증하지 못합니다. 백엔드에서 지침을 모델에 전달하고 실제 오디오로 품질을 검증해야 합니다.

45초 응답 제한, 1 MiB 응답 크기 제한, HTTPS만 지원합니다. 실패 후 녹음을 수동 재전송할 수 있습니다. 배포 시 모델 제공자 키는 백엔드에서 관리하고, 앱 입력 토큰은 테스트 서버용으로 사용하세요.

## 다음 API 연결 시 검증

1. 같은 종류의 소리라도 반복 횟수와 길이가 다르면 전사가 달라지는지 확인.
2. 여러 소리가 섞인 녹음에서 순서와 쉼이 보존되는지 확인.
3. 분류명이나 설명문이 아닌 의성어가 반환되는지 확인.
4. 무음·불확실한 소리에서 그럴듯한 소리를 만들어내지 않는지 확인.

## 코드와 검사

- `lib/sound_page.dart`: 샘플·녹음·전송·전사 UI 및 상태
- `lib/sound_service.dart`: 녹음 채널, 전사 지침, API 요청/응답
- `ios/Runner/AppDelegate.swift`: iOS 녹음 및 Flutter 채널
- `macos/Runner/MainFlutterWindow.swift`: macOS 녹음 및 Flutter 채널
- `test/widget_test.dart`: 샘플 구분, 권한 거부, 자동 종료, 응답 검증

```sh
flutter analyze
flutter test
flutter build ios --simulator --debug
```

스트리밍, 녹음 재생, 영구 기록 저장은 아직 포함하지 않습니다.
