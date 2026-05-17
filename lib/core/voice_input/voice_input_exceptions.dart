class VoiceInputUnavailableException implements Exception {
  VoiceInputUnavailableException(this.message);
  final String message;

  @override
  String toString() => message;
}

class VoiceInputListenException implements Exception {
  VoiceInputListenException(this.message);
  final String message;

  @override
  String toString() => message;
}
