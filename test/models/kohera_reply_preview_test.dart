import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_reply_preview.dart';

void main() {
  group('KoheraReplyPreview', () {
    test('constructs with all fields', () {
      const preview = KoheraReplyPreview(
        parentSenderName: 'Alice',
        parentBody: 'Hello world',
        parentFormattedHtml: '<b>Hello world</b>',
        parentMessageId: r'$123:example.com',
        parentSenderId: '@alice:example.com',
      );

      expect(preview.parentSenderName, 'Alice');
      expect(preview.parentBody, 'Hello world');
      expect(preview.parentFormattedHtml, '<b>Hello world</b>');
      expect(preview.parentMessageId, r'$123:example.com');
      expect(preview.parentSenderId, '@alice:example.com');
    });

    test('two previews with same parentMessageId are equal', () {
      const a = KoheraReplyPreview(
        parentSenderName: 'Alice',
        parentBody: 'Hello',
        parentMessageId: r'$1',
        parentSenderId: '@a:s',
      );
      const b = KoheraReplyPreview(
        parentSenderName: 'Bob',
        parentBody: 'Different',
        parentMessageId: r'$1',
        parentSenderId: '@b:s',
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('two previews with different parentMessageId are not equal', () {
      const a = KoheraReplyPreview(
        parentSenderName: 'Alice',
        parentBody: 'Hello',
        parentMessageId: r'$1',
      );
      const b = KoheraReplyPreview(
        parentSenderName: 'Alice',
        parentBody: 'Hello',
        parentMessageId: r'$2',
      );

      expect(a, isNot(equals(b)));
    });

    test('copyWith updates only specified fields', () {
      const original = KoheraReplyPreview(
        parentSenderName: 'Alice',
        parentBody: 'Hello',
        parentMessageId: r'$1',
        parentSenderId: '@alice:s',
      );

      final updated = original.copyWith(parentBody: 'Updated text');

      expect(updated.parentBody, 'Updated text');
      expect(updated.parentSenderName, 'Alice');
      expect(updated.parentMessageId, r'$1');
      expect(updated.parentSenderId, '@alice:s');
    });

    test('copyWith with no args returns equivalent copy', () {
      const original = KoheraReplyPreview(
        parentSenderName: 'Alice',
        parentBody: 'Hello',
        parentMessageId: r'$1',
      );

      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('toString contains parentMessageId', () {
      const preview = KoheraReplyPreview(
        parentSenderName: 'Alice',
        parentBody: 'Hello',
        parentMessageId: r'$123',
        parentSenderId: '@alice:s',
      );

      expect(preview.toString(), contains(r'$123'));
      expect(preview.toString(), contains('Alice'));
    });
  });
}
