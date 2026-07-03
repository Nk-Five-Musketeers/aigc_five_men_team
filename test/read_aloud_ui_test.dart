import 'dart:typed_data';

import 'package:aigc_five_men_team/core/voice_output/tts_repository.dart';
import 'package:aigc_five_men_team/core/voice_output/voice_output_player.dart';
import 'package:aigc_five_men_team/core/voice_output/voice_output_settings_store.dart';
import 'package:aigc_five_men_team/data/models/chat_message.dart';
import 'package:aigc_five_men_team/logic/voice_output_provider.dart';
import 'package:aigc_five_men_team/ui/widgets/chat_read_aloud_action.dart';
import 'package:aigc_five_men_team/ui/widgets/read_aloud_settings_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeSynthesizer implements TtsSynthesizer {
  @override
  Future<Uint8List> synthesize({
    required String text,
    String voice = 'wanqing',
    int speed = 50,
    int volume = 50,
  }) async {
    return Uint8List.fromList([1, 2, 3, 4]);
  }
}

class _FakePlayer implements VoiceOutputPlayer {
  @override
  Stream<void> get onComplete => const Stream<void>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> play(Uint8List wavBytes) async {}

  @override
  Future<void> stop() async {}
}

class _FakeSettingsStore implements VoiceOutputSettingsStore {
  @override
  Future<int?> loadSpeed() async => null;

  @override
  Future<int?> loadVolume() async => null;

  @override
  Future<void> saveSpeed(int value) async {}

  @override
  Future<void> saveVolume(int value) async {}
}

VoiceOutputProvider _provider() {
  return VoiceOutputProvider(
    synthesizer: _FakeSynthesizer(),
    player: _FakePlayer(),
    settingsStore: _FakeSettingsStore(),
  );
}

Widget _wrap(VoiceOutputProvider provider, Widget child) {
  return ChangeNotifierProvider<VoiceOutputProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

ChatMessage _message({required bool isUser, ChatMessageKind? kind}) {
  return ChatMessage(
    id: isUser ? 'user-1' : 'assistant-1',
    content: '今天想聊聊什么呢？',
    isUser: isUser,
    timestamp: DateTime(2026, 5, 31),
    kind: kind ?? ChatMessageKind.text,
  );
}

void main() {
  testWidgets('assistant reply shows a read aloud action', (tester) async {
    final provider = _provider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _wrap(provider, ChatReadAloudAction(message: _message(isUser: false))),
    );

    expect(find.text('朗读'), findsOneWidget);
    expect(find.byTooltip('朗读这条回复'), findsOneWidget);
    await tester.tap(find.byTooltip('朗读这条回复'));
    await tester.pump();
    expect(provider.playingMessageId, 'assistant-1');
  });

  testWidgets('user reply does not show a read aloud action', (tester) async {
    final provider = _provider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _wrap(provider, ChatReadAloudAction(message: _message(isUser: true))),
    );

    expect(find.text('朗读'), findsNothing);
  });

  testWidgets('error reply does not show a read aloud action', (tester) async {
    final provider = _provider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _wrap(
        provider,
        ChatReadAloudAction(
          message: _message(isUser: false, kind: ChatMessageKind.error),
        ),
      ),
    );

    expect(find.text('朗读'), findsNothing);
  });

  testWidgets('settings expose read aloud speed and volume sliders',
      (tester) async {
    final provider = _provider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _wrap(provider, const ReadAloudSettingsControls()),
    );

    expect(find.text('朗读语速'), findsOneWidget);
    expect(find.text('朗读音量'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
  });
}
