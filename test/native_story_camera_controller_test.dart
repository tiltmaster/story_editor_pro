import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('story_editor_pro');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('typed native camera API preserves the platform contract', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'initializeCamera' => <String, Object?>{
          'textureId': 42,
          'previewWidth': 1080.0,
          'previewHeight': 1920.0,
        },
        'takePicture' => 'capture.jpg',
        'startVideoRecording' => true,
        'stopVideoRecording' => 'recording.mp4',
        'switchCamera' => true,
        'setFlashMode' => true,
        'setZoomLevel' => true,
        'dispose' => true,
        _ => null,
      };
    });

    final controller = NativeStoryCameraController();
    final session = await controller.initialize(NativeStoryCameraFacing.front);

    expect(session.textureId, 42);
    expect(session.aspectRatio, closeTo(16 / 9, 0.001));
    expect(await controller.takePicture(), 'capture.jpg');
    expect(await controller.startVideoRecording('output.mp4'), isTrue);
    expect(await controller.stopVideoRecording(), 'recording.mp4');
    expect(await controller.setFlashMode(NativeStoryFlashMode.auto), isTrue);
    expect(await controller.setZoomLevel(2.5), isTrue);
    expect(await controller.switchCamera(), isTrue);
    expect(controller.facing, NativeStoryCameraFacing.back);

    expect(calls.first.method, 'initializeCamera');
    expect(calls.first.arguments, <String, Object?>{'facing': 'front'});
    expect(
      calls
          .singleWhere((call) => call.method == 'startVideoRecording')
          .arguments,
      <String, Object?>{'outputPath': 'output.mp4'},
    );
    expect(
      calls.singleWhere((call) => call.method == 'setFlashMode').arguments,
      <String, Object?>{'mode': 'auto'},
    );
    expect(
      calls.singleWhere((call) => call.method == 'setZoomLevel').arguments,
      <String, Object?>{'level': 2.5},
    );

    await controller.dispose();
  });

  test(
    'native camera can release and initialize again after lifecycle pause',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'initializeCamera') {
          return <String, Object?>{
            'textureId': calls.length,
            'previewWidth': 1080.0,
            'previewHeight': 1920.0,
          };
        }
        return true;
      });

      final controller = NativeStoryCameraController();
      await controller.initialize(NativeStoryCameraFacing.front);
      await controller.release();
      expect(controller.isInitialized, isFalse);
      await controller.initialize(NativeStoryCameraFacing.front);

      expect(
        calls.where((call) => call.method == 'initializeCamera').length,
        2,
      );
      expect(calls.where((call) => call.method == 'dispose').length, 1);
      await controller.dispose();
    },
  );

  test('concurrent recording starts issue one native call', () async {
    final startGate = Completer<bool>();
    var startCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initializeCamera') {
        return <String, Object?>{
          'textureId': 7,
          'previewWidth': 1080.0,
          'previewHeight': 1920.0,
        };
      }
      if (call.method == 'startVideoRecording') {
        startCalls++;
        return startGate.future;
      }
      return true;
    });

    final controller = NativeStoryCameraController();
    await controller.initialize(NativeStoryCameraFacing.front);
    final first = controller.startVideoRecording('first.mp4');
    final second = controller.startVideoRecording('second.mp4');

    expect(startCalls, 1);
    startGate.complete(true);
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(controller.isRecording, isTrue);
    await controller.dispose();
  });

  test('initialize waits for an in-flight lifecycle release', () async {
    final disposeGate = Completer<void>();
    final calls = <String>[];
    var textureId = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'initializeCamera') {
        textureId++;
        return <String, Object?>{
          'textureId': textureId,
          'previewWidth': 1080.0,
          'previewHeight': 1920.0,
        };
      }
      if (call.method == 'dispose') await disposeGate.future;
      return true;
    });

    final controller = NativeStoryCameraController();
    await controller.initialize(NativeStoryCameraFacing.front);
    final release = controller.release();
    final resumed = controller.initialize(NativeStoryCameraFacing.front);

    expect(calls.where((method) => method == 'initializeCamera').length, 1);
    disposeGate.complete();
    await release;
    expect((await resumed).textureId, 2);
    expect(calls, <String>['initializeCamera', 'dispose', 'initializeCamera']);
    await controller.dispose();
  });

  test('rapid zoom changes coalesce to the latest pending value', () async {
    final firstZoomGate = Completer<bool>();
    final zoomLevels = <double>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initializeCamera') {
        return <String, Object?>{
          'textureId': 9,
          'previewWidth': 1080.0,
          'previewHeight': 1920.0,
        };
      }
      if (call.method == 'setZoomLevel') {
        zoomLevels.add((call.arguments as Map)['level'] as double);
        if (zoomLevels.length == 1) return firstZoomGate.future;
        return true;
      }
      return true;
    });

    final controller = NativeStoryCameraController();
    await controller.initialize(NativeStoryCameraFacing.front);
    final first = controller.setZoomLevel(2);
    final second = controller.setZoomLevel(3);
    final latest = controller.setZoomLevel(4);

    firstZoomGate.complete(true);
    await Future.wait(<Future<bool>>[first, second, latest]);
    expect(zoomLevels, <double>[2, 4]);
    await controller.dispose();
  });

  test('terminal dispose wins over an in-flight initialization', () async {
    final initializeGate = Completer<Map<String, Object?>>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'initializeCamera') return initializeGate.future;
      return true;
    });

    final controller = NativeStoryCameraController();
    final initialization = controller.initialize(NativeStoryCameraFacing.front);
    final initializationExpectation = expectLater(
      initialization,
      throwsStateError,
    );
    final disposal = controller.dispose();
    initializeGate.complete(<String, Object?>{
      'textureId': 11,
      'previewWidth': 1080.0,
      'previewHeight': 1920.0,
    });

    await initializationExpectation;
    await disposal;
    expect(controller.isInitialized, isFalse);
    expect(calls, <String>['initializeCamera', 'dispose']);
  });
}
