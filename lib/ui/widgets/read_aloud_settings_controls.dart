import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../logic/voice_output_provider.dart';

class ReadAloudSettingsControls extends StatelessWidget {
  const ReadAloudSettingsControls({super.key});

  @override
  Widget build(BuildContext context) {
    final output = context.watch<VoiceOutputProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '回复朗读',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '点击拾忆回复下方的朗读按钮后生效',
            style: TextStyle(
              fontSize: 19,
              height: 1.4,
              fontWeight: FontWeight.w400,
              color: AppTheme.textSoft,
            ),
          ),
          const SizedBox(height: 10),
          _ReadAloudSlider(
            label: '朗读语速',
            value: output.speed,
            minimum: 0,
            onChanged: (value) => unawaited(output.setSpeed(value)),
          ),
          _ReadAloudSlider(
            label: '朗读音量',
            value: output.volume,
            minimum: 1,
            onChanged: (value) => unawaited(output.setVolume(value)),
          ),
        ],
      ),
    );
  }
}

class _ReadAloudSlider extends StatelessWidget {
  const _ReadAloudSlider({
    required this.label,
    required this.value,
    required this.minimum,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int minimum;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text,
                  ),
                ),
              ),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryDeep,
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: minimum.toDouble(),
            max: 100,
            divisions: minimum == 0 ? 20 : 99,
            label: '$value',
            onChanged: (next) => onChanged(next.round()),
          ),
        ],
      ),
    );
  }
}
