import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

/// Guards the parts of the AR contract that only break once the plugin is
/// built the way it ships: minified, on a device, inside a host application.
/// Every assertion here failed silently in a release build while `flutter
/// analyze`, `flutter test` and the debug-only CI builds stayed green.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String read(String path) => File(path).readAsStringSync();

  group('release minification keeps the MediaPipe JNI surface', () {
    test('the plugin ships consumer ProGuard rules', () {
      // MediaPipe's own AARs carry none, so if the plugin does not ship them
      // either, every consuming app that minifies loses face tracking.
      expect(
        File('android/consumer-rules.pro').existsSync(),
        isTrue,
        reason: 'android/consumer-rules.pro must travel with the AAR',
      );
      expect(
        read('android/build.gradle'),
        contains("consumerProguardFiles 'consumer-rules.pro'"),
        reason: 'consumer rules only reach consumers when Gradle declares them',
      );
    });

    test('the rules keep every package the native layer resolves by name', () {
      final rules = read('android/consumer-rules.pro');
      expect(rules, contains('-keep class com.google.mediapipe.** { *; }'));
      expect(rules, contains('-keep interface com.google.mediapipe.** { *; }'));
      expect(rules, contains('-keep class org.tensorflow.lite.** { *; }'));
      expect(
        rules,
        contains('extends com.google.protobuf.GeneratedMessageLite'),
        reason: 'graph options are protobuf-javalite messages',
      );
    });

    test('the Flutter embedding jar is only added when it exists', () {
      // Flutter 3.44.9 no longer caches android-arm-release/flutter.jar. An
      // unconditional compileOnly on it fails JetifyTransform and breaks every
      // Android build of the consuming app, release and debug alike.
      final gradle = read('android/build.gradle');
      expect(gradle, contains('if (flutterEmbeddingJar.exists())'));
      expect(
        gradle,
        isNot(contains('compileOnly files("\$flutterRoot/bin/cache')),
        reason: 'the jar must never be referenced unguarded',
      );
    });

    test('the delegate fallback survives Error, not just RuntimeException', () {
      // A stripped or missing GPU delegate raises NoSuchMethodError /
      // UnsatisfiedLinkError. Catching RuntimeException skipped the CPU path.
      final tracker = read(
        'android/src/main/kotlin/com/storyeditorpro/ar/MediaPipeFaceTracker.kt',
      );
      expect(tracker, contains('} catch (_: Throwable) {'));
      expect(tracker, isNot(contains('} catch (_: RuntimeException) {')));
    });

    test('silent capability drops are logged at a level release keeps', () {
      // Hosts commonly strip Log.v/d/i/w with -assumenosideeffects; Log.e is
      // what survives, and these two paths are the ones that disable AR.
      final controller = read(
        'android/src/main/kotlin/com/storyeditorpro/ar/FaceArController.kt',
      );
      expect(controller, contains('android.util.Log.e(TAG, "AR asset unavailable'));
      expect(controller, contains('android.util.Log.e(TAG, "Native AR failed'));
    });
  });

  group('lens identifiers agree across Dart, Kotlin and Swift', () {
    Set<String> quoted(String source) => RegExp(r'"([^"]+)"')
        .allMatches(source)
        .map((match) => match.group(1)!)
        .toSet();

    test('face lens ids match on all three platforms', () {
      final kotlin = read(
        'android/src/main/kotlin/com/storyeditorpro/ar/FaceArContract.kt',
      );
      final swift = read('ios/Classes/CreativeLensFrameRenderer.swift');

      final kotlinFace = quoted(
        RegExp(r'adornmentLensIds = setOf\(([^)]*)\)').firstMatch(kotlin)!.group(1)!,
      );
      final swiftFace = quoted(
        RegExp(r'adornmentIds: Set<String> = \[([^\]]*)\]').firstMatch(swift)!.group(1)!,
      );

      expect(kotlinFace, NativeArLensIds.face);
      expect(swiftFace, NativeArLensIds.face);
    });

    test('composed lens ids match on all three platforms', () {
      final kotlin = read(
        'android/src/main/kotlin/com/storyeditorpro/ar/FaceArContract.kt',
      );
      final swift = read('ios/Classes/CreativeLensFrameRenderer.swift');

      // Kotlin names the composed ids through LENS_* constants.
      final constants = <String, String>{
        for (final match
            in RegExp(r'const val (LENS_\w+) = "([^"]+)"').allMatches(kotlin))
          match.group(1)!: match.group(2)!,
      };
      final kotlinComposed = RegExp(r'composedLensIds = setOf\(([^)]*)\)')
          .firstMatch(kotlin)!
          .group(1)!
          .split(',')
          .map((entry) => entry.trim())
          .where(constants.containsKey)
          .map((name) => constants[name]!)
          .toSet();
      final swiftComposed = quoted(
        RegExp(r'lensIds: Set<String> = \[([^\]]*)\]', dotAll: true)
            .firstMatch(swift)!
            .group(1)!,
      );

      expect(kotlinComposed, NativeArLensIds.composed);
      expect(swiftComposed, NativeArLensIds.composed);
    });

    test('the filter catalogue reuses the same composed ids', () {
      // These are duplicated literals in StoryEditorFilters; drift there sends
      // an unknown compositionId to native and fails the whole selection.
      expect(StoryEditorFilters.composedLensIds, NativeArLensIds.composed);
      for (final id in NativeArLensIds.composed) {
        expect(
          StoryEditorFilters.presets.any((preset) => preset.id == id),
          isTrue,
          reason: '$id must stay selectable in the look carousel',
        );
      }
    });
  });

  group('AR models ship and are reachable by the path native asks for', () {
    test('both models exist as real binaries', () {
      for (final path in const [
        'assets/ar/models/face_landmarker.task',
        'assets/ar/models/selfie_segmenter.tflite',
      ]) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path is missing');
        // Catches an LFS pointer, a truncated download or an empty placeholder.
        expect(file.lengthSync(), greaterThan(100000), reason: '$path is a stub');
      }
    });

    test('the declaration and both native lookups use the same paths', () {
      final pubspec = read('pubspec.yaml');
      final android = read(
        'android/src/main/kotlin/com/storyeditorpro/StoryEditorProPlugin.kt',
      );
      final ios = read('ios/Classes/StoryEditorProPlugin.swift');

      expect(pubspec, contains('- assets/ar/models/'));
      expect(android, contains('"assets/ar/models/face_landmarker.task"'));
      expect(ios, contains('"assets/ar/models/face_landmarker.task"'));
      // Plugin assets are packaged under packages/<name>/, so both platforms
      // must resolve through the package-aware lookup, not a bare path.
      expect(android, contains('getAssetFilePathByName(logicalPath, "story_editor_pro")'));
      expect(ios, contains('lookupKey(forAsset: asset, fromPackage: "story_editor_pro")'));
    });
  });

  group('capability probing recovers', () {
    const methodChannel = MethodChannel('story_editor_pro/ar');
    const eventControlChannel = MethodChannel('story_editor_pro/ar_events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockMethodCallHandler(eventControlChannel, null);
    });

    test('a transient failure does not disable AR for the whole session', () async {
      // The camera re-probes when it resumes. Memoizing the first failure made
      // that retry a no-op and left the lens tray permanently empty.
      var attempt = 0;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method != 'getCapabilities') return null;
        if (attempt++ == 0) {
          throw PlatformException(code: 'camera_busy', message: 'Try again');
        }
        return <String, Object?>{
          'supported': true,
          'faceTracking': true,
          'preview': true,
          'recording': true,
          'lensIds': NativeArLensIds.face.toList(),
        };
      });
      messenger.setMockMethodCallHandler(eventControlChannel, (_) async => null);

      final controller = NativeArController();
      expect((await controller.getCapabilities()).available, isFalse);
      expect(controller.state, NativeArRuntimeState.unavailable);

      final retried = await controller.getCapabilities();
      expect(attempt, 2, reason: 'the second probe must reach the platform');
      expect(retried.available, isTrue);
      expect(retried.supportsLens(NativeArLensIds.neonContour), isTrue);

      await controller.dispose();
    });

    test('a successful probe is still answered once', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method != 'getCapabilities') return null;
        calls++;
        return <String, Object?>{
          'supported': true,
          'lensIds': NativeArLensIds.all.toList(),
        };
      });
      messenger.setMockMethodCallHandler(eventControlChannel, (_) async => null);

      final controller = NativeArController();
      await controller.getCapabilities();
      await controller.getCapabilities();
      expect(calls, 1);

      await controller.dispose();
    });
  });

  test('iOS replays face readiness when Dart subscribes late', () {
    // Dart only subscribes to the event channel on the first lens selection,
    // so a tracker that became ready earlier is announced on subscribe or not
    // at all. Android already replayed faceReady; iOS dropped it.
    final pipeline = read('ios/Classes/FaceARPipeline.swift');
    final setSink = RegExp(
      r'func setEventSink\(_ sink: FlutterEventSink\?\) \{(.*?)\n    \}',
      dotAll: true,
    ).firstMatch(pipeline)!.group(1)!;
    expect(setSink, contains('emitState(current)'));
    expect(pipeline, contains('"faceReady": faceReady'));
  });
}
