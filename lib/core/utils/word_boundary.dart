final RegExp _wordCharacter = RegExp(r'[\p{L}\p{M}\p{N}_]', unicode: true);

/// Whether [text] contains [word] bounded by non-word characters or string
/// edges. Word characters are Unicode letters, marks, digits and underscore,
/// so boundaries behave correctly for Cyrillic, CJK, Greek and accented names.
bool containsWord(String text, String word) {
  if (word.isEmpty) return false;
  var start = 0;
  while (true) {
    final index = text.indexOf(word, start);
    if (index == -1) return false;
    if (!_isWordCharacter(_characterBefore(text, index)) &&
        !_isWordCharacter(_characterAfter(text, index + word.length))) {
      return true;
    }
    start = index + 1;
  }
}

bool _isWordCharacter(String character) =>
    character.isNotEmpty && _wordCharacter.hasMatch(character);

String _characterBefore(String text, int index) {
  if (index <= 0) return '';
  final start = _isLowSurrogate(text.codeUnitAt(index - 1)) &&
          index >= 2 &&
          _isHighSurrogate(text.codeUnitAt(index - 2))
      ? index - 2
      : index - 1;
  return text.substring(start, index);
}

String _characterAfter(String text, int index) {
  if (index >= text.length) return '';
  final end = _isHighSurrogate(text.codeUnitAt(index)) &&
          index + 1 < text.length &&
          _isLowSurrogate(text.codeUnitAt(index + 1))
      ? index + 2
      : index + 1;
  return text.substring(index, end);
}

bool _isHighSurrogate(int unit) => (unit & 0xFC00) == 0xD800;

bool _isLowSurrogate(int unit) => (unit & 0xFC00) == 0xDC00;
