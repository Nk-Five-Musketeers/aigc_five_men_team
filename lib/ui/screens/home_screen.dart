import 'package:flutter/material.dart';

import '../widgets/big_button.dart';
import 'chat_screen.dart';
import 'gallery_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final features = _buildFeatures(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8F2FF),
              Color(0xFFF9FCFF),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final crossAxisCount = wide ? 2 : 1;
              final horizontal = wide ? 40.0 : 16.0;
              final ratio = wide ? 2.0 : 2.6;

              return TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 450),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 14),
                      child: child,
                    ),
                  );
                },
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _HeaderCard(),
                      const SizedBox(height: 16),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: features.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: ratio,
                        ),
                        itemBuilder: (context, index) {
                          final item = features[index];
                          return BigButton(
                            title: item.title,
                            subtitle: item.subtitle,
                            icon: item.icon,
                            accentColor: item.accentColor,
                            onTap: item.onTap,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<_FeatureEntry> _buildFeatures(BuildContext context) {
    return <_FeatureEntry>[
      _FeatureEntry(
        title: '暖心对话',
        subtitle: '和 BlueCare 轻松聊聊天',
        icon: Icons.chat_bubble_outline_rounded,
        accentColor: const Color(0xFF0F766E),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChatScreen()),
          );
        },
      ),
      _FeatureEntry(
        title: '记忆画册',
        subtitle: '用照片和文字留住回忆',
        icon: Icons.photo_library_outlined,
        accentColor: const Color(0xFF1D4ED8),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const GalleryScreen()),
          );
        },
      ),
      _FeatureEntry(
        title: '用药提醒',
        subtitle: '每日提醒按时吃药',
        icon: Icons.medication_liquid_outlined,
        accentColor: const Color(0xFFB45309),
        onTap: () => _showComingSoon(context),
      ),
      _FeatureEntry(
        title: '安全守护',
        subtitle: '异常动态提醒家人',
        icon: Icons.health_and_safety_outlined,
        accentColor: const Color(0xFF7C3AED),
        onTap: () => _showComingSoon(context),
      ),
    ];
  }

  static void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('此模块正在开发中，敬请期待。')),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BlueCare',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 10),
          const Text(
            '阿尔茨海默关怀助手 Demo\n更大的按钮、更清晰的信息、更简洁的交互。',
            style: TextStyle(
              color: Color(0xFFD7E5FF),
              fontSize: 16,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureEntry {
  const _FeatureEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
}
