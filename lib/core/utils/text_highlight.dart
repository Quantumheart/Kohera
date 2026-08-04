class HighlightSpan {
  const HighlightSpan(this.text, this.isMatch);
  final String text;
  final bool isMatch;
}

List<HighlightSpan> highlightSpans(String text, List<String> terms) {
  if (terms.isEmpty) return [HighlightSpan(text, false)];

  final lower = text.toLowerCase();
  final lowerTerms =
      terms.map((t) => t.toLowerCase()).where((t) => t.isNotEmpty).toList();
  if (lowerTerms.isEmpty) return [HighlightSpan(text, false)];

  final matches = <_Match>[];
  for (final term in lowerTerms) {
    var start = 0;
    while (start < text.length) {
      final index = lower.indexOf(term, start);
      if (index == -1) break;
      matches.add(_Match(index, index + term.length));
      start = index + 1;
    }
  }
  matches.sort((a, b) => a.start.compareTo(b.start));

  final merged = <_Match>[];
  for (final m in matches) {
    if (merged.isNotEmpty && m.start <= merged.last.end) {
      final last = merged.last;
      merged[merged.length - 1] =
          _Match(last.start, last.end > m.end ? last.end : m.end);
    } else {
      merged.add(m);
    }
  }

  final spans = <HighlightSpan>[];
  var pos = 0;
  for (final m in merged) {
    if (m.start > pos) {
      spans.add(HighlightSpan(text.substring(pos, m.start), false));
    }
    spans.add(HighlightSpan(text.substring(m.start, m.end), true));
    pos = m.end;
  }
  if (pos < text.length) {
    spans.add(HighlightSpan(text.substring(pos), false));
  }

  return spans;
}

class _Match {
  const _Match(this.start, this.end);
  final int start;
  final int end;
}
