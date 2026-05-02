/// 由大模型或本地规则解析出的「周围人」一条线索，用于写入 [nearby_people]。
class ExtractedRelationHint {
  ExtractedRelationHint({
    required this.name,
    this.relation,
    this.phone,
    this.note,
  });

  final String name;
  final String? relation;
  final String? phone;
  final String? note;
}
