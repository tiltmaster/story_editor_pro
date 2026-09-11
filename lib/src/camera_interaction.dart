import 'dart:ui';

/// Keeps the record gesture independent of async encoder startup. Once locked,
/// lifting a finger must not stop recording; only Stop or lifecycle teardown can.
class CameraRecordGesture {
  Offset? _origin;
  bool locked = false;
  void begin(Offset position) {
    _origin = position;
    locked = false;
  }

  bool move(Offset position, {required bool rtl}) {
    final origin = _origin;
    if (origin == null || locked) return false;
    final towardLock = (origin.dx - position.dx) * (rtl ? -1 : 1);
    if (towardLock < 48) return false;
    locked = true;
    return true;
  }

  bool get stopOnRelease => !locked;
  void lock() => locked = true;
  void reset() {
    _origin = null;
    locked = false;
  }
}

/// Scale factors produced by center-cover fitting without stretching faces.
Offset cameraPreviewCoverScale(
  Size viewport, {
  required double portraitAspect,
}) {
  if (viewport.isEmpty || !portraitAspect.isFinite || portraitAspect <= 0) {
    return const Offset(1, 1);
  }
  final ratio = viewport.aspectRatio / portraitAspect;
  return ratio > 1 ? Offset(1, ratio) : Offset(1 / ratio, 1);
}

/// Converts a preview touch to the upright unmirrored camera crop. Cover only
/// clips one axis; adjusting both axes shifts focus away from the tapped face.
Offset cameraFocusCoordinates(
  Offset normalized, {
  required Offset coverScale,
  required bool mirrored,
}) {
  double safe(double scale) => scale.isFinite && scale >= 1 ? scale : 1;
  var x = .5 + (normalized.dx - .5) / safe(coverScale.dx);
  final y = .5 + (normalized.dy - .5) / safe(coverScale.dy);
  if (mirrored) x = 1 - x;
  return Offset(x.clamp(0, 1), y.clamp(0, 1));
}
