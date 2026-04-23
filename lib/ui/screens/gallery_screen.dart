import 'package:flutter/material.dart';

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  static const List<_MemoryItem> _items = <_MemoryItem>[
    _MemoryItem('1988 夏天', '全家第一次去青岛看海，海风很大，笑声很多。', Color(0xFF1D4ED8)),
    _MemoryItem('老照片整理', '今天翻到年轻时的合影，准备做成电子画册。', Color(0xFF0F766E)),
    _MemoryItem('和朋友散步', '晚饭后在小区散步，聊了很久以前的故事。', Color(0xFFB45309)),
    _MemoryItem('生日团聚', '孩子们都回来了，一起吹蜡烛、唱生日歌。', Color(0xFF7C3AED)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('记忆画册')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEAF3FF),
              Color(0xFFF9FCFF),
            ],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 900 ? 2 : 1;
            final ratio = constraints.maxWidth >= 900 ? 2.15 : 2.45;

            return GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: ratio,
              ),
              itemBuilder: (context, index) {
                final item = _items[index];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        item.color.withOpacity(0.25),
                        item.color.withOpacity(0.07),
                      ],
                    ),
                    border: Border.all(color: item.color.withOpacity(0.26)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.photo_camera_back_outlined, color: item.color),
                          const SizedBox(width: 8),
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Text(
                        'Demo 内容，可替换为真实照片与回忆文本',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF5A6F86),
                            ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MemoryItem {
  const _MemoryItem(this.title, this.description, this.color);

  final String title;
  final String description;
  final Color color;
}
