import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Instagram/Snapchat tarzı hibrit fotoğraf/video çekim butonu.
///
/// - Kısa dokunuş (< 300ms): Fotoğraf çeker
/// - Uzun basılı tutma (>= 300ms): Video kaydı başlatır
///
/// Sıfır gecikme için GestureDetector yerine Listener kullanır.
class SmartShutterButton extends StatefulWidget {
  /// Fotoğraf çekildiğinde tetiklenir (kısa dokunuş)
  final VoidCallback onPhoto;

  /// Video kaydı başladığında tetiklenir (uzun basılı tutma)
  final VoidCallback onVideoStart;

  /// Video kaydı bittiğinde tetiklenir (parmak kaldırıldığında)
  final VoidCallback onVideoEnd;

  /// Butonun boyutu (varsayılan: 80)
  final double size;

  /// Fotoğraf modundaki renk (varsayılan: beyaz)
  final Color idleColor;

  /// Video kayıt modundaki renk (varsayılan: kırmızı)
  final Color recordingColor;

  /// Fotoğraf/video ayrımı için eşik süresi (varsayılan: 300ms)
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
  /// Kayıt durumu
  bool _isRecording = false;

  /// Parmak basılı mı?
  bool _isPressed = false;

  /// Long press timer
  Timer? _longPressTimer;

  /// Animasyon controller'ı
  late AnimationController _animationController;

  /// Dış halka büyüme animasyonu
  late Animation<double> _outerRingScale;

  /// İç daire küçülme animasyonu
  late Animation<double> _innerCircleScale;

  /// Renk geçiş animasyonu
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

    // Dış halka: 1.0 -> 1.3 (büyür)
    _outerRingScale = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    // İç daire: 1.0 -> 0.6 (küçülür)
    _innerCircleScale = Tween<double>(
      begin: 1.0,
      end: 0.6,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    // Renk: Beyaz -> Kırmızı
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

  /// Parmak basıldığında - SIFIR GECİKME
  void _onPointerDown(PointerDownEvent event) {
    if (_isPressed) return;

    setState(() => _isPressed = true);

    // Hafif haptic feedback
    HapticFeedback.lightImpact();

    // Long press timer başlat
    _longPressTimer = Timer(widget.longPressThreshold, () {
      // 300ms doldu ve parmak hala basılı -> Video modu
      if (_isPressed && mounted) {
        _startRecording();
      }
    });
  }

  /// Parmak kaldırıldığında
  void _onPointerUp(PointerUpEvent event) {
    if (!_isPressed) return;

    final wasRecording = _isRecording;

    // Timer'ı iptal et
    _longPressTimer?.cancel();
    _longPressTimer = null;

    setState(() => _isPressed = false);

    if (wasRecording) {
      // Video kaydı bitir
      _stopRecording();
    } else {
      // 300ms dolmadan parmak kalktı -> Fotoğraf
      _takePhoto();
    }
  }

  /// Parmak ekrandan çıktığında (iptal)
  void _onPointerCancel(PointerCancelEvent event) {
    _longPressTimer?.cancel();
    _longPressTimer = null;

    if (_isRecording) {
      _stopRecording();
    }

    setState(() => _isPressed = false);
  }

  /// Fotoğraf çek
  void _takePhoto() {
    HapticFeedback.mediumImpact();
    widget.onPhoto();
  }

  /// Video kaydını başlat
  void _startRecording() {
    setState(() => _isRecording = true);

    // Güçlü haptic feedback
    HapticFeedback.heavyImpact();

    // Animasyonu başlat (büyüme + kırmızıya dönüşme)
    _animationController.forward();

    widget.onVideoStart();
  }

  /// Video kaydını bitir
  void _stopRecording() {
    setState(() => _isRecording = false);

    HapticFeedback.mediumImpact();

    // Animasyonu geri al (küçülme + beyaza dönüşme)
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
            width: outerSize * 1.4, // Büyüme için alan
            height: outerSize * 1.4,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Dış halka (border)
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

                  // İç daire (dolu)
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
