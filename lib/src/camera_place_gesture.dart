import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'camera_effects.dart';
import 'place_sticker_artwork.dart';

/// Hit target lives in the same upright, cover-fitted viewport as native art.
/// It does not mirror with the selfie image: native lettering is compensated.
class CameraPlaceGesture extends StatefulWidget {
  const CameraPlaceGesture({
    super.key,
    required this.effects,
    required this.onChanged,
    required this.onCycle,
  });
  final CameraEffects effects;
  final ValueChanged<CameraEffects> onChanged;
  final VoidCallback onCycle;
  @override
  State<CameraPlaceGesture> createState() => _CameraPlaceGestureState();
}

class _CameraPlaceGestureState extends State<CameraPlaceGesture> {
  Offset _start = Offset.zero;
  late CameraEffects _initial;
  bool _dragging = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final e = widget.effects;
      final unit = math.min(box.maxWidth / 1080, box.maxHeight / 1920);
      final art = placeStickerSize(e.placeStyle) * (unit * e.placeScale);
      final rtl = Directionality.of(context) == TextDirection.rtl;
      Offset local(Offset global) =>
          (context.findRenderObject()! as RenderBox).globalToLocal(global);
      return Stack(
        children: [
          Positioned(
            left: e.placeX * box.maxWidth - art.width / 2,
            top: e.placeY * box.maxHeight - art.height / 2,
            width: art.width,
            height: art.height,
            child: Transform.rotate(
              angle: e.placeRotation,
              child: Semantics(
                label:
                    '${e.placeName}. ${rtl ? 'اضغط لتغيير النمط، اسحب للتحريك، ضم إصبعين لتغيير الحجم ولفهما للتدوير' : 'Tap to change style, drag to move, pinch to resize, twist two fingers to rotate'}',
                button: true,
                child: GestureDetector(
                  key: const ValueKey('camera-place-sticker'),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onCycle,
                  onScaleStart: (d) {
                    _start = local(d.focalPoint);
                    _initial = e;
                    setState(() => _dragging = true);
                  },
                  onScaleUpdate: (d) {
                    final delta = local(d.focalPoint) - _start;
                    widget.onChanged(
                      e.copyWith(
                        placeScale: _initial.placeScale * d.scale,
                        placeRotation: _initial.placeRotation + d.rotation,
                        placeX: _initial.placeX + delta.dx / box.maxWidth,
                        placeY: _initial.placeY + delta.dy / box.maxHeight,
                      ),
                    );
                  },
                  onScaleEnd: (_) => setState(() => _dragging = false),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: _dragging
                          ? Border.all(color: Colors.white70)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
