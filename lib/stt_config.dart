/// Developer-provided build settings. Never display or log apiKey.
class SttConfig {
  static const endpoint = String.fromEnvironment(
    'STT_API_URL',
    defaultValue: 'https://api.groq.com/openai/v1/audio/transcriptions',
  );
  static const apiKey = String.fromEnvironment('STT_API_KEY');
  static const model = String.fromEnvironment(
    'STT_MODEL',
    defaultValue: 'whisper-large-v3-turbo',
  );
  static const language = String.fromEnvironment(
    'STT_LANGUAGE',
    defaultValue: 'ko',
  );
}
