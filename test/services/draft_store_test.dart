import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DraftStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    store = DraftStore(clientName: 'alice');
  });

  group('read/write/clear', () {
    test('returns null when no draft is stored', () async {
      expect(await store.read('!room:server'), isNull);
    });

    test('round-trips text and caret', () async {
      await store.write('!room:server', const Draft(text: 'hello', caret: 2));
      final draft = await store.read('!room:server');
      expect(draft?.text, 'hello');
      expect(draft?.caret, 2);
    });

    test('overwrites an existing draft', () async {
      await store.write('!room:server', const Draft(text: 'first', caret: 5));
      await store.write('!room:server', const Draft(text: 'second', caret: 6));
      final draft = await store.read('!room:server');
      expect(draft?.text, 'second');
    });

    test('clear removes the draft', () async {
      await store.write('!room:server', const Draft(text: 'hi', caret: 2));
      await store.clear('!room:server');
      expect(await store.read('!room:server'), isNull);
    });

    test('drafts are isolated per room', () async {
      await store.write('!a:server', const Draft(text: 'in a', caret: 4));
      await store.write('!b:server', const Draft(text: 'in b', caret: 4));
      expect((await store.read('!a:server'))?.text, 'in a');
      expect((await store.read('!b:server'))?.text, 'in b');
    });
  });

  group('draftText and notifications', () {
    test('draftText returns text once prefs are ready', () async {
      await store.write('!room:server', const Draft(text: 'hi there', caret: 0));
      expect(store.draftText('!room:server'), 'hi there');
    });

    test('draftText is null after a clear', () async {
      await store.write('!room:server', const Draft(text: 'hi', caret: 0));
      await store.clear('!room:server');
      expect(store.draftText('!room:server'), isNull);
    });

    test('notifies listeners on write and clear', () async {
      var notifications = 0;
      store.addListener(() => notifications++);
      await store.write('!room:server', const Draft(text: 'hi', caret: 0));
      await store.clear('!room:server');
      expect(notifications, greaterThanOrEqualTo(2));
    });
  });

  group('account scoping', () {
    test('different accounts do not share drafts', () async {
      final bob = DraftStore(clientName: 'bob');
      await store.write('!room:server', const Draft(text: 'from alice', caret: 0));
      expect(await bob.read('!room:server'), isNull);
    });

    test('clearAccount wipes only the named account', () async {
      final bob = DraftStore(clientName: 'bob');
      await store.write('!room:server', const Draft(text: 'alice draft', caret: 0));
      await bob.write('!room:server', const Draft(text: 'bob draft', caret: 0));

      await DraftStore.clearAccount('alice');

      expect(await store.read('!room:server'), isNull);
      expect((await bob.read('!room:server'))?.text, 'bob draft');
    });
  });

  group('Draft.fromJson', () {
    test('rejects empty text', () {
      expect(Draft.fromJson({'t': '', 'c': 0}), isNull);
    });

    test('falls back to text length when caret is missing', () {
      final draft = Draft.fromJson({'t': 'abc'});
      expect(draft?.caret, 3);
    });
  });
}
