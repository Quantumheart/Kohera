import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/share_in/models/incoming_share.dart';

void main() {
  group('IncomingShareFile', () {
    test('round-trips through JSON with mimeType', () {
      const file = IncomingShareFile(
        filePath: '/share_in/abc_pic.png',
        name: 'pic.png',
        mimeType: 'image/png',
      );
      final decoded = IncomingShareFile.fromJson(file.toJson());
      expect(decoded.filePath, file.filePath);
      expect(decoded.name, file.name);
      expect(decoded.mimeType, file.mimeType);
    });

    test('falls back to filePath for missing name', () {
      final decoded = IncomingShareFile.fromJson(const {
        'filePath': '/share_in/abc.txt',
      });
      expect(decoded.name, '/share_in/abc.txt');
      expect(decoded.mimeType, isNull);
    });
  });

  group('IncomingShare', () {
    test('text-only round-trip', () {
      const share = IncomingShare(text: 'hello world');
      final decoded = IncomingShare.decode(share.encode());
      expect(decoded.text, 'hello world');
      expect(decoded.files, isEmpty);
      expect(decoded.isEmpty, isFalse);
    });

    test('files round-trip', () {
      const share = IncomingShare(
        text: 'caption',
        files: [
          IncomingShareFile(
            filePath: '/a/p.png',
            name: 'p.png',
            mimeType: 'image/png',
          ),
          IncomingShareFile(filePath: '/a/d.pdf', name: 'doc.pdf'),
        ],
      );
      final decoded = IncomingShare.decode(share.encode());
      expect(decoded.text, 'caption');
      expect(decoded.files.length, 2);
      expect(decoded.files.first.filePath, '/a/p.png');
      expect(decoded.files.last.mimeType, isNull);
    });

    test('isEmpty when blank', () {
      const blank = IncomingShare(text: '');
      expect(blank.isEmpty, isTrue);
    });

    test('isEmpty when null text and no files', () {
      const blank = IncomingShare();
      expect(blank.isEmpty, isTrue);
    });

    test('omit empty text from JSON', () {
      const share = IncomingShare(
        text: '',
        files: [IncomingShareFile(filePath: '/x', name: 'x')],
      );
      final json = share.toJson();
      expect(json.containsKey('text'), isFalse);
      expect(json.containsKey('files'), isTrue);
    });
  });
}
