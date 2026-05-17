"""
本地语音识别文本轻量整理（仅标准库，无额外依赖）。
用于 /api/speech/polish：去空白、压缩口头重复、补基础标点，不改变语义。
"""
from __future__ import annotations

import re
from typing import List

# 句末应加句号的位置（其后仍有内容且当前无标点）
_CLAUSE_BREAK = re.compile(
    r"(?<=[了啦嘛呢吧啊呀哦哈])(?=[^\s。！？；…．.!?\n，,、])"
)
# 连续相同单字重复（嗯嗯嗯、那个那个）保留 1 个
_REPEAT_CHAR = re.compile(r"(.)\1{2,}")
# 连续相同双字词（今天今天）保留 1 个
_REPEAT_BIGRAM = re.compile(r"(.{2})\1+")
_FILLER_SEQ = re.compile(r"((?:嗯|啊|呃|那个|就是|然后){2,})")

_SENTENCE_END = "。！？；…．.!?\n"


def polish_speech_transcript(raw: str) -> str:
    text = raw.strip()
    if not text:
        return text

    text = re.sub(r"\s+", "", text)
    text = _FILLER_SEQ.sub(lambda m: m.group(1)[:2], text)
    text = _REPEAT_BIGRAM.sub(r"\1", text)
    text = _REPEAT_CHAR.sub(r"\1", text)
    text = _insert_clause_commas(text)
    text = _ensure_terminal_punctuation(text)
    return text


def _insert_clause_commas(text: str) -> str:
    parts: List[str] = []
    i = 0
    while i < len(text):
        chunk = text[i:]
        m = _CLAUSE_BREAK.search(chunk)
        if not m:
            parts.append(chunk)
            break
        end = m.end()
        parts.append(chunk[:end])
        if end < len(chunk) and chunk[end] not in "，,、":
            parts.append("，")
        i += end
    return "".join(parts)


def _ensure_terminal_punctuation(text: str) -> str:
    if not text:
        return text
    if text[-1] in _SENTENCE_END:
        return text
    return f"{text}。"
