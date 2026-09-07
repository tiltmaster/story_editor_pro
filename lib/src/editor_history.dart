/// Bounded chronological history of immutable editor snapshots.
///
/// Record once after a completed action or gesture. The history intentionally
/// does not observe pointer frames or hold image/video bytes.
class EditorHistory<T> {
  EditorHistory(T initial, {this.limit = 40, bool Function(T, T)? equals})
    : assert(limit > 0),
      _equals = equals ?? ((a, b) => a == b),
      _current = initial,
      _saved = initial;

  final int limit;
  final bool Function(T, T) _equals;
  final List<T> _undo = [];
  final List<T> _redo = [];
  T _current;
  T _saved;

  T get current => _current;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasUnsavedChanges => !_equals(_saved, _current);

  bool record(T next) {
    if (_equals(_current, next)) return false;
    _undo.add(_current);
    if (_undo.length > limit) _undo.removeAt(0);
    _current = next;
    _redo.clear();
    return true;
  }

  T undo() {
    if (!canUndo) return _current;
    _redo.add(_current);
    return _current = _undo.removeLast();
  }

  T redo() {
    if (!canRedo) return _current;
    _undo.add(_current);
    return _current = _redo.removeLast();
  }

  void markSaved() => _saved = _current;

  /// Used only while installing the source media's initial overlays.
  void reset(T initial) {
    _undo.clear();
    _redo.clear();
    _current = initial;
    _saved = initial;
  }
}
