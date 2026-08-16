// coverage:ignore-file

import 'dart:async';
import 'dart:typed_data';

import 'package:kohera/core/backend/dto/account_dto.dart';
import 'package:kohera/core/backend/dto/device_key_dto.dart';
import 'package:kohera/core/backend/dto/event_dto.dart';
import 'package:kohera/core/backend/dto/member_dto.dart';
import 'package:kohera/core/backend/dto/room_dto.dart';
import 'package:kohera/core/backend/dto/user_dto.dart';
import 'package:kohera/core/backend/dto/verification_dto.dart';
import 'package:kohera/core/backend/transport/protocol.dart';

// ── MatrixBackend (the port) ──────────────────────────────────────
//
// The UI depends only on this interface.  It is implemented by:
//   - the real worker-backed adapter (issue #3, runs the SDK on an isolate)
//   - an in-memory fake (for tests)
//
// Ops are added incrementally per child issue. This cut exposes the
// rooms-list, timeline, room-management, room-state, members/users,
// messaging, and read-state ops (issues #992 foundation + #993 + #994).

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

  // ── Rooms list ────────────────────────────────────────────────

  /// Returns a snapshot of all rooms for [accountId].
  Future<List<RoomDto>> roomsList(String accountId);

  /// A stream that emits the updated room list whenever it changes.
  Stream<List<RoomDto>> roomListUpdates(String accountId);

  // ── Timeline ──────────────────────────────────────────────────

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

  // ── Room management ───────────────────────────────────────────

  Future<void> leaveRoom(String accountId, String roomId);

  Future<void> joinRoom(String accountId, String roomId);

  Future<void> inviteUser(String accountId, String roomId, String userId, {String? reason});

  Future<void> kickUser(String accountId, String roomId, String userId);

  Future<void> banUser(String accountId, String roomId, String userId);

  Future<void> unbanUser(String accountId, String roomId, String userId);

  Future<String> setRoomName(String accountId, String roomId, String name);

  Future<String> setRoomTopic(String accountId, String roomId, String topic);

  Future<String> setRoomAvatar(String accountId, String roomId, Uint8List bytes, String name, {String? mimeType});

  Future<String> createRoom(String accountId, Map<String, dynamic> options);

  // ── Room state ────────────────────────────────────────────────

  Future<Map<String, dynamic>> getRoomState(String accountId, String roomId, String eventType, String key);

  Future<String> setRoomState(String accountId, String roomId, String eventType, String key, Map<String, dynamic> content);

  Future<bool> canChangeState(String accountId, String roomId, String eventType);

  Future<int> getPowerLevel(String accountId, String roomId, String userId);

  // ── Members & users ───────────────────────────────────────────

  Future<List<MemberDto>> getJoinedMembers(String accountId, String roomId);

  Future<UserDto> getUser(String accountId, String roomId, String userId);

  Future<List<UserDto>> searchUsers(String accountId, String term);

  // ── Messaging ─────────────────────────────────────────────────

  /// Sends a raw event with [content] into [roomId]. Returns the server
  /// event id (null if the local echo could not be sent).
  Future<String?> sendMessage(
    String accountId,
    String roomId,
    Map<String, dynamic> content,
  );

  /// Sends a plain-text [text] message into [roomId]. Returns the server
  /// event id (null if the local echo could not be sent).
  Future<String?> sendText(String accountId, String roomId, String text);

  /// Sends a reaction ([key], typically an emoji) to [eventId] in [roomId].
  /// Returns the server event id of the reaction (null on failure).
  Future<String?> sendReaction(
    String accountId,
    String roomId,
    String eventId,
    String key,
  );

  /// Redacts [eventId] in [roomId] with an optional [reason]. Returns the
  /// server event id of the redaction (null on failure).
  Future<String?> redactEvent(
    String accountId,
    String roomId,
    String eventId, {
    String? reason,
  });

  /// Reports [eventId] in [roomId] to the homeserver with an optional
  /// [reason] and [score] (score is accepted for contract parity but ignored
  /// by SDK 9.0.0).
  Future<void> reportEvent(
    String accountId,
    String roomId,
    String eventId, {
    String? reason,
    int? score,
  });

  /// Uploads [bytes] as a file named [name] (optional [mimeType]) and sends
  /// the resulting m.file message event into [roomId]. Returns the server
  /// event id (null on failure).
  Future<String?> sendFile(
    String accountId,
    String roomId,
    Uint8List bytes,
    String name, {
    String? mimeType,
  });

  // ── Read state ────────────────────────────────────────────────

  /// Sets the fully-read marker for [roomId] to [eventId].
  Future<void> setReadMarker(String accountId, String roomId, String eventId);

  /// Sets a public read receipt for [roomId] at [eventId].
  Future<void> setReadReceipt(String accountId, String roomId, String eventId);

  /// Returns the serialized receipt state for [roomId] (a Map suitable for
  /// the wire — `room.receiptState.toJson()` on the worker).
  Future<Map<String, dynamic>> getReceipts(String accountId, String roomId);

  // ── E2EE ──────────────────────────────────────────────────────

  /// Whether end-to-end encryption is enabled for a specific room.
  Future<bool> encryptionEnabled(String accountId, String roomId);

  /// Returns the known device keys for [userId].
  Future<List<DeviceKeyDto>> deviceKeys(String accountId, String userId);

  /// Marks [deviceId] of [userId] as manually verified.
  Future<void> verifyDevice(String accountId, String userId, String deviceId);

  /// Starts an interactive key-verification with [userId] (and optionally a
  /// specific [deviceId]). Returns a snapshot of the initial state.
  Future<VerificationDto> startVerification(
    String accountId,
    String userId, {
    String? deviceId,
  });

  /// Whether cross-signing is enabled on the client.
  Future<bool> crossSigningEnabled(String accountId);

  /// Whether the cross-signing keys are cached locally.
  Future<bool> crossSigningIsCached(String accountId);

  /// Self-signs the current device using cross-signing, optionally unlocking
  /// SSSS with [recoveryKey].
  Future<void> crossSigningSelfSign(String accountId, {String? recoveryKey});

  /// Starts the SSSS/cross-signing bootstrap flow.
  Future<void> bootstrap(String accountId);

  /// Attempts to unlock the key backup using [recoveryKey]. Returns whether
  /// the unlock succeeded.
  Future<bool> unlockKeyBackup(String accountId, String recoveryKey);

  /// A stream that emits an event name whenever an incoming key-verification
  /// request arrives for [accountId].
  Stream<VerificationDto> keyVerificationRequests(String accountId);

  // ── Sync ──────────────────────────────────────────────────────

  /// Whether the backend is currently syncing with the homeserver.
  Future<bool> syncStatus(String accountId);

  // ── Streams ───────────────────────────────────────────────────

  /// Fires when the login state of any account changes.
  Stream<String> get onLoginStateChanged;

  /// Fires when the backend encounters an unrecoverable error.
  Stream<BackendError> get onError;
}
