import json
import os
import sys
import uuid
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, List, Optional, Tuple


_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
if _SERVER_DIR not in sys.path:
    sys.path.insert(0, _SERVER_DIR)

HOST = os.getenv("HOST", "127.0.0.1")
PORT = int(os.getenv("PORT", "8000"))
CHAT_API_URL = "https://api-ai.vivo.com.cn/v1/chat/completions"
DEFAULT_MODEL = "Volc-DeepSeek-V3.2"


class ChatProxyHandler(BaseHTTPRequestHandler):
    def _send_cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def _send_json(self, status_code: int, payload: Dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self._send_cors_headers()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_bytes(self, status_code: int, body: bytes, content_type: str) -> None:
        self.send_response(status_code)
        self.send_header("Content-Type", content_type)
        self._send_cors_headers()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_content_length(self) -> int:
        return int(self.headers.get("Content-Length", "0"))

    def _discard_request_body(self) -> None:
        """未处理的路由也需读完 body，否则客户端上传二进制时会 Connection reset。"""
        length = self._read_content_length()
        if length > 0:
            self.rfile.read(length)

    def _read_json_body(self) -> Tuple[Optional[Dict], Optional[str]]:
        content_length = self._read_content_length()
        if content_length <= 0:
            return None, "Body is required"
        try:
            raw = self.rfile.read(content_length)
            return json.loads(raw.decode("utf-8")), None
        except Exception:
            return None, "Invalid JSON"

    def _resolve_app_key(self, req_data: Dict) -> Optional[str]:
        return req_data.get("app_key") or os.getenv("VIVO_APP_KEY") or os.getenv("APP_KEY")

    def _build_platform_system_message(self, platform: str, memory_context: Optional[list]) -> Dict:
        prompt = (
            f"你是一个名为“{platform}”的老年人陪伴型 AI。\n"
            "请始终保持耐心、温和、关怀，适合与老人聊天。\n"
            "你的核心任务是：\n"
            "1. 以温柔、尊重和积极倾听的方式回应老人，避免使用生硬或专业术语。\n"
            "2. 当老人提到过往事情时，尽量联系已有记忆线索或数据库中的相关内容；如果没有明确记忆线索，也要用关怀方式继续对话。\n"
            "3. 在话题结束后自然引导进入新的、与老人记忆相关的聊天，使用提问式表达，例如“记得您说过……吗？”、“您曾经在哪里工作，那时候会冷吗？”等。\n"
            "4. 适时插入日常认知类问题，例如看到亲戚朋友照片时问“您觉得这个人是谁？”，看到生活用品时问“这个叫什么？”；这些提问应自然嵌入对话，帮助老人回忆和认知。\n"
            "5. 在日常对话中提取并整理老人最近的活动信息，例如今天吃了什么、做了什么、见了谁等，并用简短友好的方式进行回顾。\n"
            "6. 如果提供了 memory_context，请将这些内容视为可靠记忆线索，并在对话中自然回忆或确认它们。\n"
            "7. 避免直接陈述你是一个机器人，应让对话更具陪伴感，注意保持语言亲切、耐心、鼓励。"
        )
        if isinstance(memory_context, list) and memory_context:
            prompt += "\n\n以下是当前可用的记忆线索，请在对话中自然结合使用：\n"
            prompt += "\n".join(f"- {item}" for item in memory_context if isinstance(item, str))

        return {"role": "system", "content": prompt}

    def _resolve_default_system_message(
        self,
        req_data: Dict[str, Any],
        platform: str,
        memory_context: Optional[List[Any]],
    ) -> Dict[str, str]:
        pc = req_data.get("prompt_context")
        if isinstance(pc, dict) and pc:
            try:
                from prompts.prompt_composer import compose_for_request

                mc = memory_context if isinstance(memory_context, list) else None
                composed = compose_for_request(pc, memory_context=mc)
                return {
                    "role": "system",
                    "content": composed["content"],
                }
            except Exception as exc:
                print(
                    f"[prompt_context] failed, using legacy system prompt: {exc}",
                    flush=True,
                )
        legacy = self._build_platform_system_message(platform, memory_context)
        return {"role": "system", "content": legacy["content"]}

    def do_GET(self) -> None:
        if urllib.parse.urlparse(self.path).path == "/health":
            self._send_json(
                200,
                {
                    "ok": True,
                    "has_server_key": bool(os.getenv("VIVO_APP_KEY") or os.getenv("APP_KEY")),
                    "local_speech_nlp": True,
                    "vivo_asr": bool(os.getenv("VIVO_APP_KEY") or os.getenv("APP_KEY")),
                },
            )
            return
        self._send_json(404, {"error": "Not found"})

    def _handle_asr_transcribe(self) -> None:
        if not (os.getenv("VIVO_APP_KEY") or os.getenv("APP_KEY")):
            self._discard_request_body()
            self._send_json(
                400,
                {"error": "Missing AppKey. Set VIVO_APP_KEY or APP_KEY for vivo ASR."},
            )
            return

        parsed = urllib.parse.urlparse(self.path)
        mode = (urllib.parse.parse_qs(parsed.query).get("mode") or ["auto"])[0]

        content_type = self.headers.get("Content-Type", "").split(";")[0].strip().lower()
        audio_bytes = None

        try:
            if content_type.startswith("audio/") or content_type == "application/octet-stream":
                length = self._read_content_length()
                if length <= 0:
                    self._send_json(400, {"error": "Empty audio body"})
                    return
                audio_bytes = self.rfile.read(length)
            else:
                self._discard_request_body()
                self._send_json(
                    400,
                    {
                        "error": "Content-Type must be audio/wav or application/octet-stream",
                        "received": content_type or "(empty)",
                    },
                )
                return

            if not audio_bytes or len(audio_bytes) < 44:
                self._send_json(400, {"error": "Audio too short"})
                return

            from asr_http import transcribe_upload
            from speech_recognition import VivoASRError

            text, mode_used = transcribe_upload(audio_bytes, mode=mode)
            self._send_json(
                200,
                {
                    "ok": True,
                    "text": text,
                    "mode": mode_used,
                    "source": "vivo_asr",
                },
            )
        except VivoASRError as exc:
            self._send_json(
                502,
                {"error": "vivo_asr_failed", "code": exc.code, "detail": exc.desc},
            )
        except Exception as exc:
            self._send_json(500, {"error": "asr_transcribe_failed", "detail": str(exc)})

    def _handle_speech_polish(self) -> None:
        req_data, err = self._read_json_body()
        if err:
            self._send_json(400, {"error": err})
            return
        assert req_data is not None

        text = req_data.get("text")
        if not isinstance(text, str):
            self._send_json(400, {"error": "text must be a string"})
            return

        try:
            from nlp_speech_polish import polish_speech_transcript

            polished = polish_speech_transcript(text)
        except Exception as exc:
            self._send_json(500, {"error": "local_nlp_failed", "detail": str(exc)})
            return

        self._send_json(
            200,
            {
                "ok": True,
                "text": polished,
                "source": "local_nlp",
            },
        )

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_POST(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/speech/polish":
            self._handle_speech_polish()
            return
        if path == "/api/asr/transcribe":
            self._handle_asr_transcribe()
            return
        if path != "/api/chat":
            self._discard_request_body()
            self._send_json(404, {"error": "Not found", "path": path})
            return

        req_data, err = self._read_json_body()
        if err:
            self._send_json(400, {"error": err})
            return
        assert req_data is not None

        app_key = self._resolve_app_key(req_data)
        if not app_key:
            self._send_json(
                400,
                {"error": "Missing AppKey. Set VIVO_APP_KEY or APP_KEY before starting the server."},
            )
            return

        messages = req_data.get("messages")
        if not isinstance(messages, list) or not messages:
            self._send_json(400, {"error": "messages must be a non-empty array"})
            return

        platform = req_data.get("platform", "AI")
        memory_context = req_data.get("memory_context")
        chat_task = req_data.get("chat_task") or ""

        has_system_message = any(msg.get("role") == "system" for msg in messages)
        # 独立任务（选图/润色/抽取）自带 system，勿拼接陪伴长 prompt
        if not has_system_message:
            system_message = self._resolve_default_system_message(
                req_data, platform, memory_context
            )
            messages = [system_message] + messages
        elif chat_task:
            print(f"[chat_task] {chat_task}", flush=True)

        payload = {
            "model": req_data.get("model") or DEFAULT_MODEL,
            "messages": messages,
            "stream": False,
        }
        for field in (
            "temperature",
            "top_p",
            "max_tokens",
            "max_completion_tokens",
            "reasoning_effort",
            "frequency_penalty",
            "presence_penalty",
        ):
            if req_data.get(field) is not None:
                payload[field] = req_data[field]

        enable_thinking = req_data.get("enable_thinking")
        if enable_thinking is not None:
            payload["thinking"] = {"type": "enable" if enable_thinking else "disabled"}

        request_id = req_data.get("request_id") or str(uuid.uuid4())
        url = f"{CHAT_API_URL}?request_id={urllib.parse.quote(request_id)}"
        request = urllib.request.Request(
            url=url,
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "Authorization": f"Bearer {app_key}",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                self._send_bytes(
                    response.getcode(),
                    response.read(),
                    response.headers.get("Content-Type", "application/json; charset=utf-8"),
                )
        except urllib.error.HTTPError as exc:
            self._send_bytes(
                exc.code,
                exc.read(),
                exc.headers.get("Content-Type", "application/json; charset=utf-8"),
            )
        except urllib.error.URLError as exc:
            self._send_json(502, {"error": "Upstream connection failed", "detail": str(exc)})

    def log_message(self, format_text: str, *args) -> None:  # noqa: A003
        print(f"[{self.log_date_time_string()}] {self.address_string()} - {format_text % args}")


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), ChatProxyHandler)
    has_key = bool(os.getenv("VIVO_APP_KEY") or os.getenv("APP_KEY"))
    print(f"Chat proxy is running on http://{HOST}:{PORT}")
    print(f"Server AppKey loaded: {has_key}")
    print("Press Ctrl+C to stop.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        # Ctrl+C：正常停止长时间运行的 HTTP 服务，不是异常崩溃
        print("\nStopped (KeyboardInterrupt). Local chat proxy exited.", flush=True)


if __name__ == "__main__":
    main()
