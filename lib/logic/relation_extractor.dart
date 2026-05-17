import '../data/models/extracted_relation_hint.dart';

/// 大模型不可用时，从用户发言中启发式抽取人物称谓（回退方案）。
class RelationExtractor {
  static final _relThenName = RegExp(
    r'(?:我|俺)?(?:的)?(女儿|儿子|儿媳|女婿|老伴|孙子|孙女|外孙|邻居|朋友|同事|哥哥|姐姐|弟弟|妹妹|老爸|老妈|爸爸|妈妈|父亲|母亲|老公|老婆|丈夫|妻子)(?:叫|是|为)?\s*([\u4e00-\u9fa5]{2,4})',
  );

  static final _nameThenRel = RegExp(
    r'([\u4e00-\u9fa5]{2,4})\s*(?:是|为)\s*(?:我|俺)?(?:的)?(女儿|儿子|儿媳|女婿|老伴|孙子|孙女|外孙|邻居|朋友|同事|哥哥|姐姐|弟弟|妹妹|老爸|老妈|爸爸|妈妈|父亲|母亲|老公|老婆|丈夫|妻子)',
  );

  static final _phoneRe = RegExp(r'1[3-9]\d{9}');

  /// 发言里出现此类措辞且包含对应称谓时，才把该称谓写入 [ExtractedRelationHint.sameRelationKey]，
  /// 供按槽位对齐档案（触发更正/冲突）；否则允许多位同称谓亲友各自成条。
  static bool _shouldAnchorRelationSlot(String text, String relation) {
    if (!text.contains(relation)) return false;
    return RegExp(
      r'(搞错|弄错|记错|说错|纠正|更正|记成|其实是|应该说是|并非|'
      r'不是(?:他|她|这个人)?叫|不叫(?:他|她)?|'
      r'不对[，,。．]|说错了|重新说)',
    ).hasMatch(text);
  }

  static final _denyNames = <String>{
    '怎么',
    '什么',
    '今天',
    '明天',
    '现在',
    '这里',
    '那里',
    '拾忆',
    '阿姨',
    '大爷',
  };

  /// 解析中文发言，返回若干人物线索（同一句话内会去重合并）。
  static List<ExtractedRelationHint> extract(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return [];

    final merged = <String, ExtractedRelationHint>{};

    void put(ExtractedRelationHint h) {
      final key = _normName(h.name);
      if (key.length < 2 || _denyNames.contains(key)) return;
      final prev = merged[key];
      if (prev == null) {
        merged[key] = h;
        return;
      }
      merged[key] = ExtractedRelationHint(
        name: h.name,
        relation: h.relation ?? prev.relation,
        phone: h.phone ?? prev.phone,
        note: _mergeNote(prev.note, h.note),
        sameRelationKey: h.sameRelationKey ?? prev.sameRelationKey,
      );
    }

    for (final m in _relThenName.allMatches(text)) {
      final rel = m.group(1);
      final name = m.group(2);
      if (rel == null || name == null) continue;
      final slot = _shouldAnchorRelationSlot(text, rel) ? rel : null;
      put(ExtractedRelationHint(name: name, relation: rel, sameRelationKey: slot));
    }

    for (final m in _nameThenRel.allMatches(text)) {
      final name = m.group(1);
      final rel = m.group(2);
      if (rel == null || name == null) continue;
      final slot = _shouldAnchorRelationSlot(text, rel) ? rel : null;
      put(ExtractedRelationHint(name: name, relation: rel, sameRelationKey: slot));
    }

    final phones = _phoneRe.allMatches(text).map((e) => e.group(0)!).toList();
    if (phones.isNotEmpty && merged.isNotEmpty) {
      final keys = merged.keys.toList();
      final targetKey = keys.last;
      final h = merged[targetKey]!;
      merged[targetKey] = ExtractedRelationHint(
        name: h.name,
        relation: h.relation,
        phone: phones.first,
        note: h.note,
        sameRelationKey: h.sameRelationKey,
      );
    }

    return merged.values.toList();
  }

  /// 与 [LocalDatabase.normalizePersonName] 保持一致。
  static String _normName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), '');

  static String? _mergeNote(String? a, String? b) {
    final x = (a ?? '').trim();
    final y = (b ?? '').trim();
    if (x.isEmpty) return y.isEmpty ? null : y;
    if (y.isEmpty) return x;
    if (x.contains(y) || y.contains(x)) return x.length >= y.length ? x : y;
    return '$x；$y';
  }
}
