import 'dart:io';

import 'package:flutter/material.dart';
import 'package:story_editor_pro/src/camera_effects_panel.dart';
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

  testWidgets('gallery and music retain route-local configuration', (
    tester,
  ) async {
    const photos = MethodChannel('com.fluttercandies/photo_manager');
    messenger.setMockMethodCallHandler(photos, (call) async {
      switch (call.method) {
        case 'requestPermissionExtend':
          return 3;
        case 'getAssetPathList':
          return {
            'data': [
              {'id': 'all', 'name': 'Gallery', 'isAll': true, 'assetCount': 1},
            ],
          };
        case 'getAssetCountFromPath':
          return 1;
        case 'getAssetListPaged':
          return {'data': []};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(photos, null));
    var musicPicks = 0;
    final config = StoryEditorConfig(
      cameraPermissionManagedByHost: true,
      onPickMusic: (_) async {
        musicPicks++;
        return const StoryEditorMusicSelection(
          id: 'track',
          title: 'Selected track',
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StoryEditorConfigProvider(
          config: config,
          child: const StoryCameraScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('camera_effects_button')));
    await tester.pump();
    final panel = tester.widget<CameraEffectsPanel>(
      find.byType(CameraEffectsPanel),
    );
    final picking = panel.onPickBackground!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Gallery'), findsOneWidget);
    expect(
      StoryEditorConfigProvider.read(tester.element(find.text('Gallery'))),
      same(config),
    );
    expect(tester.takeException(), isNull);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await picking;
    await tester.tap(find.text('Add sound'));
    await tester.pump();
    expect(find.text('Selected track'), findsOneWidget);
    expect(musicPicks, 1);
    panel.onClose!();
    await tester.pump();
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'takePicture') {
        return File('assets/props/crown.png').absolute.path;
      }
      return true;
    });
    await tester.tap(find.byKey(AnchoredShutterControl.shutterAnchorKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(StoryEditorScreen), findsOneWidget);
    final editor = tester.widget<StoryEditorScreen>(
      find.byType(StoryEditorScreen),
    );
    expect(editor.initialMusic?.id, 'track');
    final editorConfig = StoryEditorConfigProvider.read(
      tester.element(find.byType(StoryEditorScreen)),
    );
    expect(editorConfig.onPickMusic, same(config.onPickMusic));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
