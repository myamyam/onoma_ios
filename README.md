# 소리노트 — Groq Whisper STT 테스트

사용자는 마이크 권한 허용 → 녹음 → 종료 → STT 전송만 진행합니다. API 주소·키·모델·입력 언어는 개발자가 실행 전에 설정하며 앱에 입력란을 표시하지 않습니다.

## 개발자 설정

`config/stt.local.json`의 `STT_API_KEY`에 Groq API 키를 입력하세요. 파일은 Git에서 제외됩니다. 새 체크아웃에서는 `config/stt.example.json`을 복사해 만드세요.

```json
{
  "STT_API_URL": "https://api.groq.com/openai/v1/audio/transcriptions",
  "STT_API_KEY": "여기에 Groq API 키 입력",
  "STT_MODEL": "whisper-large-v3-turbo",
  "STT_LANGUAGE": "ko"
}
```

```sh
flutter run -d macos
# iPhone 실행 (이름이 겹치는 기기가 여러 대면 목록에서 선택)
flutter run -d iPhone
```

설정을 변경하면 실행을 종료하고 위 명령으로 다시 실행하세요. Hot reload만으로는 적용되지 않습니다. `--dart-define-from-file`은 더 이상 필요하지 않으며 설정은 JSON 파일을 기준으로 합니다. 키가 없으면 녹음은 가능하지만 전송 전에 서비스 미설정 안내를 표시합니다. 설정 파일의 내용이나 키를 로그·대화에 붙여 넣지 마세요.

별도 설정 옵션 없이 빌드할 수 있습니다. 앱 시작 시 번들에 포함된 로컬 JSON을 읽습니다.

```sh
flutter build macos --debug
flutter build ios --debug
```

**현재 방식은 개발용입니다.** 로컬 JSON은 앱 asset에 포함되므로 앱 파일에서 키를 추출할 수 있습니다. 외부 사용자에게 배포할 때는 Groq 키를 백엔드에 보관하고 앱은 그 백엔드를 호출하도록 바꿔야 합니다. Git 제외는 저장소 유출 방지이며 앱에서 키 추출을 막는 기능이 아닙니다.

## 동작

- iOS·macOS 마이크로 최대 15초 녹음합니다. 첫 녹음 시 OS 권한을 요청합니다.
- 다른 앱으로 전환하면 녹음을 종료합니다.
- STT 전송 시 설정한 서버에 WAV를 업로드합니다. 자동 재시도하지 않습니다.
- 모델의 전사 텍스트를 그대로 표시합니다. 빈 결과는 별도 안내합니다.
- 전사 기록의 **녹음 듣기 / 재생 정지**로 해당 요청에 사용한 원본 녹음을 들을 수 있습니다. 다른 기록 재생·새 녹음·기록 지우기·앱 전환 시 재생을 종료합니다.
- 오디오·전사 기록은 실행 중에만 유지됩니다. 앱을 종료하면 사라집니다.
- 한국어는 `ko`, 영어는 `en`, 자동 감지는 `STT_LANGUAGE`를 빈 문자열로 지정합니다.

[Groq STT 공식 문서](https://console.groq.com/docs/speech-to-text)의 OpenAI 호환 multipart 업로드를 사용합니다. `file`은 16 kHz mono 16-bit PCM WAV이며 `model`, `language`(자동 감지는 생략), `response_format=json`을 보냅니다. 응답은 `{"text":"전사 결과"}`입니다.

일반 음성 받아쓰기 테스트이며 최종 목표인 비음성 소리의 한글 의성어 전사를 보장하지 않습니다. Qwen 전용 어댑터는 없으며 같은 계약을 지원하는 서버에 한해 설정을 바꿔 연결할 수 있습니다.

## 검증

```sh
flutter analyze
flutter test
# 키 없이 로컬 HTTPS 서버로 WAV 업로드와 오류 처리 검증 (openssl 필요)
dart run tool/stt_smoke_test.dart
```

실제 모델 호출은 개발자가 키를 설정한 뒤 확인합니다. 로컬 HTTPS 테스트는 외부 API를 호출하지 않습니다.
