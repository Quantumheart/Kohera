import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/data/models/kohera_timeline_event.dart';

/// SDK-free view of a room timeline.
///
/// Owns the current [events] snapshot and republishes it on [onEvents]
/// after every SDK timeline update. Pagination and fragmentation state
/// delegate to closures supplied by the data layer, so feature code never
/// touches the SDK `Timeline`.
class KoheraTimeline {
  KoheraTimeline({
    required this.roomId,
    required List<KoheraTimelineEvent> events,
    required bool Function() canRequestHistory,
    required bool Function() isFragmented,
    required Future<void> Function() requestHistory,
    void Function()? onDispose,
  })  : _events = events,
        _canRequestHistory = canRequestHistory,
        _isFragmented = isFragmented,
        _requestHistory = requestHistory,
        _onDispose = onDispose;

  /// The room this timeline belongs to.
  final String roomId;

  List<KoheraTimelineEvent> _events;
  final bool Function() _canRequestHistory;
  final bool Function() _isFragmented;
  final Future<void> Function() _requestHistory;
  final void Function()? _onDispose;

  final StreamController<List<KoheraTimelineEvent>> _eventsController =
      StreamController<List<KoheraTimelineEvent>>.broadcast();
  bool _disposed = false;

  /// The current event snapshot, newest first.
  List<KoheraTimelineEvent> get events => _events;

  /// Emits the full event list after each timeline update.
  Stream<List<KoheraTimelineEvent>> get onEvents => _eventsController.stream;

  /// Whether more history can be requested from the server or database.
  bool get canRequestHistory => _canRequestHistory();

  /// `true` when this timeline is a fragmented context view (loaded via an
  /// event-context ID) that cannot receive live sync events.
  bool get isFragmented => _isFragmented();

  /// Requests the next batch of history.
  Future<void> requestHistory() => _requestHistory();

  /// The event with [eventId] in the current snapshot, else null.
  KoheraTimelineEvent? eventById(String eventId) {
    for (final event in _events) {
      if (event.eventId == eventId) return event;
    }
    return null;
  }

  /// Replaces the current snapshot and emits it on [onEvents]. Called by
  /// the data layer when the SDK timeline reports an update.
  void publish(List<KoheraTimelineEvent> events) {
    if (_disposed) return;
    _events = events;
    _eventsController.add(events);
  }

  /// Releases the underlying SDK subscriptions.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onDispose?.call();
    unawaited(_eventsController.close());
  }

  @visibleForTesting
  bool get isDisposed => _disposed;
}
