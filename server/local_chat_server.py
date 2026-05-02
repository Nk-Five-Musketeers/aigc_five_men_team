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
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEBUG_MEMORY_EXPORT_PATH = os.path.join(PROJECT_ROOT, "debug_memory_export.json")
DEBUG_TABLES = (
    "elder_basic_info",
    "family_members",
    "memory_events",
    "daily_life_records",
    "conversation_records",
)


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

    def do_GET(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        if path == "/health":
            self._send_json(
                200,
                {
                    "ok": True,
                    "has_server_key": bool(os.getenv("VIVO_APP_KEY") or os.getenv("APP_KEY")),
                },
            )
            return
        if path == "/api/debug/memory-export":
            if not os.path.exists(DEBUG_MEMORY_EXPORT_PATH):
                self._send_json(200, self._empty_debug_export())
                return
            with open(DEBUG_MEMORY_EXPORT_PATH, "rb") as file:
                self._send_bytes(
                    200,
                    file.read(),
                    "application/json; charset=utf-8",
                )
                return
        self._send_json(404, {"error": "Not found"})

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_POST(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/debug/memory-export":
            req_data, err = self._read_json_body()
            if err:
                self._send_json(400, {"error": err})
                return
            assert req_data is not None
            self._append_debug_memory_export(req_data)
            self._send_json(
                200,
                {
                    "ok": True,
                    "path": DEBUG_MEMORY_EXPORT_PATH,
                },
            )
            return

        if path != "/api/chat":
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

    def _append_debug_memory_export(self, item: Dict) -> None:
        data = self._load_debug_export()
        table_updates = item.get("table_updates")

        if isinstance(table_updates, dict):
            for table_name, rows in table_updates.items():
                if table_name not in DEBUG_TABLES or not isinstance(rows, list):
                    continue
                for row in rows:
                    if isinstance(row, dict):
                        self._upsert_debug_row(data, table_name, row)
        else:
            data.setdefault("raw_exports", []).append(item)

        data["updated_at"] = item.get("exported_at")
        with open(DEBUG_MEMORY_EXPORT_PATH, "w", encoding="utf-8") as file:
            json.dump(data, file, ensure_ascii=False, indent=2)

    def _load_debug_export(self) -> Dict:
        data = self._empty_debug_export()
        if os.path.exists(DEBUG_MEMORY_EXPORT_PATH):
            try:
                with open(DEBUG_MEMORY_EXPORT_PATH, "r", encoding="utf-8") as file:
                    loaded = json.load(file)
                if isinstance(loaded, dict):
                    for table_name in DEBUG_TABLES:
                        if isinstance(loaded.get(table_name), list):
                            data[table_name] = loaded[table_name]
                    if isinstance(loaded.get("raw_exports"), list):
                        data["raw_exports"] = loaded["raw_exports"]
            except Exception:
                data = self._empty_debug_export()
        return data

    def _empty_debug_export(self) -> Dict:
        return {
            "elder_basic_info": [],
            "family_members": [],
            "memory_events": [],
            "daily_life_records": [],
            "conversation_records": [],
            "raw_exports": [],
            "updated_at": None,
        }

    def _upsert_debug_row(self, data: Dict, table_name: str, row: Dict) -> None:
        rows = data.setdefault(table_name, [])
        row_id = row.get("id")

        if table_name == "elder_basic_info":
            if rows:
                rows[0].update({key: value for key, value in row.items() if value is not None})
            else:
                rows.append(row)
            return

        if row_id is None:
            rows.append(row)
            return

        for index, existing in enumerate(rows):
            if isinstance(existing, dict) and existing.get("id") == row_id:
                merged = dict(existing)
                merged.update({key: value for key, value in row.items() if value is not None})
                rows[index] = merged
                return

        rows.append(row)

    def log_message(self, format_text: str, *args) -> None:  # noqa: A003
        print(f"[{self.log_date_time_string()}] {self.address_string()} - {format_text % args}")


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), ChatProxyHandler)
    has_key = bool(os.getenv("VIVO_APP_KEY") or os.getenv("APP_KEY"))
    print(f"Chat proxy is running on http://{HOST}:{PORT}")
    print(f"Server AppKey loaded: {has_key}")
    server.serve_forever()


if __name__ == "__main__":
    main()
