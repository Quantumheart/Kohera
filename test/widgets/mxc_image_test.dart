// ignore_for_file: prefer_const_constructors
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/services/media_resolver.dart';
import 'package:kohera/shared/widgets/mxc_image.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<MediaResolver>()])
import 'mxc_image_test.mocks.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  group('MxcImage', () {
    testWidgets('shows SizedBox while loading', (tester) async {
      final resolver = MockMediaResolver();
      // Never resolve — keep it pending
      when(resolver.resolve(any,
              width: anyNamed('width'), height: anyNamed('height')))
          .thenAnswer((_) => Completer<MediaThumbnail?>().future);

      await tester.pumpWidget(wrap(
        MxcImage(
          mxcUrl: 'mxc://example.org/abc',
          mediaResolver: resolver,
          width: 48,
          height: 48,
          fallbackText: 'No image',
          fallbackStyle: const TextStyle(fontSize: 12),
        ),
      ));

      // First frame: loading state shows SizedBox
      await tester.pump();
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('shows Image.network after successful resolution',
        (tester) async {
      final resolver = MockMediaResolver();
      when(resolver.resolve(any,
              width: anyNamed('width'), height: anyNamed('height')))
          .thenAnswer((_) async => const MediaThumbnail(
                url: 'https://cdn.example.org/abc',
                headers: {'Authorization': 'Bearer token'},
              ));

      await tester.pumpWidget(wrap(
        MxcImage(
          mxcUrl: 'mxc://example.org/abc',
          mediaResolver: resolver,
          width: 48,
          height: 48,
          fallbackText: 'No image',
          fallbackStyle: const TextStyle(fontSize: 12),
        ),
      ));

      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
    });

    testWidgets('shows fallback text when resolution returns null',
        (tester) async {
      final resolver = MockMediaResolver();
      when(resolver.resolve(any,
              width: anyNamed('width'), height: anyNamed('height')))
          .thenAnswer((_) async => null);

      await tester.pumpWidget(wrap(
        MxcImage(
          mxcUrl: 'mxc://example.org/abc',
          mediaResolver: resolver,
          width: 48,
          height: 48,
          fallbackText: 'No image',
          fallbackStyle: const TextStyle(fontSize: 12),
        ),
      ));

      await tester.pumpAndSettle();

      expect(find.text('No image'), findsOneWidget);
    });

    testWidgets('shows fallback text when mediaResolver is null and url is mxc',
        (tester) async {
      await tester.pumpWidget(wrap(
        MxcImage(
          mxcUrl: 'mxc://example.org/abc',
          mediaResolver: null,
          width: 48,
          height: 48,
          fallbackText: 'No image',
          fallbackStyle: const TextStyle(fontSize: 12),
        ),
      ));

      await tester.pumpAndSettle();

      // mxc:// URL without resolver → _resolvedUrl stays null → fallback
      expect(find.text('No image'), findsOneWidget);
    });

    testWidgets('uses http URL directly when resolver is null and url is http',
        (tester) async {
      await tester.pumpWidget(wrap(
        MxcImage(
          mxcUrl: 'https://example.org/img.png',
          mediaResolver: null,
          width: 48,
          height: 48,
          fallbackText: 'No image',
          fallbackStyle: const TextStyle(fontSize: 12),
        ),
      ));

      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
    });

    testWidgets('shows fallback text when resolver throws', (tester) async {
      final resolver = MockMediaResolver();
      when(resolver.resolve(any,
              width: anyNamed('width'), height: anyNamed('height')))
          .thenThrow(Exception('Resolution failed'));

      await tester.pumpWidget(wrap(
        MxcImage(
          mxcUrl: 'mxc://example.org/abc',
          mediaResolver: resolver,
          width: 48,
          height: 48,
          fallbackText: 'Error',
          fallbackStyle: const TextStyle(fontSize: 12),
        ),
      ));

      await tester.pumpAndSettle();

      expect(find.text('Error'), findsOneWidget);
    });

    testWidgets('re-resolves when mxcUrl changes', (tester) async {
      var callCount = 0;
      final resolver = MockMediaResolver();
      when(resolver.resolve(any,
              width: anyNamed('width'), height: anyNamed('height')))
          .thenAnswer((inv) async {
            callCount++;
            final url = inv.positionalArguments[0] as String;
            return MediaThumbnail(url: 'https://cdn/$url');
          });

      await tester.pumpWidget(wrap(
        MxcImage(
          mxcUrl: 'mxc://example.org/first',
          mediaResolver: resolver,
          width: 48,
          height: 48,
          fallbackText: 'No image',
          fallbackStyle: const TextStyle(fontSize: 12),
        ),
      ));
      await tester.pumpAndSettle();
      expect(callCount, 1);

      // Change the URL
      await tester.pumpWidget(wrap(
        MxcImage(
          mxcUrl: 'mxc://example.org/second',
          mediaResolver: resolver,
          width: 48,
          height: 48,
          fallbackText: 'No image',
          fallbackStyle: const TextStyle(fontSize: 12),
        ),
      ));
      await tester.pumpAndSettle();

      expect(callCount, 2);
    });
  });
}
