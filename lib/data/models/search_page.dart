import 'package:kohera/data/models/message_search_result.dart';

abstract class SearchPage {
  const SearchPage({
    this.results = const [],
    this.count,
    this.nextBatch,
  });

  final List<MessageSearchResult> results;
  final int? count;
  final String? nextBatch;
}

class ServerSearchPage extends SearchPage {
  const ServerSearchPage({
    super.results,
    super.count,
    super.nextBatch,
  });
}

class LocalSearchPage extends SearchPage {
  const LocalSearchPage({
    super.results,
    super.count,
    super.nextBatch,
  });
}

class UnindexedSearchResult extends SearchPage {
  const UnindexedSearchResult({
    super.results,
    int super.count = 0,
  });
}
