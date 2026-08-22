import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

FaceArFrame frame(int millisecond, {bool mirrored = false}) => FaceArFrame(
      bytes: Uint8List(4),
      width: 100,
      height: 200,
      bytesPerRow: 2,
      rotationDegrees: 0,
      format: FaceArPixelFormat.nv21,
      timestamp: DateTime.utc(2026, 1, 1, 0, 0, 0, millisecond),
      mirrored: mirrored,
    );

const detectedFace = FaceArRawDetection(
  trackingId: 7,
  bounds: Rect.fromLTWH(20, 40, 60, 100),
  landmarks: {
    FaceArLandmark.leftEye: Offset(35, 80),
    FaceArLandmark.rightEye: Offset(65, 80),
  },
  yawDegrees: 10,
  pitchDegrees: -5,
  rollDegrees: 15,
  confidence: 0.9,
);

Future<void> settleProcessor() =>
    Future<void>.delayed(const Duration(milliseconds: 15));

void main() {
  group('FaceArViewportTransform', () {
    test('applies quarter-turn sensor rotation', () {
      const transform = FaceArViewportTransform(
        imageSize: Size(100, 200),
        viewportSize: Size(200, 100),
        rotationDegrees: 90,
        mirrored: false,
      );

      expect(transform.mapPoint(const Offset(0, 0)), const Offset(1, 0));
      expect(transform.mapPoint(const Offset(100, 200)), const Offset(0, 1));
    });

    test('mirrors only the final displayed x coordinate', () {
      const normal = FaceArViewportTransform(
        imageSize: Size(100, 200),
        viewportSize: Size(100, 200),
        rotationDegrees: 0,
        mirrored: false,
      );
      const mirrored = FaceArViewportTransform(
        imageSize: Size(100, 200),
        viewportSize: Size(100, 200),
        rotationDegrees: 0,
        mirrored: true,
      );

      expect(normal.mapPoint(const Offset(20, 60)), const Offset(0.2, 0.3));
      expect(mirrored.mapPoint(const Offset(20, 60)), const Offset(0.8, 0.3));
    });

    test('accounts for BoxFit.cover viewport cropping', () {
      const transform = FaceArViewportTransform(
        imageSize: Size(200, 100),
        viewportSize: Size(100, 100),
        rotationDegrees: 0,
        mirrored: false,
      );

      expect(transform.mapPoint(const Offset(50, 50)), const Offset(0, 0.5));
      expect(transform.mapPoint(const Offset(150, 50)), const Offset(1, 0.5));
    });

    test('normalizes pose and interocular distance', () {
      const transform = FaceArViewportTransform(
        imageSize: Size(100, 200),
        viewportSize: Size(100, 200),
        rotationDegrees: 0,
        mirrored: true,
      );
      final observation = transform.mapDetection(
        detectedFace,
        DateTime.utc(2026),
      );

      expect(observation.interocularDistance, closeTo(0.3, 0.0001));
      expect(observation.yawRadians, closeTo(-0.1745329, 0.0001));
      expect(observation.pitchRadians, closeTo(-0.0872664, 0.0001));
      expect(observation.rollRadians, closeTo(-0.261799, 0.0001));
      expect(observation.confidence, 0.9);
      expect(observation.mirrored, isTrue);
    });
  });

  group('FaceArStreamProcessor', () {
    test('is single-flight and replaces backlog with newest frame', () async {
      final first = Completer<List<FaceArRawDetection>>();
      final timestamps = <DateTime>[];
      final detector = FakeFaceArDetector(handler: (input) async {
        timestamps.add(input.timestamp);
        if (timestamps.length == 1) return first.future;
        return const [detectedFace];
      });
      final processor = FaceArStreamProcessor(
        detector: detector,
        viewportSize: const Size(100, 200),
        onState: (_) {},
        maxFramesPerSecond: 1000,
      );

      processor.submit(frame(1));
      await Future<void>.delayed(Duration.zero);
      processor.submit(frame(2));
      processor.submit(frame(3));
      expect(detector.detectCount, 1);
      first.complete(const [detectedFace]);
      await settleProcessor();

      expect(detector.detectCount, 2);
      expect(timestamps.last, frame(3).timestamp);
      await processor.close();
    });

    test('reports loss threshold and clean reacquisition', () async {
      var call = 0;
      final states = <FaceArTrackingState>[];
      final detector = FakeFaceArDetector(handler: (_) {
        call++;
        return switch (call) {
          1 || 4 => const [detectedFace],
          _ => const <FaceArRawDetection>[],
        };
      });
      final processor = FaceArStreamProcessor(
        detector: detector,
        viewportSize: const Size(100, 200),
        onState: states.add,
        maxFramesPerSecond: 1000,
        missingFramesBeforeLost: 2,
      );

      for (var i = 1; i <= 4; i++) {
        processor.submit(frame(i));
        await settleProcessor();
      }

      expect(states.map((s) => s.faceLost), [false, false, true, false]);
      expect(states.last.primary?.trackingId, 7);
      await processor.close();
    });

    test('close clears pending work and releases detector exactly once', () async {
      final gate = Completer<List<FaceArRawDetection>>();
      final states = <FaceArTrackingState>[];
      final detector = FakeFaceArDetector(handler: (_) => gate.future);
      final processor = FaceArStreamProcessor(
        detector: detector,
        viewportSize: const Size(100, 200),
        onState: states.add,
        maxFramesPerSecond: 1000,
      );

      processor.submit(frame(1));
      await Future<void>.delayed(Duration.zero);
      processor.submit(frame(2));
      final closeFuture = processor.close();
      expect(detector.closed, isFalse);
      gate.complete(const [detectedFace]);
      await closeFuture;
      processor.submit(frame(3));
      await settleProcessor();

      expect(detector.closed, isTrue);
      expect(detector.detectCount, 1);
      expect(states, isEmpty);
    });

    test('detector failure does not stop later face reacquisition', () async {
      var call = 0;
      final states = <FaceArTrackingState>[];
      final detector = FakeFaceArDetector(handler: (_) {
        call++;
        if (call == 1) throw StateError('synthetic detector failure');
        return const [detectedFace];
      });
      final processor = FaceArStreamProcessor(
        detector: detector,
        viewportSize: const Size(100, 200),
        onState: states.add,
        maxFramesPerSecond: 1000,
      );

      processor.submit(frame(1));
      await settleProcessor();
      processor.submit(frame(2));
      await settleProcessor();

      expect(states, hasLength(2));
      expect(states.first.primary, isNull);
      expect(states.last.primary?.trackingId, 7);
      await processor.close();
    });
  });
}
