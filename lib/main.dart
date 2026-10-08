import 'package:flutter/material.dart';

import 'sound_page.dart';
import 'stt_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SttConfig.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '소리노트',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF386653)),
      scaffoldBackgroundColor: const Color(0xFFF6F7F2),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: const SoundPage(),
  );
}
