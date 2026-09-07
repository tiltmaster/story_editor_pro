import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight camera-session navigation state. Favorite effect IDs are saved
/// locally; camera data and location are never stored here.
class CameraEffectsUiSession {
  CameraEffectsUiSession({this.category = 2});

  static const _favoritesKey = 'story_editor_camera_favorite_effects_v1';
  int category;
  int beautyControl = 0;
  String? requestedPlaceStyle;
  final Map<int, double> scrollOffsets = {};
  final Map<int, String> selectedIds = {};
  final Set<String> _favorites = {};
  Future<void>? _loadRequest;
  bool _loaded = false;
  Future<void> _saveTail = Future<void>.value();

  bool isFavorite(String kind, String id) => _favorites.contains('$kind:$id');
  bool get favoritesLoaded => _loaded;

  Future<void> loadFavorites() => _loadRequest ??= _load();

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _favorites.addAll(preferences.getStringList(_favoritesKey) ?? []);
    } catch (_) {
      // Local storage is optional; the current camera session still works.
    } finally {
      _loaded = true;
    }
  }

  Future<void> toggleFavorite(String kind, String id) async {
    if (id == 'none' || (kind != 'look' && kind != 'lens')) return;
    await loadFavorites();
    final key = '$kind:$id';
    if (!_favorites.remove(key)) _favorites.add(key);
    final snapshot = _favorites.toList()..sort();
    _saveTail = _saveTail.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setStringList(_favoritesKey, snapshot);
      } catch (_) {
        // A storage failure never interrupts live capture.
      }
    });
    await _saveTail;
  }
}
