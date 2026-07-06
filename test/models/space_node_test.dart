import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/space_node.dart';
import 'package:kohera/shared/models/kohera_room_summary.dart';

void main() {
  group('SpaceNode', () {
    test('creates with defaults', () {
      const summary = KoheraRoomSummary(
        roomId: '!space:x.com',
        displayname: 'Test Space',
        isDirectChat: false,
        isEncrypted: false,
        isSpace: true,
        notificationCount: 0,
        highlightCount: 0,
        typingDisplayNames: [],
        pinnedEventIds: [],
        spaceChildCount: 0,
        isFavourite: false,
        lastEventPreview: 'No messages yet',
        lastEventIsThreadReply: false,
      );
      const node = SpaceNode(summary: summary);
      expect(node.summary, summary);
      expect(node.subspaces, isEmpty);
      expect(node.directChildRoomIds, isEmpty);
    });

    test('creates with subspaces and child room IDs', () {
      const parentSummary = KoheraRoomSummary(
        roomId: '!parent:x.com',
        displayname: 'Parent',
        isDirectChat: false,
        isEncrypted: false,
        isSpace: true,
        notificationCount: 0,
        highlightCount: 0,
        typingDisplayNames: [],
        pinnedEventIds: [],
        spaceChildCount: 0,
        isFavourite: false,
        lastEventPreview: 'No messages yet',
        lastEventIsThreadReply: false,
      );
      const childSummary = KoheraRoomSummary(
        roomId: '!child:x.com',
        displayname: 'Child',
        isDirectChat: false,
        isEncrypted: false,
        isSpace: true,
        notificationCount: 0,
        highlightCount: 0,
        typingDisplayNames: [],
        pinnedEventIds: [],
        spaceChildCount: 0,
        isFavourite: false,
        lastEventPreview: 'No messages yet',
        lastEventIsThreadReply: false,
      );
      const childNode = SpaceNode(summary: childSummary);

      const node = SpaceNode(
        summary: parentSummary,
        subspaces: [childNode],
        directChildRoomIds: ['!room1:x.com', '!room2:x.com'],
      );

      expect(node.subspaces, hasLength(1));
      expect(node.subspaces[0].summary, childSummary);
      expect(node.directChildRoomIds, ['!room1:x.com', '!room2:x.com']);
    });
  });
}
