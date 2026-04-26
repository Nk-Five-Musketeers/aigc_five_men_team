import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/theme.dart';
import 'logic/chat_provider.dart';
import 'ui/screens/home_screen.dart';

void main() {
  runApp(const BlueCareApp());
}

class BlueCareApp extends StatelessWidget {
  const BlueCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatProvider(),
      child: MaterialApp(
        title: '暖忆陪伴',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const HomeScreen(),
      ),
    );
  }
}
