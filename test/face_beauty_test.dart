import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/src/face_beauty.dart';
import 'package:story_editor_pro/src/native_ar_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invalid and lost poses cannot deform an unrelated image', () {
    expect(FaceBeautyPose.fromMap(null), isNull);
    expect(FaceBeautyPose.fromMap({'leftX': double.nan}), isNull);
    expect(
      FaceBeautyPose.fromMap({
        'leftX': .4,
        'leftY': .4,
        'rightX': .4,
        'rightY': .4,
      }),
      isNull,
    );
    final event = NativeArEvent.fromMap({
      'type': 'pose',
      'isPhoto': true,
      'timestampMs': 400,
      'facePose': {'leftX': .35, 'leftY': .4, 'rightX': .65, 'rightY': .4},
    });
    expect(event.type, NativeArEventType.pose);
    expect(event.isPhoto, isTrue);
    expect(event.facePose!.leftX, .35);
  });

  test(
    'video face samples expire and explicit loss takes effect immediately',
    () {
      final frames = <Map<String, double>>[
        {'timeMs': 100, 'leftX': .3, 'leftY': .4, 'rightX': .7, 'rightY': .4},
        {'timeMs': 500},
        {'timeMs': 600, 'leftX': .4, 'leftY': .4, 'rightX': .8, 'rightY': .4},
      ];
      expect(faceBeautyPoseAt(frames, 0), isNull);
      expect(faceBeautyPoseAt(frames, 200)!.leftX, .3);
      expect(faceBeautyPoseAt(frames, 351), isNull);
      expect(faceBeautyPoseAt(frames, 500), isNull);
      expect(faceBeautyPoseAt(frames, 600)!.leftX, .4);
    },
  );

  test(
    'GPU face shader enlarges eyes and leaves distant pixels unchanged',
    () async {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/story_filter.frag',
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xFFD5A084), ui.BlendMode.src);
      for (final x in [70.0, 130.0]) {
        canvas.drawCircle(
          ui.Offset(x, 80),
          8,
          ui.Paint()..color = const ui.Color(0xFF172033),
        );
      }
      for (final x in [65.0, 135.0]) {
        canvas.drawRect(
          ui.Rect.fromLTWH(x, 112, 2, 35),
          ui.Paint()..color = const ui.Color(0xFF302033),
        );
      }
      for (var x = 10; x < 45; x++) {
        for (var y = 155; y < 190; y++) {
          canvas.drawRect(
            ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
            ui.Paint()
              ..color = (x + y) % 2 == 0
                  ? const ui.Color(0xFFDEAB8F)
                  : const ui.Color(0xFFCC977B),
          );
        }
      }
      final input = await recorder.endRecording().toImage(200, 200);
      Future<List<int>> render(
        double eyes,
        FaceBeautyPose? pose, {
        double slim = 0,
        double smoothing = 0,
      }) async {
        final shader = program.fragmentShader();
        for (var i = 0; i < 27; i++) {
          shader.setFloat(i, 0);
        }
        shader
          ..setFloat(0, 200)
          ..setFloat(1, 200)
          ..setFloat(2, 1)
          ..setFloat(6, 1)
          ..setFloat(10, 1)
          ..setFloat(14, smoothing)
          ..setImageSampler(0, input);
        applyFaceBeautyUniforms(shader, pose: pose, eyes: eyes, slim: slim);
        final recording = ui.PictureRecorder();
        ui.Canvas(recording).drawRect(
          const ui.Rect.fromLTWH(0, 0, 200, 200),
          ui.Paint()..shader = shader,
        );
        final output = await recording.endRecording().toImage(200, 200);
        final data = await output.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final pixels = data!.buffer.asUint8List().toList();
        output.dispose();
        shader.dispose();
        return pixels;
      }

      final neutral = await render(0, null);
      final enlarged = await render(1, const FaceBeautyPose(.35, .4, .65, .4));
      final noFace = await render(1, null);
      final contoured = await render(
        0,
        const FaceBeautyPose(.35, .4, .65, .4),
        slim: 1,
      );
      final smoothed = await render(0, null, smoothing: 1);
      int darkPixels(List<int> data) {
        var total = 0;
        for (var y = 62; y < 98; y++) {
          for (var x = 50; x < 150; x++) {
            if (data[(y * 200 + x) * 4] < 100) total++;
          }
        }
        return total;
      }

      expect(darkPixels(enlarged), greaterThan(darkPixels(neutral) * 1.15));
      expect(
        enlarged.sublist(0, 200 * 4 * 30),
        neutral.sublist(0, 200 * 4 * 30),
      );
      expect(noFace, neutral);
      expect(
        contoured.sublist(200 * 4 * 112, 200 * 4 * 147),
        isNot(neutral.sublist(200 * 4 * 112, 200 * 4 * 147)),
      );
      expect(
        contoured.sublist(0, 200 * 4 * 90),
        neutral.sublist(0, 200 * 4 * 90),
      );
      double skinVariance(List<int> data) {
        final values = <int>[];
        for (var y = 160; y < 185; y++) {
          for (var x = 15; x < 40; x++) {
            values.add(data[(y * 200 + x) * 4]);
          }
        }
        final mean = values.reduce((a, b) => a + b) / values.length;
        return values
                .map((v) => (v - mean) * (v - mean))
                .reduce((a, b) => a + b) /
            values.length;
      }

      expect(skinVariance(smoothed), lessThan(skinVariance(neutral) * .7));
      input.dispose();
    },
  );
}
