"""HTTP 层：解析上传音频并调用 vivo ASR。"""
from __future__ import annotations

import os
import tempfile
import wave
from typing import Tuple
from urllib.parse import parse_qs

from speech_recognition import get_client


def _audio_duration_seconds_wav(path: str) -> float:
    try:
        with wave.open(path, "rb") as wf:
            frames = wf.getnframes()
            rate = wf.getframerate() or 16000
            return frames / float(rate)
    except Exception:
        return 0.0


def _resolve_mode(query: str, wav_path: str) -> str:
    params = parse_qs(query or "")
    mode = (params.get("mode") or ["auto"])[0].lower()
    if mode in ("short", "long"):
        return mode
    duration = _audio_duration_seconds_wav(wav_path)
    return "short" if 0 < duration <= 60 else "long"


def transcribe_wav_file(wav_path: str, mode: str = "auto") -> Tuple[str, str]:
    """返回 (text, mode_used)。"""
    resolved = _resolve_mode(f"mode={mode}", wav_path) if mode == "auto" else mode
    client = get_client()
    if resolved == "short":
        result = client.recognize_short(wav_path)
    else:
        result = client.recognize_long(wav_path)
    return (result.text or "").strip(), resolved


def transcribe_upload(
    audio_bytes: bytes,
    mode: str = "auto",
) -> Tuple[str, str]:
    fd, path = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    try:
        with open(path, "wb") as f:
            f.write(audio_bytes)
        return transcribe_wav_file(path, mode=mode)
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
