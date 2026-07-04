import 'dart:convert';

import 'package:aigc_five_men_team/data/repositories/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses assistant content deltas from SSE chunks', () async {
    final chunks = <List<int>>[
      utf8.encode('data: {"choices":[{"delta":{"content":"Hel"}}]}\n'),
      utf8.encode('\n'),
      utf8.encode('data: {"choices":[{"delta":{"content":"lo"}}]}\n\n'),
      utf8.encode('data: [DONE]\n\n'),
    ];

    final deltas = await assistantTextDeltasFromSse(
      Stream<List<int>>.fromIterable(chunks),
    ).toList();

    expect(deltas, <String>['Hel', 'lo']);
  });

  test('parses nested data wrapper used by proxy-compatible responses',
      () async {
    final chunks = <List<int>>[
      utf8.encode(
        'data: {"data":{"choices":[{"delta":{"content":"A"}}]}}\n\n',
      ),
      utf8.encode('data: [DONE]\n\n'),
    ];

    final deltas = await assistantTextDeltasFromSse(
      Stream<List<int>>.fromIterable(chunks),
    ).toList();

    expect(deltas, <String>['A']);
  });
}
