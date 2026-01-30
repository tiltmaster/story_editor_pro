import 'dart:async';
import 'package:flutter/services.dart';

enum CameraFacing { back, front }
enum FlashMode { off, on, auto }

class CameraController {
  static const MethodChannel _channel = MethodChannel('story_editor_pro');

  int? _textureId;
  int? _previewWidth;
  int? _previewHeight;
  bool _isInitialized = false;
  CameraFacing _currentFacing = CameraFacing.back;

  int? get textureId => _textureId;
  int? get previewWidth => _previewWidth;
  int? get previewHeight => _previewHeight;
  bool get isInitialized => _isInitialized;
  CameraFacing get currentFacing => _currentFacing;

  double get aspectRatio {
    if (_previewWidth == null || _previewHeight == null) return 16 / 9;
    return _previewWidth! / _previewHeight!;
  }

  Future<bool> checkPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> initialize({CameraFacing facing = CameraFacing.back}) async {
    _currentFacing = facing;

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'initializeCamera',
        {'facing': facing == CameraFacing.front ? 'front' : 'back'},
      );

      if (result != null) {
        _textureId = result['textureId'] as int?;
        _previewWidth = result['previewWidth'] as int?;
        _previewHeight = result['previewHeight'] as int?;
        _isInitialized = true;
      }
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }

  Future<String?> takePicture() async {
    if (!_isInitialized) {
      throw Exception('Camera not initialized');
    }

    try {
      final result = await _channel.invokeMethod<String>('takePicture');
      return result;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> switchCamera() async {
    if (!_isInitialized) return;

    try {
      await _channel.invokeMethod('switchCamera');
      _currentFacing = _currentFacing == CameraFacing.back
          ? CameraFacing.front
          : CameraFacing.back;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> setFlashMode(FlashMode mode) async {
    if (!_isInitialized) return;

    String modeStr;
    switch (mode) {
      case FlashMode.on:
        modeStr = 'on';
        break;
      case FlashMode.auto:
        modeStr = 'auto';
        break;
      default:
        modeStr = 'off';
    }

    try {
      await _channel.invokeMethod('setFlashMode', {'mode': modeStr});
    } catch (e) {
      rethrow;
    }
  }

  Future<void> setZoomLevel(double level) async {
    if (!_isInitialized) return;

    try {
      await _channel.invokeMethod('setZoomLevel', {'level': level});
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> checkGalleryPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkGalleryPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> requestGalleryPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestGalleryPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<String?> getLastGalleryImage() async {
    try {
      final result = await _channel.invokeMethod<String>('getLastGalleryImage');
      return result;
    } catch (e) {
      return null;
    }
  }

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Future<bool> startVideoRecording(String outputPath) async {
    if (!_isInitialized || _isRecording) return false;

    try {
      final result = await _channel.invokeMethod<bool>(
        'startVideoRecording',
        {'outputPath': outputPath},
      );
      _isRecording = result ?? false;
      return _isRecording;
    } catch (e) {
      _isRecording = false;
      return false;
    }
  }

  Future<String?> stopVideoRecording() async {
    if (!_isInitialized || !_isRecording) return null;

    try {
      final result = await _channel.invokeMethod<String>('stopVideoRecording');
      _isRecording = false;
      return result;
    } catch (e) {
      _isRecording = false;
      return null;
    }
  }

  Future<void> dispose() async {
    if (!_isInitialized) return;

    try {
      await _channel.invokeMethod('dispose');
      _isInitialized = false;
      _textureId = null;
    } catch (e) {
      rethrow;
    }
  }
}
