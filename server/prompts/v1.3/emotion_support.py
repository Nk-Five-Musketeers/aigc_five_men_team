"""
情绪安抚 v1.3 — 最高优先级

v1.2 → v1.3 变化:
- 删除末尾"风格提醒"行（统一由 composer 尾部处理）；其他内容不变
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

VERSION = "1.3"
LAST_UPDATE = "2026-05-22"
PRIORITY = 1

PROMPT_TEMPLATE = """【当前任务: 情绪安抚 — 最高优先级】
立即暂停: 认知提问、日常填表式问候、往事深挖追问。全心全意陪老人把情绪稳住。

【内部线索 — 不复述给老人】
- 命中关键词: {trigger_keywords}
- 情绪类型: {emotion_type}
- 触发原话摘要: {trigger_content}
以上仅供你判断情绪强度，**禁止**直接复读这些词给老人。

【三步结构】
1. 共情倾听: 先承认感受，短句，不说教、不讲大道理。例: 「我听出来您心里不得劲儿。」
2. 温柔陪伴: 「没事儿，我在这儿陪您待会儿。」
3. 缓慢转暖: 从下方「开心线索」里挑一条自然提起，不硬拗；老人不想聊就安静陪一会儿。

【开心线索（已压缩，来自老人正向记忆）】
-- 数据源: Flutter 端从 memory_events 表查询
--   SELECT title, description FROM memory_events
--   WHERE owner_user_id = ? AND (emotion IN ('开心','喜悦','满足') OR importance >= 4)
--   ORDER BY importance DESC LIMIT 4
{positive_topics}

【接下来约 1 小时内】
不安排认知干预；少追问；多倾听、多肯定；话题以轻松、熟悉、安全为主。

【禁忌】
不否定情绪（「别想多了」）；不急于解决；不突然扯远亲八卦刺激老人；不用医学建议替代陪伴。
"""

CONFIG: Dict[str, Any] = {"max_positive_lines": 4, "max_line_chars": 60}


def _lines(items: Optional[List[str]], max_n: int, max_c: int) -> str:
    if not items:
        return "（暂无偏好数据，用天气、轻松日常、慢节奏陪伴）"
    out: List[str] = []
    for i, s in enumerate(items[:max_n], start=1):
        t = (s or "").strip().replace("\n", " ")
        if len(t) > max_c:
            t = t[: max_c - 1] + "…"
        out.append(f"{i}. {t}")
    return "\n".join(out)


def get_prompt(
    *,
    emotion_type: str = "sad",
    trigger_content: str = "",
    trigger_keywords: Optional[List[str]] = None,
    positive_topics: Optional[List[str]] = None,
    **_: Any,
) -> Dict[str, Any]:
    keywords = trigger_keywords or []
    kw_txt = "、".join(keywords[:10]) if keywords else "（无具体关键词）"
    pos = _lines(
        positive_topics,
        CONFIG["max_positive_lines"],
        CONFIG["max_line_chars"],
    )
    content = PROMPT_TEMPLATE.format(
        emotion_type=emotion_type,
        trigger_content=(trigger_content or "（无）")[:200],
        trigger_keywords=kw_txt,
        positive_topics=pos,
    )
    return {
        "role": "system",
        "content": content,
        "version": VERSION,
        "priority": PRIORITY,
        "module": "emotion_support",
    }
