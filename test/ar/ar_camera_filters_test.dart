import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/src/ar/ar_camera_filters.dart';
import 'package:story_editor_pro/src/config/story_editor_filters.dart';

void main() {
  group('AR filter catalog', () {
    test('contains seven distinct effect presets plus original', () {
      final effects = ArCameraFilterCatalog.filters
          .where((filter) => filter.id != ArCameraFilterId.none)
          .toList();
      expect(effects, hasLength(7));
      expect(effects.map((filter) => filter.presetId).toSet(), hasLength(7));
      expect(effects.map((filter) => filter.shaderMode).toSet(), <int>{
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      });
      expect(
        StoryEditorFilters.arPresets.map((preset) => preset.id).toSet(),
        effects.map((filter) => filter.presetId).toSet(),
      );
    });

    test(
      'all filters have deterministic capture fallbacks and Arabic labels',
      () {
        for (final filter in ArCameraFilterCatalog.filters) {
          expect(filter.fallbackPresetId, isNotEmpty);
          expect(filter.localizedName(const Locale('ar')), isNotEmpty);
          expect(filter.localizedName(const Locale('en')), filter.nameEn);
        }
      },
    );
  });

  group('capability policy', () {
    const androidBalanced = ArCameraCapabilities(
      platform: ArCameraPlatform.android,
    );
    const iosHigh = ArCameraCapabilities(
      platform: ArCameraPlatform.ios,
      quality: ArCameraQuality.high,
    );

    test('runs single-sample effects on balanced Android', () {
      final neon = ArCameraFilterCatalog.byId(ArCameraFilterId.neonPulse);
      final resolved = ArCameraCapabilityPolicy.resolve(neon, androidBalanced);
      expect(resolved.useShader, isTrue);
      expect(resolved.animate, isTrue);
    });

    test('reserves multi-sample prism for high quality devices', () {
      final prism = ArCameraFilterCatalog.byId(ArCameraFilterId.prismPop);
      expect(
        ArCameraCapabilityPolicy.resolve(prism, androidBalanced).useShader,
        isFalse,
      );
      expect(
        ArCameraCapabilityPolicy.resolve(prism, iosHigh).useShader,
        isTrue,
      );
    });

    test('falls back safely on low-end, disabled, and non-mobile profiles', () {
      final stars = ArCameraFilterCatalog.byId(ArCameraFilterId.stargaze);
      const profiles = <ArCameraCapabilities>[
        ArCameraCapabilities(
          platform: ArCameraPlatform.android,
          quality: ArCameraQuality.low,
        ),
        ArCameraCapabilities(
          platform: ArCameraPlatform.ios,
          liveEffectsEnabled: false,
        ),
        ArCameraCapabilities(platform: ArCameraPlatform.other),
      ];
      for (final profile in profiles) {
        expect(
          ArCameraCapabilityPolicy.resolve(stars, profile).useShader,
          isFalse,
        );
      }
    });

    test('reduce motion keeps shader but disables animation', () {
      final retro = ArCameraFilterCatalog.byId(ArCameraFilterId.retroScan);
      const profile = ArCameraCapabilities(
        platform: ArCameraPlatform.ios,
        reduceMotion: true,
      );
      final resolved = ArCameraCapabilityPolicy.resolve(retro, profile);
      expect(resolved.useShader, isTrue);
      expect(resolved.animate, isFalse);
    });
  });

  test('controller clamps intensity and resets effect defaults', () {
    final controller = ArCameraFilterController();
    addTearDown(controller.dispose);
    expect(controller.select(ArCameraFilterId.neonPulse), isTrue);
    expect(controller.intensity, controller.selectedFilter.defaultIntensity);
    expect(controller.setIntensity(2), isTrue);
    expect(controller.intensity, 1);
    expect(controller.setIntensity(-3), isTrue);
    expect(controller.intensity, 0);
    controller.reset();
    expect(controller.selectedId, ArCameraFilterId.none);

    final clampedAtConstruction = ArCameraFilterController(initialIntensity: 9);
    expect(clampedAtConstruction.intensity, 1);
    clampedAtConstruction.dispose();
  });

  testWidgets('selector is interactive and displays Arabic labels', (
    tester,
  ) async {
    final controller = ArCameraFilterController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('ar'),
        delegates: const <LocalizationsDelegate<dynamic>>[
          DefaultWidgetsLocalizations.delegate,
        ],
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            color: Colors.black,
            child: ArCameraFilterSelector(controller: controller),
          ),
        ),
      ),
    );
    expect(find.text('طبيعي'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('ar-filter-ar_golden')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.selectedId, ArCameraFilterId.goldenHour);
    expect(find.text('ذهبي'), findsOneWidget);
  });

  testWidgets('selector accepts host-provided localized labels', (
    tester,
  ) async {
    final controller = ArCameraFilterController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ArCameraFilterSelector(
            controller: controller,
            labelBuilder: (id) => id == 'ar_neon' ? 'Host Neon' : id,
          ),
        ),
      ),
    );
    expect(find.text('Host Neon'), findsOneWidget);
  });

  testWidgets('surface uses no shader on low-end devices', (tester) async {
    final controller = ArCameraFilterController(
      initialFilter: ArCameraFilterId.neonPulse,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: ArCameraFilterSurface(
            controller: controller,
            capabilities: const ArCameraCapabilities(
              platform: ArCameraPlatform.android,
              quality: ArCameraQuality.low,
            ),
            child: const ColoredBox(
              key: ValueKey<String>('camera-preview'),
              color: Colors.blue,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('camera-preview')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('runtime shader asset is bundled and compiles', (tester) async {
    final program = await ui.FragmentProgram.fromAsset(
      // Package tests run with story_editor_pro as the root bundle. Host apps
      // use ArCameraFilterCatalog.shaderAsset's package-prefixed key.
      'shaders/ar_camera_filter.frag',
    );
    final shader = program.fragmentShader();
    shader.dispose();
  });

  testWidgets('live selection activates the shader surface', (tester) async {
    final program = await ui.FragmentProgram.fromAsset(
      ArCameraFilterCatalog.packageRootShaderAsset,
    );
    final controller = ArCameraFilterController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Expanded(
                child: ArCameraFilterSurface(
                  controller: controller,
                  capabilities: const ArCameraCapabilities(
                    platform: ArCameraPlatform.ios,
                    quality: ArCameraQuality.high,
                  ),
                  shaderAsset: ArCameraFilterCatalog.packageRootShaderAsset,
                  preloadedProgram: program,
                  imageFilterFactory: (_) => ui.ImageFilter.blur(sigmaX: 0.1),
                  child: const ColoredBox(color: Colors.blue),
                ),
              ),
              ArCameraFilterSelector(controller: controller),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('ar-filter-ar_golden')));
    await tester.pump();
    expect(controller.selectedFilter.presetId, 'ar_golden');
    expect(controller.selectedFilter.exportPresetId, 'goldenhour');
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('ar-filter-surface-shader')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('ar-filter-surface-empty')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('ar-filter-surface-backdrop')),
      findsOneWidget,
    );
  });

  testWidgets('unsupported shader renderer degrades without a crash', (
    tester,
  ) async {
    final program = await ui.FragmentProgram.fromAsset(
      ArCameraFilterCatalog.packageRootShaderAsset,
    );
    final controller = ArCameraFilterController(
      initialFilter: ArCameraFilterId.goldenHour,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: ArCameraFilterSurface(
            controller: controller,
            capabilities: const ArCameraCapabilities(
              platform: ArCameraPlatform.android,
              quality: ArCameraQuality.high,
            ),
            preloadedProgram: program,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('ar-filter-surface-fallback')),
      findsOneWidget,
    );
  });
}
