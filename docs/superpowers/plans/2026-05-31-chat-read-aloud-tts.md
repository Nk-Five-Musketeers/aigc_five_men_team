# Chat Read-Aloud TTS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add click-to-read Vivo TTS playback for “拾忆” replies, with persisted speed and volume settings and a Windows-first verification path.

**Architecture:** Flutter posts reply text and playback settings to the existing local Python proxy. The proxy connects to Vivo TTS over WebSocket, concatenates PCM frames, wraps them as WAV bytes, and returns `audio/wav`; Flutter plays the in-memory WAV through `audioplayers`. AppKey stays server-side, while `APP_ID=2026594139` is a non-secret configurable project value used for the upstream `vaid` header.

**Tech Stack:** Python standard library, `websocket-client`, Flutter, Dio, Provider, `audioplayers`, `shared_preferences`.

---

### Task 1: Vivo TTS synthesis core

**Files:**
- Create: `server/test_speech_synthesis.py`
- Create: `server/speech_synthesis.py`

- [ ] **Step 1: Write failing Python tests**

Add `unittest` cases that:

```python
def test_split_text_preserves_content_and_utf8_limit():
    text = "王阿姨，今天想聊聊年轻时候的故事。" * 180
    chunks = split_text_utf8(text, max_bytes=2048)
    assert "".join(chunks) == text
    assert all(len(chunk.encode("utf-8")) <= 2048 for chunk in chunks)

def test_pcm_to_wav_wraps_24khz_mono_int16():
    wav_bytes = pcm_to_wav(b"\x01\x02\x03\x04")
    with wave.open(io.BytesIO(wav_bytes), "rb") as reader:
        assert reader.getnchannels() == 1
        assert reader.getsampwidth() == 2
        assert reader.getframerate() == 24000

def test_client_sends_required_headers_and_collects_pcm_frames():
    # Inject a fake create_connection returning status 0 then status 2.
    # Assert Authorization, X-AI-GATEWAY-SIGNATURE and vaid headers.
    # Assert generated WAV contains both PCM frames.
```

- [ ] **Step 2: Run the Python test and verify RED**

Run:

```powershell
python -m unittest server.test_speech_synthesis -v
```

Expected: FAIL because `server.speech_synthesis` does not exist.

- [ ] **Step 3: Implement the synthesis core**

Create `server/speech_synthesis.py` with:

```python
DEFAULT_APP_ID = "2026594139"
DEFAULT_VOICE = "yunye"
DEFAULT_ENGINE_ID = "short_audio_synthesis_jovi"

def split_text_utf8(text: str, max_bytes: int = 2048) -> List[str]: ...
def pcm_to_wav(pcm_bytes: bytes) -> bytes: ...

class VivoTTSError(Exception): ...

class VivoTTSClient:
    def __init__(self, app_key=None, app_id=None, connection_factory=create_connection): ...
    def synthesize_wav(self, text: str, voice: str = DEFAULT_VOICE,
                       speed: int = 50, volume: int = 50) -> bytes: ...
```

The client must:

- Use `wss://api-ai.vivo.com.cn/tts`.
- Add the documented query parameters and second-precision `system_time`.
- Send `Authorization: Bearer <key>`, `X-AI-GATEWAY-SIGNATURE: developers-aigc`, and `vaid: <app_id>`.
- Base64-encode UTF-8 text and request PCM at `audio/L16;rate=24000`.
- Collect `data.audio` until `data.status == 2`.
- Split texts exceeding `2048` UTF-8 bytes and concatenate PCM before WAV wrapping.

- [ ] **Step 4: Run the Python test and verify GREEN**

Run:

```powershell
python -m unittest server.test_speech_synthesis -v
```

Expected: PASS.

### Task 2: Local proxy HTTP route

**Files:**
- Create: `server/test_tts_http.py`
- Create: `server/tts_http.py`
- Modify: `server/local_chat_server.py`

- [ ] **Step 1: Write failing request validation tests**

Add tests for:

```python
def test_parse_request_uses_confirmed_defaults():
    req = parse_tts_request({"text": "您好"})
    assert req.voice == "yunye"
    assert req.speed == 50
    assert req.volume == 50

def test_parse_request_rejects_empty_text(): ...
def test_parse_request_rejects_out_of_range_speed(): ...
def test_parse_request_rejects_out_of_range_volume(): ...
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
python -m unittest server.test_tts_http -v
```

Expected: FAIL because `server.tts_http` does not exist.

- [ ] **Step 3: Implement HTTP adaptation**

Create `server/tts_http.py`:

```python
@dataclass(frozen=True)
class TTSRequest:
    text: str
    voice: str = "yunye"
    speed: int = 50
    volume: int = 50

class TTSRequestError(ValueError): ...

def parse_tts_request(payload: Dict[str, Any]) -> TTSRequest: ...
def synthesize_request(payload: Dict[str, Any], *, app_key: str,
                       app_id: Optional[str] = None) -> bytes: ...
```

Modify `server/local_chat_server.py`:

- Add `POST /api/tts/synthesize`.
- Return `audio/wav` on success.
- Return JSON validation errors with HTTP 400.
- Return Vivo upstream failures with HTTP 502.
- Add `vivo_tts` and `vivo_tts_app_id` to `/health`.

- [ ] **Step 4: Run server tests**

Run:

```powershell
python -m unittest server.test_speech_synthesis server.test_tts_http -v
```

Expected: PASS.

### Task 3: Flutter voice-output state

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/core/voice_output/tts_repository.dart`
- Create: `lib/core/voice_output/voice_output_player.dart`
- Create: `lib/core/voice_output/voice_output_settings_store.dart`
- Create: `lib/logic/voice_output_provider.dart`
- Create: `test/voice_output_provider_test.dart`

- [ ] **Step 1: Add Flutter dependencies**

Add:

```yaml
audioplayers: ^6.4.0
shared_preferences: ^2.3.2
```

These ranges remain compatible with the declared Dart SDK while allowing the local toolchain to resolve newer compatible versions.

- [ ] **Step 2: Write failing provider tests**

Use fake repository, player, and settings store objects. Cover:

```dart
test('uses yunye and persisted speed volume when reading a reply', () async {});
test('tapping the playing reply stops playback', () async {});
test('switching reply stops previous playback first', () async {});
test('reuses cached wav bytes for the same text and settings', () async {});
test('loads and persists speed and volume settings', () async {});
```

- [ ] **Step 3: Run the provider test and verify RED**

Run:

```powershell
flutter test test\voice_output_provider_test.dart
```

Expected: FAIL because the voice-output module does not exist.

- [ ] **Step 4: Implement Flutter output modules**

Implement:

```dart
class TtsRepository {
  Future<Uint8List> synthesize({
    required String text,
    String voice = 'yunye',
    int speed = 50,
    int volume = 50,
  });
}

abstract class VoiceOutputPlayer {
  Stream<void> get onComplete;
  Future<void> play(Uint8List wavBytes);
  Future<void> stop();
  Future<void> dispose();
}

abstract class VoiceOutputSettingsStore {
  Future<int?> loadSpeed();
  Future<int?> loadVolume();
  Future<void> saveSpeed(int value);
  Future<void> saveVolume(int value);
}
```

`VoiceOutputProvider` must maintain:

- Default voice `yunye`.
- Persisted speed and volume, defaulting to `50`.
- One loading or playing message at a time.
- Tap-again stop behavior.
- Memory cache keyed by text, voice, speed and volume.
- Race protection so a stale synthesis result cannot start playback after another message is selected.

- [ ] **Step 5: Run the provider test and verify GREEN**

Run:

```powershell
flutter test test\voice_output_provider_test.dart
```

Expected: PASS.

### Task 4: Flutter UI integration

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/ui/screens/home_screen.dart`
- Create: `test/read_aloud_ui_test.dart`

- [ ] **Step 1: Write failing widget tests**

Cover:

```dart
testWidgets('assistant reply shows a read aloud action', (tester) async {});
testWidgets('user reply does not show a read aloud action', (tester) async {});
testWidgets('settings expose read aloud speed and volume sliders', (tester) async {});
```

- [ ] **Step 2: Run widget tests and verify RED**

Run:

```powershell
flutter test test\read_aloud_ui_test.dart
```

Expected: FAIL because the UI does not expose read-aloud controls.

- [ ] **Step 3: Register provider and add UI**

Modify `lib/main.dart` to use `MultiProvider` and create `VoiceOutputProvider()..loadSettings()`.

Modify `home_screen.dart`:

- Add a compact icon-and-text read-aloud action below non-user, non-error reply content.
- Use `volume_up_rounded`, `stop_circle_outlined`, and a progress indicator for idle, playing, and loading states.
- Catch playback exceptions and show a Snackbar without affecting chat.
- Add `朗读语速` and `朗读音量` sliders under the existing “语音” settings section.

- [ ] **Step 4: Run widget tests and verify GREEN**

Run:

```powershell
flutter test test\read_aloud_ui_test.dart
```

Expected: PASS.

### Task 5: Documentation and verification

**Files:**
- Modify: `README.md`
- Modify: `task_plan.md`
- Modify: `findings.md`
- Modify: `progress.md`

- [ ] **Step 1: Document runtime configuration**

Document:

```powershell
$env:VIVO_APP_KEY=""
python server\local_chat_server.py
```

Also document optional override:

```powershell
$env:VIVO_APP_ID="2026594139"
```

- [ ] **Step 2: Run Python tests**

```powershell
python -m unittest server.test_speech_synthesis server.test_tts_http -v
```

- [ ] **Step 3: Resolve Flutter dependencies and run focused tests**

```powershell
flutter pub get
flutter test test\voice_output_provider_test.dart test\read_aloud_ui_test.dart
```

- [ ] **Step 4: Run Flutter analysis and existing tests**

```powershell
flutter analyze
flutter test
```

- [ ] **Step 5: Build Windows debug app**

```powershell
flutter build windows --debug
```

- [ ] **Step 6: Perform live proxy checks when a real key is available**

Start:

```powershell
$env:VIVO_APP_KEY=""
python server\local_chat_server.py
```

Then check `/health` and send a short `/api/tts/synthesize` request. If the key is intentionally empty, report that upstream playback could not be exercised.

