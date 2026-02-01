import 'package:flutter/material.dart';
import 'dart:io';

/// Plays boomerang frames
class BoomerangPlayer extends StatefulWidget {
  final List<String> framePaths;
  final Duration frameDuration;

  const BoomerangPlayer({
    super.key,
    required this.framePaths,
    this.frameDuration = const Duration(milliseconds: 100),
  });

  @override
  State<BoomerangPlayer> createState() => _BoomerangPlayerState();
}

class _BoomerangPlayerState extends State<BoomerangPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _currentFrame = 0;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.frameDuration * widget.framePaths.length,
      vsync: this,
    )..addListener(_updateFrame);

    _controller.repeat();
  }

  void _updateFrame() {
    if (!mounted) return;

    final progress = _controller.value;
    final frameIndex = (progress * widget.framePaths.length).floor();

    if (frameIndex != _currentFrame) {
      setState(() {
        _currentFrame = frameIndex % widget.framePaths.length;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (_isPlaying) {
        _controller.stop();
      } else {
        _controller.repeat();
      }
      _isPlaying = !_isPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.framePaths.isNotEmpty && _currentFrame < widget.framePaths.length)
            Image.file(
              File(widget.framePaths[_currentFrame]),
              fit: BoxFit.cover,
            ),
          Positioned(
            bottom: 16,
            right: 16,
            child: Icon(
              _isPlaying ? Icons.pause_circle : Icons.play_circle,
              color: Colors.white,
              size: 48,
            ),
          ),
        ],
      ),
    );
  }
}
