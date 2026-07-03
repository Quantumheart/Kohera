import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_reaction.dart';

void main() {
  group('KoheraReactor', () {
    test('constructs with all fields', () {
      const reactor = KoheraReactor(
        senderId: '@alice:example.com',
        displayName: 'Alice',
        avatarUrl: 'mxc://example.com/avatar',
      );

      expect(reactor.senderId, '@alice:example.com');
      expect(reactor.displayName, 'Alice');
      expect(reactor.avatarUrl, 'mxc://example.com/avatar');
    });

    test('equality is based on senderId', () {
      const a = KoheraReactor(senderId: '@alice:example.com', displayName: 'A');
      const b = KoheraReactor(senderId: '@alice:example.com', displayName: 'B');
      const c = KoheraReactor(senderId: '@bob:example.com');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith preserves un-overridden fields', () {
      const reactor = KoheraReactor(
        senderId: '@alice:example.com',
        displayName: 'Alice',
        avatarUrl: 'mxc://example.com/avatar',
      );

      final copy = reactor.copyWith(displayName: 'Alice 2');
      expect(copy.senderId, '@alice:example.com');
      expect(copy.displayName, 'Alice 2');
      expect(copy.avatarUrl, 'mxc://example.com/avatar');
    });

    test('toString includes senderId', () {
      const reactor = KoheraReactor(senderId: '@alice:example.com');
      expect(reactor.toString(), contains('@alice:example.com'));
    });
  });

  group('KoheraReaction', () {
    test('constructs with all fields', () {
      const reaction = KoheraReaction(
        key: '👍',
        count: 3,
        reactedByMe: true,
        reactors: [],
      );

      expect(reaction.key, '👍');
      expect(reaction.count, 3);
      expect(reaction.reactedByMe, isTrue);
      expect(reaction.reactors, isEmpty);
    });

    test('equality is based on key', () {
      const a = KoheraReaction(
        key: '👍',
        count: 1,
        reactedByMe: false,
        reactors: [],
      );
      const b = KoheraReaction(
        key: '👍',
        count: 5,
        reactedByMe: true,
        reactors: [],
      );
      const c = KoheraReaction(
        key: '❤️',
        count: 1,
        reactedByMe: false,
        reactors: [],
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith preserves un-overridden fields', () {
      const reaction = KoheraReaction(
        key: '👍',
        count: 2,
        reactedByMe: false,
        reactors: [],
      );

      final copy = reaction.copyWith(reactedByMe: true);
      expect(copy.key, '👍');
      expect(copy.count, 2);
      expect(copy.reactedByMe, isTrue);
    });

    test('toString includes key and count', () {
      const reaction = KoheraReaction(
        key: '👍',
        count: 3,
        reactedByMe: true,
        reactors: [],
      );
      final str = reaction.toString();
      expect(str, contains('👍'));
      expect(str, contains('3'));
    });
  });

  group('KoheraReactionList', () {
    test('isEmpty is true for empty list', () {
      const list = KoheraReactionList([]);
      expect(list.isEmpty, isTrue);
      expect(list.isNotEmpty, isFalse);
    });

    test('isNotEmpty is true for non-empty list', () {
      const list = KoheraReactionList([
        KoheraReaction(
          key: '👍',
          count: 1,
          reactedByMe: false,
          reactors: [],
        ),
      ]);
      expect(list.isEmpty, isFalse);
      expect(list.isNotEmpty, isTrue);
    });

    test('toString includes reaction count', () {
      const list = KoheraReactionList([
        KoheraReaction(
          key: '👍',
          count: 1,
          reactedByMe: false,
          reactors: [],
        ),
        KoheraReaction(
          key: '❤️',
          count: 2,
          reactedByMe: true,
          reactors: [],
        ),
      ]);
      expect(list.toString(), contains('2 reactions'));
    });
  });
}
