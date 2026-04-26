import 'package:flutter/material.dart';

import 'config/theme.dart';
import 'ui/screens/home_screen.dart';

void main() {
  runApp(const BlueCareApp());
}

class BlueCareApp extends StatelessWidget {
  const BlueCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '心伴',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const HomeScreen(),
    );
  }
}
