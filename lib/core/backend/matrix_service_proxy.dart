// coverage:ignore-file

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/backend/dto/account_dto.dart';
import 'package:kohera/core/backend/dto/event_dto.dart';
import 'package:kohera/core/backend/dto/room_dto.dart';
import 'package:kohera/core/backend/ports/matrix_backend.dart';

// ── MatrixServiceProxy ────────────────────────────────────────────
//
// A ChangeNotifier that the UI reads from instead of the old in-process
// MatrixService.  It mirrors the same public READ shape the UI needs (rooms
// list, login state, timeline) but is backed by a [MatrixBackend] (the port),
// not a live `Client`.
//
// The proxy caches DTOs in memory, updated by event streams from the worker.
// Widget reads are synchronous (from cache). Only initial loads and pagination
// are async (they were already async via getTimeline()).

class MatrixServiceProxy extends ChangeNotifier {
  MatrixServiceProxy({required MatrixBackend backend}) : _backend = backend {
    _init();
  }

  final MatrixBackend _backend;
  StreamSubscription<String>? _loginStateSub;
  StreamSubscription<List<RoomDto>>? _roomListSub;

  // ── State the UI reads ─────────────────────────────────────────

  List<RoomDto> _rooms = const [];
  List<RoomDto> get rooms => _rooms;

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  AccountDto? _account;
  AccountDto? get account => _account;

  bool _disposed = false;
  bool get disposed => _disposed;

  // ── Timeline cache ─────────────────────────────────────────────

  final Map<String, List<EventDto>> _timelines = {};
  final Map<String, StreamSubscription<List<EventDto>>> _timelineSubs = {};

  /// Returns the cached timeline for [roomId], or null if not yet fetched.
  List<EventDto>? getTimeline(String roomId) => _timelines[roomId];

  /// Fetches the timeline from the worker, populates the cache, and notifies.
  Future<List<EventDto>> fetchTimeline(String roomId) async {
    final accountId = _account?.clientName ?? 'default';
    final events = await _backend.fetchTimeline(accountId, roomId);
    _timelines[roomId] = events;
    notifyListeners();
    return events;
  }

  /// Paginates the timeline (backward or forward) and updates the cache.
  Future<void> paginateTimeline(String roomId, String direction) async {
    final accountId = _account?.clientName ?? 'default';
    final events = await _backend.paginateTimeline(accountId, roomId, direction);
    _timelines[roomId] = events;
    notifyListeners();
  }

  /// Subscribes to timeline updates for [roomId]. New events from the worker
  /// update the cache and fire [notifyListeners]. Returns a [Stream] for
  /// widgets that want to react to individual updates.
  Stream<List<EventDto>> timelineUpdates(String roomId) {
    final accountId = _account?.clientName ?? 'default';
    final stream = _backend.timelineUpdates(accountId, roomId);
    _timelineSubs[roomId] = stream.listen((events) {
      _timelines[roomId] = events;
      notifyListeners();
    });
    return stream;
  }

  // ── Messaging (async send) ─────────────────────────────────────

  String _accountId() => _account?.clientName ?? 'default';

  /// Sends a raw event with [content] into [roomId]. Returns the server
  /// event id (may be null for a local-only echo).
  Future<String?> sendMessage(String roomId, Map<String, dynamic> content) =>
      _backend.sendMessage(_accountId(), roomId, content);

  /// Sends a plain-text [text] message into [roomId].
  Future<String?> sendText(String roomId, String text) =>
      _backend.sendText(_accountId(), roomId, text);

  /// Sends a reaction ([key], typically an emoji) to [eventId] in [roomId].
  Future<String?> sendReaction(
    String roomId,
    String eventId,
    String key,
  ) =>
      _backend.sendReaction(_accountId(), roomId, eventId, key);

  /// Redacts [eventId] in [roomId] with an optional [reason].
  Future<String?> redactEvent(
    String roomId,
    String eventId, {
    String? reason,
  }) =>
      _backend.redactEvent(_accountId(), roomId, eventId, reason: reason);

  /// Reports [eventId] in [roomId] to the homeserver.
  Future<void> reportEvent(
    String roomId,
    String eventId, {
    String? reason,
    int? score,
  }) =>
      _backend.reportEvent(_accountId(), roomId, eventId, reason: reason, score: score);

  /// Uploads [bytes] as a file named [name] and sends it into [roomId].
  Future<String?> sendFile(
    String roomId,
    Uint8List bytes,
    String name, {
    String? mimeType,
  }) =>
      _backend.sendFile(_accountId(), roomId, bytes, name, mimeType: mimeType);

  // ── Read state (sync cache + async send) ────────────────────────

  final Map<String, Map<String, dynamic>> _receipts = {};

  /// Returns the cached receipt state for [roomId], or null if not yet
  /// fetched. Synchronous — widgets read from this without awaiting.
  Map<String, dynamic>? getReceipts(String roomId) => _receipts[roomId];

  /// Fetches the receipt state for [roomId] from the backend, populates the
  /// cache, and notifies listeners. Returns the fetched state.
  Future<Map<String, dynamic>> fetchReceipts(String roomId) async {
    final receipts = await _backend.getReceipts(_accountId(), roomId);
    _receipts[roomId] = receipts;
    notifyListeners();
    return receipts;
  }

  /// Sets the fully-read marker for [roomId] to [eventId].
  Future<void> setReadMarker(String roomId, String eventId) =>
      _backend.setReadMarker(_accountId(), roomId, eventId);

  /// Sets a public read receipt for [roomId] at [eventId].
  Future<void> setReadReceipt(String roomId, String eventId) =>
      _backend.setReadReceipt(_accountId(), roomId, eventId);

  // ── Init ──────────────────────────────────────────────────────

  void _init() {
    _loginStateSub = _backend.onLoginStateChanged.listen((_) {
      unawaited(_refreshLoginState());
    });
  }

  /// Connects to the backend and starts listening for room-list updates.
  Future<void> start() async {
    await _backend.connect();
    await _refreshLoginState();
    await refreshRooms();
    _roomListSub = _backend
        .roomListUpdates(_account?.clientName ?? 'default')
        .listen((rooms) {
      _rooms = rooms;
      notifyListeners();
    });
  }

  Future<void> refreshRooms() async {
    final accountId = _account?.clientName ?? 'default';
    _rooms = await _backend.roomsList(accountId);
    notifyListeners();
  }

  Future<void> _refreshLoginState() async {
    final accounts = await _backend.accountsList();
    _account = accounts.isNotEmpty ? accounts.first : null;
    _isLoggedIn = _account?.isLoggedIn ?? false;
    notifyListeners();
  }

  // ── Dispose ────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    unawaited(_roomListSub?.cancel());
    unawaited(_loginStateSub?.cancel());
    for (final sub in _timelineSubs.values) {
      unawaited(sub.cancel());
    }
    _timelineSubs.clear();
    _timelines.clear();
    _receipts.clear();
    unawaited(_backend.disconnect());
    super.dispose();
  }
}
