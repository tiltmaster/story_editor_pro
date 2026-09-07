/// Immutable geometry and motion contract for the camera filter slider.
///
/// AR options use this same contract; adding a lens must never create a second
/// slider or change the existing selector's position, snapping, or scale curve.
abstract final class CameraFilterSliderContract {
  static const double viewportFraction = 0.18;
  static const bool pageSnapping = true;
  static const double integratedControlHeight = 126;
  static const double selectorHeight = 108;
  static const double bubbleSize = 52;
  static const double itemHeight = 96;
  static const double itemHorizontalPadding = 7;
  static const double inactiveScale = 0.82;
  static const double focusScaleDelta = 0.22;
  static const Duration swipeAnimationDuration = Duration(milliseconds: 180);

  static double focusForDistance(double distance) =>
      (1.0 - distance.abs()).clamp(0.0, 1.0);

  static double scaleForDistance(double distance) =>
      inactiveScale + (focusScaleDelta * focusForDistance(distance));

  static bool isSelected(double distance) => distance.abs() < 0.5;
}
