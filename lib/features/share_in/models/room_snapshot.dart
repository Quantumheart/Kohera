import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A compact, SDK-free projection of a joined [Room] that the iOS Share
/// Extension can render in its room picker without running the Matrix SDK.
///
/// Written by the main app on sync (see `RoomSnapshotService`) into the
/// App-Group shared store and read by the extension. The extension never
/// writes this — it only reads — to keep the SDK boundary clean.
@immutable
class RoomSnapshot {
  const RoomSnapshot({
    required this.roomId,
    required this.displayname,
    this.avatarMxc,
  });

  final String roomId;

  /// Cached display name; recomputed by the main app on each sync so the
  /// extension never has to resolve heroes/membership itself.
  final String displayname;

  /// Raw `mxc://` avatar URI string, or null. The extension can display a
  /// placeholder when null; resolving the thumbnail needs the SDK/credentials
  /// that live in the main app.
  final String? avatarMxc;

  Map<String, Object?> toJson() => {
        'roomId': roomId,
        'displayname': displayname,
        if (avatarMxc != null) 'avatarMxc': avatarMxc,
      };

  factory RoomSnapshot.fromJson(Map<String, Object?> json) => RoomSnapshot(
        roomId: json['roomId']! as String,
        displayname: json['displayname']! as String,
        avatarMxc: json['avatarMxc'] as String?,
      );

  String encode() => jsonEncode(toJson());

  factory RoomSnapshot.decode(String raw) =>
      RoomSnapshot.fromJson(jsonDecode(raw) as Map<String, Object?>);

  @override
  bool operator ==(Object other) =>
      other is RoomSnapshot && other.roomId == roomId;

  @override
  int get hashCode => roomId.hashCode;
}
