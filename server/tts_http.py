"""HTTP-facing validation for the local Vivo TTS proxy route."""

from dataclasses import dataclass
from typing import Any, Callable, Dict, Optional

try:
    from .speech_synthesis import DEFAULT_VOICE, VivoTTSClient
except ImportError:
    from speech_synthesis import DEFAULT_VOICE, VivoTTSClient


SUPPORTED_SHORT_VOICES = frozenset(
    {
        "vivoHelper",
        "yunye",
        "wanqing",
        "xiaofu",
        "yige_child",
        "yige",
        "yiyi",
        "xiaoming",
    }
)


class TTSRequestError(ValueError):
    """Raised when the local HTTP caller supplies an invalid TTS request."""


@dataclass(frozen=True)
class TTSRequest:
    text: str
    voice: str = DEFAULT_VOICE
    speed: int = 50
    volume: int = 50


def _read_bounded_int(
    payload: Dict[str, Any],
    key: str,
    *,
    default: int,
    minimum: int,
    maximum: int,
) -> int:
    value = payload.get(key, default)
    if isinstance(value, bool) or not isinstance(value, int):
        raise TTSRequestError(f"{key} must be an integer")
    if value < minimum or value > maximum:
        raise TTSRequestError(f"{key} must be between {minimum} and {maximum}")
    return value


def parse_tts_request(payload: Dict[str, Any]) -> TTSRequest:
    if not isinstance(payload, dict):
        raise TTSRequestError("Body must be a JSON object")

    text = payload.get("text")
    if not isinstance(text, str) or not text.strip():
        raise TTSRequestError("text must be a non-empty string")

    voice = payload.get("voice", DEFAULT_VOICE)
    if not isinstance(voice, str) or voice not in SUPPORTED_SHORT_VOICES:
        raise TTSRequestError("voice is not supported by short_audio_synthesis_jovi")

    return TTSRequest(
        text=text.strip(),
        voice=voice,
        speed=_read_bounded_int(
            payload,
            "speed",
            default=50,
            minimum=0,
            maximum=100,
        ),
        volume=_read_bounded_int(
            payload,
            "volume",
            default=50,
            minimum=1,
            maximum=100,
        ),
    )


def synthesize_request(
    payload: Dict[str, Any],
    *,
    app_key: str,
    app_id: Optional[str] = None,
    client_factory: Callable = VivoTTSClient,
) -> bytes:
    request = parse_tts_request(payload)
    client = client_factory(app_key=app_key, app_id=app_id)
    return client.synthesize_wav(
        request.text,
        voice=request.voice,
        speed=request.speed,
        volume=request.volume,
    )
