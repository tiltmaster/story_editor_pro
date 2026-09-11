import 'place_art.dart';
import 'place_identity.dart';
import 'place_sticker_geometry.dart';
export 'place_sticker_geometry.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:intl/date_symbol_data_local.dart';

/// A single authored image is composited natively into preview, photos and video.
/// Dimensions are camera design units (1080 x 1920), not screen pixels.
Future<Uint8List> renderPlaceSticker({
  required String style,
  required String name,
  required int variant,
  required String language,
  DateTime? date,
  CameraPlaceIdentity identity = const CameraPlaceIdentity(),
}) async {
  await initializeDateFormatting(language);
  final size = placeStickerSize(style);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PlaceStickerPainter(
    identity: identity,
    style: style,
    name: name,
    variant: variant,
    language: language,
    date: date ?? DateTime.now(),
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Could not render location sticker');
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class PlaceStickerPainter extends CustomPainter {
  const PlaceStickerPainter({
    required this.style,
    required this.name,
    required this.variant,
    required this.language,
    required this.date,
    this.identity = const CameraPlaceIdentity(),
  });
  final String style, name, language;
  final int variant;
  final DateTime date;
  final CameraPlaceIdentity identity;
  PlaceArt get art => PlaceArt(name, identity);
  bool get ar => language == 'ar';
  String t(String en, String arabic) => ar ? arabic : en;

  @override
  void paint(Canvas c, Size size) {
    final design = placeStickerSize(style);
    c.save();
    c.scale(size.width / design.width, size.height / design.height);
    if (style == 'postcard') {
      _stamp(c);
    } else if (style == 'stamp') {
      _ticket(c);
    } else {
      _pin(c);
    }
    c.restore();
  }

  void text(
    Canvas c,
    String value,
    Rect box,
    double size,
    Color color, {
    FontWeight weight = FontWeight.w600,
    bool serif = false,
    TextAlign align = TextAlign.center,
    double spacing = 0,
  }) {
    final p = TextPainter(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    );
    TextSpan span(double s) => TextSpan(
      text: value,
      style: TextStyle(
        color: color,
        fontSize: s,
        fontWeight: weight,
        fontFamily: serif && !ar ? 'Georgia' : 'sans-serif',
        fontFamilyFallback: serif && !ar ? const ['serif'] : null,
        letterSpacing: ar ? 0 : spacing,
        height: 1.2,
      ),
    );
    p.text = span(size);
    p.layout();
    p.text = span(size * math.min(1, box.width / math.max(1, p.width)));
    p.layout(minWidth: box.width, maxWidth: box.width);
    p.paint(c, Offset(box.left, box.center.dy - p.height / 2));
    p.dispose();
  }

  void rr(Canvas c, Rect rect, double radius, Color color) => c.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(radius)),
    Paint()..color = color,
  );
  void line(Canvas c, Offset a, Offset b, Color color, [double width = 2]) =>
      c.drawLine(
        a,
        b,
        Paint()
          ..color = color
          ..strokeWidth = width,
      );
  String get day => DateFormat('dd MMM yyyy', ar ? 'ar' : 'en').format(date);

  void _stamp(Canvas c) {
    final v = variant % 3;
    final ink = art.ink;
    final paper = v == 1 ? art.ink : art.paper;
    final lettering = v == 1 ? art.paper : ink;
    // Perforations cut real transparent holes into the paper, never black dots.
    final edge = Path()..addRect(const Rect.fromLTWH(12, 12, 316, 386));
    final holes = Path();
    for (double x = 24; x < 328; x += 22) {
      holes.addOval(Rect.fromCircle(center: Offset(x, 12), radius: 6));
      holes.addOval(Rect.fromCircle(center: Offset(x, 398), radius: 6));
    }
    for (double y = 24; y < 398; y += 22) {
      holes.addOval(Rect.fromCircle(center: Offset(12, y), radius: 6));
      holes.addOval(Rect.fromCircle(center: Offset(328, y), radius: 6));
    }
    final outline = Path.combine(PathOperation.difference, edge, holes);
    c.drawShadow(outline, Colors.black54, 3, false);
    c.drawPath(outline, Paint()..color = paper);
    c.drawRect(
      const Rect.fromLTWH(29, 29, 282, 352),
      Paint()
        ..color = lettering.withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    text(
      c,
      t('PLACES / COLLECTED', 'أماكن · ذكريات'),
      const Rect.fromLTWH(42, 38, 256, 27),
      15,
      lettering,
      spacing: 2,
    );
    final scene = const Rect.fromLTWH(43, 80, 254, 188);
    if (v == 1) {
      c.save();
      c.clipPath(Path()..addOval(const Rect.fromLTWH(77, 75, 186, 194)));
      art.paint(c, const Rect.fromLTWH(77, 75, 186, 194), treatment: 1);
      c.restore();
      c.drawOval(
        const Rect.fromLTWH(70, 68, 200, 208),
        Paint()
          ..color = lettering.withValues(alpha: .5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    } else if (v == 2) {
      // An engraved monochrome issue, distinct from the scenic color stamp.
      art.paint(c, scene, backdrop: false);
      for (double y = 90; y < 260; y += 12) {
        line(c, Offset(43, y), Offset(58, y), ink.withValues(alpha: .25), .7);
        line(c, Offset(283, y), Offset(297, y), ink.withValues(alpha: .25), .7);
      }
      line(c, const Offset(43, 274), const Offset(297, 274), ink, .8);
    } else {
      art.paint(c, scene);
    }
    text(
      c,
      name,
      const Rect.fromLTWH(42, 288, 256, 43),
      34,
      lettering,
      serif: true,
    );
    text(
      c,
      day,
      const Rect.fromLTWH(42, 337, 256, 25),
      16,
      lettering,
      spacing: 1,
    );
    // Small cancellation mark makes this read as postage rather than a card.
    c.save();
    c.translate(278, 274);
    c.rotate(-.25);
    c.drawCircle(
      Offset.zero,
      27,
      Paint()
        ..color = lettering.withValues(alpha: .65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    c.drawPath(
      Path()
        ..moveTo(0, -13)
        ..lineTo(4, -4)
        ..lineTo(13, 0)
        ..lineTo(4, 4)
        ..lineTo(0, 13)
        ..lineTo(-4, 4)
        ..lineTo(-13, 0)
        ..lineTo(-4, -4)
        ..close(),
      Paint()..color = lettering,
    );
    c.restore();
  }

  void plane(Canvas c, Offset at, Color color, [double scale = 1]) {
    c.save();
    c.translate(at.dx, at.dy);
    c.scale(scale);
    final p = Path()
      ..moveTo(0, -25)
      ..quadraticBezierTo(4, -29, 5, -20)
      ..lineTo(7, -7)
      ..lineTo(27, 9)
      ..lineTo(27, 14)
      ..lineTo(6, 6)
      ..lineTo(5, 20)
      ..lineTo(12, 26)
      ..lineTo(12, 29)
      ..lineTo(0, 25)
      ..lineTo(-12, 29)
      ..lineTo(-12, 26)
      ..lineTo(-5, 20)
      ..lineTo(-6, 6)
      ..lineTo(-27, 14)
      ..lineTo(-27, 9)
      ..lineTo(-7, -7)
      ..lineTo(-5, -20)
      ..quadraticBezierTo(-4, -29, 0, -25)
      ..close();
    c.drawPath(p, Paint()..color = color);
    c.restore();
  }

  void _ticket(Canvas c) {
    final v = variant % 3;
    final dark = v == 1;
    final ink = dark ? art.paper : art.ink;
    final paper = dark ? art.ink : art.paper;
    final accent = art.accent;
    final divider = v == 2 ? 176.0 : 526.0;
    final shape = Path.combine(
      PathOperation.difference,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, 8, 664, 224),
          const Radius.circular(16),
        ),
      ),
      Path()
        ..addOval(Rect.fromCircle(center: Offset(divider, 8), radius: 12))
        ..addOval(Rect.fromCircle(center: Offset(divider, 232), radius: 12)),
    );
    c.drawShadow(shape, Colors.black45, 3, false);
    c.drawPath(shape, Paint()..color = paper);
    c.save();
    c.clipPath(shape);
    final align = ar ? TextAlign.right : TextAlign.left;
    if (v == 0) {
      // Destination poster with a genuine tear-off silhouette.
      art.paint(c, const Rect.fromLTWH(8, 8, 184, 224));
      text(
        c,
        t('BOARDING PASS', 'بطاقة صعود'),
        const Rect.fromLTWH(211, 28, 295, 24),
        15,
        ink,
        align: align,
        spacing: 2,
      );
      text(
        c,
        t('DESTINATION', 'الوجهة'),
        const Rect.fromLTWH(211, 81, 295, 20),
        12,
        accent,
        align: align,
        spacing: 2,
      );
      text(
        c,
        name,
        const Rect.fromLTWH(211, 106, 295, 50),
        36,
        ink,
        align: align,
        weight: FontWeight.w800,
      );
      line(
        c,
        const Offset(211, 175),
        const Offset(505, 175),
        ink.withValues(alpha: .2),
        1,
      );
      text(
        c,
        day,
        const Rect.fromLTWH(211, 188, 295, 21),
        16,
        ink,
        align: align,
      );
    } else if (v == 1) {
      // Night-departure edition: wide illustrated horizon, light typography.
      art.paint(
        c,
        const Rect.fromLTWH(283, 64, 233, 157),
        backdrop: false,
        foreground: accent,
      );
      text(
        c,
        t('BOARDING / MEMORIES', 'رحلة · ذكريات'),
        const Rect.fromLTWH(30, 27, 476, 25),
        15,
        ink,
        align: align,
        spacing: 2,
      );
      text(
        c,
        name,
        const Rect.fromLTWH(30, 76, 265, 57),
        37,
        ink,
        serif: true,
        align: align,
      );
      text(
        c,
        day,
        const Rect.fromLTWH(30, 150, 244, 24),
        16,
        ink.withValues(alpha: .8),
        align: align,
      );
      line(c, const Offset(30, 196), const Offset(237, 196), accent, 1);
      for (double x = 33; x < 240; x += 13) {
        c.drawCircle(Offset(x, 196), 1.8, Paint()..color = accent);
      }
    } else {
      // Airmail luggage ticket: illustrated stub and a quiet journal body.
      for (var i = 0; i < 16; i++) {
        c.drawPath(
          Path()
            ..moveTo(i * 49.0, 8)
            ..lineTo(i * 49.0 + 20, 8)
            ..lineTo(i * 49.0 + 5, 18)
            ..lineTo(i * 49.0 - 15, 18)
            ..close(),
          Paint()..color = i.isEven ? accent : ink.withValues(alpha: .5),
        );
        c.drawPath(
          Path()
            ..moveTo(i * 49.0, 232)
            ..lineTo(i * 49.0 + 20, 232)
            ..lineTo(i * 49.0 + 35, 222)
            ..lineTo(i * 49.0 + 15, 222)
            ..close(),
          Paint()..color = i.isEven ? accent : ink.withValues(alpha: .5),
        );
      }
      c.save();
      c.clipPath(Path()..addOval(const Rect.fromLTWH(25, 41, 134, 134)));
      art.paint(c, const Rect.fromLTWH(25, 41, 134, 134), treatment: 1);
      c.restore();
      text(
        c,
        t('EXPLORE', 'استكشف'),
        const Rect.fromLTWH(24, 186, 136, 22),
        13,
        ink,
        spacing: 2,
      );
      text(
        c,
        t('BOARDING PASS', 'بطاقة صعود'),
        const Rect.fromLTWH(205, 35, 430, 25),
        15,
        ink,
        align: align,
        spacing: 3,
      );
      text(
        c,
        name,
        const Rect.fromLTWH(205, 82, 430, 59),
        42,
        ink,
        serif: true,
        align: align,
      );
      text(
        c,
        day,
        const Rect.fromLTWH(205, 169, 290, 23),
        17,
        ink,
        align: align,
      );
      plane(c, const Offset(607, 179), accent, .65);
    }
    for (double y = 28; y < 217; y += 12) {
      line(
        c,
        Offset(divider, y),
        Offset(divider, y + 5),
        ink.withValues(alpha: .3),
        1,
      );
    }
    if (v != 2) {
      plane(c, const Offset(596, 56), dark ? accent : ink, .65);
      text(
        c,
        t('EXPLORE', 'استكشف'),
        const Rect.fromLTWH(541, 99, 112, 23),
        13,
        ink,
        spacing: 1.5,
      );
      for (var i = 0; i < 25; i++) {
        c.drawRect(
          Rect.fromLTWH(546 + i * 4.0, 143, i % 3 == 0 ? 2.5 : 1, 36),
          Paint()..color = ink,
        );
      }
      text(
        c,
        t('TRAVEL JOURNAL', 'ذكريات السفر'),
        const Rect.fromLTWH(539, 194, 117, 18),
        10,
        ink,
      );
    }
    c.restore();
  }

  void _pin(Canvas c) {
    final v = variant % 3;
    final dark = v == 1;
    final ink = dark ? art.paper : art.ink;
    final paper = dark ? art.ink : art.paper;
    final iconX = ar ? 380.0 : 14.0;
    final labelX = ar ? 28.0 : 145.0;
    final shape = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, 17, 494, 126),
          Radius.circular(v == 2 ? 18 : 63),
        ),
      );
    c.drawShadow(shape, Colors.black38, 3, false);
    c.drawPath(shape, Paint()..color = paper);
    c.save();
    c.clipPath(
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(iconX, 23, 116, 114),
          Radius.circular(v == 2 ? 12 : 57),
        ),
      ),
    );
    art.paint(c, Rect.fromLTWH(iconX, 23, 116, 114), treatment: v == 2 ? 1 : 0);
    c.restore();
    text(
      c,
      name,
      Rect.fromLTWH(labelX, 51, 337, 49),
      33,
      ink,
      align: ar ? TextAlign.right : TextAlign.left,
      weight: FontWeight.w700,
      serif: v == 2,
    );
    // Small regional color signature instead of a large editorial banner.
    for (var i = 0; i < 3; i++) {
      rr(
        c,
        Rect.fromLTWH(ar ? labelX + 311 - i * 13 : labelX + i * 13, 113, 8, 3),
        1.5,
        art.accent.withValues(alpha: 1 - i * .25),
      );
    }
  }

  @override
  bool shouldRepaint(covariant PlaceStickerPainter old) =>
      old.identity != identity ||
      old.style != style ||
      old.name != name ||
      old.variant != variant ||
      old.language != language ||
      old.date != date;
}
