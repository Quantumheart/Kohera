import 'dart:async';
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
class DraftStore extends ChangeNotifier {
  DraftStore({required this.clientName, Future<SharedPreferences>? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance() {
    unawaited(_prefs.then((p) {
      _cache = p;
      _safeNotify();
    }));
  }

  bool _disposed = false;

  /// Notifies listeners unless the store has been disposed. A pending async
  /// [write]/[clear] can resolve after the owning provider tears the store down
  /// on account switch; notifying then would throw.
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static const _prefix = 'draft';

  final String clientName;
  final Future<SharedPreferences> _prefs;

  /// Resolved [SharedPreferences] once ready, enabling synchronous reads for
  /// the room list. Null until the async instance lands, during which
  /// [draftText] reports no draft.
  SharedPreferences? _cache;

  static String _key(String clientName, String roomId) =>
      '$_prefix:$clientName:$roomId';

  Draft? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? Draft.fromJson(json) : null;
    } on FormatException {
      return null;
    }
  }

  /// The stored draft text for [roomId], or null when there is none. Synchronous
  /// so tiles can read it during build; drives the room-list draft indicator.
  String? draftText(String roomId) =>
      _decode(_cache?.getString(_key(clientName, roomId)))?.text;

  Future<Draft?> read(String roomId) async {
    final prefs = await _prefs;
    return _decode(prefs.getString(_key(clientName, roomId)));
  }

  Future<void> write(String roomId, Draft draft) async {
    final prefs = await _prefs;
    _cache = prefs;
    await prefs.setString(
      _key(clientName, roomId),
      jsonEncode(draft.toJson()),
    );
    _safeNotify();
  }

  Future<void> clear(String roomId) async {
    final prefs = await _prefs;
    _cache = prefs;
    await prefs.remove(_key(clientName, roomId));
    _safeNotify();
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
