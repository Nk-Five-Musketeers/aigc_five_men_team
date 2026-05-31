/// 把用户在聊天中口语化的描述（如"这是我的大学毕业照"）转成
/// 相册可读的题注（如"大学毕业照"）。
///
/// 只处理高置信度的对话开头词；不可识别的句子原样返回，
/// 避免误伤本来就是好题注的文本。
String cleanAlbumCaption(String? raw) {
  if (raw == null) return '';
  var text = raw.trim();
  if (text.isEmpty) return text;

  // 按长 -> 短匹配，避免局部命中。
  const prefixes = <String>[
    '这一张照片是我的',
    '这一张照片是我',
    '这一张照片是',
    '这张照片是我的',
    '这张照片是我',
    '这张照片是',
    '这一张是我的',
    '这一张是我',
    '这一张是',
    '这张是我的',
    '这张是我',
    '这张是',
    '这个是我的',
    '这个是我',
    '这个是',
    '这是我的',
    '这是我',
    '这是',
    '我的',
  ];
  for (final p in prefixes) {
    if (text.startsWith(p)) {
      text = text.substring(p.length).trimLeft();
      break;
    }
  }

  // 去掉句末标点和语气词。
  text = text.replaceAll(RegExp(r'[啊呀呢哦呵嗨吧。，,!！?？\.\s]+$'), '');

  // 如果剥得只剩极短内容（< 2 个有效字符），退回原文 —— 宁可保留口语，
  // 也不要变成"我的"或"是"这种碎片。
  if (text.runes.length < 2) return raw.trim();
  return text;
}
