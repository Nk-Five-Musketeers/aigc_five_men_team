"""
认知干预 — 低频、自然、可中止
优先级: 5（最低；情绪安抚与老人抵触时绝对不做）

数据库:
- 读 family_relations: name, relationship, photo_path → 亲属识别题
- 读 cognitive_tests: 历史正确率/难度 → 调整题目难度与停做规则
- 写 cognitive_tests: 题目类型、展示图、老人回答、是否有效、时间戳
- conversation_logs: 可选
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

VERSION = "1.0"
LAST_UPDATE = "2026-05-03"
PRIORITY = 5

PROMPT_TEMPLATE = """【当前任务: 认知小游戏（非考试）】
优先级 5。若老人情绪低落、说「不知道」「别问了」或明显抵触，立刻结束本任务，改闲聊或情绪安抚。

【硬规则（程序已做部分校验，模型须配合）】
- 每天最多 3 次；两次间隔至少 1 小时；连续 2 次无效/失败则当天不再认知提问。
- 仅在一次话题自然空档插入；不打断老人倾诉。

【本轮参数】
- 类型: {test_type}  （object=物品, family=家人, scene=场景）
- 图片: {image_path}
- 可选项(若有): {options}

【对话策略】
1. 自然展示图片后问一句，如「奶奶您瞅瞅，这是啥呀？」「这是家里哪位呀？」勿说测验、检查。
2. 答对: 简短肯定「对，记性不错。」勿夸张吹捧。
3. 答错: 温柔告知正确说法，马上转轻松话题。
4. 答不上: 「没事儿，想不起来也正常。」直接告知答案，再转话题。

【有效回答判定（程序主判，模型辅助描述）】
有效: 直接答、犹豫但尝试、要提示。
无效: 转移话题、抵触、长时间沉默——立即停止认知题。

【写库说明（伪代码）】
```
INSERT INTO cognitive_tests (user_id, test_type, image_path, user_answer, is_valid, score_note, created_at)
```

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
    **_: Any,
) -> Dict[str, Any]:
    opts = options
    if opts:
        opt_txt = " / ".join(opts[:6])
    else:
        opt_txt = CONFIG["default_options"]
    content = PROMPT_TEMPLATE.format(
        test_type=test_type,
        image_path=image_path or "（由程序填入本地路径或 URL）",
        options=opt_txt,
    )
    return {
        "role": "system",
        "content": content,
        "version": VERSION,
        "priority": PRIORITY,
        "module": "cognitive_test",
    }
