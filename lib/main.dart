import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/theme.dart';
import 'logic/chat_provider.dart';
import 'logic/voice_output_provider.dart';
import 'ui/screens/home_screen.dart';

void main() {
  runApp(const BlueCareApp());
}

class BlueCareApp extends StatelessWidget {
  const BlueCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(
          create: (_) => VoiceOutputProvider()..loadSettings(),
        ),
      ],
      child: MaterialApp(
        title: '拾忆',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const HomeScreen(),
      ),
    );
  }
}
