import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kohera/features/share_in/models/pending_share.dart';
import 'package:kohera/features/share_in/models/room_snapshot.dart';

/// App-Group shared-defaults key holding the JSON array of [RoomSnapshot].
const String kRoomSnapshotKey = 'roomSnapshot';

/// App-Group shared-defaults key holding the JSON array of [PendingShare].
const String kPendingSharesKey = 'pendingShares';

/// App-Group shared-defaults key holding the active account's clientName
/// (the `MatrixService.clientName` the Share Extension should attribute
/// staged shares to).
const String kActiveAccountIdKey = 'activeAccountId';

/// Write-only target for [RoomSnapshotService] so it can be tested without a
/// real platform channel.
abstract class RoomSnapshotSink {
  Future<void> writeRoomSnapshot(List<RoomSnapshot> snapshots);
}

/// Dart-side bridge over the `kohera/share` platform channel.
///
/// The iOS Share Extension writes [PendingShare] entries and the main app
/// reads them; the main app writes [RoomSnapshot] snapshots and the extension
/// reads them. Both flows live in the App-Group `UserDefaults` suite
/// `group.io.github.quantumheart.kohera`, which only iOS exposes via this
/// channel. On platforms without a native handler (Android/desktop/web) every
/// call degrades to a no-op so callers never need to branch on platform.
class ShareInStore implements RoomSnapshotSink {
  ShareInStore({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('kohera/share');

  final MethodChannel _channel;

  Future<List<RoomSnapshot>> readRoomSnapshot() async {
    final raw = await _invokeJson<String>('readRoomSnapshot');
    if (raw == null || raw.isEmpty) return const [];
    return _decodeList(raw, RoomSnapshot.fromJson);
  }

  @override
  Future<void> writeRoomSnapshot(List<RoomSnapshot> snapshots) async {
    final raw = jsonEncode(snapshots.map((s) => s.toJson()).toList());
    await _invokeVoid('writeRoomSnapshot', raw);
  }

  Future<List<PendingShare>> readPendingShares() async {
    final raw = await _invokeJson<String>('readPendingShares');
    if (raw == null || raw.isEmpty) return const [];
    return _decodeList(raw, PendingShare.fromJson);
  }

  Future<void> clearPendingShare(String id) async {
    await _invokeVoid('clearPendingShare', id);
  }

  Future<void> clearAllPendingShares() async {
    await _invokeVoid('clearAllPendingShares', null);
  }

  Future<String?> readActiveAccountId() async {
    try {
      return await _channel.invokeMethod<String>('readActiveAccountId');
    } on PlatformException catch (e) {
      debugPrint('[Kohera] ShareInStore readActiveAccountId unavailable: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> writeActiveAccountId(String accountId) async {
    await _invokeVoid('writeActiveAccountId', accountId);
  }

  Future<T?> _invokeJson<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on PlatformException catch (e) {
      debugPrint('[Kohera] ShareInStore $method unavailable: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _invokeVoid(String method, Object? arg) async {
    try {
      await _channel.invokeMethod<void>(method, arg);
    } on PlatformException catch (e) {
      debugPrint('[Kohera] ShareInStore $method unavailable: $e');
    } on MissingPluginException {
      // No native handler on this platform — share-in is iOS-only for now.
    }
  }

  static List<T> _decodeList<T>(
    String raw,
    T Function(Map<String, Object?>) fromJson,
  ) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, Object?>>()
        .map(fromJson)
        .toList(growable: false);
  }
}
