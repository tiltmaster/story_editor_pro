import 'dart:math' as math;
import 'dart:ui';

/// Artwork dimensions within an upright 1080 x 1920 camera frame.
Size placeStickerSize(String style) => switch (style) {
  'postcard' => const Size(340, 410),
  'stamp' => const Size(680, 240),
  _ => const Size(510, 120),
};

double placeStickerMaxScale(String style) =>
    math.min(1.6, 1040 / placeStickerSize(style).width);
