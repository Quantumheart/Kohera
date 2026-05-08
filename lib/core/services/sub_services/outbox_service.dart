import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/sub_services/outbox_connectivity.dart';
import 'package:kohera/core/services/sub_services/outbox_database.dart';
import 'package:matrix/matrix.dart';

@immutable
class OutboxEntryView {
  const OutboxEntryView({
    required this.txid,
    required this.roomId,
    required this.attempts,
    required this.nextRetryAt,
    required this.finalFailed,
  });

  final String txid;
  final String roomId;
  final int attempts;
  final DateTime nextRetryAt;
  final bool finalFailed;
}

class _Entry {
  _Entry({
    required this.txid,
    required this.roomId,
    required this.attempts,
    required this.nextRetryAt,
  });

  final String txid;
  final String roomId;
  int attempts;
  DateTime nextRetryAt;
  Timer? timer;
  bool inFlight = false;
  bool finalFailed = false;
}

class OutboxService extends ChangeNotifier {
  OutboxService({
    required Client client,
    required String clientName,
    OutboxDatabase? databaseOverride,
    OutboxConnectivity? connectivity,
    @visibleForTesting math.Random? random,
    @visibleForTesting Duration Function(int attempts)? backoffOverride,
    @visibleForTesting int? recentTimelineLookback,
    @visibleForTesting Duration? connectivityDebounce,
  })  : _client = client,
        _db = databaseOverride ?? OutboxDatabase(clientName: clientName),
        _connectivity = connectivity,
        _random = random ?? math.Random(),
        _backoffOverride = backoffOverride,
        _recentLookback = recentTimelineLookback ?? 50,
        _connectivityDebounce =
            connectivityDebounce ?? const Duration(seconds: 2);

  static const int kMaxAttempts = 8;
  static const Duration kMaxBackoff = Duration(seconds: 60);

  final Client _client;
  final OutboxDatabase _db;
  final OutboxConnectivity? _connectivity;
  final math.Random _random;
  final Duration Function(int)? _backoffOverride;
  final int _recentLookback;
  final Duration _connectivityDebounce;

  final Map<String, _Entry> _entries = {};
  StreamSubscription<SyncUpdate>? _syncSub;
  StreamSubscription<Event>? _timelineSub;
  StreamSubscription<bool>? _connectivitySub;
  Timer? _drainDebounceTimer;
  bool _wasOffline = false;
  bool _started = false;
  bool _scanned = false;
  bool _disposed = false;

  Map<String, OutboxEntryView> get entries => {
        for (final e in _entries.values)
          e.txid: OutboxEntryView(
            txid: e.txid,
            roomId: e.roomId,
            attempts: e.attempts,
            nextRetryAt: e.nextRetryAt,
            finalFailed: e.finalFailed,
          ),
      };

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    debugPrint('[Kohera] outbox: start');
    _timelineSub = _client.onTimelineEvent.stream.listen(_onTimelineEvent);
    _syncSub = _client.onSync.stream.listen((_) {
      if (!_scanned) {
        _scanned = true;
        unawaited(_initialScan());
      }
      if (_wasOffline) {
        debugPrint('[Kohera] outbox: sync resumed after offline, draining');
        _wasOffline = false;
        _scheduleDrain(immediate: true);
      }
    });
    final c = _connectivity;
    if (c != null) {
      _wasOffline = !(await c.isOnline());
      _connectivitySub = c.onlineChanges.listen((online) {
        debugPrint('[Kohera] outbox: connectivity online=$online');
        if (!online) {
          _wasOffline = true;
          return;
        }
        if (_wasOffline) {
          _wasOffline = false;
          _scheduleDrain();
        }
      });
    }
  }

  void _scheduleDrain({bool immediate = false}) {
    if (_disposed) return;
    _drainDebounceTimer?.cancel();
    final delay = immediate ? Duration.zero : _connectivityDebounce;
    _drainDebounceTimer = Timer(delay, () {
      if (_disposed) return;
      _drain();
    });
  }

  void _drain() {
    debugPrint('[Kohera] outbox: drain (${_entries.length} entries)');
    for (final entry in _entries.values.toList()) {
      if (entry.inFlight || entry.finalFailed) continue;
      entry.nextRetryAt = DateTime.now();
      _scheduleRetry(entry);
    }
  }

  Future<void> _initialScan() async {
    if (_disposed) return;
    debugPrint('[Kohera] outbox: initial scan');
    final db = _client.database;
    final persisted = {
      for (final a in await _db.all()) a.txid: a,
    };
    final liveTxids = <String>{};
    for (final room in _client.rooms) {
      final List<Event> stuck;
      try {
        stuck = await db.getEventList(room, onlySending: true);
      } catch (e) {
        debugPrint('[Kohera] outbox: getEventList failed for ${room.id}: $e');
        continue;
      }
      for (final ev in stuck) {
        final txid = ev.transactionId ?? ev.eventId;
        liveTxids.add(txid);
        if (_entries.containsKey(txid)) continue;
        final prior = persisted[txid];
        final entry = _Entry(
          txid: txid,
          roomId: room.id,
          attempts: prior?.attempts ?? 0,
          nextRetryAt: prior?.nextRetryAt ?? DateTime.now(),
        );
        if (entry.attempts >= kMaxAttempts) {
          entry.finalFailed = true;
        }
        _entries[txid] = entry;
        if (!entry.finalFailed) _scheduleRetry(entry);
      }
    }
    await _db.retainOnly(liveTxids);
    debugPrint(
      '[Kohera] outbox: scan done, ${_entries.length} entries (${liveTxids.length} live)',
    );
    _safeNotify();
  }

  void _onTimelineEvent(Event event) {
    final txid = event.transactionId;
    if (txid == null) return;
    final entry = _entries[txid];
    if (entry == null) return;
    if (event.status.isSynced) {
      debugPrint('[Kohera] outbox: $txid graduated to synced');
      _evict(txid);
    }
  }

  void _evict(String txid) {
    final entry = _entries.remove(txid);
    entry?.timer?.cancel();
    if (!_disposed) {
      unawaited(
        _db.remove(txid).catchError((Object e) {
          debugPrint('[Kohera] outbox: remove $txid failed: $e');
        }),
      );
    }
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _scheduleRetry(_Entry entry) {
    entry.timer?.cancel();
    final now = DateTime.now();
    final delay = entry.nextRetryAt.isAfter(now)
        ? entry.nextRetryAt.difference(now)
        : Duration.zero;
    entry.timer = Timer(delay, () => unawaited(_retry(entry.txid)));
  }

  Future<void> _retry(String txid) async {
    final entry = _entries[txid];
    if (entry == null || _disposed) return;
    if (entry.inFlight || entry.finalFailed) return;
    entry.inFlight = true;
    _safeNotify();
    try {
      await _retryInner(txid, entry);
    } finally {
      entry.inFlight = false;
    }
  }

  Future<void> _retryInner(String txid, _Entry entry) async {
    final room = _client.getRoomById(entry.roomId);
    if (room == null) {
      debugPrint('[Kohera] outbox: room ${entry.roomId} gone, dropping $txid');
      _evict(txid);
      return;
    }
    if (await _isAlreadyAccepted(room, txid)) {
      debugPrint('[Kohera] outbox: $txid already accepted by server, evicting');
      _evict(txid);
      return;
    }
    Event? stuck;
    try {
      final list = await _client.database.getEventList(
        room,
        onlySending: true,
      );
      for (final ev in list) {
        if ((ev.transactionId ?? ev.eventId) == txid) {
          stuck = ev;
          break;
        }
      }
    } catch (e) {
      debugPrint('[Kohera] outbox: lookup $txid failed: $e');
    }
    if (stuck == null) {
      debugPrint('[Kohera] outbox: stuck event $txid not found, evicting');
      _evict(txid);
      return;
    }
    String? result;
    try {
      result = await stuck.sendAgain(txid: txid);
    } catch (e) {
      debugPrint('[Kohera] outbox: sendAgain $txid threw: $e');
      result = null;
    }
    if (result != null) {
      debugPrint('[Kohera] outbox: $txid sendAgain succeeded ($result)');
      return;
    }
    entry.attempts += 1;
    if (entry.attempts >= kMaxAttempts) {
      entry.finalFailed = true;
      debugPrint('[Kohera] outbox: $txid hit cap, marking final-failed');
      await _db
          .upsert(
        OutboxAttempt(
          txid: entry.txid,
          roomId: entry.roomId,
          attempts: entry.attempts,
          nextRetryAt: entry.nextRetryAt,
        ),
      )
          .catchError((Object e) {
        debugPrint('[Kohera] outbox: persist cap state $txid failed: $e');
      });
      _safeNotify();
      return;
    }
    final delay = computeBackoff(entry.attempts);
    entry.nextRetryAt = DateTime.now().add(delay);
    debugPrint(
      '[Kohera] outbox: $txid attempt ${entry.attempts} failed, '
      'next in ${delay.inMilliseconds}ms',
    );
    await _db
        .upsert(
      OutboxAttempt(
        txid: entry.txid,
        roomId: entry.roomId,
        attempts: entry.attempts,
        nextRetryAt: entry.nextRetryAt,
      ),
    )
        .catchError((Object e) {
      debugPrint('[Kohera] outbox: persist $txid failed: $e');
    });
    _scheduleRetry(entry);
    _safeNotify();
  }

  Future<bool> _isAlreadyAccepted(Room room, String txid) async {
    try {
      final events = await _client.database.getEventList(
        room,
        limit: _recentLookback,
      );
      for (final ev in events) {
        if (ev.transactionId == txid && ev.status.isSynced) return true;
      }
    } catch (e) {
      debugPrint('[Kohera] outbox: dedup lookup failed for $txid: $e');
    }
    return false;
  }

  @visibleForTesting
  Duration computeBackoff(int attempts) {
    final override = _backoffOverride;
    if (override != null) return override(attempts);
    final shift = attempts.clamp(0, 6);
    final baseSeconds = math.min(kMaxBackoff.inSeconds, 1 << shift);
    final base = Duration(seconds: baseSeconds);
    final jitter = 0.75 + _random.nextDouble() * 0.5;
    return Duration(milliseconds: (base.inMilliseconds * jitter).round());
  }

  @visibleForTesting
  Future<void> runScanForTest() => _initialScan();

  @visibleForTesting
  Future<void> retryNowForTest(String txid) => _retry(txid);

  @visibleForTesting
  void drainNowForTest() => _drain();

  @override
  void dispose() {
    _disposed = true;
    debugPrint('[Kohera] outbox: dispose');
    for (final e in _entries.values) {
      e.timer?.cancel();
    }
    _entries.clear();
    _drainDebounceTimer?.cancel();
    _drainDebounceTimer = null;
    unawaited(_syncSub?.cancel());
    unawaited(_timelineSub?.cancel());
    unawaited(_connectivitySub?.cancel());
    _syncSub = null;
    _timelineSub = null;
    _connectivitySub = null;
    unawaited(_db.close());
    final c = _connectivity;
    if (c != null) unawaited(c.dispose());
    super.dispose();
  }
}
