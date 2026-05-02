import json
import os
import uuid
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, Optional, Tuple


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

    def _read_json_body(self) -> Tuple[Optional[Dict], Optional[str]]:
        content_length = int(self.headers.get("Content-Length", "0"))
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

    def do_GET(self) -> None:
        if urllib.parse.urlparse(self.path).path == "/health":
            self._send_json(
                200,
                {
                    "ok": True,
                    "has_server_key": bool(os.getenv("VIVO_APP_KEY") or os.getenv("APP_KEY")),
                },
            )
            return
        self._send_json(404, {"error": "Not found"})

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_POST(self) -> None:
        if urllib.parse.urlparse(self.path).path != "/api/chat":
            self._send_json(404, {"error": "Not found"})
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
        system_message = self._build_platform_system_message(platform, memory_context)

        has_system_message = any(msg.get("role") == "system" for msg in messages)
        if not has_system_message:
            messages = [system_message] + messages

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
