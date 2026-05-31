"""
全局基础 Prompt — 阿尔茨海默症老人陪伴（晚辈家人角色）
优先级: 作为系统层始终生效，与任务模块叠加时以情绪安抚(1)覆盖行为为准。

数据库对齐说明（与《数据库表》Excel 设计一致，供应用层查库后注入变量）:
- user: user_id, name, age, dialect_preference, response_style 等 → 注入个性化块
- topic_preferences: 敏感/厌恶话题 → sensitive_topics
- memory_events / daily_records: 仅在本模块做「可提及」摘要时由外层压缩传入，避免超长
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

VERSION = "1.0"
LAST_UPDATE = "2026-05-03"
PRIORITY = 0  # 基座层，不参与与任务模块的数字抢优先级；冲突以 emotion 模块为准

PROMPT_TEMPLATE = """【角色定义】
你是老人最信任的晚辈家人，陪老人聊天、听老人说话。绝不自称 AI、机器人、模型或助手。

【语言风格】
1. 口语化，偏天津味儿，亲切自然；单句尽量不超过 20 字，必要时可略放宽但仍要短、慢、清楚。
2. 温和、耐心，先接住情绪再聊事。
3. dialect_preference 越高，天津方言成分越多；为 0 时以标准口语为主，仅略带亲切语气。

【绝对禁令】
1. 不纠正老人记忆对错；不较真时间地点。
2. 不否定、不反驳、不质问老人。
3. 不让老人觉得在考试、测验、背题。
4. 不编造老人没说过经历；不清楚就说「记不清不打紧」。
5. 不给诊断、用药、治疗建议；身体严重不适只建议联系家人或医生。
6. 不用括号表达动作、表情或心理活动（如（微笑）、（叹气）、（点头）、（停顿））；情绪和语气直接融入口语里，别用括号标注。

【核心原则】
情绪优先；认真倾听；尽量关联已知记忆线索；自然带出新话题，不填表式追问。

【个性化配置】
- 方言偏好(0-1): {dialect_preference}
- 回复风格: {response_style}

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
    dialect_preference: float = 0.6,
    response_style: str = "简短温柔",
    sensitive_topics: Optional[List[str]] = None,
    memory_snippets: Optional[List[str]] = None,
    **_: Any,
) -> Dict[str, Any]:
    """
    生成全局 system prompt。

    应用层建议查询:
    - SELECT ... FROM user WHERE user_id = ?
    - SELECT 厌恶/敏感话题 FROM topic_preferences WHERE user_id = ? AND avoid = 1 (字段名以实际表为准)
    - 从 memory_events / daily_records 各取少量摘要拼成 memory_snippets（总长由外层控制）
    """
    topics = sensitive_topics or []
    topics_txt = "、".join(topics[:8]) if topics else "（无）"
    snippets = _clip_list(
        memory_snippets or [],
        CONFIG["max_memory_snippets"],
        CONFIG["max_snippet_chars"],
    )
    content = PROMPT_TEMPLATE.format(
        dialect_preference=dialect_preference,
        response_style=response_style,
        sensitive_topics=topics_txt,
        memory_snippets=snippets,
    )
    return {
        "role": "system",
        "content": content,
        "version": VERSION,
        "priority": PRIORITY,
        "module": "global",
    }
