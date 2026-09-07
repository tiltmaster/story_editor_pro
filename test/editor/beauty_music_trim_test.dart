import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  group('authored camera looks', () {
    test('prioritizes authored looks and keeps legacy looks at the end', () {
      expect(StoryEditorFilters.presets.first.id, StoryEditorFilters.none);
      expect(
        StoryEditorFilters.presets
            .skip(1)
            .take(5)
            .map((preset) => preset.id)
            .toList(),
        ['vhs1993', 'daytime', 'timefocus', 'kuwaitgold', 'retrodate'],
      );
      expect(
        StoryEditorFilters.presets
            .skip(StoryEditorFilters.presets.length - 2)
            .map((preset) => preset.id),
        orderedEquals(['softbeauty', 'cleanglow']),
      );
    });

    test('color presets leave the independent beauty amount unchanged', () {
      final ids = StoryEditorFilters.presets.map((preset) => preset.id).toSet();
      expect(ids, isNot(contains('naturalskin')));
      expect(ids, isNot(contains('freshglow')));
      expect(ids, isNot(contains('softportrait')));
      for (final id in ids) {
        expect(StoryEditorFilters.beautyStrength(id, 1), 0);
      }
    });

    test('creative effects are scoped to their material presets', () {
      expect(StoryEditorFilters.beautyStrength('softbeauty', 1), 0);
      expect(StoryEditorFilters.beautyStrength('none', 1), 0);
      expect(
        StoryEditorFilters.vhsStrength('vhs1993', 1),
        closeTo(0.68, 0.001),
      );
      expect(StoryEditorFilters.bloomStrength('daytime', 1), greaterThan(0));
      expect(StoryEditorFilters.beautyStrength('timefocus', 1), 0);
      expect(
        StoryEditorFilters.splitToneStrength('kuwaitgold', 1),
        greaterThan(0),
      );
      expect(StoryEditorFilters.splitToneStrength('retrodate', 1), lessThan(0));
      expect(StoryEditorFilters.grainStrength('none', 1), 0);
    });

    test(
      'all five signature looks have distinct bounded render signatures',
      () {
        const presets = <String>[
          'vhs1993',
          'daytime',
          'timefocus',
          'kuwaitgold',
          'retrodate',
        ];
        final signatures = presets.map((preset) {
          final p = StoryEditorFilters.resolve(preset, 1);
          return <double>[
            p.brightness,
            p.contrast,
            p.saturation,
            p.red,
            p.green,
            p.blue,
            StoryEditorFilters.beautyStrength(preset, 1),
            StoryEditorFilters.vhsStrength(preset, 1),
            StoryEditorFilters.bloomStrength(preset, 1),
            StoryEditorFilters.grainStrength(preset, 1),
            StoryEditorFilters.halationStrength(preset, 1),
            StoryEditorFilters.splitToneStrength(preset, 1),
            StoryEditorFilters.chromaStrength(preset, 1),
          ].map((value) => value.toStringAsFixed(4)).join('|');
        }).toSet();

        expect(signatures, hasLength(presets.length));
        expect(StoryEditorFilters.bloomStrength('daytime', -1), 0);
        expect(
          StoryEditorFilters.bloomStrength('daytime', 2),
          StoryEditorFilters.bloomStrength('daytime', 1),
        );
        expect(StoryEditorFilters.chromaStrength('none', 1), 0);
      },
    );

    test(
      'camera uses pixel effects plus native saved-media lens compositions',
      () {
        final camera = File(
          'lib/src/story_camera_screen.dart',
        ).readAsStringSync();
        final editor = File(
          'lib/src/story_editor_screen.dart',
        ).readAsStringSync();
        final filters = File(
          'lib/src/config/story_editor_filters.dart',
        ).readAsStringSync();
        final shader = File('shaders/story_filter.frag').readAsStringSync();
        final iosExporter = File(
          'ios/Classes/VideoOverlayProcessor.swift',
        ).readAsStringSync();

        expect(camera, isNot(contains('StoryAuthoredFilterOverlay(')));
        expect(editor, isNot(contains('StoryAuthoredFilterOverlay(')));
        expect(filters, isNot(contains('class StoryAuthoredFilterOverlay')));
        expect(camera, contains('needsVignette && !useShader'));
        expect(camera, contains('useGpuEffects: true'));
        expect(
          RegExp(r'useGpuEffects: false').allMatches(camera).length,
          greaterThanOrEqualTo(2),
        );
        expect(camera, contains('setFloat(20'));
        expect(editor, contains('StoryEditorFilters.chromaStrength('));
        expect(shader, isNot(contains('float dropout')));
        expect(shader, isNot(contains('float scan =')));
        expect(iosExporter, isNot(contains('CIStripesGenerator')));
        expect(iosExporter, contains('kernel vec4 storyParityFilter('));
        expect(iosExporter, contains('extent: targetExtent'));
        expect(iosExporter, isNot(contains('720.0 / max(output.extent.width')));
        expect(
          File(
            'android/src/main/kotlin/com/storyeditorpro/ar/CreativeLensRenderer.kt',
          ).readAsStringSync(),
          contains('CameraX compositor for authored camera lenses'),
        );
        expect(
          File(
            'ios/Classes/CreativeLensFrameRenderer.swift',
          ).readAsStringSync(),
          contains('live texture, photo capture and'),
        );
        expect(camera, contains('StoryEditorFilters.isComposedLens(filter)'));
        expect(camera, matches(RegExp(r'isComposedLens\(\s*preset\.id')));
        final androidController = File(
          'android/src/main/kotlin/com/storyeditorpro/ar/FaceArController.kt',
        ).readAsStringSync();
        expect(androidController, contains('CameraEffect.VIDEO_CAPTURE'));
        expect(androidController, contains('CameraEffect.IMAGE_CAPTURE'));
        expect(
          androidController,
          contains('internal const val OVERLAY_QUEUE_DEPTH = 0'),
        );
        expect(
          androidController,
          contains('drawCreative || drawFace || overlayHadArtwork'),
        );
        expect(androidController, isNot(contains('drawFrameAsync(')));
        expect(
          androidController,
          isNot(contains('requestCreativeDraw(pending)')),
        );
        expect(
          androidController,
          isNot(contains('OUTPUT_IMAGE_FORMAT_RGBA_8888')),
        );
        expect(
          androidController,
          isNot(contains('if (!faceTrackingSupported || closed) return null')),
        );
        final iosPipeline = File(
          'ios/Classes/FaceARPipeline.swift',
        ).readAsStringSync();
        final iosPlugin = File(
          'ios/Classes/StoryEditorProPlugin.swift',
        ).readAsStringSync();
        expect(iosPipeline, contains('activeCreativeRenderer?.render('));
        expect(iosPipeline, contains('creativeRenderer = nil'));
        expect(iosPipeline, contains('private let renderLock = NSLock()'));
        expect(iosPlugin, contains('let photoBuffer = photo.pixelBuffer'));
        expect(
          iosPlugin,
          contains('photoOutput.availablePhotoPixelFormatTypes'),
        );
        expect(
          iosPlugin,
          contains('kCVPixelBufferPixelFormatTypeKey as String'),
        );
        expect(iosPlugin, contains('settings.isHighResolutionPhotoEnabled ='));
        expect(iosPlugin, contains('Filtered photo buffer is unavailable'));
        expect(iosPlugin, contains('Filtered photo encoding failed'));
        expect(iosPlugin, contains('photoRequiresEffectProcessing'));
        expect(
          iosPlugin,
          isNot(contains('let renderedFrame = latestPixelBuffer')),
        );
      },
    );

    test('creative shader ABI and native exporters stay in parity', () {
      final shader = File('shaders/story_filter.frag').readAsStringSync();
      final camera = File(
        'lib/src/story_camera_screen.dart',
      ).readAsStringSync();
      final editor = File(
        'lib/src/story_editor_screen.dart',
      ).readAsStringSync();
      final androidRenderer = File(
        'android/src/main/kotlin/com/storyeditorpro/TextureRenderer.kt',
      ).readAsStringSync();
      final androidExporter = File(
        'android/src/main/kotlin/com/storyeditorpro/VideoOverlayProcessor.kt',
      ).readAsStringSync();
      final iosExporter = File(
        'ios/Classes/VideoOverlayProcessor.swift',
      ).readAsStringSync();

      var shaderIndex = -1;
      for (final uniform in const <String>[
        'uBloom',
        'uGrain',
        'uHalation',
        'uSplitTone',
        'uChroma',
      ]) {
        final next = shader.indexOf('uniform float $uniform');
        expect(next, greaterThan(shaderIndex), reason: uniform);
        shaderIndex = next;
        expect(androidRenderer, contains('uniform float $uniform;'));
      }

      for (final method in const <String>[
        'bloomStrength',
        'grainStrength',
        'halationStrength',
        'splitToneStrength',
        'chromaStrength',
      ]) {
        expect(camera, contains('StoryEditorFilters.$method('));
        expect(editor, contains('StoryEditorFilters.$method('));
      }

      for (final field in const <String>[
        'bloom',
        'grain',
        'halation',
        'splitTone',
        'chroma',
      ]) {
        expect(androidExporter, contains('val $field: Float = 0f'));
        expect(iosExporter, contains('$field: Double'));
      }

      expect(RegExp(r'texture\(uTexture').allMatches(shader), hasLength(9));
      expect(shader, contains('vec3 n0'));
      expect(shader, isNot(contains('glowPx')));
      expect(shader, isNot(contains('meanVar')));
      expect(shader, contains('mod('));
      expect(androidRenderer, contains('precision highp float;'));
      expect(androidRenderer, contains('GL_FRAGMENT_PRECISION_HIGH'));
      expect(androidRenderer, contains('vec3 n0'));
      expect(androidRenderer, isNot(contains('glowPx')));
      expect(iosExporter, contains('vec3 n0'));
      expect(iosExporter, isNot(contains('spatialRoiInset')));
      expect(androidRenderer, contains('vec2 proceduralUv ='));
      expect(iosExporter, contains('vec2 proceduralUv ='));
      expect(androidRenderer, contains('1.0 - screenUv.y'));
      expect(iosExporter, contains('1.0 - uv.y'));
      expect(iosExporter, isNot(contains('CINoiseReduction')));
      expect(iosExporter, isNot(contains('CIBloom')));
      expect(
        iosExporter,
        contains('The iOS parity filter kernel is unavailable'),
      );
      final nativeWorkflow = File(
        '.github/workflows/native-quality-gates.yml',
      ).readAsStringSync();
      expect(
        nativeWorkflow,
        contains(':story_editor_pro:testDebugUnitTest --no-daemon'),
      );
      expect(
        nativeWorkflow.indexOf('flutter build apk --debug --no-pub'),
        lessThan(
          nativeWorkflow.indexOf(
            ':story_editor_pro:testDebugUnitTest --no-daemon',
          ),
        ),
      );
    });

    test('removed beauty implementation leaves no vendored runtime', () {
      final shader = File('shaders/story_filter.frag').readAsStringSync();
      final androidRenderer = File(
        'android/src/main/kotlin/com/storyeditorpro/TextureRenderer.kt',
      ).readAsStringSync();
      final iosExporter = File(
        'ios/Classes/VideoOverlayProcessor.swift',
      ).readAsStringSync();

      expect(Directory('vendor/gpupixel').existsSync(), isFalse);
      for (final source in <String>[shader, androidRenderer, iosExporter]) {
        expect(source, isNot(contains('GPUPixel')));
        expect(source, isNot(contains('meanVar')));
        expect(source, isNot(contains('highPass')));
      }

      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/ar/THIRD_PARTY_NOTICES.md'));
      expect(pubspec, isNot(contains('vendor/gpupixel')));
      final privacyManifest = File(
        'ios/Resources/PrivacyInfo.xcprivacy',
      ).readAsStringSync();
      expect(
        privacyManifest,
        contains('NSPrivacyCollectedDataTypePerformanceData'),
      );
    });

    test('Android camera stack declares the MediaPipe API floor', () {
      final pluginGradle = File('android/build.gradle').readAsStringSync();
      expect(pluginGradle, contains('minSdk 24'));
    });

    test('capture freezes the visible filter before camera I/O', () {
      final camera = File(
        'lib/src/story_camera_screen.dart',
      ).readAsStringSync();
      final snapshotIndex = camera.indexOf(
        'final capturedFilterId = _activeFilterId;',
      );
      final captureIndex = camera.indexOf(
        'final imagePath = await _capturePhotoPath();',
      );

      expect(snapshotIndex, greaterThanOrEqualTo(0));
      expect(captureIndex, greaterThan(snapshotIndex));
      expect(camera, contains('initialFilterPreset: capturedPixelFilterId'));
      expect(camera, contains('initialFilterStrength: capturedFilterStrength'));
      expect(camera, contains('await _ensureCameraFilterShader()'));
      expect(camera, contains('bool _canSelectFilterIndex(int index)'));
      expect(camera, contains('preset.id == StoryEditorFilters.none'));
      expect(camera, contains('filterId: capturedFilterId'));
      expect(
        camera,
        contains('if (_nativeArPrepared) await _applyNativeArSelection();'),
      );
      expect(camera, contains('!StoryEditorFilters.isNativeLens(filterId)'));
      expect(camera, contains('String _pixelFilterIdForSavedMedia('));
      expect(
        camera,
        matches(
          RegExp(r'if \(!mounted\) return;\s*// Save photo to active tile'),
        ),
      );

      final editor = File(
        'lib/src/story_editor_screen.dart',
      ).readAsStringSync();
      expect(editor, contains('await _filterShaderLoadFuture'));
      expect(editor, contains('await _ensureFilterShaderReady();'));
      expect(editor, contains('String get _effectiveFilterPreset'));
      expect(editor, contains('StoryEditorFilters.isNativeLens('));
    });
  });

  test('music result serializes metadata without playback credentials', () {
    final result = StoryResult(
      filePath: '/private/story.mp4',
      fileName: 'story.mp4',
      mediaType: StoryMediaType.video,
      fileSize: 128,
      createdAt: DateTime.utc(2026),
      music: const StoryEditorMusicSelection(
        id: 'track-1',
        title: 'Safe title',
        artist: 'Artist',
        startMs: 1500,
        durationMs: 12000,
      ),
    );

    final json = result.toJson();
    expect(json['music'], {
      'id': 'track-1',
      'title': 'Safe title',
      'artist': 'Artist',
      'startMs': 1500,
      'durationMs': 12000,
    });
    expect(json.toString(), isNot(contains('url')));
    expect(json.toString(), isNot(contains('token')));
  });

  group('video trim validation', () {
    test('accepts full and bounded ranges', () {
      expect(
        () => VideoOverlayExportService.validateTrimRange(0, 0),
        returnsNormally,
      );
      expect(
        () => VideoOverlayExportService.validateTrimRange(250, 5000),
        returnsNormally,
      );
    });

    test('rejects negative and reversed ranges before native export', () {
      expect(
        () => VideoOverlayExportService.validateTrimRange(-1, 1000),
        throwsArgumentError,
      );
      expect(
        () => VideoOverlayExportService.validateTrimRange(1000, 1000),
        throwsArgumentError,
      );
      expect(
        () => VideoOverlayExportService.validateTrimRange(2000, 1000),
        throwsArgumentError,
      );
    });
  });
}
