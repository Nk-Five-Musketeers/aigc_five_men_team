"""
将全局 prompt 与单任务 prompt 合并为一条 system 消息。

设计要点:
- 情绪安抚(优先级 1)的指令块放在**最后**，便于模型「就近遵循」。
- 粗略按字符数截断，避免过长（约对应你方 1000 token 量级上限，可按需调 CONFIG）。

请求体示例（与 local_chat_server 的 prompt_context 字段对齐）::

    "prompt_context": {
        "global": {
            "dialect_preference": 0.7,
            "response_style": "简短温柔",
            "sensitive_topics": ["…"],
            "memory_snippets": ["…"]
        },
        "active_task": "memory_chat",
        "task": {
            "relevant_memories": [{"memory_id": "1", "summary": "…"}],
            "conversation_context": "天冷"
        }
    }

active_task 可选: daily_greeting | memory_chat | cognitive_test | emotion_support | null（仅全局）
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

_DIR = Path(__file__).resolve().parent

CONFIG: Dict[str, Any] = {
    "max_total_chars": 2400,
    "separator": "\n\n---\n\n",
}


def _load(filename: str) -> Any:
    path = _DIR / filename
    mod_name = "_promptmod_" + filename.replace(".py", "").replace(".", "_")
    spec = importlib.util.spec_from_file_location(mod_name, path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_gp = _load("global_prompt_v1.0.py")
_dg = _load("daily_greeting_v1.0.py")
_mc = _load("memory_chat_v1.0.py")
_ct = _load("cognitive_test_v1.0.py")
_es = _load("emotion_support_v1.0.py")

_TASK_LOADERS: Dict[str, Callable[..., Dict[str, Any]]] = {
    "daily_greeting": _dg.get_prompt,
    "memory_chat": _mc.get_prompt,
    "cognitive_test": _ct.get_prompt,
    "emotion_support": _es.get_prompt,
}


def _truncate(s: str, max_chars: int) -> Tuple[str, bool]:
    s = s.strip()
    if len(s) <= max_chars:
        return s, False
    return s[: max_chars - 1] + "…", True


def compose_system_prompt(
    *,
    global_params: Optional[Dict[str, Any]] = None,
    active_task: Optional[str] = None,
    task_params: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    返回可插入 OpenAI 风格 messages 的 dict: role, content。
    另附 prompt_meta（调用方可选择不入库 upstream）。
    """
    gp = global_params or {}
    tk = task_params or {}
    sep: str = CONFIG["separator"]
    max_total: int = int(CONFIG["max_total_chars"])

    blocks: List[str] = []
    meta: List[Dict[str, Any]] = []

    g = _gp.get_prompt(**gp)
    blocks.append(g["content"])
    meta.append(
        {"module": "global", "version": g["version"], "priority": g["priority"]}
    )

    task_name = (active_task or "").strip() or None
    loaders_order: List[str] = []
    if task_name == "emotion_support":
        loaders_order = ["emotion_support"]
    elif task_name in _TASK_LOADERS:
        loaders_order = [task_name]

    for name in loaders_order:
        fn = _TASK_LOADERS[name]
        part = fn(**tk)
        blocks.append(part["content"])
        meta.append(
            {
                "module": part.get("module", name),
                "version": part["version"],
                "priority": part["priority"],
            }
        )

    merged = sep.join(blocks)
    merged, truncated = _truncate(merged, max_total)

    return {
        "role": "system",
        "content": merged,
        "prompt_meta": {
            "modules": meta,
            "truncated": truncated,
            "max_total_chars": max_total,
        },
    }


def compose_for_request(
    prompt_context: Dict[str, Any],
    *,
    memory_context: Optional[List[Any]] = None,
) -> Dict[str, Any]:
    """
    从 HTTP 请求里的 prompt_context 组装；若 global 未带 memory_snippets 且提供了 memory_context，则自动映射为摘要列表。
    """
    g = dict(prompt_context.get("global") or {})
    if memory_context and not g.get("memory_snippets"):
        snippets = [str(x) for x in memory_context if isinstance(x, str)]
        if snippets:
            g["memory_snippets"] = snippets
    return compose_system_prompt(
        global_params=g,
        active_task=prompt_context.get("active_task"),
        task_params=dict(prompt_context.get("task") or {}),
    )
