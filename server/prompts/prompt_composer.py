"""
将全局 prompt 与单任务 prompt 合并为一条 system 消息。

设计要点:
- 情绪安抚(优先级 1)的指令块放在**最后**，便于模型「就近遵循」。
- 分模块字符预算截断，再拼接；max_total_chars 为兜底上限。
- 支持 version 参数选择 v1.0 / v1.1 / v1.2，默认 v1.2。
- v1.2: memory_snippets 独立预算(300 chars)，懒加载 prompt 模块。

请求体示例（与 local_chat_server 的 prompt_context 字段对齐）::

    "prompt_context": {
        "global": {
            "dialect": "天津话",
            "sensitive_topics": ["…"],
            "elder_profile_brief": "…"
        },
        "memory_snippets": ["…"],
        "active_task": "memory_chat",
        "task": {
            "relevant_memories": [{"id": "1", "title": "…"}],
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

# 分模块字符预算: 各自独立截断到额度内, 再拼接; max_total_chars 仅兜底
CONFIG: Dict[str, Any] = {
    "max_total_chars": 2400,
    "budget_global": 1200,
    "budget_task": 900,
    "budget_memory": 300,
    "separator": "\n\n---\n\n",
}

# ---------------------------------------------------------------------------
# 懒加载: 存 (filename, func_name) 元组, 首次 compose 时按需加载并缓存
# ---------------------------------------------------------------------------
_VERSION_LOADERS: Dict[str, Dict[str, Tuple[str, str]]] = {
    "v1.0": {
        "global": ("v1.0/global_prompt.py", "get_prompt"),
        "daily_greeting": ("v1.0/daily_greeting.py", "get_prompt"),
        "memory_chat": ("v1.0/memory_chat.py", "get_prompt"),
        "cognitive_test": ("v1.0/cognitive_test.py", "get_prompt"),
        "emotion_support": ("v1.0/emotion_support.py", "get_prompt"),
    },
    "v1.1": {
        "global": ("v1.1/global_prompt.py", "get_prompt"),
        "daily_greeting": ("v1.1/daily_greeting.py", "get_prompt"),
        "memory_chat": ("v1.1/memory_chat.py", "get_prompt"),
        "cognitive_test": ("v1.1/cognitive_test.py", "get_prompt"),
        "emotion_support": ("v1.1/emotion_support.py", "get_prompt"),
    },
    "v1.2": {
        "global": ("v1.2/global_prompt.py", "get_prompt"),
        "daily_greeting": ("v1.2/daily_greeting.py", "get_prompt"),
        "memory_chat": ("v1.2/memory_chat.py", "get_prompt"),
        "cognitive_test": ("v1.2/cognitive_test.py", "get_prompt"),
        "emotion_support": ("v1.2/emotion_support.py", "get_prompt"),
    },
}

_MODULE_CACHE: Dict[Tuple[str, str], Callable[..., Dict[str, Any]]] = {}


def _load_module(filename: str) -> Any:
    path = _DIR / filename
    mod_name = (
        "_promptmod_"
        + filename.replace(".py", "").replace(".", "_").replace("/", "_").replace("\\", "_")
    )
    spec = importlib.util.spec_from_file_location(mod_name, path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _get_loader(version: str, module_name: str) -> Callable[..., Dict[str, Any]]:
    cache_key = (version, module_name)
    if cache_key in _MODULE_CACHE:
        return _MODULE_CACHE[cache_key]
    entry = _VERSION_LOADERS[version][module_name]
    filename, func_name = entry
    mod = _load_module(filename)
    fn = getattr(mod, func_name)
    _MODULE_CACHE[cache_key] = fn
    return fn


def _truncate(s: str, max_chars: int) -> Tuple[str, bool]:
    s = s.strip()
    if len(s) <= max_chars:
        return s, False
    return s[: max_chars - 1] + "…", True


def _compose_global_block(
    version: str,
    params: Dict[str, Any],
    budget: int,
) -> Tuple[str, Dict[str, Any], bool]:
    loader = _get_loader(version, "global")
    g = loader(**params)
    content, truncated = _truncate(g["content"], budget)
    meta = {"module": "global", "version": g["version"], "priority": g["priority"]}
    return content, meta, truncated


def _compose_task_block(
    version: str,
    task_name: str,
    params: Dict[str, Any],
    budget: int,
) -> Tuple[str, Dict[str, Any], bool]:
    loader = _get_loader(version, task_name)
    part = loader(**params)
    content, truncated = _truncate(part["content"], budget)
    meta = {
        "module": part.get("module", task_name),
        "version": part["version"],
        "priority": part["priority"],
    }
    return content, meta, truncated


def _compose_memory_block(
    memory_snippets: List[str],
    budget: int,
) -> Tuple[str, Dict[str, Any], bool]:
    if not memory_snippets:
        return "", {"module": "memory", "snippets": 0}, False
    lines: List[str] = []
    for i, s in enumerate(memory_snippets[:3], start=1):
        t = (s or "").strip().replace("\n", " ")
        if len(t) > 80:
            t = t[:79] + "…"
        lines.append(f"{i}. {t}")
    content = "【可自然提及的压缩记忆摘要】\n" + ("\n".join(lines) if lines else "（暂无）")
    content, truncated = _truncate(content, budget)
    meta = {"module": "memory", "snippets": len(lines)}
    return content, meta, truncated


def compose_system_prompt(
    *,
    global_params: Optional[Dict[str, Any]] = None,
    active_task: Optional[str] = None,
    task_params: Optional[Dict[str, Any]] = None,
    memory_snippets: Optional[List[str]] = None,
    version: str = "v1.2",
) -> Dict[str, Any]:
    """
    返回可插入 OpenAI 风格 messages 的 dict: role, content。
    另附 prompt_meta（调用方可选择不入库 upstream）。

    version: "v1.0" | "v1.1" | "v1.2"，默认 v1.2。
    """
    if version not in _VERSION_LOADERS:
        raise ValueError(
            f"Unsupported prompt version: {version}. "
            f"Use: {', '.join(sorted(_VERSION_LOADERS))}"
        )

    gp = global_params or {}
    tk = task_params or {}
    sep: str = CONFIG["separator"]
    max_total: int = int(CONFIG["max_total_chars"])
    budget_global: int = int(CONFIG["budget_global"])
    budget_task: int = int(CONFIG["budget_task"])
    budget_memory: int = int(CONFIG["budget_memory"])

    blocks: List[str] = []
    meta: List[Dict[str, Any]] = []
    any_truncated = False

    # 1) 全局基座 (PRIORITY=0) — 始终在最前
    g_content, g_meta, g_trunc = _compose_global_block(
        version, gp, budget_global
    )
    blocks.append(g_content)
    meta.append(g_meta)
    any_truncated = any_truncated or g_trunc

    # 2) 任务块
    task_name = (active_task or "").strip() or None
    if task_name and task_name in _VERSION_LOADERS[version]:
        t_content, t_meta, t_trunc = _compose_task_block(
            version, task_name, tk, budget_task
        )
        blocks.append(t_content)
        meta.append(t_meta)
        any_truncated = any_truncated or t_trunc

    # 3) 记忆块 — 独立 budget
    m_content, m_meta, m_trunc = _compose_memory_block(
        memory_snippets or [], budget_memory
    )
    if m_content:
        blocks.append(m_content)
        meta.append(m_meta)
        any_truncated = any_truncated or m_trunc

    merged = sep.join(blocks)
    merged, total_trunc = _truncate(merged, max_total)

    return {
        "role": "system",
        "content": merged,
        "prompt_meta": {
            "modules": meta,
            "truncated": any_truncated or total_trunc,
            "max_total_chars": max_total,
            "budgets": {
                "global": budget_global,
                "task": budget_task,
                "memory": budget_memory,
            },
            "version": version,
        },
    }


def compose_for_request(
    prompt_context: Dict[str, Any],
    *,
    memory_context: Optional[List[Any]] = None,
    version: str = "v1.2",
) -> Dict[str, Any]:
    """
    从 HTTP 请求里的 prompt_context 组装 system prompt。

    向后兼容:
    - 优先读 prompt_context["memory_snippets"]（v1.2 顶层字段）
    - 回退读 prompt_context["global"]["memory_snippets"]（旧格式）
    - memory_context 参数作为最后兜底
    """
    g = dict(prompt_context.get("global") or {})

    # 移除旧格式下可能存在 global 中的 memory_snippets, 避免被 global
    # loader 误用（v1.2 global 已不再接收该参数）
    g.pop("memory_snippets", None)

    # 解析 memory_snippets: 新顶层 > 旧 global 内 > memory_context 参数
    snippets: Optional[List[str]] = None
    raw_top = prompt_context.get("memory_snippets")
    if isinstance(raw_top, list):
        snippets = [str(x) for x in raw_top if isinstance(x, str)]
    if not snippets:
        raw_old = (prompt_context.get("global") or {}).get("memory_snippets")
        if isinstance(raw_old, list):
            snippets = [str(x) for x in raw_old if isinstance(x, str)]
    if not snippets and memory_context:
        snippets = [str(x) for x in memory_context if isinstance(x, str)]

    return compose_system_prompt(
        global_params=g,
        active_task=prompt_context.get("active_task"),
        task_params=dict(prompt_context.get("task") or {}),
        memory_snippets=snippets,
        version=version,
    )
