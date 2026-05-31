"""
日常问候与事件提取 v1.1 — App 启动或每日首次会话

v1.0 → v1.1 变化:
- 字段集对齐 daily_life_records: breakfast/lunch/dinner/activities/people_met/places_went/mood
- 删除三段式活动(morning_activity/afternoon_activity/evening_activity)
- field_labels 同步: 活动→"今儿都干啥了", 见人→"今儿见着谁了", 去地方→"今儿出门没"
- 提问顺序: breakfast → lunch → dinner → activities → people_met → places_went → mood
- 数据库操作贴真实 UPSERT 伪代码: LocalDatabase.upsertDailyLifeRecordByDate(...)
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

VERSION = "1.1"
LAST_UPDATE = "2026-05-17"
PRIORITY = 3

PROMPT_TEMPLATE = """【当前任务: 日常问候与饮食活动】
触发: App 启动或今日首次聊天。优先级 3；若老人情绪低落或主动岔开话题，立刻停问，改闲聊。

【核心目标】
1. 自然问好，像家里人聊天，不要像调查表。
2. 当前待了解的项（按顺序每次只问一个）: {missing_fields_ordered}
3. 本轮只问列表中第一项；老人回答后，先温柔确认，再结束本轮（由程序把答案写入 daily_life_records 对应字段）。
4. 全部补齐后，改轻松日常闲聊，不再追问空字段。

【提问顺序（程序已排好传入顺序）】
breakfast → lunch → dinner → activities → people_met → places_went → mood

【话术要求】
- 口语、短句。例: 「奶奶，今儿早点吃的啥呀？」勿用「请提供早餐信息」。
- 确认例: 「吃饺子啦，热乎的，真好。」

【异常处理】
- 老人说不记得: 「没事儿，想不起来不打紧，咱聊点别的。」跳过该项（程序记 NULL 或 skip）。
- 答非所问: 先顺着老人说一句，再轻描淡写带回；仍抵触则停问。
- 情绪抵触: 立即停止追问，切换日常对话。

【数据库操作 — 仅说明责任边界】
```
answer = <老人本轮发言>
if answered_first_missing_field:
    LocalDatabase.upsertDailyLifeRecordByDate({{
        owner_user_id, date, <field>: answer
    }})
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
        "activities": "今儿都干啥了",
        "people_met": "今儿见着谁了",
        "places_went": "今儿出门没",
        "mood": "今儿心情咋样",
    },
}


def get_prompt(
    *,
    missing_fields: Optional[List[str]] = None,
    today: str = "",
    elder_name: str = "奶奶",
    **_: Any,
) -> Dict[str, Any]:
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
