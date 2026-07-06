import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/space_node.dart';
import 'package:kohera/features/spaces/widgets/space_reparent_controller.dart';
import 'package:kohera/shared/models/kohera_room_summary.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';

@GenerateNiceMocks([MockSpec<Room>()])

KoheraRoomSummary _summary(String id) => KoheraRoomSummary(
  roomId: id,
  displayname: id,
  isDirectChat: false,
  isEncrypted: false,
  isSpace: true,
  notificationCount: 0,
  highlightCount: 0,
  typingDisplayNames: const [],
  pinnedEventIds: const [],
  spaceChildCount: 0,
  isFavourite: false,
  lastEventPreview: 'No messages yet',
  lastEventIsThreadReply: false,
);


void main() {
  // ── Controller state transitions ──────────────────────────
  group('SpaceReparentController', () {
    late SpaceReparentController controller;

    setUp(() => controller = SpaceReparentController());

    test('initial state is not dragging', () {
      expect(controller.isDragging, isFalse);
      expect(controller.draggingData, isNull);
      expect(controller.hoveredHeaderId, isNull);
    });

    test('startDrag sets dragging state', () {
      controller.startDrag(SpaceDragData(spaceId: '!a:x'));
      expect(controller.isDragging, isTrue);
      expect(controller.draggingData, isA<SpaceDragData>());
    });

    test('setHoveredHeader updates and notifies', () {
      var count = 0;
      controller.addListener(() => count++);
      controller.setHoveredHeader('!h:x');
      expect(controller.hoveredHeaderId, '!h:x');
      expect(count, 1);
      // Same value doesn't re-notify.
      controller.setHoveredHeader('!h:x');
      expect(count, 1);
    });

    test('endDrag clears all state', () {
      controller.startDrag(SpaceDragData(spaceId: '!a:x'));
      controller.setHoveredHeader('!h:x');
      controller.endDrag();
      expect(controller.isDragging, isFalse);
      expect(controller.draggingData, isNull);
      expect(controller.hoveredHeaderId, isNull);
    });
  });

  // ── wouldCreateCycle ──────────────────────────────────────
  group('wouldCreateCycle', () {
    // Build a tree: A -> B -> C
    late List<SpaceNode> tree;

    setUp(() {
      tree = [
        SpaceNode(
          summary: _summary('!a:x'),
          subspaces: [
            SpaceNode(
              summary: _summary('!b:x'),
              subspaces: [
                SpaceNode(summary: _summary('!c:x')),
              ],
            ),
          ],
        ),
        SpaceNode(summary: _summary('!d:x')),
      ];
    });

    test('self-drop is a cycle', () {
      expect(wouldCreateCycle(tree, '!a:x', '!a:x'), isTrue);
    });

    test('reparenting D under A is valid (no cycle)', () {
      expect(wouldCreateCycle(tree, '!a:x', '!d:x'), isFalse);
    });

    test('reparenting A under C creates a cycle (A->B->C, C would be parent of A)', () {
      expect(wouldCreateCycle(tree, '!c:x', '!a:x'), isTrue);
    });

    test('reparenting A under B creates a cycle', () {
      expect(wouldCreateCycle(tree, '!b:x', '!a:x'), isTrue);
    });

    test('reparenting B under D is valid', () {
      expect(wouldCreateCycle(tree, '!d:x', '!b:x'), isFalse);
    });

    test('unknown candidate returns false', () {
      expect(wouldCreateCycle(tree, '!a:x', '!unknown:x'), isFalse);
    });
  });
}
