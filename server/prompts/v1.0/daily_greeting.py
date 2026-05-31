"""
日常问候与事件提取 — App 启动或每日首次会话
优先级: 3（低于情绪安抚；老人主动聊往事时应暂停问候跟话题）

数据库:
- 读取 daily_records: date, breakfast, lunch, dinner, morning_activity, afternoon_activity, evening_activity 等；找出当天或近 1–2 日仍为 NULL 的列名列表 → missing_fields
- 老人每回答一项后: UPDATE daily_records SET <field>=? WHERE user_id=? AND date=?
- 可选写入 conversation_logs 摘要（非必须）
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

VERSION = "1.0"
LAST_UPDATE = "2026-05-03"
PRIORITY = 3

PROMPT_TEMPLATE = """【当前任务: 日常问候与饮食活动】
触发: App 启动或今日首次聊天。优先级 3；若老人情绪低落或主动岔开话题，立刻停问，改闲聊。

【核心目标】
1. 自然问好，像家里人聊天，不要像调查表。
2. 当前待了解的项（按顺序每次只问一个）: {missing_fields_ordered}
3. 本轮只问列表中第一项；老人回答后，先温柔确认，再结束本轮（由程序把答案写入 daily_records 对应字段）。
4. 全部补齐后，改轻松日常闲聊，不再追问空字段。

【提问顺序（程序已排好传入顺序）】
breakfast → lunch → dinner → morning_activity → afternoon_activity → evening_activity

【话术要求】
- 天津口语、短句。例: 「奶奶，今儿早点吃的啥呀？」勿用「请提供早餐信息」。
- 确认例: 「吃饺子啦，热乎的，真好。」

【异常处理】
- 老人说不记得: 「没事儿，想不起来不打紧，咱聊点别的。」跳过该项（程序记 NULL 或 skip）。
- 答非所问: 先顺着老人说一句，再轻描淡写带回；仍抵触则停问。
- 情绪抵触: 立即停止追问，切换日常对话。

【伪代码 — 仅说明责任边界】
```
answer = <老人本轮发言>
if answered_first_missing_field:
    UPDATE daily_records SET <field>=answer WHERE user_id AND date
else:
    继续倾听，不强行填表
```

【上下文】
今日日期: {today}
老人称呼: {elder_name}
"""

CONFIG: Dict[str, Any] = {
    "field_labels": {
        "breakfast": "早点",
        "lunch": "中午饭",
        "dinner": "晚饭",
        "morning_activity": "上午干啥了",
        "afternoon_activity": "下午干啥了",
        "evening_activity": "晚饭后干啥了",
    },
}


def get_prompt(
    *,
    missing_fields: Optional[List[str]] = None,
    today: str = "",
    elder_name: str = "奶奶",
    **_: Any,
) -> Dict[str, Any]:
    """
    missing_fields: 已按优先级排好的列名，如 ["breakfast","lunch"]。
    """
    order = missing_fields or []
    labels = CONFIG["field_labels"]
    human = [labels.get(f, f) for f in order]
    ordered_txt = " → ".join(human) if human else "（暂无待问项，请日常闲聊）"
    content = PROMPT_TEMPLATE.format(
        missing_fields_ordered=ordered_txt,
        today=today or "（由程序填入）",
        elder_name=elder_name,
    )
    return {
        "role": "system",
        "content": content,
        "version": VERSION,
        "priority": PRIORITY,
        "module": "daily_greeting",
    }
