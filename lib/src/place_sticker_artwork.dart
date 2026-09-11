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
}) async {
  await initializeDateFormatting(language);
  final size = placeStickerSize(style);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PlaceStickerPainter(
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
  });
  final String style, name, language;
  final int variant;
  final DateTime date;
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
    final ink = [
      const Color(0xff184b42),
      const Color(0xff204d82),
      const Color(0xffad3b43),
    ][v];
    final paper = [
      const Color(0xfffff9e9),
      const Color(0xfff0f7fb),
      const Color(0xfffff3ed),
    ][v];
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
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    text(
      c,
      t('PLACES / COLLECTED', 'أماكن · ذكريات'),
      const Rect.fromLTWH(42, 38, 256, 27),
      15,
      ink,
      spacing: 2,
    );
    final art = const Rect.fromLTWH(43, 80, 254, 188);
    c.save();
    c.clipRect(art);
    c.drawRect(art, Paint()..color = ink.withValues(alpha: .09));
    if (v == 0) {
      c.drawCircle(
        const Offset(225, 127),
        30,
        Paint()..color = const Color(0xffed9953),
      );
      for (var i = 0; i < 4; i++) {
        final p = Path()
          ..moveTo(43, 200 + i * 19)
          ..cubicTo(125, 120 + i * 25, 205, 265 - i * 8, 297, 168 + i * 21)
          ..lineTo(297, 268)
          ..lineTo(43, 268)
          ..close();
        c.drawPath(p, Paint()..color = ink.withValues(alpha: .20 + i * .17));
      }
    } else if (v == 1) {
      // Engraved compass rose with a fine latitude grid.
      for (var i = 0; i < 5; i++) {
        c.drawOval(
          Rect.fromCenter(
            center: const Offset(170, 173),
            width: 185 - i * 32,
            height: 157,
          ),
          Paint()
            ..color = ink.withValues(alpha: .20)
            ..style = PaintingStyle.stroke,
        );
      }
      for (var i = 0; i < 8; i++) {
        c.save();
        c.translate(170, 173);
        c.rotate(i * math.pi / 4);
        c.drawPath(
          Path()
            ..moveTo(0, -70)
            ..lineTo(11, 0)
            ..lineTo(0, 18)
            ..lineTo(-11, 0)
            ..close(),
          Paint()..color = ink.withValues(alpha: i.isEven ? .9 : .35),
        );
        c.restore();
      }
      c.drawCircle(const Offset(170, 173), 8, Paint()..color = paper);
    } else {
      // Botanical engraving; no generic date banner.
      for (var i = 0; i < 5; i++) {
        c.save();
        c.translate(170, 240);
        c.rotate((i - 2) * .32);
        line(c, Offset.zero, const Offset(0, -138), ink, 2);
        for (var j = 0; j < 4; j++) {
          final y = -28.0 - j * 28;
          final p = Path()
            ..moveTo(0, y)
            ..quadraticBezierTo(-50, y - 26, -29, y - 43)
            ..quadraticBezierTo(-4, y - 39, 0, y);
          c.drawPath(p, Paint()..color = ink.withValues(alpha: .8));
          c.save();
          c.scale(-1, 1);
          c.drawPath(p, Paint()..color = ink.withValues(alpha: .55));
          c.restore();
        }
        c.restore();
      }
    }
    c.restore();
    text(c, name, const Rect.fromLTWH(42, 282, 256, 46), 36, ink, serif: true);
    text(c, day, const Rect.fromLTWH(42, 333, 256, 25), 16, ink, spacing: 1);
    // Small cancellation mark makes this read as postage rather than a card.
    c.save();
    c.translate(278, 274);
    c.rotate(-.25);
    c.drawCircle(
      Offset.zero,
      27,
      Paint()
        ..color = ink.withValues(alpha: .65)
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
      Paint()..color = ink,
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
    final ink = dark ? const Color(0xffe5f9ef) : const Color(0xff203842);
    final paper = [
      const Color(0xfffffaf1),
      const Color(0xff153e3a),
      const Color(0xffe9f4fc),
    ][v];
    final accent = [
      const Color(0xffe16d42),
      const Color(0xffb4e2ba),
      const Color(0xff2863a5),
    ][v];
    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(8, 8, 664, 224),
      const Radius.circular(18),
    );
    final path = Path()..addRRect(rect);
    final cuts = Path()
      ..addOval(Rect.fromCircle(center: const Offset(502, 8), radius: 12))
      ..addOval(Rect.fromCircle(center: const Offset(502, 232), radius: 12));
    final shape = Path.combine(PathOperation.difference, path, cuts);
    c.drawShadow(shape, Colors.black45, 3, false);
    c.drawPath(shape, Paint()..color = paper);
    c.save();
    c.clipPath(shape);
    if (v == 2) {
      for (var i = 0; i < 9; i++) {
        line(
          c,
          Offset(20 + i * 72.0, 8),
          Offset(-100 + i * 72.0, 232),
          accent.withValues(alpha: .06),
          25,
        );
      }
    }
    rr(c, const Rect.fromLTWH(26, 27, 32, 32), 16, accent);
    plane(c, const Offset(42, 42), dark ? paper : Colors.white, .38);
    text(
      c,
      t('BOARDING PASS', 'بطاقة صعود'),
      const Rect.fromLTWH(72, 26, 400, 30),
      20,
      ink,
      align: ar ? TextAlign.right : TextAlign.left,
      spacing: 3,
    );
    text(
      c,
      t('DESTINATION', 'الوجهة'),
      const Rect.fromLTWH(32, 76, 435, 22),
      13,
      accent,
      align: ar ? TextAlign.right : TextAlign.left,
      spacing: 2,
    );
    text(
      c,
      name,
      const Rect.fromLTWH(32, 99, 435, 56),
      42,
      ink,
      align: ar ? TextAlign.right : TextAlign.left,
      weight: FontWeight.w800,
    );
    line(
      c,
      const Offset(32, 171),
      const Offset(474, 171),
      ink.withValues(alpha: .18),
    );
    text(
      c,
      day,
      const Rect.fromLTWH(32, 182, 220, 24),
      17,
      ink,
      align: TextAlign.left,
    );
    text(
      c,
      t('TRAVEL JOURNAL', 'ذكريات السفر'),
      const Rect.fromLTWH(270, 182, 203, 24),
      12,
      ink,
      align: TextAlign.right,
      spacing: 1.5,
    );
    for (double y = 27; y < 220; y += 12) {
      line(c, Offset(502, y), Offset(502, y + 5), ink.withValues(alpha: .3));
    }
    plane(c, const Offset(584, 66), accent, .9);
    text(
      c,
      t('EXPLORE', 'استكشف'),
      const Rect.fromLTWH(518, 105, 132, 28),
      15,
      ink,
      spacing: 2,
    );
    // Decorative boarding-pass stripes, intentionally not a fake scannable code.
    for (var i = 0; i < 28; i++) {
      c.drawRect(
        Rect.fromLTWH(529 + i * 4.0, 151, i % 3 == 0 ? 2.8 : 1.2, 39),
        Paint()..color = ink,
      );
    }
    text(
      c,
      date.day.toString().padLeft(2, '0'),
      const Rect.fromLTWH(524, 199, 120, 18),
      12,
      ink,
    );
    c.restore();
  }

  void _pin(Canvas c) {
    final v = variant % 3;
    final dark = v == 1;
    final ink = dark ? Colors.white : const Color(0xff192c35);
    final paper = dark
        ? const Color(0xee192c35)
        : (v == 2 ? const Color(0xffdff0cf) : const Color(0xfffaf8f2));
    final shape = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, 12, 494, 96),
          Radius.circular(v == 2 ? 12 : 48),
        ),
      );
    c.drawShadow(shape, Colors.black38, 3, false);
    c.drawPath(shape, Paint()..color = paper);
    final x = ar ? 451.0 : 58.0;
    final p = Path()
      ..moveTo(x, 85)
      ..cubicTo(x - 8, 74, x - 23, 62, x - 23, 48)
      ..cubicTo(x - 23, 17, x + 23, 17, x + 23, 48)
      ..cubicTo(x + 23, 62, x + 8, 74, x, 85)
      ..close();
    c.drawPath(p, Paint()..color = v == 0 ? const Color(0xffd75448) : ink);
    c.drawCircle(Offset(x, 47), 8, Paint()..color = paper);
    text(
      c,
      name,
      Rect.fromLTWH(ar ? 32 : 99, 29, 378, 62),
      33,
      ink,
      align: ar ? TextAlign.right : TextAlign.left,
      weight: FontWeight.w700,
    );
  }

  @override
  bool shouldRepaint(covariant PlaceStickerPainter old) =>
      old.style != style ||
      old.name != name ||
      old.variant != variant ||
      old.language != language ||
      old.date != date;
}
