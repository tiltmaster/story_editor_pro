import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum NativeStoryCameraFacing { front, back }

enum NativeStoryFlashMode { off, on, auto }

@immutable
class NativeStoryCameraSession {
  const NativeStoryCameraSession({
    required this.textureId,
    required this.previewWidth,
    required this.previewHeight,
  });

  final int textureId;
  final double previewWidth;
  final double previewHeight;

  double get aspectRatio {
    final longEdge = previewWidth > previewHeight
        ? previewWidth
        : previewHeight;
    final shortEdge = previewWidth > previewHeight
        ? previewHeight
        : previewWidth;
    return shortEdge == 0 ? 1 : longEdge / shortEdge;
  }

  factory NativeStoryCameraSession.fromMap(Map<Object?, Object?> map) {
    final textureId = map['textureId'];
    final previewWidth = map['previewWidth'];
    final previewHeight = map['previewHeight'];
    if (textureId is! num || previewWidth is! num || previewHeight is! num) {
      throw const FormatException('Invalid native camera session response');
    }
    if (textureId.toInt() < 0 || previewWidth <= 0 || previewHeight <= 0) {
      throw const FormatException('Invalid native camera texture metadata');
    }
    return NativeStoryCameraSession(
      textureId: textureId.toInt(),
      previewWidth: previewWidth.toDouble(),
      previewHeight: previewHeight.toDouble(),
    );
  }
}

class NativeStoryCameraController {
  NativeStoryCameraController({
    MethodChannel? methodChannel,
    VoidCallback? onDisposed,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel('story_editor_pro'),
       _onDisposed = onDisposed;

  final MethodChannel _methodChannel;
  VoidCallback? _onDisposed;
  NativeStoryCameraSession? _session;
  NativeStoryCameraFacing _facing = NativeStoryCameraFacing.front;
  bool _recording = false;
  bool _disposed = false;
  Future<NativeStoryCameraSession>? _initializeRequest;
  Future<void>? _releaseRequest;
  Future<String>? _captureRequest;
  Future<bool>? _startRecordingRequest;
  Future<String>? _stopRecordingRequest;
  Future<bool>? _switchRequest;
  Future<bool>? _flashRequest;
  Future<bool>? _zoomRequest;
  NativeStoryFlashMode? _pendingFlashMode;
  double? _pendingZoomLevel;

  NativeStoryCameraSession? get session => _session;
  NativeStoryCameraFacing get facing => _facing;
  bool get isInitialized => _session != null && !_disposed;
  bool get isRecording => _recording;

  Future<NativeStoryCameraSession> initialize(NativeStoryCameraFacing facing) {
    _checkNotDisposed();
    final active = _initializeRequest;
    if (active != null) return active;
    final current = _session;
    if (current != null) {
      if (_facing == facing) {
        return Future<NativeStoryCameraSession>.value(current);
      }
      throw StateError('Use switchCamera to change an active native session');
    }

    late final Future<NativeStoryCameraSession> request;
    request = _initialize(facing).whenComplete(() {
      if (identical(_initializeRequest, request)) _initializeRequest = null;
    });
    _initializeRequest = request;
    return request;
  }

  Future<NativeStoryCameraSession> _initialize(
    NativeStoryCameraFacing facing,
  ) async {
    final releasing = _releaseRequest;
    if (releasing != null) await releasing;
    _checkNotDisposed();
    final raw = await _methodChannel.invokeMethod<Object?>(
      'initializeCamera',
      <String, Object?>{'facing': facing.name},
    );
    _checkNotDisposed();
    if (raw is! Map) {
      throw const FormatException('Native camera did not return a session');
    }
    final next = NativeStoryCameraSession.fromMap(raw);
    _facing = facing;
    _session = next;
    return next;
  }

  Future<String> takePicture() {
    _checkInitialized();
    final active = _captureRequest;
    if (active != null) return active;
    late final Future<String> request;
    request = _takePicture().whenComplete(() {
      if (identical(_captureRequest, request)) _captureRequest = null;
    });
    _captureRequest = request;
    return request;
  }

  Future<String> _takePicture() async {
    final path = await _methodChannel.invokeMethod<String>('takePicture');
    if (path == null || path.isEmpty) {
      throw PlatformException(
        code: 'empty_capture_path',
        message: 'Native camera did not return a capture path',
      );
    }
    return path;
  }

  Future<bool> startVideoRecording(String outputPath) {
    _checkInitialized();
    if (_recording) return Future<bool>.value(true);
    final active = _startRecordingRequest;
    if (active != null) return active;
    late final Future<bool> request;
    request = _startVideoRecording(outputPath).whenComplete(() {
      if (identical(_startRecordingRequest, request)) {
        _startRecordingRequest = null;
      }
    });
    _startRecordingRequest = request;
    return request;
  }

  Future<bool> _startVideoRecording(String outputPath) async {
    final started = await _methodChannel.invokeMethod<bool>(
      'startVideoRecording',
      <String, Object?>{'outputPath': outputPath},
    );
    _recording = started == true;
    return _recording;
  }

  Future<String> stopVideoRecording() {
    _checkInitialized();
    final active = _stopRecordingRequest;
    if (active != null) return active;
    late final Future<String> request;
    request = _stopVideoRecording().whenComplete(() {
      if (identical(_stopRecordingRequest, request)) {
        _stopRecordingRequest = null;
      }
    });
    _stopRecordingRequest = request;
    return request;
  }

  Future<String> _stopVideoRecording() async {
    final starting = _startRecordingRequest;
    if (starting != null) await starting;
    final path = await _methodChannel.invokeMethod<String>(
      'stopVideoRecording',
    );
    _recording = false;
    if (path == null || path.isEmpty) {
      throw PlatformException(
        code: 'empty_recording_path',
        message: 'Native camera did not return a recording path',
      );
    }
    return path;
  }

  Future<bool> switchCamera() {
    _checkInitialized();
    final active = _switchRequest;
    if (active != null) return active;
    late final Future<bool> request;
    request = _switchCamera().whenComplete(() {
      if (identical(_switchRequest, request)) _switchRequest = null;
    });
    _switchRequest = request;
    return request;
  }

  Future<bool> _switchCamera() async {
    final switched =
        await _methodChannel.invokeMethod<bool>('switchCamera') == true;
    if (switched) {
      _facing = _facing == NativeStoryCameraFacing.front
          ? NativeStoryCameraFacing.back
          : NativeStoryCameraFacing.front;
    }
    return switched;
  }

  Future<bool> setFlashMode(NativeStoryFlashMode mode) {
    _checkInitialized();
    _pendingFlashMode = mode;
    final active = _flashRequest;
    if (active != null) return active;
    late final Future<bool> request;
    request = _drainFlashRequests().whenComplete(() {
      if (identical(_flashRequest, request)) _flashRequest = null;
    });
    _flashRequest = request;
    return request;
  }

  Future<bool> _drainFlashRequests() async {
    var succeeded = true;
    while (_pendingFlashMode != null) {
      final mode = _pendingFlashMode!;
      _pendingFlashMode = null;
      succeeded =
          await _methodChannel.invokeMethod<bool>(
            'setFlashMode',
            <String, Object?>{'mode': mode.name},
          ) ==
          true;
    }
    return succeeded;
  }

  Future<bool> setZoomLevel(double level) {
    _checkInitialized();
    _pendingZoomLevel = level;
    final active = _zoomRequest;
    if (active != null) return active;
    late final Future<bool> request;
    request = _drainZoomRequests().whenComplete(() {
      if (identical(_zoomRequest, request)) _zoomRequest = null;
    });
    _zoomRequest = request;
    return request;
  }

  Future<bool> _drainZoomRequests() async {
    var succeeded = true;
    while (_pendingZoomLevel != null) {
      final level = _pendingZoomLevel!;
      _pendingZoomLevel = null;
      succeeded =
          await _methodChannel.invokeMethod<bool>(
            'setZoomLevel',
            <String, Object?>{'level': level},
          ) ==
          true;
    }
    return succeeded;
  }

  Future<void> release() {
    if (_disposed) return Future<void>.value();
    final active = _releaseRequest;
    if (active != null) return active;
    late final Future<void> request;
    request = _release().whenComplete(() {
      if (identical(_releaseRequest, request)) _releaseRequest = null;
    });
    _releaseRequest = request;
    return request;
  }

  Future<void> _release() async {
    _session = null;
    _pendingFlashMode = null;
    _pendingZoomLevel = null;
    final pending = <Future<Object?>>[
      if (_initializeRequest != null) _initializeRequest!,
      if (_captureRequest != null) _captureRequest!,
      if (_startRecordingRequest != null) _startRecordingRequest!,
      if (_stopRecordingRequest != null) _stopRecordingRequest!,
      if (_switchRequest != null) _switchRequest!,
      if (_flashRequest != null) _flashRequest!,
      if (_zoomRequest != null) _zoomRequest!,
    ];
    if (pending.isNotEmpty) {
      await Future.wait(pending.map(_settle));
    }
    _session = null;
    _recording = false;
    try {
      await _methodChannel.invokeMethod<void>('dispose');
    } on MissingPluginException {
      // Unsupported platforms are a safe no-op.
    } on PlatformException {
      // Camera teardown is best effort.
    }
  }

  Future<void> _settle(Future<Object?> future) async {
    try {
      await future;
    } catch (_) {
      // Release still owns teardown after an in-flight operation fails.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      final releasing = _releaseRequest;
      if (releasing != null) {
        await releasing;
        return;
      }
      await _release();
    } finally {
      final onDisposed = _onDisposed;
      _onDisposed = null;
      onDisposed?.call();
    }
  }

  void _checkInitialized() {
    _checkNotDisposed();
    if (_session == null) throw StateError('Native camera is not initialized');
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('Native camera has been disposed');
  }
}
