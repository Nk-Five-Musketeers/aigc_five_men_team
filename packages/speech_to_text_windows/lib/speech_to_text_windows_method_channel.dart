import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// Method channel helper (upstream parity).
class SpeechToTextWindowsMethodChannel extends SpeechToTextPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('speech_to_text_windows');

  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
