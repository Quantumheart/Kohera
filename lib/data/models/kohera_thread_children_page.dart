import 'package:flutter/foundation.dart';
import 'package:kohera/data/models/kohera_timeline_event.dart';

/// One page of thread reply events for a thread root.
@immutable
class KoheraThreadChildrenPage {
  const KoheraThreadChildrenPage({required this.events, this.nextBatch});

  /// The reply events, oldest first.
  final List<KoheraTimelineEvent> events;

  /// The pagination token for the next page, or null when exhausted.
  final String? nextBatch;
}
