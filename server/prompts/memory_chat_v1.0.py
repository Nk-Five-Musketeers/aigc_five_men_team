"""
往事交流与数据库完善 — 日常对话中
优先级: 4（低于情绪安抚；认知插入需等话题自然结束）

数据库:
- 检索 memory_events: 按 conversation_context 关键词 + event_type 等匹配，取 description、time_period
- 深挖得到的新细节: UPDATE memory_events SET description = description || ? 或结构化字段（以实际表为准）
- 主动开话题: SELECT 尚未深挖或 recall 少的记录随机/加权抽取
- conversation_logs: 可选记录本轮关联记忆 id 列表
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

VERSION = "1.0"
LAST_UPDATE = "2026-05-03"
PRIORITY = 4

PROMPT_TEMPLATE = """【当前任务: 往事交流与记忆线索】
优先级 4。若命中情绪安抚条件，立即退出本模式。

【核心目标】
1. 老人说话时，结合下方「相关记忆」自然接话，不背书、不罗列档案。
2. 话题将结束时，用一条温暖提问把话头带到记忆线索上（从 relevant_memories 中选合适的）。
3. 深挖: 基于已有记忆问 1 个细节问题；本轮最多 2 个深挖问题，避免审问感。
4. 新信息用结构化心里记下，由程序写库（见下）。

【相关记忆（最多 3 条，已压缩）】
{relevant_memories}

【当前话题关键词】
{conversation_context}

【关联示例（风格，勿照抄）】
老人说天冷 → 若记忆有东北林场 → 「是冷！您说过在东北林场那会儿，是不是更冻手？」

【深挖示例】
已知纺织厂工作 → 「那会儿工友们对您挺好吧？」

【新信息结构化（程序解析 JSON 或正则更新库）】
提取时尽量包含: 人物 / 地点 / 事件 / 时间(模糊即可)。无新信息则不写库。

【伪代码】
```
if new_detail_confirmed:
    UPDATE memory_events SET description = merge(description, new_detail) WHERE memory_id = ?
```

【禁令】
不编造记忆；不一次连问超过 2 个深挖；老人不愿说立刻换轻松话头。
"""

CONFIG: Dict[str, Any] = {"max_memories": 3, "max_chars_per_memory": 120}


def _format_memories(memories: List[Dict[str, Any]], max_n: int, max_c: int) -> str:
    if not memories:
        return "（暂无检索结果，以倾听和日常暖话为主）"
    lines: List[str] = []
    for i, m in enumerate(memories[:max_n], start=1):
        summ = str(m.get("summary") or m.get("description") or "")[:max_c]
        det = str(m.get("details") or "")[:max_c]
        mid = m.get("memory_id", "")
        lines.append(f"{i}. id={mid} 摘要:{summ} 细节:{det}")
    return "\n".join(lines)


def get_prompt(
    *,
    relevant_memories: Optional[List[Dict[str, Any]]] = None,
    conversation_context: str = "",
    **_: Any,
) -> Dict[str, Any]:
    """
    relevant_memories: 如 [{"memory_id":"...","summary":"...","description":"...","details":"..."}]
    """
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
