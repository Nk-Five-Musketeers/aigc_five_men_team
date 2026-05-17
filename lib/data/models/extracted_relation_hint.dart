/// 由大模型或本地规则解析出的「周围人」一条线索，用于写入 [nearby_people]。
class ExtractedRelationHint {
  ExtractedRelationHint({
    required this.name,
    this.relation,
    this.phone,
    this.note,
    this.sameRelationKey,
  });

  final String name;
  final String? relation;
  final String? phone;
  final String? note;

  /// 与本地档案中已有条目对应的称谓槽位（如「女儿」），用于姓名更正时按称谓匹配同一人而非新建。
  final String? sameRelationKey;
}
