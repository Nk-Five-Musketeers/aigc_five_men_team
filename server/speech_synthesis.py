"""Vivo TTS WebSocket client used by the local chat proxy."""

import base64
import io
import json
import os
import time
import uuid
import wave
from typing import Callable, Dict, List, Optional
from urllib.parse import urlencode

TTS_URL = "wss://api-ai.vivo.com.cn/tts"
DEFAULT_APP_ID = "2026594139"
DEFAULT_ENGINE_ID = "short_audio_synthesis_jovi"
DEFAULT_USER_ID = "2addc42b7ae689dfdf1c63e220df52a2"
DEFAULT_VOICE = "wanqing"
MAX_TEXT_BYTES = 2048
_SENTENCE_BOUNDARIES = frozenset("。！？；…．.!?\n，,、：:")


def _create_connection(*args, **kwargs):
    try:
        from websocket import create_connection
    except ImportError as exc:
        raise RuntimeError(
            "websocket-client is required for Vivo TTS. "
            "Run: pip install -r server/requirements-asr.txt"
        ) from exc
    return create_connection(*args, **kwargs)


class VivoTTSError(Exception):
    """Raised when Vivo TTS rejects a request or returns malformed audio."""

    def __init__(self, code: int, desc: str) -> None:
        self.code = code
        self.desc = desc
        super().__init__(f"TTS Error {code}: {desc}")


def split_text_utf8(text: str, max_bytes: int = MAX_TEXT_BYTES) -> List[str]:
    """Split text without breaking Unicode characters, preferring punctuation."""
    if max_bytes <= 0:
        raise ValueError("max_bytes must be positive")
    if not text:
        return []

    chunks: List[str] = []
    remaining = text
    while remaining:
        encoded = remaining.encode("utf-8")
        if len(encoded) <= max_bytes:
            chunks.append(remaining)
            break

        byte_count = 0
        safe_count = 0
        boundary_count = 0
        for index, char in enumerate(remaining):
            char_size = len(char.encode("utf-8"))
            if byte_count + char_size > max_bytes:
                break
            byte_count += char_size
            safe_count = index + 1
            if char in _SENTENCE_BOUNDARIES:
                boundary_count = safe_count

        if safe_count == 0:
            raise ValueError("max_bytes is too small for one UTF-8 character")

        cut = boundary_count or safe_count
        chunks.append(remaining[:cut])
        remaining = remaining[cut:]
    return chunks


def pcm_to_wav(pcm_bytes: bytes) -> bytes:
    """Wrap mono 16-bit 24 kHz PCM bytes in a WAV container."""
    output = io.BytesIO()
    with wave.open(output, "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(24000)
        writer.writeframes(pcm_bytes)
    return output.getvalue()


class VivoTTSClient:
    """Small synchronous adapter around Vivo's streaming TTS WebSocket."""

    def __init__(
        self,
        app_key: Optional[str] = None,
        app_id: Optional[str] = None,
        engine_id: str = DEFAULT_ENGINE_ID,
        connection_factory: Callable = _create_connection,
    ) -> None:
        self.app_key = app_key or os.getenv("VIVO_APP_KEY") or os.getenv("APP_KEY")
        if not self.app_key:
            raise ValueError(
                "AppKey is required. Set VIVO_APP_KEY or APP_KEY environment variable."
            )
        self.app_id = (
            app_id
            or os.getenv("VIVO_APP_ID")
            or os.getenv("APP_ID")
            or DEFAULT_APP_ID
        )
        self.engine_id = engine_id
        self._connection_factory = connection_factory

    def synthesize_wav(
        self,
        text: str,
        voice: str = DEFAULT_VOICE,
        speed: int = 50,
        volume: int = 50,
    ) -> bytes:
        pcm_parts = [
            self._synthesize_pcm_chunk(chunk, voice=voice, speed=speed, volume=volume)
            for chunk in split_text_utf8(text)
        ]
        pcm_bytes = b"".join(pcm_parts)
        if not pcm_bytes:
            raise VivoTTSError(11010, "TTS returned empty audio")
        return pcm_to_wav(pcm_bytes)

    def _build_url(self) -> str:
        params = {
            "engineid": self.engine_id,
            "system_time": str(int(time.time())),
            "user_id": DEFAULT_USER_ID,
            "model": "V1809A",
            "product": "PD1809",
            "package": "com.vivo.agent",
            "client_version": "47405",
            "system_version": "PD1809_A_7.6.22",
            "sdk_version": "1.1.2.1",
            "android_version": "9",
            "requestId": str(uuid.uuid4()),
        }
        return f"{TTS_URL}?{urlencode(params)}"

    def _headers(self) -> Dict[str, str]:
        return {
            "Authorization": f"Bearer {self.app_key}",
            "X-AI-GATEWAY-SIGNATURE": "developers-aigc",
            "vaid": self.app_id,
        }

    def _synthesize_pcm_chunk(
        self,
        text: str,
        *,
        voice: str,
        speed: int,
        volume: int,
    ) -> bytes:
        ws = self._connection_factory(
            self._build_url(),
            header=self._headers(),
            timeout=30,
        )
        pcm_parts: List[bytes] = []
        try:
            payload = {
                "aue": 0,
                "auf": "audio/L16;rate=24000",
                "vcn": voice,
                "speed": speed,
                "volume": volume,
                "text": base64.b64encode(text.encode("utf-8")).decode("ascii"),
                "encoding": "utf8",
                "reqId": int(time.time() * 1_000_000),
            }
            ws.send(json.dumps(payload, ensure_ascii=False))

            while True:
                message = json.loads(ws.recv())
                error_code = int(message.get("error_code", 0))
                if error_code != 0:
                    raise VivoTTSError(
                        error_code,
                        str(message.get("error_msg") or "Unknown Vivo TTS error"),
                    )

                data = message.get("data") or {}
                audio = data.get("audio")
                if audio:
                    pcm_parts.append(base64.b64decode(audio))
                if int(data.get("status", -1)) == 2:
                    break
        finally:
            ws.close()

        return b"".join(pcm_parts)
