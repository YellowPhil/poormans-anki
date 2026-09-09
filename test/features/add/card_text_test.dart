import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/features/add/card_text.dart';

void main() {
  group('splitCardText', () {
    test('splits on the first standalone --- line', () {
      final (:front, :back) = splitCardText("l'eau\n---\nwater");
      expect(front, "l'eau");
      expect(back, 'water');
    });

    test('without a separator the back is empty', () {
      final (:front, :back) = splitCardText('just a note\nsecond line');
      expect(front, 'just a note\nsecond line');
      expect(back, '');
    });

    test('later --- lines stay in the back', () {
      final (:front, :back) = splitCardText('a\n---\nb\n---\nc');
      expect(front, 'a');
      expect(back, 'b\n---\nc');
    });

    test(
      'tolerates surrounding whitespace on the separator and trims sides',
      () {
        final (:front, :back) = splitCardText('  a  \n ---  \n\n b \n');
        expect(front, 'a');
        expect(back, 'b');
      },
    );

    test('inline --- inside a line is not a separator', () {
      final (:front, :back) = splitCardText('a --- b\nc');
      expect(front, 'a --- b\nc');
      expect(back, '');
    });
  });

  test('joinCardText round-trips through splitCardText', () {
    final text = joinCardText('front', 'back');
    expect(text, 'front\n---\nback');
    final (:front, :back) = splitCardText(text);
    expect((front, back), ('front', 'back'));
    expect(joinCardText('only', ''), 'only');
  });

  group('insertSeparator', () {
    test(
      'appends separator after the text and puts the cursor on the new line',
      () {
        final (:text, :cursor) = insertSeparator("l'eau", "l'eau".length);
        expect(text, "l'eau\n---\n");
        expect(cursor, text.length);
      },
    );

    test('does not double a trailing newline', () {
      final (:text, :cursor) = insertSeparator('a\n', 2);
      expect(text, 'a\n---\n');
      expect(cursor, text.length);
    });

    test('is a no-op when a separator already exists', () {
      final (:text, :cursor) = insertSeparator('a\n---\nb', 1);
      expect(text, 'a\n---\nb');
      expect(cursor, 1);
    });

    test('on empty text yields just the separator with cursor at end', () {
      final (:text, :cursor) = insertSeparator('', 0);
      expect(text, '\n---\n');
      expect(cursor, text.length);
    });
  });

  test('hasSeparator detects a standalone --- line only', () {
    expect(hasSeparator('a\n---\nb'), isTrue);
    expect(hasSeparator('a\n---\n'), isTrue);
    expect(hasSeparator('a --- b'), isFalse);
    expect(hasSeparator(''), isFalse);
  });
}
