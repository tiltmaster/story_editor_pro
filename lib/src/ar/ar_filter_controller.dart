import 'package:flutter/foundation.dart';
import 'ar_filter.dart';
import 'ar_filter_catalog.dart';

/// Lightweight selection state. No camera frame or personal data is accepted.
class ArCameraFilterController extends ChangeNotifier {
  ArCameraFilterController({
    ArCameraFilterId initialFilter = ArCameraFilterId.none,
    double? initialIntensity,
  }) : _selectedId = initialFilter,
       _intensity =
           (initialIntensity ??
                   ArCameraFilterCatalog.byId(initialFilter).defaultIntensity)
               .clamp(0.0, 1.0);

  ArCameraFilterId _selectedId;
  double _intensity;
  bool _disposed = false;
  ArCameraFilterId get selectedId => _selectedId;
  ArCameraFilter get selectedFilter => ArCameraFilterCatalog.byId(_selectedId);
  double get intensity => _intensity;

  bool select(ArCameraFilterId id) {
    if (_disposed || id == _selectedId) return false;
    _selectedId = id;
    _intensity = ArCameraFilterCatalog.byId(id).defaultIntensity;
    notifyListeners();
    return true;
  }

  bool setIntensity(double value) {
    final next = value.clamp(0.0, 1.0);
    if (_disposed || next == _intensity) return false;
    _intensity = next;
    notifyListeners();
    return true;
  }

  void reset() => select(ArCameraFilterId.none);
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
