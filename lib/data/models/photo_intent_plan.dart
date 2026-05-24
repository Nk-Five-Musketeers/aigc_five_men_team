/// 大模型对用户「要哪些照片」的结构化判定（再用于本地 catalog 匹配）。
class PhotoIntentPlan {
  const PhotoIntentPlan({
    required this.wantPhotos,
    this.includeFilters = const [],
    this.excludeFilters = const [],
    this.maxPhotos = 0,
    this.reasonSummary = '',
  });

  final bool wantPhotos;
  final List<PhotoIntentFilter> includeFilters;
  final List<PhotoIntentFilter> excludeFilters;

  /// 0 表示由客户端按用户话术再推断张数上限。
  final int maxPhotos;
  final String reasonSummary;

  static const empty = PhotoIntentPlan(wantPhotos: false);
}

class PhotoIntentFilter {
  const PhotoIntentFilter({
    this.photoIds = const [],
    this.categories = const [],
    this.keywords = const [],
    this.labels = const [],
  });

  final List<String> photoIds;
  final List<String> categories;
  final List<String> keywords;
  final List<String> labels;

  bool get isEmpty =>
      photoIds.isEmpty &&
      categories.isEmpty &&
      keywords.isEmpty &&
      labels.isEmpty;
}
