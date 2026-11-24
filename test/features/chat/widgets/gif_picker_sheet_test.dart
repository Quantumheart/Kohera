import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kohera/features/chat/services/giphy_service.dart';
import 'package:kohera/features/chat/widgets/gif_picker_sheet.dart';
import 'package:material_ui/material_ui.dart';

class _FakeGiphyService extends GiphyService {
  _FakeGiphyService({required this.trendingResult})
    : super(
        apiKey: 'test',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

  final List<GiphyGif> trendingResult;
  String? lastQuery;

  @override
  Future<List<GiphyGif>> trending({int offset = 0}) async => trendingResult;

  @override
  Future<List<GiphyGif>> search(String query, {int offset = 0}) async {
    lastQuery = query;
    return trendingResult;
  }
}

const _gif1 = GiphyGif(
  id: '1',
  title: 'One',
  downsizedUrl: 'https://example.com/1.gif',
  originalUrl: 'https://example.com/1o.gif',
);

const _gif2 = GiphyGif(
  id: '2',
  title: 'Two',
  downsizedUrl: 'https://example.com/2.gif',
  originalUrl: 'https://example.com/2o.gif',
);

void main() {
  testWidgets('shows trending GIFs in a grid', (tester) async {
    final service = _FakeGiphyService(trendingResult: const [_gif1, _gif2]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, child: GifPickerSheet(service: service)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(2));
    expect(find.text('Powered by GIPHY'), findsOneWidget);
  });

  testWidgets('tapping a GIF pops the sheet with it', (tester) async {
    final service = _FakeGiphyService(trendingResult: const [_gif1]);
    GiphyGif? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showGifPickerSheet(context, service: service);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ClipRRect).first);
    await tester.pumpAndSettle();

    expect(result, _gif1);
  });

  testWidgets('search field triggers debounced search', (tester) async {
    final service = _FakeGiphyService(trendingResult: const [_gif1]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, child: GifPickerSheet(service: service)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'cats');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(service.lastQuery, 'cats');
  });

  testWidgets('empty results show placeholder text', (tester) async {
    final service = _FakeGiphyService(trendingResult: const []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, child: GifPickerSheet(service: service)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No GIFs found'), findsOneWidget);
  });
}
