import 'package:flutter/material.dart';

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('记忆画册')),
      body: const Center(
        child: Text('画册模块骨架已创建'),
      ),
    );
  }
}
