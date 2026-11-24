import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kohera/features/chat/services/giphy_service.dart';

GiphyService _service(http.Response Function(http.Request) handler) {
  return GiphyService(
    apiKey: 'test-key',
    client: MockClient((request) async => handler(request)),
  );
}

const _gifJson = '''
{
  "data": [
    {
      "id": "abc123",
      "title": "Happy Cat",
      "images": {
        "downsized": {"url": "https://media.giphy.com/media/abc123/down.gif"},
        "original": {"url": "https://media.giphy.com/media/abc123/orig.gif"}
      }
    },
    {
      "id": "def456",
      "title": "No Downsized",
      "images": {
        "original": {"url": "https://media.giphy.com/media/def456/orig.gif"}
      }
    },
    {
      "id": "ghi789",
      "title": "No Images",
      "images": {}
    }
  ]
}
''';

void main() {
  group('GiphyService', () {
    test('trending builds correct URI and parses results', () async {
      http.Request? captured;
      final service = _service((request) {
        captured = request;
        return http.Response(_gifJson, 200);
      });

      final gifs = await service.trending(offset: 25);

      expect(captured!.url.host, 'api.giphy.com');
      expect(captured!.url.path, '/v1/gifs/trending');
      expect(captured!.url.queryParameters['api_key'], 'test-key');
      expect(captured!.url.queryParameters['offset'], '25');
      expect(captured!.url.queryParameters['limit'], '25');
      expect(captured!.url.queryParameters.containsKey('q'), isFalse);

      expect(gifs, hasLength(2));
      expect(gifs[0].id, 'abc123');
      expect(gifs[0].title, 'Happy Cat');
      expect(gifs[0].sendUrl, 'https://media.giphy.com/media/abc123/down.gif');
      expect(gifs[1].sendUrl, 'https://media.giphy.com/media/def456/orig.gif');
    });

    test('search includes query parameter', () async {
      http.Request? captured;
      final service = _service((request) {
        captured = request;
        return http.Response('{"data": []}', 200);
      });

      final gifs = await service.search('cats');

      expect(captured!.url.path, '/v1/gifs/search');
      expect(captured!.url.queryParameters['q'], 'cats');
      expect(gifs, isEmpty);
    });

    test('search omits empty query parameter', () async {
      http.Request? captured;
      final service = _service((request) {
        captured = request;
        return http.Response('{"data": []}', 200);
      });

      await service.search('');

      expect(captured!.url.queryParameters.containsKey('q'), isFalse);
    });

    test('non-200 response throws GiphyException', () async {
      final service = _service((_) => http.Response('error', 429));

      expect(
        service.trending(),
        throwsA(
          isA<GiphyException>().having(
            (e) => e.message,
            'message',
            contains('429'),
          ),
        ),
      );
    });

    test('malformed items without URLs are skipped', () async {
      final service = _service(
        (_) => http.Response(
          '{"data": [{"id": "x", "title": "t", "images": {}}]}',
          200,
        ),
      );

      expect(await service.trending(), isEmpty);
    });
  });

  group('GiphyGif', () {
    test('previewUrl falls back to original', () {
      const gif = GiphyGif(
        id: '1',
        title: 't',
        downsizedUrl: '',
        originalUrl: 'orig',
      );
      expect(gif.previewUrl, 'orig');
      expect(gif.sendUrl, 'orig');
    });
  });
}
