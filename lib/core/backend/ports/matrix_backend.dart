// coverage:ignore-file

import 'dart:async';

import 'package:kohera/core/backend/dto/account_dto.dart';
import 'package:kohera/core/backend/dto/event_dto.dart';
import 'package:kohera/core/backend/dto/room_dto.dart';
import 'package:kohera/core/backend/transport/protocol.dart';

// ── MatrixBackend (the port) ──────────────────────────────────────
//
// The UI depends only on this interface.  It is implemented by:
//   - the real worker-backed adapter (issue #3, runs the SDK on an isolate)
//   - an in-memory fake (for tests)
//
// Ops are added incrementally per child issue.  This first cut exposes only
// the rooms-list capability (issue #4 `backend-rooms-capability`).

abstract class MatrixBackend {
  // ── Lifecycle ──────────────────────────────────────────────────

  /// Connects to the backend (spawns the worker, restores the session, etc.)
  Future<void> connect();

  /// Disconnects and releases resources.
  Future<void> disconnect();

  /// Whether the backend is connected and ready.
  bool get isReady;

  // ── Accounts ──────────────────────────────────────────────────

  /// Returns the list of known accounts.
  Future<List<AccountDto>> accountsList();

  // ── Rooms list (first capability) ─────────────────────────────

  /// Returns a snapshot of all rooms for [accountId].
  Future<List<RoomDto>> roomsList(String accountId);

  /// A stream that emits the updated room list whenever it changes.
  Stream<List<RoomDto>> roomListUpdates(String accountId);

  // ── Timeline (second capability) ─────────────────────────────

  Future<List<EventDto>> fetchTimeline(
    String accountId,
    String roomId, {
    int limit = 50,
  });

  Future<List<EventDto>> paginateTimeline(
    String accountId,
    String roomId,
    String direction, {
    int limit = 50,
  });

  Stream<List<EventDto>> timelineUpdates(String accountId, String roomId);

  // ── Streams ───────────────────────────────────────────────────

  /// Fires when the login state of any account changes.
  Stream<String> get onLoginStateChanged;

  /// Fires when the backend encounters an unrecoverable error.
  Stream<BackendError> get onError;
}
