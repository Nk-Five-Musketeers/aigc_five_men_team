"""
模块化 system prompt（文件名含 v1.0；因 Python 模块名不能含点号，故用 importlib 按路径加载）。

用法:
    from prompts import get_global_prompt, get_daily_greeting_prompt, ...
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


_gp = _load("global_prompt_v1.0.py")
_dg = _load("daily_greeting_v1.0.py")
_mc = _load("memory_chat_v1.0.py")
_ct = _load("cognitive_test_v1.0.py")
_es = _load("emotion_support_v1.0.py")

get_global_prompt: Callable[..., Dict[str, Any]] = _gp.get_prompt
get_daily_greeting_prompt: Callable[..., Dict[str, Any]] = _dg.get_prompt
get_memory_chat_prompt: Callable[..., Dict[str, Any]] = _mc.get_prompt
get_cognitive_test_prompt: Callable[..., Dict[str, Any]] = _ct.get_prompt
get_emotion_support_prompt: Callable[..., Dict[str, Any]] = _es.get_prompt

from .prompt_composer import compose_for_request, compose_system_prompt

__all__ = [
    "get_global_prompt",
    "get_daily_greeting_prompt",
    "get_memory_chat_prompt",
    "get_cognitive_test_prompt",
    "get_emotion_support_prompt",
    "compose_system_prompt",
    "compose_for_request",
]
