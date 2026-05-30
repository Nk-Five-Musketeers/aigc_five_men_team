import 'dart:async';
import 'dart:convert';
import 'dart:io';

class NarrationSpeaker {
  Process? _activeProcess;
  Completer<void>? _activeCompleter;

  bool get isSupported => Platform.isWindows;

  // Desktop pause cancels the current speech process; resume restarts the sentence.
  bool get canResumePausedUtterance => false;

  Future<void> speak(String text, {required double rate}) async {
    if (!Platform.isWindows) {
      return Future<void>.error(
        UnsupportedError('当前设备暂不支持直接朗读，请在 Windows 或浏览器中使用听回忆模式。'),
      );
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future<void>.value();

    _completeActive();

    final completer = Completer<void>();
    _activeCompleter = completer;
    final stderrText = StringBuffer();
    final encodedText = base64Encode(utf8.encode(trimmed));
    final encodedCommand = _encodedPowerShellCommand(
      _speechScript(
        speechRate: _windowsSpeechRate(rate),
        oneCoreRate: _oneCoreSpeechRate(rate),
        encodedText: encodedText,
      ),
    );

    try {
      final process = await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-WindowStyle',
          'Hidden',
          '-ExecutionPolicy',
          'Bypass',
          '-EncodedCommand',
          encodedCommand,
        ],
        runInShell: false,
      );
      _activeProcess = process;

      unawaited(process.stdout.drain<void>());
      process.stderr.transform(utf8.decoder).listen(stderrText.write);
      await process.stdin.close();

      unawaited(process.exitCode.then((exitCode) {
        if (_activeProcess != process) return;
        _activeProcess = null;
        _activeCompleter = null;
        if (completer.isCompleted) return;
        if (exitCode == 0) {
          completer.complete();
        } else {
          final detail = stderrText.toString().trim();
          completer.completeError(
            StateError(detail.isEmpty ? '朗读这一句时遇到问题。' : detail),
          );
        }
      }));
    } catch (error) {
      _activeProcess = null;
      _activeCompleter = null;
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    return completer.future;
  }

  void pause() {
    _completeActive();
  }

  void resume() {}

  void stop() {
    _completeActive();
  }

  void dispose() {
    stop();
  }

  void _completeActive() {
    final process = _activeProcess;
    final completer = _activeCompleter;
    _activeProcess = null;
    _activeCompleter = null;
    process?.kill();
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  int _windowsSpeechRate(double rate) {
    return ((rate.clamp(0.6, 1.6) - 1.0) * 8).round().clamp(-5, 5);
  }

  String _oneCoreSpeechRate(double rate) {
    final gentleRate = (rate.clamp(0.6, 1.6) * 0.92).clamp(0.55, 1.45);
    return gentleRate.toStringAsFixed(2);
  }

  String _encodedPowerShellCommand(String script) {
    final bytes = <int>[];
    for (final codeUnit in script.codeUnits) {
      bytes
        ..add(codeUnit & 0xff)
        ..add((codeUnit >> 8) & 0xff);
    }
    return base64Encode(bytes);
  }

  String _speechScript({
    required int speechRate,
    required String oneCoreRate,
    required String encodedText,
  }) {
    return '''
\$ErrorActionPreference = 'Stop'
\$ProgressPreference = 'SilentlyContinue'
\$textBytes = [Convert]::FromBase64String('$encodedText')
\$text = [Text.Encoding]::UTF8.GetString(\$textBytes)
if (\$text.Trim().Length -le 0) { exit 0 }

function Invoke-OneCoreSpeech {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  \$null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType=WindowsRuntime]
  \$null = [Windows.Media.SpeechSynthesis.SpeechSynthesisStream, Windows.Media.SpeechSynthesis, ContentType=WindowsRuntime]
  \$synth = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::new()
  \$temp = [System.IO.Path]::GetTempFileName() + '.wav'
  try {
    \$voices = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { \$_.Language -like 'zh*' }
    \$voice = \$voices | Where-Object { \$_.DisplayName -like '*Yaoyao*' } | Select-Object -First 1
    if (\$voice -eq \$null) {
      \$voice = \$voices | Where-Object { \$_.Gender -eq [Windows.Media.SpeechSynthesis.VoiceGender]::Female } | Select-Object -First 1
    }
    if (\$voice -eq \$null) {
      \$voice = \$voices | Select-Object -First 1
    }
    if (\$voice -eq \$null) {
      throw 'No Chinese OneCore voice is installed.'
    }

    \$synth.Voice = \$voice
    \$synth.Options.SpeakingRate = [double]'$oneCoreRate'
    \$synth.Options.AudioPitch = 0.96
    \$synth.Options.AudioVolume = 1.0

    \$op = \$synth.SynthesizeTextToStreamAsync(\$text)
    \$method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
      Where-Object {
        \$_.Name -eq 'AsTask' -and
        \$_.GetParameters().Count -eq 1 -and
        \$_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*'
      } |
      Select-Object -First 1
    \$task = \$method.MakeGenericMethod([Windows.Media.SpeechSynthesis.SpeechSynthesisStream]).Invoke(\$null, @(\$op))
    \$task.Wait()

    \$stream = \$task.Result
    \$file = [System.IO.File]::OpenWrite(\$temp)
    \$netStream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead(\$stream)
    \$netStream.CopyTo(\$file)
    \$netStream.Close()
    \$file.Close()

    Add-Type -AssemblyName System
    \$player = New-Object System.Media.SoundPlayer \$temp
    \$player.Load()
    \$player.PlaySync()
    \$player.Dispose()
  } finally {
    \$synth.Dispose()
    if (Test-Path \$temp) { Remove-Item -LiteralPath \$temp -Force -ErrorAction SilentlyContinue }
  }
}

function Invoke-SapiSpeech {
  Add-Type -AssemblyName System.Speech
  \$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
  try {
    \$synth.SetOutputToDefaultAudioDevice()
    \$voice = \$synth.GetInstalledVoices() |
      Where-Object { \$_.VoiceInfo.Culture.Name -like 'zh*' -and \$_.VoiceInfo.Gender -eq [System.Speech.Synthesis.VoiceGender]::Female } |
      Select-Object -First 1
    if (\$voice -eq \$null) {
      \$voice = \$synth.GetInstalledVoices() | Where-Object { \$_.VoiceInfo.Culture.Name -like 'zh*' } | Select-Object -First 1
    }
    if (\$voice -ne \$null) { \$synth.SelectVoice(\$voice.VoiceInfo.Name) }
    \$synth.Rate = $speechRate
    \$synth.Volume = 95
    \$synth.Speak(\$text) | Out-Null
  } finally {
    \$synth.Dispose()
  }
}

try {
  Invoke-OneCoreSpeech
} catch {
  Invoke-SapiSpeech
}
''';
  }
}
