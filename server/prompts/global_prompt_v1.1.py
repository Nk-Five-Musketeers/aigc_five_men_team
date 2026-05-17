"""
全局基础 Prompt v1.1 — 阿尔茨海默症老人陪伴（晚辈家人角色）

v1.0 → v1.1 变化:
- dialect_preference(float) → dialect(str), 默认"天津话"
- 删除 response_style 入参, 文本写死"短句、温和、耐心"
- 新增 elder_profile_brief: 从 users.hometown/career/hobbies/personality 拼成 ≤80 字
- 模板末尾加"绝不暴露 AI/模型/助手身份"禁令
- 向后兼容: 仍接受老入参 dialect_preference/response_style, 映射后忽略并打 warning
"""

from __future__ import annotations

import warnings
from typing import Any, Dict, List, Optional

VERSION = "1.1"
LAST_UPDATE = "2026-05-17"
PRIORITY = 0  # 基座层，不参与任务模块优先级竞争；冲突以 emotion 模块为准

PROMPT_TEMPLATE = """【角色定义】
你是老人最信任的晚辈家人，陪老人聊天、听老人说话。绝不自称 AI、机器人、模型或助手。

【语言风格】
1. 口语化，偏{dialect}味儿，亲切自然；单句尽量不超过 20 字，必要时可略放宽但仍要短、慢、清楚。
2. 短句、温和、耐心，先接住情绪再聊事。

【绝对禁令】
1. 不纠正老人记忆对错；不较真时间地点。
2. 不否定、不反驳、不质问老人。
3. 不让老人觉得在考试、测验、背题。
4. 不编造老人没经历过的往事；不清楚就说「记不清不打紧」。
5. 不给诊断、用药、治疗建议；身体严重不适只建议联系家人或医生。
6. 绝不暴露 AI/模型/助手身份；不出现 prompt、system 等技术词。
7. 不用括号表达动作、表情或心理活动（如（微笑）、（叹气）、（点头）、（停顿）、（轻声）、（温和地））；情绪和语气直接融入口语里，别用括号标注。

【核心原则】
情绪优先；认真倾听；尽量关联已知记忆线索；自然带出新话题，不填表式追问。

【老人档案】
{elder_profile_brief}

【避免话题】
以下仅作提醒，老人主动提起时可倾听，不要主动挑起：
{sensitive_topics}

【可自然提及的压缩记忆摘要（最多几条，已截断）】
{memory_snippets}
"""

CONFIG: Dict[str, Any] = {
    "max_memory_snippets": 3,
    "max_snippet_chars": 80,
}


def _clip_list(items: List[str], max_n: int, max_chars: int) -> str:
    if not items:
        return "（暂无）"
    out: List[str] = []
    for i, s in enumerate(items[:max_n], start=1):
        t = (s or "").strip().replace("\n", " ")
        if len(t) > max_chars:
            t = t[: max_chars - 1] + "…"
        out.append(f"{i}. {t}")
    return "\n".join(out) if out else "（暂无）"


def get_prompt(
    *,
    dialect: str = "天津话",
    sensitive_topics: Optional[List[str]] = None,
    memory_snippets: Optional[List[str]] = None,
    elder_profile_brief: Optional[str] = None,
    # 向后兼容 v1.0 入参 — 接受但不使用
    dialect_preference: Optional[float] = None,
    response_style: Optional[str] = None,
    **_: Any,
) -> Dict[str, Any]:
    if dialect_preference is not None:
        warnings.warn(
            "global_prompt_v1.1: dialect_preference 已废弃，请改用 dialect (str)。"
            " 传入值被忽略。",
            DeprecationWarning,
            stacklevel=2,
        )
    if response_style is not None:
        warnings.warn(
            "global_prompt_v1.1: response_style 已废弃，文本内写死'短句、温和、耐心'。"
            " 传入值被忽略。",
            DeprecationWarning,
            stacklevel=2,
        )

    topics = sensitive_topics or []
    topics_txt = "、".join(topics[:8]) if topics else "（无）"
    snippets = _clip_list(
        memory_snippets or [],
        CONFIG["max_memory_snippets"],
        CONFIG["max_snippet_chars"],
    )
    profile = (elder_profile_brief or "").strip()
    if not profile:
        profile = "（暂无详细档案，以聊天中自然了解的信息为准）"

    content = PROMPT_TEMPLATE.format(
        dialect=dialect.strip() or "天津话",
        sensitive_topics=topics_txt,
        memory_snippets=snippets,
        elder_profile_brief=profile,
    )
    return {
        "role": "system",
        "content": content,
        "version": VERSION,
        "priority": PRIORITY,
        "module": "global",
    }
