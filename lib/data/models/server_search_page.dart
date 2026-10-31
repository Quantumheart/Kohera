import 'package:kohera/data/models/message_search_result.dart';

class ServerSearchPage {
  const ServerSearchPage({
    this.results = const [],
    this.count,
    this.nextBatch,
  });

  final List<MessageSearchResult> results;
  final int? count;
  final String? nextBatch;
}
