/// Utilities for parsing a user-entered Matrix room address.
library;

/// A parsed Matrix room address: a room ID or alias plus optional via servers.
///
/// [address] is always a room ID (`!id:server`) or alias (`#alias:server`).
/// [via] is extracted from `?via=` query parameters on `matrix.to` links.
class ParsedMatrixAddress {
  const ParsedMatrixAddress({required this.address, this.via});

  /// The room ID (`!id:server`) or alias (`#alias:server`) to join.
  final String address;

  /// Via server names to use when joining (from `?via=` params), if any.
  final List<String>? via;
}

/// Parses a raw user-entered Matrix address into a [ParsedMatrixAddress].
///
/// Accepts:
/// - A room alias: `#alias:server.org`
/// - A room ID: `!id:server.org`
/// - A `matrix.to` link: `https://matrix.to/#/#alias:server.org?via=s1&via=s2`
///   or `https://matrix.to/#/!id:server.org/$eventId`
///
/// Returns `null` if [input] is empty or not a recognised room/space address.
/// User identifiers (`@user:server`) are rejected — only rooms and spaces.
ParsedMatrixAddress? parseMatrixAddress(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  // Strip the matrix.to prefix, leaving the identifier (and any query/path).
  var body = trimmed;
  if (trimmed.startsWith('https://matrix.to/#/') ||
      trimmed.startsWith('http://matrix.to/#/')) {
    body = trimmed.substring(trimmed.indexOf('#/') + 2);
  }

  // Split off a query string (via params) — only meaningful for matrix.to links.
  String? query;
  final q = body.indexOf('?');
  if (q >= 0) {
    query = body.substring(q + 1);
    body = body.substring(0, q);
  }

  // Strip an event-id path segment if present (e.g. "!room:server/$eventId").
  final slash = body.indexOf('/');
  if (slash >= 0) {
    body = body.substring(0, slash);
  }

  final identifier = Uri.decodeComponent(body);
  if (!_isRoomIdOrAlias(identifier)) return null;

  List<String>? via;
  if (query != null && query.isNotEmpty) {
    final extracted = _extractVia(query);
    via = extracted.isEmpty ? null : extracted;
  }
  return ParsedMatrixAddress(address: identifier, via: via);
}

/// Whether [s] looks like a Matrix room ID (`!…:server`) or alias (`#…:server`).
bool _isRoomIdOrAlias(String s) {
  if (s.length < 3) return false;
  final sigil = s[0];
  if (sigil != '#' && sigil != '!') return false;
  final colon = s.indexOf(':');
  if (colon <= 1) return false; // need a localpart and a server part
  return _idCharRegex.hasMatch(s);
}

// Room ID/alias localpart + server. Permissive but rejects whitespace, sigils
// in the middle, and query/fragment characters. The SDK performs the real
// validation when joining.
final _idCharRegex = RegExp(r'^[#!][A-Za-z0-9._=\-+/]+:[A-Za-z0-9.:\-]+$');

/// Extracts all `via=…` values from a query string, preserving order and
/// repeated keys (`?via=s1&via=s2` → `['s1', 's2']`).
List<String> _extractVia(String queryString) {
  final result = <String>[];
  for (final pair in queryString.split('&')) {
    final eq = pair.indexOf('=');
    if (eq < 0) continue;
    final key = pair.substring(0, eq);
    final value = pair.substring(eq + 1);
    if (key == 'via' && value.isNotEmpty) {
      result.add(Uri.decodeComponent(value));
    }
  }
  return result;
}
