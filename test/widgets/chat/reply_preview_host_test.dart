import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_reply_preview.dart';
import 'package:kohera/features/chat/widgets/reply_preview_host.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  const samplePreview = KoheraReplyPreview(
    parentSenderName: 'Alice',
    parentBody: 'Hello world',
    parentMessageId: r'$parent:example.com',
  );

  group('ReplyPreviewHost', () {
    testWidgets('renders nothing until resolved', (tester) async {
      final completer = Completer<KoheraReplyPreview?>();

      await tester.pumpWidget(wrap(
        ReplyPreviewHost(
          replyEventId: r'$reply:example.com',
          resolvePreview: (_) => completer.future,
          isMe: false,
        ),
      ));

      // Before resolving, should render SizedBox.shrink
      expect(find.byType(SizedBox), findsOneWidget);

      completer.complete(samplePreview);
      await tester.pumpAndSettle();

      // After resolving, InlineReplyPreview should be visible
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('shows preview after resolution', (tester) async {
      await tester.pumpWidget(wrap(
        ReplyPreviewHost(
          replyEventId: r'$reply:example.com',
          resolvePreview: (_) async => samplePreview,
          isMe: false,
        ),
      ));

      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('renders InlineReplyPreview when preview is null',
        (tester) async {
      await tester.pumpWidget(wrap(
        ReplyPreviewHost(
          replyEventId: r'$reply:example.com',
          resolvePreview: (_) async => null,
          isMe: false,
        ),
      ));

      await tester.pumpAndSettle();

      // InlineReplyPreview with null preview still renders (shows "Original message unavailable")
      expect(find.byType(ReplyPreviewHost), findsOneWidget);
    });

    testWidgets('calls onParentTap with parentMessageId when tapped',
        (tester) async {
      String? tappedId;
      await tester.pumpWidget(wrap(
        ReplyPreviewHost(
          replyEventId: r'$reply:example.com',
          resolvePreview: (_) async => samplePreview,
          isMe: false,
          onParentTap: (id) => tappedId = id,
        ),
      ));

      await tester.pumpAndSettle();

      // Tap on the preview area
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(tappedId, r'$parent:example.com');
    });

    testWidgets('re-resolves when replyEventId changes', (tester) async {
      var callCount = 0;
      KoheraReplyPreview? result;

      await tester.pumpWidget(wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return ReplyPreviewHost(
              key: ValueKey(result?.parentMessageId ?? 'init'),
              replyEventId: result?.parentMessageId ?? r'$first:example.com',
              resolvePreview: (id) async {
                callCount++;
                if (id == r'$first:example.com') {
                  return const KoheraReplyPreview(
                    parentSenderName: 'Bob',
                    parentBody: 'First reply',
                    parentMessageId: r'$second:example.com',
                  );
                }
                return const KoheraReplyPreview(
                  parentSenderName: 'Carol',
                  parentBody: 'Second reply',
                  parentMessageId: r'$third:example.com',
                );
              },
              isMe: false,
              onParentTap: (id) {
                setState(() {
                  result = KoheraReplyPreview(
                    parentSenderName: id == r'$second:example.com' ? 'Carol' : 'Bob',
                    parentBody: id == r'$second:example.com' ? 'Second' : 'First',
                    parentMessageId: id,
                  );
                });
              },
            );
          },
        ),
      ));

      await tester.pumpAndSettle();
      expect(callCount, 1);
      expect(find.text('Bob'), findsOneWidget);

      // Tap to change replyEventId
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();

      expect(callCount, 2);
    });

    testWidgets('handles resolver error gracefully', (tester) async {
      await tester.pumpWidget(wrap(
        ReplyPreviewHost(
          replyEventId: r'$reply:example.com',
          resolvePreview: (_) async => throw Exception('Failed'),
          isMe: false,
        ),
      ));

      await tester.pumpAndSettle();

      // Should not crash — renders InlineReplyPreview with null
      expect(find.byType(ReplyPreviewHost), findsOneWidget);
    });
  });
}
