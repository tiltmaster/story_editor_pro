import 'dart:async';

import 'package:flutter/widgets.dart';

import 'face_ar_models.dart';
import 'face_ar_transform.dart';

abstract interface class FaceArDetector {
  Future<List<FaceArRawDetection>> detect(FaceArFrame frame);
  Future<void> close();
}

/// Injectable detector for deterministic tests and privacy-safe demos.
class FakeFaceArDetector implements FaceArDetector {
  FakeFaceArDetector({this.handler});

  final FutureOr<List<FaceArRawDetection>> Function(FaceArFrame frame)? handler;
  int detectCount = 0;
  bool closed = false;

  @override
  Future<List<FaceArRawDetection>> detect(FaceArFrame frame) async {
    if (closed) return const [];
    detectCount++;
    return await handler?.call(frame) ?? const [];
  }

  @override
  Future<void> close() async => closed = true;
}

typedef FaceArStateListener = void Function(FaceArTrackingState state);

/// Single-flight, bounded-rate scheduler. When busy, only the newest frame is
/// kept. This prevents camera backpressure and bounds sensitive memory.
class FaceArStreamProcessor {
  FaceArStreamProcessor({
    required FaceArDetector detector,
    required this.viewportSize,
    required this.onState,
    this.maxFramesPerSecond = 15,
    this.missingFramesBeforeLost = 2,
  }) : _detector = detector,
       assert(maxFramesPerSecond > 0),
       assert(missingFramesBeforeLost > 0);

  final FaceArDetector _detector;
  final Size viewportSize;
  final FaceArStateListener onState;
  final double maxFramesPerSecond;
  final int missingFramesBeforeLost;

  FaceArFrame? _pending;
  DateTime? _lastStartedAt;
  Timer? _timer;
  bool _busy = false;
  bool _closed = false;
  Completer<void>? _idle;
  bool _hadFace = false;
  int _missingFrames = 0;

  void submit(FaceArFrame frame) {
    if (_closed) return;
    _pending = frame;
    _schedule();
  }

  void _schedule() {
    if (_closed || _busy || _timer != null || _pending == null) return;
    final interval = Duration(
      microseconds: (Duration.microsecondsPerSecond / maxFramesPerSecond).ceil(),
    );
    final elapsed = _lastStartedAt == null
        ? interval
        : DateTime.now().difference(_lastStartedAt!);
    if (elapsed < interval) {
      _timer = Timer(interval - elapsed, () {
        _timer = null;
        _schedule();
      });
      return;
    }
    final frame = _pending!;
    _pending = null;
    _busy = true;
    _idle = Completer<void>();
    _lastStartedAt = DateTime.now();
    unawaited(_process(frame));
  }

  Future<void> _process(FaceArFrame frame) async {
    try {
      List<FaceArRawDetection> raw;
      try {
        raw = await _detector.detect(frame);
      } catch (_) {
        // A detector failure must never take down capture. Treat this sample as
        // missing and let later frames reacquire the face.
        raw = const [];
      }
      if (_closed) return;
      final transform = FaceArViewportTransform(
        imageSize: Size(frame.width.toDouble(), frame.height.toDouble()),
        viewportSize: viewportSize,
        rotationDegrees: frame.rotationDegrees,
        mirrored: frame.mirrored,
      );
      final observations = raw
          .map((face) => transform.mapDetection(face, frame.timestamp))
          .toList(growable: false)
        ..sort((a, b) => b.bounds.size.longestSide.compareTo(
              a.bounds.size.longestSide,
            ));
      if (observations.isEmpty) {
        _missingFrames++;
        final lost = _hadFace && _missingFrames >= missingFramesBeforeLost;
        if (lost) _hadFace = false;
        _emit(FaceArTrackingState(
          observations: const [],
          faceLost: lost,
          timestamp: frame.timestamp,
        ));
      } else {
        _missingFrames = 0;
        _hadFace = true;
        _emit(FaceArTrackingState(
          observations: observations,
          faceLost: false,
          timestamp: frame.timestamp,
        ));
      }
    } finally {
      _busy = false;
      _idle?.complete();
      _idle = null;
      _schedule();
    }
  }

  void _emit(FaceArTrackingState state) {
    try {
      onState(state);
    } catch (_) {
      // Renderer callbacks are isolated from camera ingestion.
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pending = null;
    _timer?.cancel();
    _timer = null;
    if (_busy) await _idle?.future;
    await _detector.close();
  }
}
