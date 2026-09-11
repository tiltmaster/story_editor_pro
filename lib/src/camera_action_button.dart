import 'package:flutter/material.dart';

/// Shared camera/editor chrome: compact glass circle, full 48dp touch target.
class CameraActionButton extends StatelessWidget {
  const CameraActionButton({
    super.key,
    required this.child,
    this.onTap,
    this.label,
    this.active = false,
    this.size = 44,
  });
  final Widget child;
  final VoidCallback? onTap;
  final String? label;
  final bool active;
  final double size;
  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      label: label,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: CameraActionSurface(
          size: size,
          active: active,
          child: Opacity(opacity: onTap == null ? .35 : 1, child: child),
        ),
      ),
    );
    return label == null ? button : Tooltip(message: label!, child: button);
  }
}

/// Shared visual surface for taps and anchored popup-menu triggers.
class CameraActionSurface extends StatelessWidget {
  const CameraActionSurface({
    super.key,
    required this.child,
    this.active = false,
    this.size = 44,
  });
  final Widget child;
  final bool active;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size < 48 ? 48 : size,
    height: size < 48 ? 48 : size,
    child: Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? Colors.white.withValues(alpha: .30)
              : Colors.black.withValues(alpha: .42),
          border: Border.all(color: Colors.white.withValues(alpha: .22)),
        ),
        child: Center(child: child),
      ),
    ),
  );
}
