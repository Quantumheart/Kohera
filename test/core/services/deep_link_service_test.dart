import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/deep_link_service.dart';

void main() {
  group('parseDeepLinkUri', () {
    // (uri, expectedIdentifier, expectedAction, expectedVia, expectedEventId)
    const cases = <(String, String, String?, List<String>, String?)>[
      // ── matrix: scheme ───────────────────────────────────────────
      // query string must NOT be glued onto the identifier (#1).
      (
        'matrix:u/alice%3Aexample.org?action=chat',
        '@alice:example.org',
        'chat',
        [],
        null,
      ),
      // room id with action + via servers (the fork's join links).
      (
        'matrix:roomid/!id%3Aexample.org?action=join&via=server.one&via=server.two',
        '!id:example.org',
        'join',
        ['server.one', 'server.two'],
        null,
      ),
      // room id WITHOUT a leading `!` (spec form) — sigil is implied.
      (
        'matrix:roomid/id%3Aexample.org?action=join',
        '!id:example.org',
        'join',
        [],
        null,
      ),
      // room alias.
      (
        'matrix:r/room%3Aexample.org?action=join',
        '#room:example.org',
        'join',
        [],
        null,
      ),
      // event link by alias (matrix:r/<alias>/e/<event>) (#3).
      (
        r'matrix:r/room%3Aexample.org/e/$event%3Aexample.org',
        '#room:example.org',
        null,
        [],
        r'$event:example.org',
      ),
      // event link by room id (matrix:roomid/<id>/e/<event>) (#3).
      (
        r'matrix:roomid/!id%3Aexample.org/e/$event%3Aexample.org',
        '!id:example.org',
        null,
        [],
        r'$event:example.org',
      ),
      // ── custom scheme ─────────────────────────────────────────────
      // pathSegments are already decoded — must not double-decode (#2b),
      // and an encoded '#' sigil (fork-side fix) survives.
      (
        'io.github.quantumheart.kohera://chat/%23room%3Aexample.org',
        '#room:example.org',
        null,
        [],
        null,
      ),
      (
        'io.github.quantumheart.kohera://chat/%21id%3Aexample.org',
        '!id:example.org',
        null,
        [],
        null,
      ),
      (
        'io.github.quantumheart.kohera://chat/%40alice%3Aexample.org',
        '@alice:example.org',
        null,
        [],
        null,
      ),
      // custom scheme with the wrong host is ignored.
      ('io.github.quantumheart.kohera://other/something', '', null, [], null),
      // ── https://matrix.to ──────────────────────────────────────────
      (
        'https://matrix.to/#/%21id%3Aexample.org',
        '!id:example.org',
        null,
        [],
        null,
      ),
      // alias via matrix.to (the '#' starts the fragment, the sigil '#' is
      // the first char of the identifier).
      (
        'https://matrix.to/#/%23room%3Aexample.org',
        '#room:example.org',
        null,
        [],
        null,
      ),
      // matrix.to with an event id segment (#3).
      (
        r'https://matrix.to/#/%21id%3Aexample.org/$event%3Aexample.org',
        '!id:example.org',
        null,
        [],
        r'$event:example.org',
      ),
      // matrix.to with ?via= servers (the query lives inside the fragment).
      (
        'https://matrix.to/#/%23room%3Aexample.org?via=server.one',
        '#room:example.org',
        null,
        ['server.one'],
        null,
      ),
      // empty matrix.to fragment is ignored.
      ('https://matrix.to/#/', '', null, [], null),
      // ── real-world shapes (raw `#` sigil, unencoded colon) ─────────
      // The exact link from the issue: matrix.to with a raw `#` alias.
      (
        'https://matrix.to/#/#freenet-locutus:matrix.org',
        '#freenet-locutus:matrix.org',
        null,
        [],
        null,
      ),
      // matrix: alias join link for the same room.
      (
        'matrix:r/freenet-locutus:matrix.org?action=join',
        '#freenet-locutus:matrix.org',
        'join',
        [],
        null,
      ),
      // ── exact shapes the Kohera matrix.to fork emits ───────────────
      // Desktop matrix: URIs strip the sigil (and the `$` from event ids);
      // the parser must re-add them.
      (
        'matrix:roomid/room123%3Amatrix.org?action=join&via=matrix.org',
        '!room123:matrix.org',
        'join',
        ['matrix.org'],
        null,
      ),
      (
        'matrix:roomid/room123%3Amatrix.org/e/event456%3Amatrix.org?action=join',
        '!room123:matrix.org',
        'join',
        [],
        r'$event456:matrix.org',
      ),
      (
        'matrix:r/freenet-locutus%3Amatrix.org/e/event456%3Amatrix.org?action=join&via=matrix.org',
        '#freenet-locutus:matrix.org',
        'join',
        ['matrix.org'],
        r'$event456:matrix.org',
      ),
    ];

    for (final (uri, identifier, action, via, eventId) in cases) {
      test('parses "$uri"', () {
        final parsed = parseDeepLinkUri(Uri.parse(uri));
        if (identifier.isEmpty) {
          expect(parsed, isNull, reason: '$uri should not produce an intent');
          return;
        }
        expect(parsed, isNotNull, reason: '$uri should parse');
        expect(parsed!.identifier, identifier);
        expect(parsed.action, action);
        expect(parsed.via, via);
        expect(parsed.eventId, eventId);
      });
    }

    test('returns null for an unrecognised scheme', () {
      expect(parseDeepLinkUri(Uri.parse('https://example.com/rooms/foo')),
          isNull);
    });

    test('returns null for a matrix: uri missing the identifier', () {
      expect(parseDeepLinkUri(Uri.parse('matrix:u')), isNull);
    });
  });
}
