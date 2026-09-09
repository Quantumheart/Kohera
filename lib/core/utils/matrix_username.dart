/// Longest localpart the Matrix spec allows once `@` and `:server` are added.
const int kMaxLocalpartLength = 255;

final RegExp _validLocalpart = RegExp(r'^[a-z0-9._=\-/+]+$');
final RegExp _uppercase = RegExp('[A-Z]');

/// Validates a Matrix user ID localpart, returning `null` when it is usable.
///
/// Mirrors the grammar in the client-server spec so the form can reject
/// hopeless usernames before spending a round trip on the homeserver.
String? validateLocalpart(String localpart) {
  if (localpart.isEmpty) return 'Please enter a username';
  if (localpart.length > kMaxLocalpartLength) {
    return 'Username must be $kMaxLocalpartLength characters or fewer';
  }
  if (localpart.startsWith('_')) {
    return 'Username cannot start with an underscore';
  }
  if (_uppercase.hasMatch(localpart)) {
    return 'Username must be lowercase';
  }
  if (!_validLocalpart.hasMatch(localpart)) {
    return 'Use only letters, numbers and . _ = - / +';
  }
  return null;
}

/// Renders the full Matrix ID a [localpart] would claim on [homeserver].
///
/// [homeserver] may be typed with or without a scheme, port, path, or
/// surrounding whitespace; all are reduced to the bare server name.
String formatMatrixId({
  required String localpart,
  required String homeserver,
}) {
  final serverName = _serverName(homeserver);
  if (serverName.isEmpty) return '@$localpart';
  return '@$localpart:$serverName';
}

String _serverName(String homeserver) {
  var value = homeserver.trim().toLowerCase();
  if (value.isEmpty) return '';
  value = value.replaceFirst(RegExp('^[a-z][a-z0-9+.-]*://'), '');
  value = value.split('/').first;
  return value;
}
