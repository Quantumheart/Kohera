import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/poll_content.dart';
import 'package:kohera/data/models/kohera_event_types.dart';

const String _startType = KoheraEventTypes.pollStart;
const String _textKey = 'org.matrix.msc1767.text';

Map<String, Object?> _pollContent(String question) => {
      _textKey: question,
      _startType: {
        'kind': 'org.matrix.msc3381.poll.disclosed',
        'max_selections': 1,
        'question': {
          _textKey: question,
          'body': question,
        },
        'answers': [
          {'id': 'a1', _textKey: 'Yes'},
        ],
      },
    };

void main() {
  group('pollBodyFromContent', () {
    test('returns formatted body for poll-start event with question', () {
      expect(
        pollBodyFromContent(_startType, _pollContent('Tea or coffee?')),
        '📊 Poll: Tea or coffee?',
      );
    });

    test('returns generic poll body when question is empty', () {
      expect(pollBodyFromContent(_startType, _pollContent('')), '📊 Poll');
    });

    test('returns null for non-poll event', () {
      expect(
        pollBodyFromContent(KoheraEventTypes.message, const {}),
        isNull,
      );
    });

    test('does not throw on a malformed poll missing org.matrix.msc1767.text',
        () {
      // Reproduces the crash where PollEventContent.fromJson did
      // `mText: json[mTextJsonKey]` with a null value.
      final content = <String, Object?>{
        // No top-level org.matrix.msc1767.text fallback.
        _startType: {
          'kind': 'org.matrix.msc3381.poll.disclosed',
          'max_selections': 1,
          'question': {'body': 'Tea or coffee?'},
          'answers': [
            {'id': 'a1'},
          ],
        },
      };
      expect(
        pollBodyFromContent(_startType, content),
        '📊 Poll: Tea or coffee?',
      );
    });

    test('returns generic body when start content is missing entirely', () {
      expect(pollBodyFromContent(_startType, const {}), '📊 Poll');
    });
  });
}
