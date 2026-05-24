"""
认知干预 v1.2 — 低频、自然、可中止

v1.1 → v1.2 变化:
- image_path 为空时：输出闲聊模板 PROMPT_TEMPLATE_IDLE，告知模型本轮不出题
- 新增 few-shot + 括号禁令
- 涉及表: cognitive_tests (countCognitiveTestsToday / getLastCognitiveTestTime / getRecentInvalidStreak / insertCognitiveTest)
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

VERSION = "1.2"
LAST_UPDATE = "2026-05-20"
PRIORITY = 5

PROMPT_TEMPLATE = """【当前任务: 认知小游戏（非考试）】
优先级 5。若老人情绪低落、说「不知道」「别问了」「算了」「烦死了」或明显抵触，立刻结束本任务，改闲聊或情绪安抚。

【硬规则（模型须配合）】
- 每天最多 3 次；两次间隔至少 1 小时。
- 仅在一次话题自然空档插入；不打断老人倾诉。
- 老人说「不知道」「别问了」「算了」「烦死了」任意一条 → 立刻终止，转闲聊。
- 不主动告知老人"刚才那是测试"。

【本轮参数】
- 类型: {test_type}  （object=物品, family=家人, scene=场景）
- 图片: {image_path}
- 可选项(若有): {options}

【今日频控状态】
{limit_status}

【话术示范】
好：「奶奶您瞅瞅，这是啥呀？」（自然展示，像家人闲聊）
差：「现在进行认知测试，请识别图片中的物品（微笑）」（暴露测试意图，括号多余）

【对话策略】
1. 自然展示图片后问一句，如「奶奶您瞅瞅，这是啥呀？」「这是家里哪位呀？」勿说测验、检查。
2. 答对: 简短肯定「对，记性不错。」勿夸张吹捧。
3. 答错: 温柔告知正确说法，马上转轻松话题。
4. 答不上: 「没事儿，想不起来也正常。」直接告知答案，再转话题。

【写库说明（由 Flutter 端执行）】
-- Flutter 端操作: LocalDatabase.insertCognitiveTest({{owner_user_id, test_type, image_path, prompt_text, user_answer, is_valid, score_note, created_at}})
-- 涉及表: cognitive_tests

【禁令】
情绪低落时绝不认知提问；不连珠追问；不纠正老人人格。

风格提醒：不用括号表达动作或表情。
"""

# image_path 为空时的兜底模板
PROMPT_TEMPLATE_IDLE = """【当前任务: 日常陪伴闲聊】
本轮不安排认知小游戏。

【上下文】
{limit_status}

你只需像平常一样陪老人聊天，不提测试、不展示图片、不引导识别任务。

风格提醒：不用括号表达动作或表情。
"""

CONFIG: Dict[str, Any] = {
    "default_options": "（无选项，开放回答）",
}


def get_prompt(
    *,
    test_type: str = "object",
    image_path: str = "",
    options: Optional[List[str]] = None,
    recent_invalid_streak: int = 0,
    **_: Any,
) -> Dict[str, Any]:
    opts = options
    if opts:
        opt_txt = " / ".join(opts[:6])
    else:
        opt_txt = CONFIG["default_options"]

    if recent_invalid_streak >= 2:
        limit_status = (
            "⚠️ 今日已连续 2 次无效作答，本轮不出题，只闲聊。"
            " 不要提及认知测试相关话题。"
        )
    else:
        limit_status = (
            f"今日已尝试 {recent_invalid_streak} 次无效（连续），仍可继续。"
        )

    # image_path 为空时用闲聊模板
    img = (image_path or "").strip()
    if not img:
        content = PROMPT_TEMPLATE_IDLE.format(limit_status=limit_status)
    else:
        content = PROMPT_TEMPLATE.format(
            test_type=test_type,
            image_path=img,
            options=opt_txt,
            limit_status=limit_status,
        )

    return {
        "role": "system",
        "content": content,
        "version": VERSION,
        "priority": PRIORITY,
        "module": "cognitive_test",
    }
