import base64
import io
import json
import unittest
import wave
from urllib.parse import parse_qs, urlparse

from server.speech_synthesis import VivoTTSClient, pcm_to_wav, split_text_utf8


class _FakeWebSocket:
    def __init__(self, responses):
        self._responses = list(responses)
        self.sent = []
        self.closed = False

    def send(self, payload):
        self.sent.append(payload)

    def recv(self):
        return self._responses.pop(0)

    def close(self):
        self.closed = True


class SpeechSynthesisTest(unittest.TestCase):
    def test_split_text_preserves_content_and_utf8_limit(self):
        text = "王阿姨，今天想聊聊年轻时候的故事。" * 180

        chunks = split_text_utf8(text, max_bytes=2048)

        self.assertEqual("".join(chunks), text)
        self.assertGreater(len(chunks), 1)
        self.assertTrue(
            all(len(chunk.encode("utf-8")) <= 2048 for chunk in chunks)
        )

    def test_pcm_to_wav_wraps_24khz_mono_int16(self):
        pcm = b"\x01\x02\x03\x04"

        wav_bytes = pcm_to_wav(pcm)

        with wave.open(io.BytesIO(wav_bytes), "rb") as reader:
            self.assertEqual(reader.getnchannels(), 1)
            self.assertEqual(reader.getsampwidth(), 2)
            self.assertEqual(reader.getframerate(), 24000)
            self.assertEqual(reader.readframes(reader.getnframes()), pcm)

    def test_client_sends_required_headers_and_collects_pcm_frames(self):
        pcm_frames = [b"\x01\x02", b"\x03\x04"]
        ws = _FakeWebSocket(
            [
                json.dumps(
                    {
                        "error_code": 0,
                        "data": {
                            "audio": base64.b64encode(pcm_frames[0]).decode(),
                            "status": 0,
                        },
                    }
                ),
                json.dumps(
                    {
                        "error_code": 0,
                        "data": {
                            "audio": base64.b64encode(pcm_frames[1]).decode(),
                            "status": 2,
                        },
                    }
                ),
            ]
        )
        captured = {}

        def fake_connection(url, header, timeout):
            captured["url"] = url
            captured["header"] = header
            captured["timeout"] = timeout
            return ws

        client = VivoTTSClient(
            app_key="server-key",
            app_id="2026594139",
            connection_factory=fake_connection,
        )

        wav_bytes = client.synthesize_wav("您好", voice="yunye", speed=45, volume=60)

        with wave.open(io.BytesIO(wav_bytes), "rb") as reader:
            self.assertEqual(
                reader.readframes(reader.getnframes()),
                b"".join(pcm_frames),
            )

        headers = captured["header"]
        self.assertEqual(headers["Authorization"], "Bearer server-key")
        self.assertEqual(headers["X-AI-GATEWAY-SIGNATURE"], "developers-aigc")
        self.assertEqual(headers["vaid"], "2026594139")
        self.assertEqual(captured["timeout"], 30)

        query = parse_qs(urlparse(captured["url"]).query)
        self.assertEqual(query["engineid"], ["short_audio_synthesis_jovi"])
        self.assertIn("requestId", query)
        self.assertIn("system_time", query)

        payload = json.loads(ws.sent[0])
        self.assertEqual(payload["aue"], 0)
        self.assertEqual(payload["auf"], "audio/L16;rate=24000")
        self.assertEqual(payload["vcn"], "yunye")
        self.assertEqual(payload["speed"], 45)
        self.assertEqual(payload["volume"], 60)
        self.assertEqual(base64.b64decode(payload["text"]).decode("utf-8"), "您好")
        self.assertTrue(ws.closed)


if __name__ == "__main__":
    unittest.main()
