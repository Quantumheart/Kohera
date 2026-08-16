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
    unawaited(_backend.disconnect());
    super.dispose();
  }
}
