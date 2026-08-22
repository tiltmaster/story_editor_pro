import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import 'face_ar_models.dart';
import 'glasses_pose.dart';

const String glassesRuntimeMeshAsset =
    'packages/story_editor_pro/assets/ar/glasses/runtime_mesh.json';
const String glassesFallbackImageAsset =
    'packages/story_editor_pro/assets/ar/glasses/ar_glasses_classic_front.png';
const String glassesPreviewAsset =
    'packages/story_editor_pro/assets/ar/glasses/ar_glasses_classic_preview.png';
const int glassesLiveTriangleBudget = 1200;

@immutable
class GlassesVertex {
  const GlassesVertex(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

@immutable
class GlassesTriangle {
  const GlassesTriangle(this.a, this.b, this.c, this.materialIndex);
  final int a;
  final int b;
  final int c;
  final int materialIndex;
}

@immutable
class GlassesMaterial {
  const GlassesMaterial({required this.name, required this.color});
  final String name;
  final Color color;
}

/// Compact Blender-authored mesh normalized so its nominal IPD is one unit.
@immutable
class GlassesRuntimeMesh {
  const GlassesRuntimeMesh({
    required this.vertices,
    required this.triangles,
    required this.materials,
    this.nominalEyeDistance = 1,
  });

  final List<GlassesVertex> vertices;
  final List<GlassesTriangle> triangles;
  final List<GlassesMaterial> materials;
  final double nominalEyeDistance;

  bool get isRenderable =>
      vertices.length >= 3 && triangles.isNotEmpty && materials.isNotEmpty;

  factory GlassesRuntimeMesh.fromJson(Map<String, dynamic> json) {
    final rawVertices = json['vertices'] as List<dynamic>? ?? const [];
    final vertices = rawVertices
        .map((dynamic raw) {
          final values = (raw as List<dynamic>).cast<num>();
          return GlassesVertex(
            values[0].toDouble(),
            values[1].toDouble(),
            values[2].toDouble(),
          );
        })
        .toList(growable: false);

    final rawTriangles = json['triangles'] as List<dynamic>? ?? const [];
    final triangleMaterials =
        (json['triangle_material_ids'] as List<dynamic>? ?? const [])
            .cast<num>();
    final triangles = <GlassesTriangle>[];
    for (var i = 0; i < rawTriangles.length; i++) {
      final indices = (rawTriangles[i] as List<dynamic>).cast<num>();
      if (indices.length < 3) continue;
      triangles.add(
        GlassesTriangle(
          indices[0].toInt(),
          indices[1].toInt(),
          indices[2].toInt(),
          i < triangleMaterials.length ? triangleMaterials[i].toInt() : 0,
        ),
      );
    }

    final rawMaterials =
        (json['material_groups'] ?? json['materials']) as List<dynamic>? ??
        const [];
    final materials = rawMaterials
        .map((dynamic raw) {
          final map = (raw as Map).cast<String, dynamic>();
          final rgba =
              (map['base_color_rgba'] ?? map['color_rgba'] ?? map['color'])
                  as List<dynamic>? ??
              const <num>[0.08, 0.08, 0.10, 1];
          int channel(int index) {
            final value = index < rgba.length
                ? (rgba[index] as num).toDouble()
                : 1;
            return ((value <= 1 ? value * 255 : value).round()).clamp(0, 255);
          }

          return GlassesMaterial(
            name: (map['name'] as String?) ?? 'material',
            color: Color.fromARGB(
              channel(3),
              channel(0),
              channel(1),
              channel(2),
            ),
          );
        })
        .toList(growable: false);
    final usableMaterials = materials.isEmpty
        ? const <GlassesMaterial>[
            GlassesMaterial(name: 'frame', color: Color(0xFF17191E)),
          ]
        : materials;
    final nominal =
        (json['runtime_nominal_eye_distance'] as num?) ??
        (json['nominal_eye_distance'] as num?) ??
        1;
    return GlassesRuntimeMesh(
      vertices: vertices,
      triangles: triangles,
      materials: usableMaterials,
      nominalEyeDistance: nominal.toDouble(),
    );
  }
}

class GlassesMeshRepository {
  GlassesMeshRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  Future<GlassesRuntimeMesh?>? _pending;

  Future<GlassesRuntimeMesh?> load() => _pending ??= _load();

  Future<GlassesRuntimeMesh?> _load() async {
    Object? lastError;
    for (final path in const <String>[
      glassesRuntimeMeshAsset,
      'assets/ar/glasses/runtime_mesh.json',
    ]) {
      try {
        // loadString delegates payloads over 50KB to a helper isolate. The
        // compact runtime mesh sits right at that threshold; decoding the
        // already-small LOD2 bytes directly avoids isolate startup on lens
        // selection and remains deterministic in Flutter's test runner.
        final data = await _bundle.load(path);
        final source = utf8.decode(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final mesh = GlassesRuntimeMesh.fromJson(
          (jsonDecode(source) as Map).cast<String, dynamic>(),
        );
        if (mesh.isRenderable) return mesh;
      } catch (error) {
        lastError = error;
      }
    }
    assert(() {
      debugPrint('Glasses runtime mesh unavailable: $lastError');
      return true;
    }());
    return null;
  }
}

@immutable
class _ProjectedVertex {
  const _ProjectedVertex(this.position, this.depth);
  final Offset position;
  final double depth;
}

@immutable
class _ProjectedTriangle {
  const _ProjectedTriangle({
    required this.a,
    required this.b,
    required this.c,
    required this.depth,
    required this.color,
  });
  final Offset a;
  final Offset b;
  final Offset c;
  final double depth;
  final Color color;
}

/// CPU-projects the Blender mesh with yaw/pitch/roll and painter-sorts its
/// triangles. This is real 3D geometry projection, but deliberately avoids a
/// heavyweight scene engine. An analytic face ellipsoid hides temple geometry
/// behind the head; it cannot occlude against hair, hands, or other faces.
class GlassesMeshPainter extends CustomPainter {
  GlassesMeshPainter({
    required this.mesh,
    required this.pose,
    this.normalizedCoordinates = true,
    this.enableAnalyticFaceOcclusion = true,
  });

  final GlassesRuntimeMesh mesh;
  final GlassesPose pose;
  final bool normalizedCoordinates;
  final bool enableAnalyticFaceOcclusion;

  @override
  void paint(Canvas canvas, Size size) {
    paintMesh(
      canvas,
      size,
      mesh,
      pose,
      normalizedCoordinates: normalizedCoordinates,
      enableAnalyticFaceOcclusion: enableAnalyticFaceOcclusion,
    );
  }

  static void paintMesh(
    Canvas canvas,
    Size size,
    GlassesRuntimeMesh mesh,
    GlassesPose pose, {
    bool normalizedCoordinates = true,
    bool enableAnalyticFaceOcclusion = true,
  }) {
    if (pose.opacity <= 0 || !mesh.isRenderable) return;
    final center = normalizedCoordinates
        ? Offset(pose.center.dx * size.width, pose.center.dy * size.height)
        : pose.center;
    final eyeDistancePixels = normalizedCoordinates
        ? pose.interocularDistance * size.width
        : pose.interocularDistance;
    final scale = eyeDistancePixels / math.max(mesh.nominalEyeDistance, 0.01);
    final yawCos = math.cos(pose.yaw);
    final yawSin = math.sin(pose.yaw);
    final pitchCos = math.cos(pose.pitch);
    final pitchSin = math.sin(pose.pitch);
    final rollCos = math.cos(pose.roll);
    final rollSin = math.sin(pose.roll);
    const focalLength = 5.2;

    final projected = <_ProjectedVertex>[];
    final transformed = <GlassesVertex>[];
    for (final vertex in mesh.vertices) {
      // Mesh convention: +X subject-right, +Y up, -Z camera-facing.
      final yawX = vertex.x * yawCos + vertex.z * yawSin;
      final yawZ = -vertex.x * yawSin + vertex.z * yawCos;
      final pitchY = vertex.y * pitchCos - yawZ * pitchSin;
      final pitchZ = vertex.y * pitchSin + yawZ * pitchCos;
      transformed.add(GlassesVertex(yawX, pitchY, pitchZ));
      final perspective =
          focalLength /
          (focalLength + pitchZ).clamp(focalLength * 0.35, focalLength * 2);
      final x = yawX * perspective;
      final y = pitchY * perspective;
      projected.add(
        _ProjectedVertex(
          Offset(
            center.dx + (x * rollCos + y * rollSin) * scale,
            center.dy + (x * rollSin - y * rollCos) * scale,
          ),
          pitchZ,
        ),
      );
    }

    final drawList = <_ProjectedTriangle>[];
    for (final triangle in mesh.triangles) {
      if (triangle.a >= projected.length ||
          triangle.b >= projected.length ||
          triangle.c >= projected.length) {
        continue;
      }
      final va = transformed[triangle.a];
      final vb = transformed[triangle.b];
      final vc = transformed[triangle.c];
      final avgX = (va.x + vb.x + vc.x) / 3;
      final avgY = (va.y + vb.y + vc.y) / 3;
      final avgZ = (va.z + vb.z + vc.z) / 3;
      if (enableAnalyticFaceOcclusion &&
          _behindApproximateFace(avgX, avgY, avgZ)) {
        continue;
      }
      final pa = projected[triangle.a];
      final pb = projected[triangle.b];
      final pc = projected[triangle.c];
      final material =
          mesh.materials[triangle.materialIndex.clamp(
            0,
            mesh.materials.length - 1,
          )];
      final edgeA = vb.x - va.x;
      final edgeAy = vb.y - va.y;
      final edgeAz = vb.z - va.z;
      final edgeB = vc.x - va.x;
      final edgeBy = vc.y - va.y;
      final edgeBz = vc.z - va.z;
      final normalZ = edgeA * edgeBy - edgeAy * edgeB;
      final normalLength = math.sqrt(
        math.pow(edgeAy * edgeBz - edgeAz * edgeBy, 2) +
            math.pow(edgeAz * edgeB - edgeA * edgeBz, 2) +
            normalZ * normalZ,
      );
      final facing = normalLength <= 0.00001
          ? 0.65
          : (normalZ.abs() / normalLength).clamp(0.0, 1.0);
      final light = 0.58 + facing * 0.42;
      final base = material.color;
      final color = Color.fromARGB(
        (base.a * 255 * pose.opacity).round().clamp(0, 255),
        (base.r * 255 * light).round().clamp(0, 255),
        (base.g * 255 * light).round().clamp(0, 255),
        (base.b * 255 * light).round().clamp(0, 255),
      );
      drawList.add(
        _ProjectedTriangle(
          a: pa.position,
          b: pb.position,
          c: pc.position,
          depth: (pa.depth + pb.depth + pc.depth) / 3,
          color: color,
        ),
      );
    }
    // Positive Z is farther from camera: paint far geometry first.
    drawList.sort((a, b) => b.depth.compareTo(a.depth));
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    for (final triangle in drawList) {
      paint.color = triangle.color;
      canvas.drawPath(
        Path()
          ..moveTo(triangle.a.dx, triangle.a.dy)
          ..lineTo(triangle.b.dx, triangle.b.dy)
          ..lineTo(triangle.c.dx, triangle.c.dy)
          ..close(),
        paint,
      );
    }
  }

  static bool _behindApproximateFace(double x, double y, double z) {
    const radiusX = 1.24;
    const radiusY = 1.62;
    const centerY = -0.64;
    final nx = x / radiusX;
    final ny = (y - centerY) / radiusY;
    final radial = nx * nx + ny * ny;
    if (radial >= 1) return false;
    final frontSurface = -0.06 - 0.22 * math.sqrt(1 - radial);
    return z > frontSurface;
  }

  @override
  bool shouldRepaint(covariant GlassesMeshPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.pose != pose ||
      oldDelegate.normalizedCoordinates != normalizedCoordinates ||
      oldDelegate.enableAnalyticFaceOcclusion != enableAnalyticFaceOcclusion;
}

/// Live face-lens surface. The detector coordinates already include crop,
/// rotation and selfie mirroring, so this widget never mirrors them again.
class GlassesLensOverlay extends StatefulWidget {
  const GlassesLensOverlay({
    super.key,
    required this.trackingState,
    this.repository,
    this.preloadedMesh,
    this.preferMesh = true,
    this.semanticLabel = 'Face-tracked glasses',
  });

  final ValueListenable<FaceArTrackingState> trackingState;
  final GlassesMeshRepository? repository;
  final GlassesRuntimeMesh? preloadedMesh;
  final bool preferMesh;
  final String semanticLabel;

  @override
  State<GlassesLensOverlay> createState() => _GlassesLensOverlayState();
}

class _GlassesLensOverlayState extends State<GlassesLensOverlay>
    with SingleTickerProviderStateMixin {
  final GlassesPoseTracker _tracker = GlassesPoseTracker();
  late final Ticker _ticker;
  late GlassesMeshRepository _repository;
  GlassesRuntimeMesh? _mesh;
  GlassesPose? _pose;
  Duration _lastPaintTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? GlassesMeshRepository();
    _mesh = widget.preloadedMesh;
    widget.trackingState.addListener(_trackingChanged);
    _ticker = createTicker(_onTick);
    _loadMesh();
    _trackingChanged();
  }

  Future<void> _loadMesh() async {
    if (_mesh != null || !widget.preferMesh) return;
    final mesh = await _repository.load();
    if (!mounted) return;
    setState(() => _mesh = mesh);
  }

  void _trackingChanged() {
    final state = widget.trackingState.value;
    final pose = _tracker.update(state.primary, state.timestamp);
    if (!mounted) return;
    setState(() => _pose = pose);
    if (pose != null && !_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    // 30fps is visually stable with 15fps landmarks and halves UI-thread work.
    if (elapsed - _lastPaintTick < const Duration(milliseconds: 30)) return;
    _lastPaintTick = elapsed;
    final pose = _tracker.poseAt(DateTime.now());
    if (!mounted) return;
    if (pose == null) _ticker.stop();
    setState(() => _pose = pose);
  }

  @override
  void didUpdateWidget(covariant GlassesLensOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackingState != widget.trackingState) {
      oldWidget.trackingState.removeListener(_trackingChanged);
      _tracker.reset();
      widget.trackingState.addListener(_trackingChanged);
      _trackingChanged();
    }
    if (oldWidget.preloadedMesh != widget.preloadedMesh &&
        widget.preloadedMesh != null) {
      _mesh = widget.preloadedMesh;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pose = _pose;
    if (pose == null || pose.opacity <= 0.001) {
      return const SizedBox.expand(
        key: ValueKey<String>('glasses-lens-no-face'),
      );
    }
    final mesh = _mesh;
    if (widget.preferMesh &&
        mesh != null &&
        mesh.triangles.length <= glassesLiveTriangleBudget) {
      return Semantics(
        image: true,
        label: widget.semanticLabel,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              key: const ValueKey<String>('glasses-lens-mesh'),
              painter: GlassesMeshPainter(mesh: mesh, pose: pose),
              size: Size.infinite,
            ),
          ),
        ),
      );
    }
    return Semantics(
      image: true,
      label: widget.semanticLabel,
      child: IgnorePointer(child: _GlassesFlatFallback(pose: pose)),
    );
  }

  @override
  void dispose() {
    widget.trackingState.removeListener(_trackingChanged);
    _ticker.dispose();
    super.dispose();
  }
}

class _GlassesFlatFallback extends StatelessWidget {
  const _GlassesFlatFallback({required this.pose});
  final GlassesPose pose;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
      final width = pose.interocularDistance * size.width * 2.18;
      final height = width * 0.40;
      return Stack(
        key: const ValueKey<String>('glasses-lens-flat-fallback'),
        children: <Widget>[
          Positioned(
            left: pose.center.dx * size.width - width / 2,
            top: pose.center.dy * size.height - height * 0.48,
            width: width,
            height: height,
            child: Opacity(
              opacity: pose.opacity,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(pose.pitch * 0.55)
                  ..rotateY(-pose.yaw * 0.72)
                  ..rotateZ(pose.roll),
                child: Image.asset(
                  glassesFallbackImageAsset,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      CustomPaint(painter: _VectorGlassesFallbackPainter()),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _VectorGlassesFallbackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF15171C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.5, size.height * 0.11)
      ..strokeCap = StrokeCap.round;
    final lensWidth = size.width * 0.34;
    final lensHeight = size.height * 0.60;
    final top = size.height * 0.18;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.10, top, lensWidth, lensHeight),
        Radius.circular(size.height * 0.18),
      ),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.56, top, lensWidth, lensHeight),
        Radius.circular(size.height * 0.18),
      ),
      stroke,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.43,
        size.height * 0.34,
        size.width * 0.14,
        size.height * 0.25,
      ),
      math.pi,
      math.pi,
      false,
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
