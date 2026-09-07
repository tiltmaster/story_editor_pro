import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('story_editor_pro');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    await CameraPrewarm.discard();
  });

  tearDown(() async {
    await CameraPrewarm.discard();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'concurrent native prewarm calls initialize one camera session',
    () async {
      final initializeGate = Completer<Map<String, Object?>>();
      var initializeCalls = 0;
      var disposeCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initializeCamera') {
          initializeCalls++;
          return initializeGate.future;
        }
        if (call.method == 'dispose') disposeCalls++;
        return true;
      });

      final first = CameraPrewarm.prewarm(cameraPermissionGranted: true);
      final second = CameraPrewarm.prewarm(cameraPermissionGranted: true);
      await Future<void>.delayed(Duration.zero);

      expect(initializeCalls, 1);
      initializeGate.complete(<String, Object?>{
        'textureId': 31,
        'previewWidth': 1080.0,
        'previewHeight': 1920.0,
      });
      await Future.wait(<Future<void>>[first, second]);

      final prepared = await CameraPrewarm.takeNativePrepared();
      expect(prepared, isNotNull);
      expect(prepared!.session.textureId, 31);
      expect(prepared.facing, NativeStoryCameraFacing.back);
      expect(initializeCalls, 1);
      expect(disposeCalls, 0);

      await prepared.controller.dispose();
      expect(disposeCalls, 1);
    },
  );

  test('discard owns and releases an in-flight native warmup', () async {
    final initializeGate = Completer<Map<String, Object?>>();
    final initializeSeen = Completer<void>();
    var disposeCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initializeCamera') {
        initializeSeen.complete();
        return initializeGate.future;
      }
      if (call.method == 'dispose') disposeCalls++;
      return true;
    });

    final warming = CameraPrewarm.prewarm(cameraPermissionGranted: true);
    await initializeSeen.future;
    final discarding = CameraPrewarm.discard();
    initializeGate.complete(<String, Object?>{
      'textureId': 44,
      'previewWidth': 1080.0,
      'previewHeight': 1920.0,
    });

    await Future.wait(<Future<void>>[warming, discarding]);
    expect(disposeCalls, 1);
    expect(await CameraPrewarm.takeNativePrepared(), isNull);
  });

  test(
    'prewarm requested during discard starts after discard completes',
    () async {
      final firstGate = Completer<Map<String, Object?>>();
      final secondGate = Completer<Map<String, Object?>>();
      final firstSeen = Completer<void>();
      final secondSeen = Completer<void>();
      var initializeCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initializeCamera') {
          initializeCalls++;
          if (initializeCalls == 1) {
            firstSeen.complete();
            return firstGate.future;
          }
          secondSeen.complete();
          return secondGate.future;
        }
        return true;
      });

      final firstWarm = CameraPrewarm.prewarm(cameraPermissionGranted: true);
      await firstSeen.future;
      final discarding = CameraPrewarm.discard();
      final secondWarm = CameraPrewarm.prewarm(
        front: true,
        cameraPermissionGranted: true,
      );
      firstGate.complete(<String, Object?>{
        'textureId': 51,
        'previewWidth': 1080.0,
        'previewHeight': 1920.0,
      });

      await Future.wait(<Future<void>>[firstWarm, discarding]);
      await secondSeen.future;
      secondGate.complete(<String, Object?>{
        'textureId': 52,
        'previewWidth': 1080.0,
        'previewHeight': 1920.0,
      });
      await secondWarm;

      final prepared = await CameraPrewarm.takeNativePrepared();
      expect(initializeCalls, 2);
      expect(prepared, isNotNull);
      expect(prepared!.session.textureId, 52);
      expect(prepared.facing, NativeStoryCameraFacing.front);
      await prepared.controller.dispose();
    },
  );

  test('opposite facing replaces an unused warm session', () async {
    var initializeCalls = 0;
    var disposeCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initializeCamera') {
        initializeCalls++;
        return <String, Object?>{
          'textureId': initializeCalls,
          'previewWidth': 1080.0,
          'previewHeight': 1920.0,
        };
      }
      if (call.method == 'dispose') disposeCalls++;
      return true;
    });

    await CameraPrewarm.prewarm(cameraPermissionGranted: true);
    await CameraPrewarm.prewarm(front: true, cameraPermissionGranted: true);

    final prepared = await CameraPrewarm.takeNativePrepared();
    expect(initializeCalls, 2);
    expect(disposeCalls, 1);
    expect(prepared!.facing, NativeStoryCameraFacing.front);
    await prepared.controller.dispose();
    expect(disposeCalls, 2);
  });

  test('failed native warmup is consumed exactly once', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initializeCamera') {
        throw PlatformException(code: 'CAMERA_UNAVAILABLE');
      }
      return true;
    });

    await CameraPrewarm.prewarm(cameraPermissionGranted: true);

    expect(await CameraPrewarm.takeNativePrepared(), isNull);
    expect(CameraPrewarm.takeNativeInitializationFailure(), isTrue);
    expect(CameraPrewarm.takeNativeInitializationFailure(), isFalse);
  });

  test('camera permission denial is a no-op, not a native failure', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return true;
    });

    await CameraPrewarm.prewarm(cameraPermissionGranted: false);

    expect(calls, 0);
    expect(await CameraPrewarm.takeNativePrepared(), isNull);
    expect(CameraPrewarm.takeNativeInitializationFailure(), isFalse);
  });

  test('prepared session has exactly one owner', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initializeCamera') {
        return <String, Object?>{
          'textureId': 61,
          'previewWidth': 1080.0,
          'previewHeight': 1920.0,
        };
      }
      return true;
    });

    await CameraPrewarm.prewarm(cameraPermissionGranted: true);
    final first = CameraPrewarm.takeNativePrepared();
    final second = CameraPrewarm.takeNativePrepared();
    final owners = await Future.wait(<Future<NativePrewarmedCamera?>>[
      first,
      second,
    ]);

    expect(owners.whereType<NativePrewarmedCamera>(), hasLength(1));
    await owners.whereType<NativePrewarmedCamera>().single.controller.dispose();
  });

  test(
    'take claim blocks a later prewarm from opening a second camera',
    () async {
      final initializeGate = Completer<Map<String, Object?>>();
      var initializeCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initializeCamera') {
          initializeCalls++;
          return initializeGate.future;
        }
        return true;
      });

      final warming = CameraPrewarm.prewarm(cameraPermissionGranted: true);
      await Future<void>.delayed(Duration.zero);
      final taking = CameraPrewarm.takeNativePrepared();
      final lateWarm = CameraPrewarm.prewarm(
        front: true,
        cameraPermissionGranted: true,
      );
      initializeGate.complete(<String, Object?>{
        'textureId': 71,
        'previewWidth': 1080.0,
        'previewHeight': 1920.0,
      });

      await warming;
      final prepared = await taking;
      await lateWarm;
      await Future<void>.delayed(Duration.zero);

      expect(initializeCalls, 1);
      expect(prepared, isNotNull);
      expect(prepared!.facing, NativeStoryCameraFacing.back);
      await prepared.controller.dispose();
    },
  );

  test(
    'take waits for an opposite-facing warm queued before its claim',
    () async {
      final firstGate = Completer<Map<String, Object?>>();
      final secondGate = Completer<Map<String, Object?>>();
      final secondSeen = Completer<void>();
      var initializeCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initializeCamera') {
          initializeCalls++;
          if (initializeCalls == 1) return firstGate.future;
          secondSeen.complete();
          return secondGate.future;
        }
        return true;
      });

      final firstWarm = CameraPrewarm.prewarm(cameraPermissionGranted: true);
      await Future<void>.delayed(Duration.zero);
      final frontWarm = CameraPrewarm.prewarm(
        front: true,
        cameraPermissionGranted: true,
      );
      final taking = CameraPrewarm.takeNativePrepared();
      firstGate.complete(<String, Object?>{
        'textureId': 81,
        'previewWidth': 1080.0,
        'previewHeight': 1920.0,
      });
      await secondSeen.future;
      secondGate.complete(<String, Object?>{
        'textureId': 82,
        'previewWidth': 1080.0,
        'previewHeight': 1920.0,
      });

      await Future.wait(<Future<void>>[firstWarm, frontWarm]);
      final prepared = await taking;

      expect(initializeCalls, 2);
      expect(prepared, isNotNull);
      expect(prepared!.session.textureId, 82);
      expect(prepared.facing, NativeStoryCameraFacing.front);
      await prepared.controller.dispose();
    },
  );

  test('take claim blocks prewarm queued after an active discard', () async {
    final disposeGate = Completer<void>();
    var initializeCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initializeCamera') {
        initializeCalls++;
        return <String, Object?>{
          'textureId': 91,
          'previewWidth': 1080.0,
          'previewHeight': 1920.0,
        };
      }
      if (call.method == 'dispose') await disposeGate.future;
      return true;
    });

    await CameraPrewarm.prewarm(cameraPermissionGranted: true);
    final discarding = CameraPrewarm.discard();
    await Future<void>.delayed(Duration.zero);
    final taking = CameraPrewarm.takeNativePrepared();
    final lateWarm = CameraPrewarm.prewarm(cameraPermissionGranted: true);
    disposeGate.complete();

    await discarding;
    expect(await taking, isNull);
    await lateWarm;
    await Future<void>.delayed(Duration.zero);
    expect(initializeCalls, 1);
  });

  test('empty take remains protected by a route-level lease', () async {
    var initializeCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initializeCamera') {
        initializeCalls++;
        return <String, Object?>{
          'textureId': 101,
          'previewWidth': 1080.0,
          'previewHeight': 1920.0,
        };
      }
      return true;
    });

    final routeLease = CameraPrewarm.acquireRouteLease();
    expect(await CameraPrewarm.takeNativePrepared(), isNull);
    await CameraPrewarm.prewarm(cameraPermissionGranted: true);
    expect(initializeCalls, 0);

    routeLease.release();
    await CameraPrewarm.prewarm(cameraPermissionGranted: true);
    expect(initializeCalls, 1);
  });

  test('wrong-facing disposal does not release the route lease', () async {
    var initializeCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initializeCamera') {
        initializeCalls++;
        return <String, Object?>{
          'textureId': 110 + initializeCalls,
          'previewWidth': 1080.0,
          'previewHeight': 1920.0,
        };
      }
      return true;
    });

    await CameraPrewarm.prewarm(cameraPermissionGranted: true);
    final routeLease = CameraPrewarm.acquireRouteLease();
    final prepared = await CameraPrewarm.takeNativePrepared();
    await prepared!.controller.dispose();
    await CameraPrewarm.prewarm(front: true, cameraPermissionGranted: true);
    expect(initializeCalls, 1);

    routeLease.release();
    await CameraPrewarm.prewarm(front: true, cameraPermissionGranted: true);
    expect(initializeCalls, 2);
  });

  test(
    'native failure fallback remains protected for the route lifetime',
    () async {
      var initializeCalls = 0;
      var failInitialization = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initializeCamera') {
          initializeCalls++;
          if (failInitialization) {
            throw PlatformException(code: 'CAMERA_UNAVAILABLE');
          }
          return <String, Object?>{
            'textureId': 121,
            'previewWidth': 1080.0,
            'previewHeight': 1920.0,
          };
        }
        return true;
      });

      await CameraPrewarm.prewarm(cameraPermissionGranted: true);
      final routeLease = CameraPrewarm.acquireRouteLease();
      expect(await CameraPrewarm.takeNativePrepared(), isNull);
      expect(CameraPrewarm.takeNativeInitializationFailure(), isTrue);
      failInitialization = false;
      await CameraPrewarm.prewarm(cameraPermissionGranted: true);
      expect(initializeCalls, 1);

      routeLease.release();
      await CameraPrewarm.prewarm(cameraPermissionGranted: true);
      expect(initializeCalls, 2);
    },
  );

  test('startup metric accepts the inclusive 700ms target only', () {
    CameraStartupMetrics metrics(Duration routeToPreviewReady) =>
        CameraStartupMetrics(
          usedPrewarm: true,
          controllerInitialization: const Duration(milliseconds: 450),
          screenWaitForController: Duration.zero,
          routeToPreviewReady: routeToPreviewReady,
        );

    expect(metrics(const Duration(milliseconds: 700)).metWarmTarget, isTrue);
    expect(metrics(const Duration(milliseconds: 701)).metWarmTarget, isFalse);
  });
}
