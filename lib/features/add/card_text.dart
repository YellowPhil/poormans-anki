final _separatorLine = RegExp(r'^[ \t]*---[ \t]*$', multiLine: true);

/// The first standalone `---` line divides front from back; the back is optional.
({String front, String back}) splitCardText(String text) {
  final match = _separatorLine.firstMatch(text);
  if (match == null) return (front: text.trim(), back: '');
  return (
    front: text.substring(0, match.start).trim(),
    back: text.substring(match.end).trim(),
  );
}

String joinCardText(String front, String back) =>
    back.isEmpty ? front : '$front\n---\n$back';

bool hasSeparator(String text) => _separatorLine.hasMatch(text);

({String text, int cursor}) insertSeparator(String text, int cursor) {
  if (hasSeparator(text)) return (text: text, cursor: cursor);
  final prefix = text.endsWith('\n') ? text : '$text\n';
  final next = '$prefix---\n';
  return (text: next, cursor: next.length);
}
