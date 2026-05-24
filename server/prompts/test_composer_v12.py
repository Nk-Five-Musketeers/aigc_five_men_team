"""
prompt_composer v1.2 与服务端 prompt 模块的冒烟测试。

用法:
    cd server/prompts
    python -m pytest test_composer_v12.py -v
    或
    python test_composer_v12.py
"""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from typing import Any

_DIR = Path(__file__).resolve().parent
if str(_DIR) not in sys.path:
    sys.path.insert(0, str(_DIR))


def _load(filename: str) -> Any:
    """用 importlib 加载含点号的文件名模块。"""
    path = _DIR / filename
    if not path.is_file():
        raise FileNotFoundError(path)
    mod_name = "_test_" + filename.replace(".py", "").replace(".", "_")
    spec = importlib.util.spec_from_file_location(mod_name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# 按需加载各 v1.2 模块
_gp12 = _load("global_prompt_v1.2.py")
_dg12 = _load("daily_greeting_v1.2.py")
_mc12 = _load("memory_chat_v1.2.py")
_ct12 = _load("cognitive_test_v1.2.py")
_es12 = _load("emotion_support_v1.2.py")


class TestV12Modules(unittest.TestCase):
    """验证各 v1.2 模块 get_prompt 不抛异常且返回正确的结构。"""

    def test_global_prompt_v12_default(self):
        result = _gp12.get_prompt()
        self.assertEqual(result["role"], "system")
        self.assertIn("晚辈家人", result["content"])
        self.assertEqual(result["version"], "1.2")
        self.assertEqual(result["priority"], 0)
        self.assertEqual(result["module"], "global")

    def test_global_prompt_v12_bracket_ban_first(self):
        """括号禁令应为第 1 条且在正文中。"""
        result = _gp12.get_prompt()
        content = result["content"]
        ban_idx = content.find("不用括号表达动作")
        correct_idx = content.find("不纠正老人记忆")
        self.assertGreater(ban_idx, 0)
        self.assertGreater(correct_idx, ban_idx, "括号禁令应在记忆禁令之前")

    def test_global_prompt_v12_bracket_examples(self):
        """括号禁令需包含正确/错误对照示例。"""
        result = _gp12.get_prompt()
        self.assertIn("（微笑）", result["content"])
        self.assertIn("我看着就高兴", result["content"])

    def test_global_prompt_v12_with_params(self):
        result = _gp12.get_prompt(
            dialect="四川话",
            sensitive_topics=["老伴去世"],
            elder_profile_brief="王阿姨，生于1952，籍贯天津，职业教师",
        )
        self.assertIn("四川话", result["content"])
        self.assertIn("老伴去世", result["content"])
        self.assertIn("王阿姨", result["content"])
        # memory_snippets 不再在 global 模板中
        self.assertNotIn("可自然提及的压缩记忆摘要", result["content"])

    def test_global_prompt_v12_ignores_old_params(self):
        """向后兼容旧入参但不报错。"""
        result = _gp12.get_prompt(
            dialect_preference=0.8,
            response_style="详细耐心",
            memory_snippets=["旧格式传入的记忆"],
        )
        self.assertEqual(result["version"], "1.2")

    def test_daily_greeting_v12(self):
        result = _dg12.get_prompt(
            missing_fields=["breakfast", "lunch"],
            today="2026-05-20",
            elder_name="奶奶",
        )
        self.assertEqual(result["version"], "1.2")
        self.assertEqual(result["priority"], 3)
        self.assertIn("早点", result["content"])
        self.assertIn("中午饭", result["content"])
        self.assertIn("不用括号表达动作", result["content"])

    def test_daily_greeting_v12_all_filled(self):
        result = _dg12.get_prompt(missing_fields=[])
        self.assertIn("暂无待问项", result["content"])

    def test_daily_greeting_v12_db_comment(self):
        result = _dg12.get_prompt(missing_fields=["breakfast"])
        self.assertIn("Flutter 端操作", result["content"])
        self.assertIn("daily_life_records", result["content"])

    def test_memory_chat_v12(self):
        result = _mc12.get_prompt(
            relevant_memories=[
                {
                    "id": 1,
                    "title": "东北林场工作",
                    "description": "冬天很冷",
                    "event_time": "1970年代",
                    "location": "黑龙江",
                    "people_involved": "老王",
                },
            ],
            conversation_context="天冷",
        )
        self.assertEqual(result["version"], "1.2")
        self.assertIn("东北林场工作", result["content"])
        self.assertIn("黑龙江", result["content"])
        self.assertIn("不用括号表达动作", result["content"])

    def test_memory_chat_v12_fewshot(self):
        result = _mc12.get_prompt()
        self.assertIn("话术示范", result["content"])
        self.assertIn("冻手吧", result["content"])

    def test_memory_chat_v12_empty_memories(self):
        result = _mc12.get_prompt(relevant_memories=[])
        self.assertIn("暂无检索结果", result["content"])

    def test_cognitive_test_v12(self):
        result = _ct12.get_prompt(
            test_type="object",
            image_path="/photos/apple.jpg",
            recent_invalid_streak=0,
        )
        self.assertEqual(result["version"], "1.2")
        self.assertIn("仍可继续", result["content"])
        self.assertIn("不用括号表达动作", result["content"])

    def test_cognitive_test_v12_streak_limit(self):
        result = _ct12.get_prompt(recent_invalid_streak=2)
        self.assertIn("不出题", result["content"])
        self.assertIn("只闲聊", result["content"])

    def test_cognitive_test_v12_empty_image(self):
        """image_path 为空时应输出闲聊模板。"""
        result = _ct12.get_prompt(
            test_type="object",
            image_path="",
            recent_invalid_streak=0,
        )
        self.assertIn("日常陪伴闲聊", result["content"])
        self.assertIn("不安排认知小游戏", result["content"])
        self.assertNotIn("本轮参数", result["content"])

    def test_cognitive_test_v12_fewshot(self):
        result = _ct12.get_prompt(image_path="/test.jpg")
        self.assertIn("话术示范", result["content"])

    def test_emotion_support_v12(self):
        result = _es12.get_prompt(
            emotion_type="sad",
            trigger_content="我有点想她了",
            trigger_keywords=["想她", "难受"],
            positive_topics=["东北林场", "纺织厂", "唱歌"],
        )
        self.assertEqual(result["version"], "1.2")
        self.assertEqual(result["priority"], 1)
        self.assertIn("内部线索", result["content"])
        self.assertIn("想她", result["content"])
        self.assertIn("东北林场", result["content"])
        self.assertIn("不用括号表达动作", result["content"])

    def test_emotion_support_v12_db_source(self):
        result = _es12.get_prompt(positive_topics=["测试"])
        self.assertIn("memory_events", result["content"])
        self.assertIn("emotion IN", result["content"])

    def test_emotion_support_v12_no_keywords(self):
        result = _es12.get_prompt(trigger_keywords=[])
        self.assertIn("无具体关键词", result["content"])


class TestComposerV12(unittest.TestCase):
    """验证 composer v1.2 组装逻辑。"""

    @classmethod
    def setUpClass(cls):
        from prompt_composer import compose_for_request, compose_system_prompt

        cls.compose_system_prompt = staticmethod(compose_system_prompt)
        cls.compose_for_request = staticmethod(compose_for_request)

    def test_compose_default_v12(self):
        result = self.compose_system_prompt()
        self.assertEqual(result["role"], "system")
        self.assertIn("v1.2", result["prompt_meta"]["version"])
        self.assertIn("晚辈家人", result["content"])

    def test_compose_with_emotion_support_v12(self):
        result = self.compose_system_prompt(
            active_task="emotion_support",
            task_params={"emotion_type": "sad", "trigger_content": "难受"},
        )
        self.assertIn("情绪安抚", result["content"])

    def test_compose_with_memory_chat_v12(self):
        result = self.compose_system_prompt(
            active_task="memory_chat",
            task_params={"conversation_context": "天冷"},
        )
        self.assertIn("往事交流", result["content"])

    def test_compose_memory_block_independent(self):
        """memory_snippets 应作为独立 block 出现在内容中。"""
        result = self.compose_system_prompt(
            memory_snippets=["东北林场工作，冬天很冷"],
        )
        self.assertIn("可自然提及的压缩记忆摘要", result["content"])
        self.assertIn("东北林场工作", result["content"])
        # 验证 meta 中有 memory 模块
        modules = [m["module"] for m in result["prompt_meta"]["modules"]]
        self.assertIn("memory", modules)

    def test_compose_memory_budget_enforced(self):
        """超长 memory_snippets 应被截断到 budget_memory 内。"""
        long_snippet = "很长的记忆内容" * 80  # ~800 chars
        result = self.compose_system_prompt(
            memory_snippets=[long_snippet, long_snippet],
        )
        # memory block 不应超过 budget_memory (300 chars)
        content = result["content"]
        memory_start = content.find("可自然提及的压缩记忆摘要")
        if memory_start >= 0:
            memory_part = content[memory_start:]
            self.assertLessEqual(len(memory_part), 350)  # 留一点余量给 "…"

    def test_compose_v11_backward_compat(self):
        """v1.1 仍可正常使用。"""
        result = self.compose_system_prompt(version="v1.1")
        self.assertEqual(result["prompt_meta"]["version"], "v1.1")

    def test_compose_v10_backward_compat(self):
        """v1.0 仍可正常使用。"""
        result = self.compose_system_prompt(version="v1.0")
        self.assertEqual(result["prompt_meta"]["version"], "v1.0")

    def test_compose_invalid_version(self):
        with self.assertRaises(ValueError):
            self.compose_system_prompt(version="v9.9")

    def test_compose_budget_truncation(self):
        long_snippets = ["X" * 2000]
        result = self.compose_system_prompt(
            global_params={"dialect": "天津话"},
            memory_snippets=long_snippets,
        )
        content_len = len(result["content"])
        max_chars = 2400
        self.assertLessEqual(content_len, max_chars + 10)

    def test_compose_for_request_new_format(self):
        """v1.2 新格式: memory_snippets 在顶层。"""
        ctx = {
            "global": {
                "dialect": "天津话",
                "sensitive_topics": ["疾病"],
                "elder_profile_brief": "王阿姨，天津人",
            },
            "memory_snippets": ["东北林场工作"],
            "active_task": "memory_chat",
            "task": {"conversation_context": "天冷"},
        }
        result = self.compose_for_request(ctx)
        self.assertEqual(result["role"], "system")
        self.assertIn("王阿姨", result["content"])
        self.assertIn("往事交流", result["content"])
        self.assertIn("东北林场工作", result["content"])

    def test_compose_for_request_old_format(self):
        """向后兼容: memory_snippets 在 global 内。"""
        ctx = {
            "global": {
                "dialect": "天津话",
                "memory_snippets": ["旧格式记忆"],
                "elder_profile_brief": "王阿姨",
            },
        }
        result = self.compose_for_request(ctx)
        # global 内 memory_snippets 应被提取到独立 memory block
        self.assertIn("旧格式记忆", result["content"])

    def test_compose_for_request_memory_context_fallback(self):
        ctx = {"global": {"dialect": "天津话"}}
        result = self.compose_for_request(ctx, memory_context=["兜底记忆A", "兜底记忆B"])
        self.assertIn("兜底记忆A", result["content"])


class TestLazyLoading(unittest.TestCase):
    """验证懒加载正确性。"""

    def test_lazy_load_cache_hit(self):
        """二次调用应命中缓存，不重复加载。"""
        from prompt_composer import _MODULE_CACHE, compose_system_prompt

        # 清空缓存
        _MODULE_CACHE.clear()

        # 第一次调用 — 触发加载
        result1 = compose_system_prompt(version="v1.2")
        cache_size1 = len(_MODULE_CACHE)
        self.assertGreater(cache_size1, 0, "首次调用应将加载结果缓存")

        # 第二次调用 — 应命中缓存
        result2 = compose_system_prompt(version="v1.2")
        self.assertEqual(len(_MODULE_CACHE), cache_size1, "二次调用不应新增缓存条目")

        self.assertEqual(result1["content"], result2["content"])


if __name__ == "__main__":
    unittest.main()
