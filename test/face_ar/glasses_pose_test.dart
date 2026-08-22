import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/src/camera_filter_rail.dart';
import 'package:story_editor_pro/src/config/story_editor_strings.dart';
import 'package:story_editor_pro/src/face_ar/face_ar_models.dart';
import 'package:story_editor_pro/src/face_ar/glasses_capture_compositor.dart';
import 'package:story_editor_pro/src/face_ar/glasses_mesh.dart';
import 'package:story_editor_pro/src/face_ar/glasses_pose.dart';

FaceArObservation observation({
  Offset leftEye = const Offset(0.4, 0.35),
  Offset rightEye = const Offset(0.6, 0.35),
  double confidence = 0.95,
  double yaw = 0,
  double pitch = 0,
  double roll = 0,
  DateTime? timestamp,
  bool mirrored = true,
}) {
  final at = timestamp ?? DateTime.utc(2026, 1, 1);
  return FaceArObservation(
    trackingId: 7,
    bounds: const Rect.fromLTWH(0.25, 0.15, 0.5, 0.65),
    landmarks: <FaceArLandmark, Offset>{
      FaceArLandmark.leftEye: leftEye,
      FaceArLandmark.rightEye: rightEye,
    },
    yawRadians: yaw,
    pitchRadians: pitch,
    rollRadians: roll,
    interocularDistance: (rightEye - leftEye).distance,
    confidence: confidence,
    timestamp: at,
    mirrored: mirrored,
  );
}

const mesh = GlassesRuntimeMesh(
  vertices: <GlassesVertex>[
    GlassesVertex(-0.7, 0.2, -0.25),
    GlassesVertex(0.7, 0.2, -0.25),
    GlassesVertex(0, -0.25, -0.25),
  ],
  triangles: <GlassesTriangle>[GlassesTriangle(0, 1, 2, 0)],
  materials: <GlassesMaterial>[
    GlassesMaterial(name: 'frame', color: Color(0xFF15171C)),
  ],
);

class _FixedMeshRepository extends GlassesMeshRepository {
  @override
  Future<GlassesRuntimeMesh?> load() async => mesh;
}

void main() {
  test('glasses is a distinct localized face lens at the end of the rail', () {
    final index = CameraFilterRailCatalog.presets.length - 1;
    expect(CameraFilterRailCatalog.isGlassesIndex(index), isTrue);
    expect(CameraFilterRailCatalog.isArIndex(index), isFalse);
    expect(CameraFilterRailCatalog.presets[index].id, 'ar_glasses');
    const english = StoryEditorStrings();
    const arabic = StoryEditorStrings(cameraFilterArGlasses: 'نظارات');
    expect(english.filterNameForPreset('ar_glasses'), 'Glasses');
    expect(arabic.filterNameForPreset('ar_glasses'), 'نظارات');
  });

  test(
    'pose uses eye midpoint and smooths without lagging a reacquisition',
    () {
      final tracker = GlassesPoseTracker();
      final start = DateTime.utc(2026, 1, 1);
      final first = tracker.update(observation(timestamp: start), start)!;
      expect(first.center, const Offset(0.5, 0.35));
      expect(first.interocularDistance, closeTo(0.2, 0.0001));

      final nextAt = start.add(const Duration(milliseconds: 66));
      final next = tracker.update(
        observation(
          leftEye: const Offset(0.42, 0.36),
          rightEye: const Offset(0.62, 0.36),
          yaw: 0.2,
          timestamp: nextAt,
        ),
        nextAt,
      )!;
      expect(next.center.dx, inInclusiveRange(0.5, 0.52));
      expect(next.yaw, inExclusiveRange(0, 0.2));

      final jumpAt = nextAt.add(const Duration(milliseconds: 66));
      final reacquired = tracker.update(
        observation(
          leftEye: const Offset(0.05, 0.2),
          rightEye: const Offset(0.25, 0.2),
          timestamp: jumpAt,
        ),
        jumpAt,
      )!;
      expect(reacquired.center, const Offset(0.15, 0.2));
    },
  );

  test('loss hysteresis holds, fades, then removes the lens', () {
    final tracker = GlassesPoseTracker();
    final start = DateTime.utc(2026, 1, 1);
    tracker.update(observation(timestamp: start), start);
    expect(
      tracker.poseAt(start.add(const Duration(milliseconds: 120)))!.opacity,
      1,
    );
    expect(
      tracker.poseAt(start.add(const Duration(milliseconds: 240)))!.opacity,
      closeTo(0.5, 0.02),
    );
    expect(
      tracker.poseAt(start.add(const Duration(milliseconds: 340))),
      isNull,
    );
  });

  test('angle smoothing follows the shortest path around pi', () {
    final tracker = GlassesPoseTracker();
    final start = DateTime.utc(2026, 1, 1);
    tracker.update(observation(roll: math.pi - 0.04), start);
    final nextAt = start.add(const Duration(milliseconds: 66));
    final pose = tracker.update(
      observation(roll: -math.pi + 0.04, timestamp: nextAt),
      nextAt,
    )!;
    expect(pose.roll.abs(), greaterThan(3));
  });

  test('capture transform reverses only the mirrored preview mapping', () {
    const transform = GlassesCaptureTransform(
      viewportSize: Size(300, 600),
      imageSize: Size(400, 400),
      previewMirrored: true,
    );
    // Cover scale is 1.5; 150 horizontal source pixels are cropped per side.
    expect(transform.coverScale, 1.5);
    expect(
      transform.viewportPointToImage(const Offset(0.25, 0.5)),
      const Offset(250, 200),
    );
    final captured = transform.poseToImage(
      GlassesPose(
        center: const Offset(0.25, 0.5),
        interocularDistance: 0.2,
        yaw: 0.3,
        pitch: 0.1,
        roll: 0.2,
        opacity: 1,
        timestamp: DateTime.utc(2026),
        mirrored: true,
      ),
    );
    expect(captured.center, const Offset(250, 200));
    expect(captured.interocularDistance, 40);
    expect(captured.yaw, -0.3);
    expect(captured.roll, -0.2);
  });

  test('capture transform preserves unmirrored pose orientation', () {
    const transform = GlassesCaptureTransform(
      viewportSize: Size(400, 400),
      imageSize: Size(800, 800),
      previewMirrored: false,
    );
    final captured = transform.poseToImage(
      GlassesPose(
        center: const Offset(0.25, 0.5),
        interocularDistance: 0.2,
        yaw: 0.3,
        pitch: 0.1,
        roll: -0.2,
        opacity: 1,
        timestamp: DateTime.utc(2026),
        mirrored: false,
      ),
    );
    expect(captured.center, const Offset(200, 400));
    expect(captured.interocularDistance, 160);
    expect(captured.yaw, 0.3);
    expect(captured.roll, -0.2);
  });

  test('runtime mesh parser consumes Blender compact contract', () {
    final parsed = GlassesRuntimeMesh.fromJson(<String, dynamic>{
      'vertices': <List<num>>[
        <num>[-0.5, 0, -0.2],
        <num>[0.5, 0, -0.2],
        <num>[0, 0.3, -0.2],
      ],
      'triangles': <List<int>>[
        <int>[0, 1, 2],
      ],
      'triangle_material_ids': <int>[0],
      'material_groups': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'frame',
          'base_color_rgba': <double>[0.1, 0.2, 0.3, 1],
        },
      ],
      'runtime_nominal_eye_distance': 1,
    });
    expect(parsed.isRenderable, isTrue);
    expect(parsed.vertices, hasLength(3));
    expect(parsed.triangles.single.materialIndex, 0);
  });

  testWidgets('bundled Blender runtime mesh stays inside the live budget', (
    tester,
  ) async {
    final bundled = await GlassesMeshRepository().load();
    expect(bundled, isNotNull);
    expect(bundled!.isRenderable, isTrue);
    expect(
      bundled.triangles.length,
      lessThanOrEqualTo(glassesLiveTriangleBudget),
    );
    expect(bundled.nominalEyeDistance, 1);
  });

  testWidgets(
    'live overlay renders mesh and does not mirror coordinates again',
    (tester) async {
      final start = DateTime.now();
      final state = ValueNotifier<FaceArTrackingState>(
        FaceArTrackingState(
          observations: <FaceArObservation>[
            observation(timestamp: start, mirrored: true),
          ],
          faceLost: false,
          timestamp: start,
        ),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 600,
            child: GlassesLensOverlay(
              trackingState: state,
              preloadedMesh: mesh,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('glasses-lens-mesh')),
        findsOneWidget,
      );
      expect(find.byType(Transform), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('oversized runtime mesh uses bounded flat fallback', (
    tester,
  ) async {
    final start = DateTime.now();
    final state = ValueNotifier<FaceArTrackingState>(
      FaceArTrackingState(
        observations: <FaceArObservation>[observation(timestamp: start)],
        faceLost: false,
        timestamp: start,
      ),
    );
    addTearDown(state.dispose);
    final oversized = GlassesRuntimeMesh(
      vertices: mesh.vertices,
      triangles: List<GlassesTriangle>.filled(
        glassesLiveTriangleBudget + 1,
        const GlassesTriangle(0, 1, 2, 0),
      ),
      materials: mesh.materials,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 600,
          child: GlassesLensOverlay(
            trackingState: state,
            preloadedMesh: oversized,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('glasses-lens-flat-fallback')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('glasses-lens-mesh')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  test('compositor cleanup deletes only its managed cache output', () async {
    final directory = await Directory.systemTemp.createTemp('glasses_test_');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final original = File(
      '${directory.path}${Platform.pathSeparator}capture.png',
    );
    final managed = File(
      '${directory.path}${Platform.pathSeparator}'
      '${GlassesCaptureCompositor.outputPrefix}123.png',
    );
    await original.writeAsBytes(const <int>[1, 2, 3]);
    await managed.writeAsBytes(const <int>[1, 2, 3]);
    final compositor = GlassesCaptureCompositor(
      repository: _FixedMeshRepository(),
      outputDirectoryProvider: () async => directory,
    );
    expect(await compositor.deleteManagedOutput(original.path), isFalse);
    expect(await original.exists(), isTrue);
    expect(await compositor.deleteManagedOutput(managed.path), isTrue);
    expect(await managed.exists(), isFalse);
  });
}
