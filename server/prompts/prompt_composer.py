"""
将全局 prompt 与单任务 prompt 合并为一条 system 消息。

设计要点:
- 情绪安抚(优先级 1)的指令块放在**最后**，便于模型「就近遵循」。
- 分模块字符预算截断，再拼接；max_total_chars 为兜底上限。
- 支持 version 参数选择 v1.0 / v1.1，默认 v1.1。

请求体示例（与 local_chat_server 的 prompt_context 字段对齐）::

    "prompt_context": {
        "global": {
            "dialect": "天津话",
            "sensitive_topics": ["…"],
            "memory_snippets": ["…"],
            "elder_profile_brief": "…"
        },
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


def _load(filename: str) -> Any:
    path = _DIR / filename
    mod_name = "_promptmod_" + filename.replace(".py", "").replace(".", "_")
    spec = importlib.util.spec_from_file_location(mod_name, path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# v1.0 loaders (保留, 可通过 version="v1.0" 回退)
_gp_v10 = _load("global_prompt_v1.0.py")
_dg_v10 = _load("daily_greeting_v1.0.py")
_mc_v10 = _load("memory_chat_v1.0.py")
_ct_v10 = _load("cognitive_test_v1.0.py")
_es_v10 = _load("emotion_support_v1.0.py")

# v1.1 loaders (默认)
_gp_v11 = _load("global_prompt_v1.1.py")
_dg_v11 = _load("daily_greeting_v1.1.py")
_mc_v11 = _load("memory_chat_v1.1.py")
_ct_v11 = _load("cognitive_test_v1.1.py")
_es_v11 = _load("emotion_support_v1.1.py")

_VERSION_LOADERS: Dict[str, Dict[str, Callable[..., Dict[str, Any]]]] = {
    "v1.0": {
        "global": _gp_v10.get_prompt,
        "daily_greeting": _dg_v10.get_prompt,
        "memory_chat": _mc_v10.get_prompt,
        "cognitive_test": _ct_v10.get_prompt,
        "emotion_support": _es_v10.get_prompt,
    },
    "v1.1": {
        "global": _gp_v11.get_prompt,
        "daily_greeting": _dg_v11.get_prompt,
        "memory_chat": _mc_v11.get_prompt,
        "cognitive_test": _ct_v11.get_prompt,
        "emotion_support": _es_v11.get_prompt,
    },
}


def _truncate(s: str, max_chars: int) -> Tuple[str, bool]:
    s = s.strip()
    if len(s) <= max_chars:
        return s, False
    return s[: max_chars - 1] + "…", True


def _compose_global_block(
    loader: Callable[..., Dict[str, Any]],
    params: Dict[str, Any],
    budget: int,
) -> Tuple[str, Dict[str, Any], bool]:
    g = loader(**params)
    content, truncated = _truncate(g["content"], budget)
    meta = {"module": "global", "version": g["version"], "priority": g["priority"]}
    return content, meta, truncated


def _compose_task_block(
    loader: Callable[..., Dict[str, Any]],
    task_name: str,
    params: Dict[str, Any],
    budget: int,
) -> Tuple[str, Dict[str, Any], bool]:
    part = loader(**params)
    content, truncated = _truncate(part["content"], budget)
    meta = {
        "module": part.get("module", task_name),
        "version": part["version"],
        "priority": part["priority"],
    }
    return content, meta, truncated


def compose_system_prompt(
    *,
    global_params: Optional[Dict[str, Any]] = None,
    active_task: Optional[str] = None,
    task_params: Optional[Dict[str, Any]] = None,
    version: str = "v1.1",
) -> Dict[str, Any]:
    """
    返回可插入 OpenAI 风格 messages 的 dict: role, content。
    另附 prompt_meta（调用方可选择不入库 upstream）。

    version: "v1.0" | "v1.1"，默认 v1.1。
    """
    loaders = _VERSION_LOADERS.get(version)
    if loaders is None:
        raise ValueError(f"Unsupported prompt version: {version}. Use v1.0 or v1.1.")

    gp = global_params or {}
    tk = task_params or {}
    sep: str = CONFIG["separator"]
    max_total: int = int(CONFIG["max_total_chars"])
    budget_global: int = int(CONFIG["budget_global"])
    budget_task: int = int(CONFIG["budget_task"])

    blocks: List[str] = []
    meta: List[Dict[str, Any]] = []
    any_truncated = False

    # 1) 全局基座 (PRIORITY=0) — 始终在最前
    g_content, g_meta, g_trunc = _compose_global_block(
        loaders["global"], gp, budget_global
    )
    blocks.append(g_content)
    meta.append(g_meta)
    any_truncated = any_truncated or g_trunc

    # 2) 任务块 — 拼接顺序:
    #    emotion_support 放在最后（就近遵循），其余按传入 active_task
    task_name = (active_task or "").strip() or None
    if task_name and task_name in loaders:
        t_content, t_meta, t_trunc = _compose_task_block(
            loaders[task_name], task_name, tk, budget_task
        )
        blocks.append(t_content)
        meta.append(t_meta)
        any_truncated = any_truncated or t_trunc

    # 3) 如果 active_task 不是 emotion_support 但有 emotion_support 的独立块需求,
    #    这里不做自动注入——emotion_support 由 router 决定 active_task 时自带。

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
            },
            "version": version,
        },
    }


def compose_for_request(
    prompt_context: Dict[str, Any],
    *,
    memory_context: Optional[List[Any]] = None,
    version: str = "v1.1",
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
        version=version,
    )
