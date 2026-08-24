import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('story_editor_pro/ar');
  const eventControlChannel = MethodChannel('story_editor_pro/ar_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockMethodCallHandler(eventControlChannel, null);
  });

  test('native AR uses the typed capability and lens contract', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      if (call.method == 'getCapabilities') {
        return <String, Object?>{
          'available': true,
          'faceTracking': true,
          'preview': true,
          'recording': true,
          'lensIds': NativeArLensIds.glasses.toList(),
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(eventControlChannel, (_) async => null);

    final controller = NativeArController();
    final capabilities = await controller.getCapabilities();
    expect(capabilities.available, isTrue);
    expect(capabilities.supportsLens(NativeArLensIds.classicGlasses), isTrue);
    expect(capabilities.supportsLens(NativeArLensIds.aviatorGold), isTrue);
    expect(capabilities.supportsLens(NativeArLensIds.visorCyan), isTrue);

    await controller.prepare();
    expect(controller.state, NativeArRuntimeState.preparing);
    expect(
      await controller.setLens(NativeArLensIds.classicGlasses, intensity: 4),
      isTrue,
    );
    expect(await controller.setEnabled(true), isTrue);

    final lensCall = calls.singleWhere((call) => call.method == 'setLens');
    expect(lensCall.arguments, <String, Object?>{
      'lensId': NativeArLensIds.classicGlasses,
      'intensity': 1.0,
    });
    expect(
      calls.map((call) => call.method),
      containsAllInOrder(<String>[
        'getCapabilities',
        'prepare',
        'setLens',
        'setEnabled',
      ]),
    );

    await controller.dispose();
  });

  test(
    'unsupported native AR degrades to unavailable without throwing',
    () async {
      messenger.setMockMethodCallHandler(
        methodChannel,
        (_) async => <String, Object?>{'available': false},
      );

      final controller = NativeArController();
      final capabilities = await controller.getCapabilities();

      expect(capabilities.available, isFalse);
      expect(controller.state, NativeArRuntimeState.unavailable);
      expect(await controller.setLens(NativeArLensIds.classicGlasses), isFalse);
      expect(await controller.setEnabled(true), isFalse);
      await controller.dispose();
    },
  );

  test('platform failures are exposed as typed non-fatal errors', () async {
    messenger.setMockMethodCallHandler(methodChannel, (_) async {
      throw PlatformException(code: 'license_missing', message: 'Unavailable');
    });

    final controller = NativeArController();
    final capabilities = await controller.getCapabilities();

    expect(capabilities.available, isFalse);
    expect(controller.state, NativeArRuntimeState.unavailable);
    expect(controller.lastFailure?.code, 'license_missing');
    expect(controller.lastFailure?.message, 'Unavailable');
    await controller.dispose();
  });

  test('native event maps preserve state, tracking, and errors', () {
    final tracking = NativeArEvent.fromMap(<String, Object?>{
      'type': 'tracking',
      'state': 'active',
      'faceTracked': true,
    });
    final error = NativeArEvent.fromMap(<String, Object?>{
      'type': 'error',
      'state': 'unavailable',
      'code': 'model_load_failed',
      'message': 'Could not load model',
    });

    expect(tracking.type, NativeArEventType.tracking);
    expect(tracking.state, NativeArRuntimeState.active);
    expect(tracking.faceTracked, isTrue);
    expect(error.type, NativeArEventType.error);
    expect(error.state, NativeArRuntimeState.unavailable);
    expect(error.failure?.code, 'model_load_failed');
  });
}
