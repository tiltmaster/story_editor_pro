import 'dart:ui' as ui;

/// Small, upright, unmirrored eye anchors; camera pixels stay on the GPU.
class FaceBeautyPose {
  const FaceBeautyPose(this.leftX, this.leftY, this.rightX, this.rightY);

  final double leftX, leftY, rightX, rightY;

  static FaceBeautyPose? fromMap(Object? value) {
    if (value is! Map) return null;
    final coordinates = [
      'leftX',
      'leftY',
      'rightX',
      'rightY',
    ].map((key) => value[key]).toList();
    if (coordinates.any((n) => n is! num || !n.isFinite || n < 0 || n > 1)) {
      return null;
    }
    final c = coordinates.cast<num>().map((n) => n.toDouble()).toList();
    if ((c[0] - c[2]).abs() + (c[1] - c[3]).abs() < .015) return null;
    return FaceBeautyPose(c[0], c[1], c[2], c[3]);
  }

  Map<String, double> toMap() => {
    'leftX': leftX,
    'leftY': leftY,
    'rightX': rightX,
    'rightY': rightY,
  };
}

/// Append-only shader ABI after the existing look uniforms (0–20).
void applyFaceBeautyUniforms(
  ui.FragmentShader shader, {
  FaceBeautyPose? pose,
  double eyes = 0,
  double slim = 0,
}) {
  shader
    ..setFloat(21, pose?.leftX ?? 0)
    ..setFloat(22, pose?.leftY ?? 0)
    ..setFloat(23, pose?.rightX ?? 0)
    ..setFloat(24, pose?.rightY ?? 0)
    ..setFloat(25, pose != null && eyes.isFinite ? eyes.clamp(0, 1) : 0)
    ..setFloat(26, pose != null && slim.isFinite ? slim.clamp(0, 1) : 0);
}

/// Video timestamps are relative to recording, never wall-clock time. Explicit
/// loss samples and a 250ms age limit prevent a frozen warp on an absent face.
FaceBeautyPose? faceBeautyPoseAt(
  List<Map<String, double>> frames,
  double timeMs,
) {
  var low = 0;
  var high = frames.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if ((frames[mid]['timeMs'] ?? 0) <= timeMs) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  if (low == 0) return null;
  final frame = frames[low - 1];
  if (timeMs - (frame['timeMs'] ?? 0) > 250) return null;
  return FaceBeautyPose.fromMap(frame);
}
