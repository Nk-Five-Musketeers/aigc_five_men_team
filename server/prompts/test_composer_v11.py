"""
prompt_composer v1.1 与服务端 prompt 模块的冒烟测试。

用法:
    cd server/prompts
    python -m pytest test_composer_v11.py -v
    或
    python test_composer_v11.py
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


# 按需加载各模块
_gp11 = _load("global_prompt_v1.1.py")
_dg11 = _load("daily_greeting_v1.1.py")
_mc11 = _load("memory_chat_v1.1.py")
_ct11 = _load("cognitive_test_v1.1.py")
_es11 = _load("emotion_support_v1.1.py")


class TestV11Modules(unittest.TestCase):
    """验证各 v1.1 模块 get_prompt 不抛异常且返回正确的结构。"""

    def test_global_prompt_v11_default(self):
        result = _gp11.get_prompt()
        self.assertEqual(result["role"], "system")
        self.assertIn("晚辈家人", result["content"])
        self.assertEqual(result["version"], "1.1")
        self.assertEqual(result["priority"], 0)
        self.assertEqual(result["module"], "global")

    def test_global_prompt_v11_with_params(self):
        result = _gp11.get_prompt(
            dialect="四川话",
            sensitive_topics=["老伴去世", "身体疾病"],
            memory_snippets=["东北林场工作", "纺织厂女工"],
            elder_profile_brief="王阿姨，生于1952，籍贯天津，职业教师",
        )
        self.assertIn("四川话", result["content"])
        self.assertIn("老伴去世", result["content"])
        self.assertIn("东北林场工作", result["content"])
        self.assertIn("王阿姨", result["content"])

    def test_global_prompt_v11_backward_compat(self):
        import warnings

        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            result = _gp11.get_prompt(dialect_preference=0.8, response_style="详细耐心")
            self.assertEqual(result["version"], "1.1")
            self.assertTrue(any("dialect_preference" in str(x.message) for x in w))
            self.assertTrue(any("response_style" in str(x.message) for x in w))

    def test_daily_greeting_v11(self):
        result = _dg11.get_prompt(
            missing_fields=["breakfast", "lunch"],
            today="2026-05-17",
            elder_name="奶奶",
        )
        self.assertEqual(result["version"], "1.1")
        self.assertEqual(result["priority"], 3)
        self.assertIn("早点", result["content"])
        self.assertIn("中午饭", result["content"])
        self.assertNotIn("morning_activity", result["content"])

    def test_daily_greeting_v11_all_filled(self):
        result = _dg11.get_prompt(missing_fields=[])
        self.assertIn("暂无待问项", result["content"])

    def test_memory_chat_v11(self):
        result = _mc11.get_prompt(
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
        self.assertEqual(result["version"], "1.1")
        self.assertIn("东北林场工作", result["content"])
        self.assertIn("黑龙江", result["content"])

    def test_memory_chat_v11_empty_memories(self):
        result = _mc11.get_prompt(relevant_memories=[])
        self.assertIn("暂无检索结果", result["content"])

    def test_cognitive_test_v11(self):
        result = _ct11.get_prompt(
            test_type="object",
            image_path="/photos/apple.jpg",
            recent_invalid_streak=0,
        )
        self.assertEqual(result["version"], "1.1")
        self.assertIn("仍可继续", result["content"])

    def test_cognitive_test_v11_streak_limit(self):
        result = _ct11.get_prompt(recent_invalid_streak=2)
        self.assertIn("不出题", result["content"])
        self.assertIn("只闲聊", result["content"])

    def test_emotion_support_v11(self):
        result = _es11.get_prompt(
            emotion_type="sad",
            trigger_content="我有点想她了",
            trigger_keywords=["想她", "难受"],
            positive_topics=["东北林场", "纺织厂", "唱歌"],
        )
        self.assertEqual(result["version"], "1.1")
        self.assertEqual(result["priority"], 1)
        self.assertIn("内部线索", result["content"])
        self.assertIn("想她", result["content"])
        self.assertIn("东北林场", result["content"])

    def test_emotion_support_v11_no_keywords(self):
        result = _es11.get_prompt(trigger_keywords=[])
        self.assertIn("无具体关键词", result["content"])


class TestComposerV11(unittest.TestCase):
    """验证 composer v1.1 组装逻辑。"""

    @classmethod
    def setUpClass(cls):
        from prompt_composer import compose_for_request, compose_system_prompt

        cls.compose_system_prompt = staticmethod(compose_system_prompt)
        cls.compose_for_request = staticmethod(compose_for_request)

    def test_compose_default_v11(self):
        result = self.compose_system_prompt()
        self.assertEqual(result["role"], "system")
        self.assertIn("v1.1", result["prompt_meta"]["version"])
        self.assertIn("晚辈家人", result["content"])

    def test_compose_with_emotion_support(self):
        result = self.compose_system_prompt(
            active_task="emotion_support",
            task_params={"emotion_type": "sad", "trigger_content": "难受"},
        )
        self.assertIn("情绪安抚", result["content"])

    def test_compose_with_memory_chat(self):
        result = self.compose_system_prompt(
            active_task="memory_chat",
            task_params={"conversation_context": "天冷"},
        )
        self.assertIn("往事交流", result["content"])

    def test_compose_v10_fallback(self):
        result = self.compose_system_prompt(version="v1.0")
        self.assertEqual(result["prompt_meta"]["version"], "v1.0")

    def test_compose_invalid_version(self):
        with self.assertRaises(ValueError):
            self.compose_system_prompt(version="v9.9")

    def test_compose_budget_truncation(self):
        long_snippets = ["X" * 2000]
        result = self.compose_system_prompt(
            global_params={"memory_snippets": long_snippets, "dialect": "天津话"},
        )
        content_len = len(result["content"])
        max_chars = 2400
        self.assertLessEqual(content_len, max_chars + 10)

    def test_compose_for_request_full_context(self):
        ctx = {
            "global": {
                "dialect": "天津话",
                "sensitive_topics": ["疾病"],
                "memory_snippets": ["记忆1"],
                "elder_profile_brief": "王阿姨，天津人",
            },
            "active_task": "memory_chat",
            "task": {"conversation_context": "天冷"},
        }
        result = self.compose_for_request(ctx)
        self.assertEqual(result["role"], "system")
        self.assertIn("王阿姨", result["content"])
        self.assertIn("往事交流", result["content"])

    def test_compose_for_request_memory_context_fallback(self):
        ctx = {"global": {"dialect": "天津话"}}
        result = self.compose_for_request(ctx, memory_context=["记忆A", "记忆B"])
        self.assertIn("记忆A", result["content"])


if __name__ == "__main__":
    unittest.main()
