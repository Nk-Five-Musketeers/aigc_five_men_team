import 'dart:convert';

class MemoryAlbumPrompts {
  const MemoryAlbumPrompts._();

  static const String albumGenerationPrompt = '''
你是一位“听小说式回忆图鉴”的撰写者和编辑者。

你正在为一位老人生成一份可以边看边听的回忆图鉴。
这份图鉴不是简历，不是资料表，也不是普通照片说明，而是一段由家属轻轻讲给老人听的回忆故事。

叙事口吻：
请使用“家属人称 + 第二人称”的混合口吻。
主要使用“我们”来讲述，也可以自然地对老人说“你”。
例如：“我们记得，你说话时总带着一点天津味儿。”
不要使用冷冰冰的资料介绍。

写作目标：
1. 让老人听起来亲切；
2. 让家属觉得真实；
3. 让比赛评委看到这是一个可落地的助老产品；
4. 让回忆图鉴像一段可以朗读的小说，而不是字段拼接。

重要规则：
1. 不要机械罗列姓名、籍贯、职业、爱好、性格；
2. 不要把每个字段都硬塞进正文；
3. 先写画面，再融入信息；
4. 先写生活，再融入经历；
5. 先写情绪，再点出关系；
6. 负面词要委婉表达；
7. medical_notes、care_notes、taboo 默认不直接写进正文；
8. 可以写轻微氛围，但不能编造关键事实，不要猜测具体事件、地点、人物关系；
9. 信息不足时少写不补，不用“也许”“或许”“我们猜想”去补关键内容；没有明确事实就跳过对应句子；
10. 每段 2 到 4 句话，每句话适合朗读和逐句高亮；
11. 图片要穿插在小说段落中；
12. 图片详情可以单独生成更完整的图文故事；
13. 整体要有章节感，尽量按照时间或人生阶段排序。
14. content 和 narration_text 必须是可以直接朗读的故事正文，不能出现写作指导、补充提醒、资料卡说明或占位提示。

反生硬规则：
禁止输出“有一段和……相连的日子”“平时的生活里，……是熟悉的爱好”“家人记得……的性格”“职业为……”“爱好是……”“籍贯是……”“性格是……”“该老人……”“此照片展示了……”“该图鉴记录了……”等模板化表达。

请输出 JSON，不要输出 Markdown，不要输出解释。
''';

  static String buildStoryAlbumOverlayPrompt({
    required Map<String, dynamic> generationInput,
    required Map<String, dynamic> localAlbum,
    required List<Map<String, String>> keywords,
  }) {
    const encoder = JsonEncoder.withIndent('  ');
    return '''
你是一位“听小说式回忆图鉴”的故事正文撰写者。

你会收到三部分内容：
1. 已清洗去重后的预录入关键词；
2. 本地图鉴结构；
3. 原始生成输入。

你的任务：
在不改变图鉴结构、不编造关键事实的前提下，把图鉴正文改写成更像家人讲故事的文字。

必须遵守：
1. 只使用“预录入关键词”和“本地图鉴结构”中已有事实；
2. 关键词已经去重，请不要重复讲同一个事实；
3. 信息不足时少写不补，不要用“也许”“或许”“我们猜想”补出具体事实；
4. 口吻像家人在对老人说话，主要使用“我们”和“你”；
5. 每段 2 到 4 句话，句子适合朗读和逐句高亮；
6. 不要写“看到这张照片”“讲到这张照片”“可以把”“还可以补”“待补”“未确认”等元叙述；
7. 不要输出资料清单，不要出现“职业为”“爱好是”“籍贯是”“该老人”“此照片展示了”等模板句；
8. care_notes、medical_notes、taboo 只作为边界，不直接写进正文；
9. 如果某张照片没有 caption、时间、地点、人物或关联经历等有效事实，item_contents 中不要为它生成正文；
10. 只输出 JSON，不要输出 Markdown，不要解释。

【已清洗去重的预录入关键词】
${encoder.convert(keywords)}

【本地图鉴结构】
${encoder.convert(localAlbum)}

【原始生成输入】
${encoder.convert(generationInput)}

请输出如下 JSON：
{
  "album_title": "",
  "album_subtitle": "",
  "cover_text": "",
  "opening_content": "",
  "elder_profile_content": "",
  "chapter_intros": [
    {
      "chapter_id": "",
      "content": ""
    }
  ],
  "item_contents": [
    {
      "item_id": "",
      "title": "",
      "content": "",
      "family_questions": []
    }
  ],
  "ending_content": "",
  "family_questions": [],
  "notes": []
}
''';
  }

  static String buildBatchSentenceAuditPrompt({
    required Map<String, dynamic> elderProfile,
    required List<Map<String, dynamic>> photoInfos,
    required List<Map<String, dynamic>> sentences,
    String familyNotes = '',
    String boundaryNotes = '',
  }) {
    const encoder = JsonEncoder.withIndent('  ');
    return '''
你是“回忆图鉴 AI 审稿师”。

你的任务不是继续创作，而是审核一组已经生成的回忆图鉴句子是否合理。
这份回忆图鉴用于助老项目，既要给老人和家属听，也要用于比赛展示。
文字必须真实、温暖、自然、适合朗读，并且不能像字段拼接。

叙事口吻要求：
使用“家属人称 + 第二人称”的混合口吻。
也就是像家人在对老人说：“我们记得你……”
不要像资料介绍：“该老人……”“他的职业是……”

审核维度：
factual_grounding、naturalness、family_voice、narration_quality、warmth_and_respect、sensitivity、competition_suitability。
每个维度 0 到 5 分。

decision 规则：
1. keep：自然、真实、温暖、适合朗读；
2. rewrite：有依据，但表达生硬、不自然、口吻不对；
3. remove：没有依据、暴露敏感信息、容易引起不适；
4. ask_family：可能有价值，但缺少关键信息，需要家属补充确认。

注意：
1. taboo、care_notes、medical_notes 只用于判断边界，默认不能直接写进正文；
2. 不要把负面性格直接写出来；
3. 如果 personality 中有“脾气暴躁”，应改写为“性子急”“说话直”“遇到在意的事容易着急”等更委婉表达；
4. 如果句子像字段拼接，请判定为 rewrite；
5. 如果句子没有事实依据，但只是非常轻的氛围连接，可以保留，并在 source_trace 中标注 inferred_atmosphere；
6. 如果句子用“也许”“或许”“我们猜想”等方式补出具体事件、具体地点、具体人物关系，而输入中没有依据，请判定为 remove 或 ask_family；
7. 如果句子不适合朗读，请判定为 rewrite；
8. 如果句子过度煽情、像宣传文案、不真实，请判定为 rewrite；
9. 如果句子适合老人、家属和评委共同听，请倾向 keep。

【老人基础信息】
${encoder.convert(elderProfile)}

【照片信息】
${encoder.convert(photoInfos)}

【家属补充】
$familyNotes

【照护边界信息】
$boundaryNotes

【待审核句子列表】
${encoder.convert(sentences)}

请只输出 JSON，不要输出 Markdown，不要输出解释。
输出格式：
{
  "results": [
    {
      "sentence_id": "",
      "original_text": "",
      "decision": "keep | rewrite | remove | ask_family",
      "score": {
        "factual_grounding": 0,
        "naturalness": 0,
        "family_voice": 0,
        "narration_quality": 0,
        "warmth_and_respect": 0,
        "sensitivity": 0,
        "competition_suitability": 0
      },
      "issues": [
        {
          "type": "too_stiff | field_stacking | unsupported_claim | insensitive_wording | too_abstract | too_long | too_short | privacy_risk | tone_mismatch",
          "description": ""
        }
      ],
      "source_trace": [
        {
          "source_type": "elder_field | photo | family_note | inferred_atmosphere",
          "source_key": "",
          "source_value": "",
          "support_level": "strong | medium | weak"
        }
      ],
      "rewrite_text": "",
      "family_question": ""
    }
  ]
}
''';
  }

  static String buildParagraphRevisionPrompt({
    required Map<String, dynamic> elderProfile,
    required String originalParagraph,
    required List<Map<String, dynamic>> auditResults,
    required List<String> processedSentences,
  }) {
    const encoder = JsonEncoder.withIndent('  ');
    return '''
你是一位“回忆图鉴段落润色师”。

你需要根据 AI 审核后的句子，把段落润色得更自然、更连贯。

注意：
1. 不能新增没有依据的关键事实；
2. 不能暴露 medical_notes、care_notes、taboo；
3. 不能直接写负面词；
4. 保持“我们 + 你”的家属叙事口吻；
5. 保持适合朗读的节奏；
6. 每段控制在 2 到 4 句话；
7. 不要写成资料列表；
8. 不要过度煽情；
9. 不要改变照片和老人信息中的事实。
10. 信息不足时少写不补，不用猜想补出新的关键事实。

【老人信息】
${encoder.convert(elderProfile)}

【原段落】
$originalParagraph

【审核结果】
${encoder.convert(auditResults)}

【处理后的句子】
${encoder.convert(processedSentences)}

请只输出润色后的段落文本，不要输出解释。
''';
  }
}
