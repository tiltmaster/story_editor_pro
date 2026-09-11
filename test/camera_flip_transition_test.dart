import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const native = MethodChannel('story_editor_pro');
  const ar = MethodChannel('story_editor_pro/ar');
  const events = MethodChannel('story_editor_pro/ar_events');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final arCalls = <MethodCall>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    arCalls.clear();
    messenger.setMockMethodCallHandler(
      native,
      (call) async => switch (call.method) {
        'initializeCamera' => {
          'textureId': 42,
          'previewWidth': 1080.0,
          'previewHeight': 1920.0,
        },
        'getCameraControls' => {
          'minZoom': 1.0,
          'maxZoom': 4.0,
          'minExposure': -2.0,
          'maxExposure': 2.0,
          'focus': true,
          'exposure': true,
        },
        _ => true,
      },
    );
    messenger.setMockMethodCallHandler(ar, (call) async {
      arCalls.add(call);
      if (call.method == 'getCapabilities') {
        return {
          'available': true,
          'faceTracking': true,
          'backgrounds': true,
          'preview': true,
          'recording': true,
          'lensIds': NativeArLensIds.all.toList(),
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(permissions, (_) async => 0);
  });
  tearDown(() {
    for (final channel in [native, ar, events, permissions]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets(
    'camera flip remains covered until correctly composed frames arrive',
    (tester) async {
      final readyFrame = Completer<bool>();
      messenger.setMockMethodCallHandler(ar, (call) async {
        arCalls.add(call);
        if (call.method == 'getCapabilities') {
          return {
            'available': true,
            'preview': true,
            'recording': true,
            'lensIds': NativeArLensIds.all.toList(),
          };
        }
        if (call.method == 'awaitFrame') return readyFrame.future;
        return null;
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: StoryEditorConfigProvider(
            config: StoryEditorConfig(cameraPermissionManagedByHost: true),
            child: StoryCameraScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byTooltip('Flip camera'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('camera_switch_cover')), findsOneWidget);
      expect(arCalls.last.method, 'awaitFrame');
      await tester.tap(find.byTooltip('Flip camera'));
      await tester.pump();
      expect(arCalls.where((call) => call.method == 'awaitFrame').length, 1);
      readyFrame.complete(true);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('camera_switch_cover')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
