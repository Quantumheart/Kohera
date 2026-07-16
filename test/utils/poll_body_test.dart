import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/poll_body.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Event>()])
import 'poll_body_test.mocks.dart';

const String _startType = PollEventContent.startType;

MockEvent _pollEvent(String question) {
  final event = MockEvent();
  when(event.type).thenReturn(_startType);
  when(event.content).thenReturn({
    PollEventContent.mTextJsonKey: question,
    _startType: {
      'kind': 'org.matrix.msc3381.poll.disclosed',
      'max_selections': 1,
      'question': {
        PollEventContent.mTextJsonKey: question,
        'body': question,
      },
      'answers': [
        {'id': 'a1', PollEventContent.mTextJsonKey: 'Yes'},
      ],
    },
  });
  return event;
}

void main() {
  group('pollStartBody', () {
    test('returns formatted body for poll-start event with question', () {
      expect(pollStartBody(_pollEvent('Tea or coffee?')), '📊 Poll: Tea or coffee?');
    });

    test('returns generic poll body when question is empty', () {
      expect(pollStartBody(_pollEvent('')), '📊 Poll');
    });

    test('returns null for non-poll event', () {
      final event = MockEvent();
      when(event.type).thenReturn(EventTypes.Message);
      expect(pollStartBody(event), isNull);
    });
  });
}
