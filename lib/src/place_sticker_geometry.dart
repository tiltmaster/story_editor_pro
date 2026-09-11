import 'dart:math' as math;
import 'dart:ui';

/// Artwork dimensions within an upright 1080 x 1920 camera frame.
Size placeStickerSize(String style) => switch (style) {
  'postcard' => const Size(340, 410),
  'stamp' => const Size(680, 240),
  _ => const Size(510, 160),
};

/// Axis-aligned bounds after rotating around the sticker center.
Size rotatedPlaceStickerSize(String style, double angle) {
  final size = placeStickerSize(style);
  final c = math.cos(angle).abs(), s = math.sin(angle).abs();
  return Size(
    size.width * c + size.height * s,
    size.width * s + size.height * c,
  );
}

double placeStickerMaxScale(String style, [double rotation = 0]) {
  final size = rotatedPlaceStickerSize(style, rotation);
  return math.min(1.6, math.min(1040 / size.width, 1860 / size.height));
}
