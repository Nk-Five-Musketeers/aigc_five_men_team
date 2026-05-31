import 'package:shared_preferences/shared_preferences.dart';

abstract class VoiceOutputSettingsStore {
  Future<int?> loadSpeed();

  Future<int?> loadVolume();

  Future<void> saveSpeed(int value);

  Future<void> saveVolume(int value);
}

class SharedPreferencesVoiceOutputSettingsStore
    implements VoiceOutputSettingsStore {
  static const String _speedKey = 'tts_read_aloud_speed';
  static const String _volumeKey = 'tts_read_aloud_volume';

  @override
  Future<int?> loadSpeed() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(_speedKey);
  }

  @override
  Future<int?> loadVolume() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(_volumeKey);
  }

  @override
  Future<void> saveSpeed(int value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_speedKey, value);
  }

  @override
  Future<void> saveVolume(int value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_volumeKey, value);
  }
}
