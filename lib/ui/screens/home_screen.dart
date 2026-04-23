import 'package:flutter/material.dart';

import '../widgets/big_button.dart';
import 'chat_screen.dart';
import 'gallery_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BlueCare')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            BigButton(
              title: '暖心对话',
              icon: Icons.chat_bubble_outline,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChatScreen()),
                );
              },
            ),
            BigButton(
              title: '记忆画册',
              icon: Icons.photo_library_outlined,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GalleryScreen()),
                );
              },
            ),
            const BigButton(
              title: '用药提醒',
              icon: Icons.medication_outlined,
              onTap: _noop,
            ),
            const BigButton(
              title: '安全守护',
              icon: Icons.health_and_safety_outlined,
              onTap: _noop,
            ),
          ],
        ),
      ),
    );
  }

  static void _noop() {}
}
