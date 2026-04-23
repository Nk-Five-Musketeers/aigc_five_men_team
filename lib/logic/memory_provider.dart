import 'package:flutter/foundation.dart';

import '../data/models/story_item.dart';

class MemoryProvider extends ChangeNotifier {
  final List<StoryItem> _stories = <StoryItem>[];

  List<StoryItem> get stories => List.unmodifiable(_stories);

  void addStory(StoryItem item) {
    _stories.add(item);
    notifyListeners();
  }
}
