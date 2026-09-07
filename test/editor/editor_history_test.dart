import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/src/editor_history.dart';

void main() {
  test(
    'undo and redo follow chronology across different editing operations',
    () {
      final history = EditorHistory<List<String>>(
        [],
        equals: (a, b) =>
            a.length == b.length &&
            a.indexed.every((entry) => entry.$2 == b[entry.$1]),
      );
      history.record(['drawing']);
      history.record(['drawing', 'text']);
      history.record(['drawing', 'text', 'sticker']);
      history.record(['drawing', 'text moved', 'sticker']);
      expect(history.undo(), ['drawing', 'text', 'sticker']);
      expect(history.undo(), ['drawing', 'text']);
      expect(history.undo(), ['drawing']);
      expect(history.redo(), ['drawing', 'text']);
      expect(history.redo(), ['drawing', 'text', 'sticker']);
      expect(history.redo(), ['drawing', 'text moved', 'sticker']);
    },
  );

  test('no-op gestures preserve redo but a new edit starts a new branch', () {
    final history = EditorHistory(0);
    history.record(1);
    history.record(2);
    history.undo();
    expect(history.record(1), isFalse);
    expect(history.canRedo, isTrue);
    history.record(3);
    expect(history.canRedo, isFalse);
    expect(history.undo(), 1);
  });

  test('dirty state follows saved version through undo and redo', () {
    final history = EditorHistory((muted: false, trim: 0));
    history.record((muted: true, trim: 0));
    history.markSaved();
    expect(history.hasUnsavedChanges, isFalse);
    history.record((muted: true, trim: 1200));
    expect(history.hasUnsavedChanges, isTrue);
    history.undo();
    expect(history.hasUnsavedChanges, isFalse);
    history.undo();
    expect(history.hasUnsavedChanges, isTrue);
    history.redo();
    expect(history.hasUnsavedChanges, isFalse);
  });

  test(
    'history is bounded and initial media installation resets old edits',
    () {
      final history = EditorHistory(0, limit: 2);
      history.record(1);
      history.record(2);
      history.record(3);
      expect(history.undo(), 2);
      expect(history.undo(), 1);
      expect(history.canUndo, isFalse);
      expect(history.undo(), 1);
      history.reset(5);
      expect(history.current, 5);
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
      expect(history.hasUnsavedChanges, isFalse);
    },
  );
}
