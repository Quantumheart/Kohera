import 'package:kohera/data/models/message_search_result.dart';

class UnindexedSearchResult {
  const UnindexedSearchResult({
    this.results = const [],
    this.count = 0,
  });

  final List<MessageSearchResult> results;
  final int count;
}
