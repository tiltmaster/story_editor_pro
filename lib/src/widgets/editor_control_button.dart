import 'package:flutter/material.dart';

/// Shared editor action with a platform-appropriate 48dp hit target, visible
/// pressed/selected states, tooltip and screen-reader label.
class EditorControlButton extends StatelessWidget {
  const EditorControlButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconWidget,
    this.isActive = false,
    this.isEnabled = true,
    this.size = 48,
  }) : assert(icon != null || iconWidget != null);

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final Widget? iconWidget;
  final bool isActive;
  final bool isEnabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: isEnabled,
      selected: isActive,
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox.square(
          dimension: size < 48 ? 48 : size,
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              onTap: isEnabled ? onPressed : null,
              radius: 28,
              containedInkWell: true,
              customBorder: const CircleBorder(),
              highlightColor: Colors.white.withValues(alpha: 0.16),
              splashColor: Colors.white.withValues(alpha: 0.22),
              child: Ink(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.30)
                      : Colors.black.withValues(alpha: 0.48),
                  border: Border.all(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.72)
                        : Colors.white.withValues(alpha: 0.25),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Opacity(
                    opacity: isEnabled ? 1 : 0.38,
                    child:
                        iconWidget ?? Icon(icon, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
