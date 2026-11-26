import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/models/kohera_thread_summary.dart';
import 'package:kohera/features/chat/services/thread_summary.dart';

void main() {
  KoheraThreadSummary summaryWith({required int unreadCount}) {
    return KoheraThreadSummary(
      rootEventId: r'$r',
      rootBody: 'Root',
      rootRedacted: false,
      rootTimestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      replyCount: 0,
      unreadCount: unreadCount,
      lastActivity: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  group('totalThreadUnread', () {
    test('sums unread across summaries', () {
      final summaries = [
        summaryWith(unreadCount: 2),
        summaryWith(unreadCount: 3),
        summaryWith(unreadCount: 0),
      ];
      expect(totalThreadUnread(summaries), 5);
    });

    test('empty list sums to zero', () {
      expect(totalThreadUnread(const []), 0);
    });
  });
}
