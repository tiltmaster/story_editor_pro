import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class BoomerangEditorScreen extends StatefulWidget {
  final String videoPath;
  final Color? primaryColor;

  const BoomerangEditorScreen({
    super.key,
    required this.videoPath,
    this.primaryColor,
  });

  @override
  State<BoomerangEditorScreen> createState() => _BoomerangEditorScreenState();
}

class _BoomerangEditorScreenState extends State<BoomerangEditorScreen> {
  late VideoPlayerController _videoController;
  bool _isInitialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    _videoController = VideoPlayerController.file(File(widget.videoPath));

    try {
      await _videoController.initialize();
      _videoController.setLooping(true);
      _videoController.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Video init error: $e');
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  void _onClose() {
    Navigator.pop(context);
  }

  Future<void> _onConfirm() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    // Video zaten hazır, sadece path'i döndür
    Navigator.pop(context, widget.videoPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video Player
          if (_isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _videoController.value.aspectRatio,
                child: VideoPlayer(_videoController),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Top Controls
          Container(child: _buildTopControls()),

          // Bottom Controls
          _buildBottomControls(),

          // Saving indicator
          if (_isSaving)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Close button
              GestureDetector(
                onTap: _onClose,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.close, color: Colors.white, size: 28),
                ),
              ),
              // Boomerang badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.all_inclusive, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Boomerang',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 44), // Balance for close button
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final primaryColor = widget.primaryColor ?? const Color(0xFFC13584);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Confirm button
              GestureDetector(
                onTap: _onConfirm,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primaryColor,
                        primaryColor.withValues(alpha: 0.8),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
