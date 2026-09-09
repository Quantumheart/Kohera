import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/matrix_username.dart';

void main() {
  group('validateLocalpart', () {
    test('accepts a plain lowercase localpart', () {
      expect(validateLocalpart('ada'), isNull);
    });

    test('accepts every character the grammar allows', () {
      expect(validateLocalpart('ada.lovelace_1=x-y/z+w'), isNull);
    });

    test('rejects an empty localpart', () {
      expect(validateLocalpart(''), 'Please enter a username');
    });

    test('rejects uppercase', () {
      expect(validateLocalpart('Ada'), 'Username must be lowercase');
    });

    test('rejects a leading underscore', () {
      expect(
        validateLocalpart('_ada'),
        'Username cannot start with an underscore',
      );
    });

    test('rejects characters outside the grammar', () {
      expect(validateLocalpart('bad@user'), isNotNull);
      expect(validateLocalpart('has space'), isNotNull);
      expect(validateLocalpart('emoji😀'), isNotNull);
    });

    test('rejects a localpart over the length limit', () {
      expect(
        validateLocalpart('a' * (kMaxLocalpartLength + 1)),
        contains('$kMaxLocalpartLength characters'),
      );
      expect(validateLocalpart('a' * kMaxLocalpartLength), isNull);
    });
  });

  group('formatMatrixId', () {
    test('builds a full Matrix ID', () {
      expect(
        formatMatrixId(localpart: 'ada', homeserver: 'matrix.org'),
        '@ada:matrix.org',
      );
    });

    test('strips the scheme', () {
      expect(
        formatMatrixId(localpart: 'ada', homeserver: 'https://matrix.org'),
        '@ada:matrix.org',
      );
    });

    test('strips a trailing path and surrounding whitespace', () {
      expect(
        formatMatrixId(localpart: 'ada', homeserver: '  matrix.org/foo  '),
        '@ada:matrix.org',
      );
    });

    test('keeps an explicit port', () {
      expect(
        formatMatrixId(localpart: 'ada', homeserver: 'https://example.com:8448'),
        '@ada:example.com:8448',
      );
    });

    test('lowercases the server name', () {
      expect(
        formatMatrixId(localpart: 'ada', homeserver: 'Matrix.ORG'),
        '@ada:matrix.org',
      );
    });

    test('omits the server when the homeserver is blank', () {
      expect(formatMatrixId(localpart: 'ada', homeserver: '   '), '@ada');
    });
  });
}
