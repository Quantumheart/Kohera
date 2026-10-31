import 'package:kohera/data/models/message_search_result.dart';

class LocalSearchPage {
  const LocalSearchPage({
    this.results = const [],
    this.count,
    this.nextBatch,
  });

  final List<MessageSearchResult> results;
  final int? count;
  final String? nextBatch;
}
