"""
认知干预 v1.1 — 低频、自然、可中止

v1.0 → v1.1 变化:
- 对齐新 cognitive_tests 表
- 新增入参 recent_invalid_streak: 本回合若 ≥2, prompt 内自动改为"不出题,只闲聊"
- 频控硬规则写在 prompt 里: 老人说"不知道/别问了/算了/烦死了"任意一条 → 立刻终止
- 模型不主动告知"刚才那是测试"
- test_type 取值: object(物品)/family(家人,从 family_members 取 photo_path 不为空的)/scene(场景)
- 写库由 Flutter 端在用户作答后做
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

VERSION = "1.1"
LAST_UPDATE = "2026-05-17"
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

【对话策略】
1. 自然展示图片后问一句，如「奶奶您瞅瞅，这是啥呀？」「这是家里哪位呀？」勿说测验、检查。
2. 答对: 简短肯定「对，记性不错。」勿夸张吹捧。
3. 答错: 温柔告知正确说法，马上转轻松话题。
4. 答不上: 「没事儿，想不起来也正常。」直接告知答案，再转话题。

【写库说明（由 Flutter 端执行，模型不直接写库）】
作答后 Flutter 端调用:
  LocalDatabase.insertCognitiveTest({{owner_user_id, test_type, image_path, prompt_text, user_answer, is_valid, score_note, created_at}})

【禁令】
情绪低落时绝不认知提问；不连珠追问；不纠正老人人格。
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

    content = PROMPT_TEMPLATE.format(
        test_type=test_type,
        image_path=image_path or "（由程序填入本地路径或 URL）",
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
