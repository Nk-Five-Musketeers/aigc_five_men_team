"""
往事交流与数据库完善 v1.1 — 日常对话中

v1.0 → v1.1 变化:
- 相关记忆数据口径明确: Flutter 端检索 memory_events 按 importance DESC, last_used ASC NULLS FIRST 取 top 3
- 入参 relevant_memories 字段标准化为 {id, title, description, event_time, location, people_involved}
- 模型引用记忆后由 Flutter 端调用 LocalDatabase.touchMemoryEventUsage(eventId)
- 提取新信息写库由 chat_repository.dart 的 extractFullMemoryFromChat 已在做, prompt 仅强调"自然引导,不要审问"
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

VERSION = "1.1"
LAST_UPDATE = "2026-05-17"
PRIORITY = 4

PROMPT_TEMPLATE = """【当前任务: 往事交流与记忆线索】
优先级 4。若命中情绪安抚条件，立即退出本模式。

【核心目标】
1. 老人说话时，结合下方「相关记忆」自然接话，不背书、不罗列档案。
2. 话题将结束时，用一条温暖提问把话头带到记忆线索上（从 relevant_memories 中选合适的）。
3. 深挖: 基于已有记忆问 1 个细节问题；本轮最多 2 个深挖问题，避免审问感。
4. 新信息自然引导老人说出，由程序写库——不要审问式提取。

【相关记忆（最多 3 条，已压缩；按重要度降序、越久没用越优先）】
{relevant_memories}

【当前话题关键词】
{conversation_context}

【关联示例（风格，勿照抄）】
老人说天冷 → 若记忆有东北林场 → 「是冷！您说过在东北林场那会儿，是不是更冻手？」

【深挖示例】
已知纺织厂工作 → 「那会儿工友们对您挺好吧？」

【禁令】
不编造记忆；不一次连问超过 2 个深挖；老人不愿说立刻换轻松话头。
"""

CONFIG: Dict[str, Any] = {"max_memories": 3, "max_chars_per_memory": 120}


def _format_memories(memories: List[Dict[str, Any]], max_n: int, max_c: int) -> str:
    if not memories:
        return "（暂无检索结果，以倾听和日常暖话为主）"
    lines: List[str] = []
    for i, m in enumerate(memories[:max_n], start=1):
        title = str(m.get("title") or "")[:max_c]
        desc = str(m.get("description") or "")[:max_c]
        event_time = str(m.get("event_time") or "")
        location = str(m.get("location") or "")
        people = str(m.get("people_involved") or "")
        mid = m.get("id", "")
        parts = [f"id={mid}"]
        if event_time:
            parts.append(f"时间:{event_time}")
        if title:
            parts.append(f"摘要:{title}")
        if desc:
            parts.append(f"细节:{desc}")
        if location:
            parts.append(f"地点:{location}")
        if people:
            parts.append(f"人物:{people}")
        lines.append(f"{i}. {' | '.join(parts)}")
    return "\n".join(lines)


def get_prompt(
    *,
    relevant_memories: Optional[List[Dict[str, Any]]] = None,
    conversation_context: str = "",
    **_: Any,
) -> Dict[str, Any]:
    mem = _format_memories(
        relevant_memories or [],
        CONFIG["max_memories"],
        CONFIG["max_chars_per_memory"],
    )
    content = PROMPT_TEMPLATE.format(
        relevant_memories=mem,
        conversation_context=conversation_context or "（空）",
    )
    return {
        "role": "system",
        "content": content,
        "version": VERSION,
        "priority": PRIORITY,
        "module": "memory_chat",
    }
