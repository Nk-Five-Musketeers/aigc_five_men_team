"""
模块化 system prompt（文件名含版本号；因 Python 模块名不能含点号，故用 importlib 按路径加载）。

用法:
    from prompts import get_global_prompt, get_daily_greeting_prompt, ...

默认 v1.1；旧 v1.0 入口保留为 get_*_v10 以便灰度回退。
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import Any, Callable, Dict

_DIR = Path(__file__).resolve().parent


def _load(filename: str) -> Any:
    path = _DIR / filename
    if not path.is_file():
        raise FileNotFoundError(path)
    mod_name = "prompts_" + filename.replace(".py", "").replace(".", "_")
    spec = importlib.util.spec_from_file_location(mod_name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# v1.1 (默认)
_gp11 = _load("global_prompt_v1.1.py")
_dg11 = _load("daily_greeting_v1.1.py")
_mc11 = _load("memory_chat_v1.1.py")
_ct11 = _load("cognitive_test_v1.1.py")
_es11 = _load("emotion_support_v1.1.py")

# v1.0 (保留, 供回退)
_gp10 = _load("global_prompt_v1.0.py")
_dg10 = _load("daily_greeting_v1.0.py")
_mc10 = _load("memory_chat_v1.0.py")
_ct10 = _load("cognitive_test_v1.0.py")
_es10 = _load("emotion_support_v1.0.py")

# 默认入口 → v1.1
get_global_prompt: Callable[..., Dict[str, Any]] = _gp11.get_prompt
get_daily_greeting_prompt: Callable[..., Dict[str, Any]] = _dg11.get_prompt
get_memory_chat_prompt: Callable[..., Dict[str, Any]] = _mc11.get_prompt
get_cognitive_test_prompt: Callable[..., Dict[str, Any]] = _ct11.get_prompt
get_emotion_support_prompt: Callable[..., Dict[str, Any]] = _es11.get_prompt

# v1.0 回退入口
get_global_prompt_v10: Callable[..., Dict[str, Any]] = _gp10.get_prompt
get_daily_greeting_prompt_v10: Callable[..., Dict[str, Any]] = _dg10.get_prompt
get_memory_chat_prompt_v10: Callable[..., Dict[str, Any]] = _mc10.get_prompt
get_cognitive_test_prompt_v10: Callable[..., Dict[str, Any]] = _ct10.get_prompt
get_emotion_support_prompt_v10: Callable[..., Dict[str, Any]] = _es10.get_prompt

from .prompt_composer import compose_for_request, compose_system_prompt

__all__ = [
    "get_global_prompt",
    "get_daily_greeting_prompt",
    "get_memory_chat_prompt",
    "get_cognitive_test_prompt",
    "get_emotion_support_prompt",
    "get_global_prompt_v10",
    "get_daily_greeting_prompt_v10",
    "get_memory_chat_prompt_v10",
    "get_cognitive_test_prompt_v10",
    "get_emotion_support_prompt_v10",
    "compose_system_prompt",
    "compose_for_request",
]
