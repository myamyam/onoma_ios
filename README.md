# flutter test

## API setting

`config/stt.local.json`의 `STT_API_KEY`에 API 키(groq)를 입력.

## 실행

```sh
flutter run -d macos
# iPhone 실행 (이름이 겹치는 기기가 여러 대면 목록에서 선택)
flutter run -d iPhone
```

## 동작

- iOS·macOS 마이크로 최대 15초 녹음
- STT 전송 시 설정한 서버에 WAV를 업로드
- 모델의 전사 텍스트를 그대로 표시
- 전사 기록의 **녹음 듣기 / 재생 정지**로 해당 요청에 사용한 원본 녹음을 다시 듣기
- 한국어는 `ko`, 영어는 `en`, 자동 감지는 `STT_LANGUAGE`를 빈 문자열로 지정합니다.
