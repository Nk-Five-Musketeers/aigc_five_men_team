import unittest

from server.tts_http import TTSRequestError, parse_tts_request, synthesize_request


class _FakeTTSClient:
    instances = []

    def __init__(self, app_key=None, app_id=None):
        self.app_key = app_key
        self.app_id = app_id
        self.calls = []
        self.__class__.instances.append(self)

    def synthesize_wav(self, text, voice, speed, volume):
        self.calls.append(
            {
                "text": text,
                "voice": voice,
                "speed": speed,
                "volume": volume,
            }
        )
        return b"RIFF-fake-wav"


class TTSHttpTest(unittest.TestCase):
    def setUp(self):
        _FakeTTSClient.instances.clear()

    def test_parse_request_uses_confirmed_defaults(self):
        req = parse_tts_request({"text": " 您好 "})

        self.assertEqual(req.text, "您好")
        self.assertEqual(req.voice, "yunye")
        self.assertEqual(req.speed, 50)
        self.assertEqual(req.volume, 50)

    def test_parse_request_rejects_empty_text(self):
        with self.assertRaisesRegex(TTSRequestError, "text"):
            parse_tts_request({"text": "  "})

    def test_parse_request_rejects_out_of_range_speed(self):
        with self.assertRaisesRegex(TTSRequestError, "speed"):
            parse_tts_request({"text": "您好", "speed": 101})

    def test_parse_request_rejects_out_of_range_volume(self):
        with self.assertRaisesRegex(TTSRequestError, "volume"):
            parse_tts_request({"text": "您好", "volume": 0})

    def test_synthesize_request_forwards_server_credentials_and_settings(self):
        wav = synthesize_request(
            {"text": "您好", "speed": 42, "volume": 63},
            app_key="server-key",
            app_id="2026594139",
            client_factory=_FakeTTSClient,
        )

        self.assertEqual(wav, b"RIFF-fake-wav")
        client = _FakeTTSClient.instances[0]
        self.assertEqual(client.app_key, "server-key")
        self.assertEqual(client.app_id, "2026594139")
        self.assertEqual(
            client.calls,
            [
                {
                    "text": "您好",
                    "voice": "yunye",
                    "speed": 42,
                    "volume": 63,
                }
            ],
        )


if __name__ == "__main__":
    unittest.main()
