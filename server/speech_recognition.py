"""
蓝星语音识别模块 (Vivo ASR)
基于 WebSocket 协议的实时语音识别，支持短语音识别和长语音听写。
"""
import os
import uuid
import json
import time
import struct
import threading
import wave
from dataclasses import dataclass
from typing import Callable, List, Optional, Union
from urllib import parse

from websocket import create_connection


DOMAIN = "api-ai.vivo.com.cn"
URI = "/asr/v2"

SAMPLE_FRAMES = 1280          # 每帧40ms (16kHz, 16bit)
SLEEP_PER_FRAME = 0.04        # 每帧间隔
DEFAULT_USER_ID = "2addc42b7ae689dfdf1c63e220df52a2"


@dataclass
class ShortResult:
    """短语音识别结果"""
    text: str
    request_id: str
    sid: str


@dataclass
class LongResult:
    """长语音听写结果"""
    text: str
    sentences: List[str]
    request_id: str
    sid: str


class VivoASRError(Exception):
    """语音识别错误"""

    def __init__(self, code: int, desc: str) -> None:
        self.code = code
        self.desc = desc
        super().__init__(f"ASR Error {code}: {desc}")


class VivoASRClient:
    """蓝星语音识别客户端"""

    def __init__(self, app_key: Optional[str] = None) -> None:
        self.app_key = app_key or os.getenv("VIVO_APP_KEY")
        if not self.app_key:
            raise ValueError(
                "AppKey is required. Set VIVO_APP_KEY environment variable "
                "or pass app_key parameter."
            )

    def recognize_short(
        self,
        audio: Union[str, bytes],
        on_partial: Optional[Callable[[str, bool], None]] = None,
        user_id: Optional[str] = None,
    ) -> ShortResult:
        """短语音识别（单轮 ≤60s）

        Args:
            audio: WAV 文件路径或 PCM int16 字节数据
            on_partial: 中间结果回调 (text, is_last)
            user_id: 用户标识

        Returns:
            ShortResult(text=完整文本, request_id=请求ID, sid=会话ID)
        """
        wav_data = self._load_audio(audio)
        return self._run_short(wav_data, user_id, on_partial)

    def recognize_long(
        self,
        audio: Union[str, bytes],
        on_partial: Optional[Callable[[str], None]] = None,
        on_sentence: Optional[Callable[[str, bool], None]] = None,
        user_id: Optional[str] = None,
    ) -> LongResult:
        """长语音听写（不限时长）

        Args:
            audio: WAV 文件路径或 PCM int16 字节数据
            on_partial: 中间可变结果回调 (var_text)
            on_sentence: 完整句子回调 (onebest, is_last)
            user_id: 用户标识

        Returns:
            LongResult(text=完整文本, sentences=句子列表, request_id, sid)
        """
        wav_data = self._load_audio(audio)
        return self._run_long(wav_data, user_id, on_partial, on_sentence)

    # ------------------------------------------------------------------
    # 内部实现
    # ------------------------------------------------------------------

    def _load_audio(self, audio: Union[str, bytes]) -> List[int]:
        """加载音频数据，返回 int16 采样列表"""
        if isinstance(audio, str):
            return self._read_wav(audio)
        if isinstance(audio, bytes):
            return list(struct.unpack(f"{len(audio) // 2}h", audio))
        raise TypeError("audio must be a file path (str) or PCM bytes")

    @staticmethod
    def _read_wav(path: str) -> List[int]:
        """读取 WAV 文件，返回 int16 采样列表"""
        try:
            import soundfile
            wav_data, _sr = soundfile.read(path, dtype="int16")
            return list(wav_data)
        except ImportError:
            pass

        with wave.open(path, "rb") as wf:
            nframes = wf.getnframes()
            raw = wf.readframes(nframes)
            return list(struct.unpack(f"{nframes}h", raw))

    def _build_url(self, engine_id: str, user_id: Optional[str]) -> str:
        """构建 WebSocket 握手 URL"""
        params = {
            "client_version": parse.quote("unknown"),
            "package": parse.quote("unknown"),
            "sdk_version": parse.quote("unknown"),
            "user_id": parse.quote(user_id or DEFAULT_USER_ID),
            "android_version": parse.quote("unknown"),
            "system_time": parse.quote(str(int(round(time.time() * 1000)))),
            "net_type": "1",
            "engineid": engine_id,
            "requestId": parse.quote(str(uuid.uuid4())),
        }
        param_str = "&".join(f"{k}={v}" for k, v in params.items())
        return f"ws://{DOMAIN}{URI}?{param_str}"

    def _send_audio(self, ws, wav_data: List[int]) -> None:
        """发送音频数据（在独立线程中运行）"""
        try:
            nlen = len(wav_data)
            pack = struct.pack(f"{nlen}h", *wav_data)
            byte_data = list(pack)

            cur = 0
            nbytes = nlen * 2

            while cur < nbytes:
                remaining = nbytes - cur
                chunk_sz = min(SAMPLE_FRAMES, remaining)
                chunk = bytes(byte_data[cur : cur + chunk_sz])
                cur += chunk_sz

                if len(chunk) < SAMPLE_FRAMES:
                    break

                ws.send_binary(chunk)
                time.sleep(SLEEP_PER_FRAME)

            ws.send_binary(b"--end--")
        except Exception:
            pass

    # -- 短语音识别 -----------------------------------------------------

    def _run_short(
        self,
        wav_data: List[int],
        user_id: Optional[str],
        on_partial: Optional[Callable],
    ) -> ShortResult:
        ws = create_connection(
            self._build_url("shortasrinput", user_id),
            header={"Authorization": f"Bearer {self.app_key}"},
        )

        request_id = str(uuid.uuid1()).replace("-", "")
        start = {
            "type": "started",
            "request_id": request_id,
            "asr_info": {
                "front_vad_time": 6000,
                "end_vad_time": 2000,
                "audio_type": "pcm",
                "chinese2digital": 1,
                "punctuation": 1,
            },
            "business_info": "",
        }
        ws.send(json.dumps(start))

        # 等待握手确认
        resp = json.loads(ws.recv())
        if resp.get("action") == "error":
            ws.close()
            raise VivoASRError(resp["code"], resp["desc"])

        t_send = threading.Thread(target=self._send_audio, args=(ws, wav_data))
        t_send.start()

        full_text = ""
        sid = ""
        try:
            while True:
                msg = json.loads(ws.recv())
                if msg.get("action") == "error":
                    raise VivoASRError(msg["code"], msg["desc"])

                if msg.get("action") == "result" and msg.get("type") == "asr":
                    data = msg.get("data", {})
                    text = data.get("text", "")
                    is_last = data.get("is_last", False)
                    sid = msg.get("sid", "")

                    if text and on_partial:
                        on_partial(text, is_last)

                    if is_last:
                        full_text = text
                        break
        finally:
            t_send.join()
            try:
                ws.send_binary(b"--close--")
            except Exception:
                pass
            ws.close()

        return ShortResult(text=full_text, request_id=request_id, sid=sid)

    # -- 长语音听写 -----------------------------------------------------

    def _run_long(
        self,
        wav_data: List[int],
        user_id: Optional[str],
        on_partial: Optional[Callable],
        on_sentence: Optional[Callable],
    ) -> LongResult:
        ws = create_connection(
            self._build_url("longasrlisten", user_id),
            header={"Authorization": f"Bearer {self.app_key}"},
        )

        request_id = str(uuid.uuid1()).replace("-", "")
        start = {
            "type": "started",
            "request_id": request_id,
            "asr_info": {
                "audio_type": "pcm",
                "punctuation": 1,
            },
            "business_info": "",
        }
        ws.send(json.dumps(start))

        resp = json.loads(ws.recv())
        if resp.get("action") == "error":
            ws.close()
            raise VivoASRError(resp["code"], resp["desc"])

        t_send = threading.Thread(target=self._send_audio, args=(ws, wav_data))
        t_send.start()

        sentences: List[str] = []
        sid = ""
        try:
            while True:
                msg = json.loads(ws.recv())
                if msg.get("action") == "error":
                    raise VivoASRError(msg["code"], msg["desc"])

                if msg.get("action") != "result" or msg.get("type") != "asr":
                    continue

                code = msg.get("code")
                data = msg.get("data", {})
                sid = msg.get("sid", "")

                if code == 8:
                    var_text = data.get("var", "")
                    if var_text and on_partial:
                        on_partial(var_text)

                elif code in (0, 9):
                    onebest = data.get("onebest", "")
                    if onebest and on_sentence:
                        on_sentence(onebest, code == 9)
                    if onebest:
                        sentences.append(onebest)
                    if code == 9:
                        break
        finally:
            t_send.join()
            try:
                ws.send_binary(b"--close--")
            except Exception:
                pass
            ws.close()

        return LongResult(
            text="".join(sentences),
            sentences=sentences,
            request_id=request_id,
            sid=sid,
        )


# ------------------------------------------------------------------
# 全局单例
# ------------------------------------------------------------------

_client: Optional[VivoASRClient] = None
_lock = threading.Lock()


def get_client(app_key: Optional[str] = None) -> VivoASRClient:
    """获取全局 ASR 客户端单例"""
    global _client
    if _client is None:
        with _lock:
            if _client is None:
                _client = VivoASRClient(app_key=app_key)
    return _client


# ------------------------------------------------------------------
# 独立运行入口
# ------------------------------------------------------------------

if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("usage: python speech_recognition.py <wav_file> [short|long]")
        print("  short - 短语音识别 (默认)")
        print("  long  - 长语音听写")
        sys.exit(1)

    wav_path = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 else "short"

    client = VivoASRClient()

    if mode == "long":
        print("[长语音听写] 开始识别...")

        def on_partial(text):
            print(f"  [中间] {text}")

        def on_sentence(text, is_last):
            tag = "最后一句" if is_last else "完整句子"
            print(f"  [{tag}] {text}")

        result = client.recognize_long(
            wav_path, on_partial=on_partial, on_sentence=on_sentence
        )
        print(f"\n结果: {result.text}")
        print(f"句子数: {len(result.sentences)}")
    else:
        print("[短语音识别] 开始识别...")

        def on_partial(text, is_last):
            tag = "最终" if is_last else "中间"
            print(f"  [{tag}] {text}")

        result = client.recognize_short(wav_path, on_partial=on_partial)
        print(f"\n结果: {result.text}")
