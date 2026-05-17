import '../services/voice_input_service.dart';

class AsrUtils {
  AsrUtils._();

  /// 单次语音识别（与主界面语音条共用实现；桌面 / Web / 移动端由系统插件决定）。
  static Future<String> speechToText({String speechMode = '自动识别'}) {
    return VoiceInputService.listenOnce(speechMode: speechMode);
  }
}
