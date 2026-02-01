import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Instagram/Snapchat style hybrid photo/video capture button.
///
/// - Short tap (< 300ms): Takes photo
/// - Long press (>= 300ms): Starts video recording
///
/// Uses Listener instead of GestureDetector for zero delay.
class SmartShutterButton extends StatefulWidget {
  /// Triggered when photo is taken (short tap)
  final VoidCallback onPhoto;

  /// Triggered when video recording starts (long press)
  final VoidCallback onVideoStart;

  /// Triggered when video recording ends (finger lifted)
  final VoidCallback onVideoEnd;

  /// Button size (default: 80)
  final double size;

  /// Color in photo mode (default: white)
  final Color idleColor;

  /// Color in video recording mode (default: red)
  final Color recordingColor;

  /// Threshold duration for photo/video distinction (default: 300ms)
  final Duration longPressThreshold;

  const SmartShutterButton({
    super.key,
    required this.onPhoto,
    required this.onVideoStart,
    required this.onVideoEnd,
    this.size = 80,
    this.idleColor = Colors.white,
    this.recordingColor = const Color(0xFFFF3B30),
    this.longPressThreshold = const Duration(milliseconds: 300),
  });

  @override
  State<SmartShutterButton> createState() => _SmartShutterButtonState();
}

class _SmartShutterButtonState extends State<SmartShutterButton>
    with SingleTickerProviderStateMixin {
  /// Recording state
  bool _isRecording = false;

  /// Is finger pressed?
  bool _isPressed = false;

  /// Long press timer
  Timer? _longPressTimer;

  /// Animation controller
  late AnimationController _animationController;

  /// Outer ring scale up animation
  late Animation<double> _outerRingScale;

  /// Inner circle scale down animation
  late Animation<double> _innerCircleScale;

  /// Color transition animation
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // Outer ring: 1.0 -> 1.3 (grows)
    _outerRingScale = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    // Inner circle: 1.0 -> 0.6 (shrinks)
    _innerCircleScale = Tween<double>(
      begin: 1.0,
      end: 0.6,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    // Color: White -> Red
    _colorAnimation = ColorTween(
      begin: widget.idleColor,
      end: widget.recordingColor,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  /// When finger is pressed - ZERO DELAY
  void _onPointerDown(PointerDownEvent event) {
    if (_isPressed) return;

    setState(() => _isPressed = true);

    // Light haptic feedback
    HapticFeedback.lightImpact();

    // Start long press timer
    _longPressTimer = Timer(widget.longPressThreshold, () {
      // 300ms elapsed and finger still pressed -> Video mode
      if (_isPressed && mounted) {
        _startRecording();
      }
    });
  }

  /// When finger is lifted
  void _onPointerUp(PointerUpEvent event) {
    if (!_isPressed) return;

    final wasRecording = _isRecording;

    // Cancel timer
    _longPressTimer?.cancel();
    _longPressTimer = null;

    setState(() => _isPressed = false);

    if (wasRecording) {
      // End video recording
      _stopRecording();
    } else {
      // Finger lifted before 300ms -> Photo
      _takePhoto();
    }
  }

  /// When finger leaves screen (cancel)
  void _onPointerCancel(PointerCancelEvent event) {
    _longPressTimer?.cancel();
    _longPressTimer = null;

    if (_isRecording) {
      _stopRecording();
    }

    setState(() => _isPressed = false);
  }

  /// Take photo
  void _takePhoto() {
    HapticFeedback.mediumImpact();
    widget.onPhoto();
  }

  /// Start video recording
  void _startRecording() {
    setState(() => _isRecording = true);

    // Strong haptic feedback
    HapticFeedback.heavyImpact();

    // Start animation (grow + turn red)
    _animationController.forward();

    widget.onVideoStart();
  }

  /// Stop video recording
  void _stopRecording() {
    setState(() => _isRecording = false);

    HapticFeedback.mediumImpact();

    // Reverse animation (shrink + turn white)
    _animationController.reverse();

    widget.onVideoEnd();
  }

  @override
  Widget build(BuildContext context) {
    final outerSize = widget.size;
    final innerSize = widget.size * 0.75;
    final strokeWidth = widget.size * 0.05;

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return SizedBox(
            width: outerSize * 1.4, // Space for growth
            height: outerSize * 1.4,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ring (border)
                  Transform.scale(
                    scale: _outerRingScale.value,
                    child: Container(
                      width: outerSize,
                      height: outerSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _colorAnimation.value ?? widget.idleColor,
                          width: strokeWidth,
                        ),
                      ),
                    ),
                  ),

                  // Inner circle (filled)
                  Transform.scale(
                    scale: _innerCircleScale.value,
                    child: Container(
                      width: innerSize,
                      height: innerSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _colorAnimation.value ?? widget.idleColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
