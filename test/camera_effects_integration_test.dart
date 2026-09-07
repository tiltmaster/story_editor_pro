import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:story_editor_pro/story_editor_pro.dart';
import 'package:story_editor_pro/src/camera_effects.dart';
import 'package:story_editor_pro/src/camera_effects_panel.dart';

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
    'small Arabic camera keeps shutter visible and Back closes only effects',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const StoryEditorConfigProvider(
            config: StoryEditorConfig(cameraPermissionManagedByHost: true),
            child: StoryCameraScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byKey(const ValueKey('camera_effects_button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('camera_effects_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(CameraEffectsPanel), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(const ValueKey('camera_filter_slider')), findsNothing);
      final tray = tester.getRect(find.byType(CameraEffectsPanel));
      final shutter = tester.getRect(
        find.byKey(AnchoredShutterControl.shutterAnchorKey),
      );
      final toggle = tester.getRect(
        find.byKey(const ValueKey('camera_effects_button')),
      );
      expect(tray.bottom, lessThan(shutter.top));
      expect(toggle.bottom, lessThan(tray.top));
      expect(tester.takeException(), isNull);

      final panel = tester.widget<CameraEffectsPanel>(
        find.byType(CameraEffectsPanel),
      );
      arCalls.clear();
      panel.onChanged(const CameraEffects(beauty: .65), panel.lookId, .5);
      await tester.pump();
      expect(
        arCalls.where((call) => call.method == 'setLens'),
        isEmpty,
        reason: 'Smoothing and color strength only change the shader',
      );

      final hiddenCarousel = tester.widget<PageView>(
        find.byKey(const ValueKey('camera_filter_slider'), skipOffstage: false),
      );
      final carouselPosition = hiddenCarousel.controller!.position;

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(CameraEffectsPanel), findsNothing);
      expect(find.byType(StoryCameraScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('camera_filter_slider')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<PageView>(
              find.byKey(const ValueKey('camera_filter_slider')),
            )
            .controller!
            .position,
        same(carouselPosition),
        reason: 'The carousel keeps its position while controls are open',
      );
      await tester.tap(find.text('المزيد'));
      await tester.pump();
      expect(find.text('أقل'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('المزيد'), findsOneWidget);
      expect(find.byType(StoryCameraScreen), findsOneWidget);
      expect(
        tester.getRect(find.byKey(AnchoredShutterControl.shutterAnchorKey)),
        shutter,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}
