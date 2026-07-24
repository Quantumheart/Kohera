import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/matrix_address_parser.dart';

void main() {
  group('parseMatrixAddress', () {
    test('parses a room alias', () {
      final result = parseMatrixAddress('#general:example.com');
      expect(result, isNotNull);
      expect(result!.address, '#general:example.com');
      expect(result.via, isNull);
    });

    test('parses a room ID', () {
      final result = parseMatrixAddress('!abc123:example.com');
      expect(result, isNotNull);
      expect(result!.address, '!abc123:example.com');
      expect(result.via, isNull);
    });

    test('parses a matrix.to link with an alias', () {
      final result = parseMatrixAddress('https://matrix.to/#/#space:example.com');
      expect(result, isNotNull);
      expect(result!.address, '#space:example.com');
      expect(result.via, isNull);
    });

    test('parses a matrix.to link with a room ID', () {
      final result = parseMatrixAddress('https://matrix.to/#/!room:example.com');
      expect(result, isNotNull);
      expect(result!.address, '!room:example.com');
    });

    test('extracts multiple via servers from a matrix.to link', () {
      final result = parseMatrixAddress(
        'https://matrix.to/#/#room:example.com?via=s1.org&via=s2.org',
      );
      expect(result, isNotNull);
      expect(result!.address, '#room:example.com');
      expect(result.via, ['s1.org', 's2.org']);
    });

    test('extracts a single via server', () {
      final result = parseMatrixAddress(
        'https://matrix.to/#/!room:example.com?via=via.example.org',
      );
      expect(result, isNotNull);
      expect(result!.address, '!room:example.com');
      expect(result.via, ['via.example.org']);
    });

    test('strips an event-id path segment from a matrix.to link', () {
      final result = parseMatrixAddress(
        r'https://matrix.to/#/!room:example.com/$event:example.com',
      );
      expect(result, isNotNull);
      expect(result!.address, '!room:example.com');
    });

    test('strips an event-id path segment from a raw room ID permalink', () {
      final result = parseMatrixAddress(
        r'!room:example.com/$event:example.com',
      );
      expect(result, isNotNull);
      expect(result!.address, '!room:example.com');
    });

    test('accepts http matrix.to links', () {
      final result = parseMatrixAddress('http://matrix.to/#/#room:example.com');
      expect(result, isNotNull);
      expect(result!.address, '#room:example.com');
    });

    test('trims surrounding whitespace', () {
      final result = parseMatrixAddress('  #room:example.com  ');
      expect(result, isNotNull);
      expect(result!.address, '#room:example.com');
    });

    test('rejects empty input', () {
      expect(parseMatrixAddress(''), isNull);
      expect(parseMatrixAddress('   '), isNull);
    });

    test('rejects a user identifier (@user:server)', () {
      expect(parseMatrixAddress('@alice:example.com'), isNull);
      expect(
        parseMatrixAddress('https://matrix.to/#/@alice:example.com'),
        isNull,
      );
    });

    test('rejects arbitrary text', () {
      expect(parseMatrixAddress('hello world'), isNull);
      expect(parseMatrixAddress('https://example.com'), isNull);
    });

    test('rejects an identifier without a server part', () {
      expect(parseMatrixAddress('#nocolon'), isNull);
      expect(parseMatrixAddress('!nocolon'), isNull);
    });

    test('returns null via when query has no via params', () {
      final result = parseMatrixAddress(
        'https://matrix.to/#/#room:example.com?other=foo',
      );
      expect(result, isNotNull);
      expect(result!.address, '#room:example.com');
      expect(result.via, isNull);
    });
  });
}
