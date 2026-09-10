import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An unsent compose draft for one room: the message text and caret position.
class Draft {
  const Draft({required this.text, required this.caret});

  final String text;
  final int caret;

  Map<String, dynamic> toJson() => {'t': text, 'c': caret};

  static Draft? fromJson(Map<String, dynamic> json) {
    final text = json['t'];
    if (text is! String || text.isEmpty) return null;
    final caret = json['c'];
    return Draft(
      text: text,
      caret: caret is int ? caret : text.length,
    );
  }
}

/// Account-scoped, on-disk persistence for compose drafts.
///
/// Keys are namespaced by client name so each account keeps its own drafts and
/// [clearAccount] can wipe them on logout. Storage is plaintext, matching the
/// SDK database that already holds each room's decrypted history.
class DraftStore {
  DraftStore({required this.clientName, Future<SharedPreferences>? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance();

  static const _prefix = 'draft';

  final String clientName;
  final Future<SharedPreferences> _prefs;

  static String _key(String clientName, String roomId) =>
      '$_prefix:$clientName:$roomId';

  Future<Draft?> read(String roomId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key(clientName, roomId));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? Draft.fromJson(json) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(String roomId, Draft draft) async {
    final prefs = await _prefs;
    await prefs.setString(
      _key(clientName, roomId),
      jsonEncode(draft.toJson()),
    );
  }

  Future<void> clear(String roomId) async {
    final prefs = await _prefs;
    await prefs.remove(_key(clientName, roomId));
  }

  /// Removes every draft belonging to [clientName]. Called on logout so an
  /// account's unsent text does not outlive its session.
  ///
  /// Best-effort: draft cleanup is non-critical, so a storage failure here must
  /// never disrupt the logout flow that has already torn down the session.
  static Future<void> clearAccount(String clientName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountPrefix = '$_prefix:$clientName:';
      final keys =
          prefs.getKeys().where((k) => k.startsWith(accountPrefix)).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('[Kohera] Draft cleanup failed for $clientName: $e');
    }
  }
}
