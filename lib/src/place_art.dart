import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'place_identity.dart';

/// Original vector illustrations: no downloads, network lookup or camera stall.
class PlaceArt {
  PlaceArt(String name, CameraPlaceIdentity identity)
    : motif = resolvePlaceMotif(name, identity);
  final PlaceMotif motif;
  Color get ink => switch (motif) {
    PlaceMotif.redFort || PlaceMotif.desert => const Color(0xff713e32),
    PlaceMotif.eiffel || PlaceMotif.cafe => const Color(0xff443446),
    PlaceMotif.park || PlaceMotif.market => const Color(0xff204e43),
    _ => const Color(0xff163f58),
  };
  Color get accent => switch (motif) {
    PlaceMotif.redFort || PlaceMotif.desert => const Color(0xffd98255),
    PlaceMotif.eiffel || PlaceMotif.cafe => const Color(0xffd593a0),
    PlaceMotif.park || PlaceMotif.market => const Color(0xff8eab6a),
    _ => const Color(0xff50a9b6),
  };
  Color get paper => Color.lerp(const Color(0xfffffcf2), accent, .10)!;
  IconData get icon => switch (motif) {
    PlaceMotif.cafe => Icons.local_cafe_outlined,
    PlaceMotif.coast => Icons.waves_rounded,
    PlaceMotif.park => Icons.park_outlined,
    PlaceMotif.mountain => Icons.landscape_outlined,
    PlaceMotif.museum => Icons.museum_outlined,
    PlaceMotif.market => Icons.storefront_outlined,
    PlaceMotif.airport => Icons.flight_rounded,
    PlaceMotif.desert => Icons.wb_sunny_outlined,
    PlaceMotif.neighborhood => Icons.map_outlined,
    _ => Icons.location_city_rounded,
  };

  /// Coordinates stay upright even in an Arabic layout; only label flow changes.
  void paint(
    Canvas c,
    Rect rect, {
    int treatment = 0,
    bool backdrop = true,
    Color? foreground,
  }) {
    c.save();
    c.clipRect(rect);
    c.translate(rect.left, rect.top);
    c.scale(rect.width / 100, rect.height / 100);
    final color = foreground ?? ink;
    final light = foreground == null
        ? accent
        : foreground.withValues(alpha: .5);
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void path(
      List<Offset> points, {
      Color? tint,
      bool close = false,
      double width = 1.5,
    }) {
      final p = Path()..addPolygon(points, close);
      c.drawPath(
        p,
        Paint()
          ..color = tint ?? color
          ..style = close ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    void line(
      double x,
      double y,
      double x2,
      double y2, {
      Color? tint,
      double width = 1.5,
    }) => path([Offset(x, y), Offset(x2, y2)], tint: tint, width: width);
    void box(double x, double y, double w, double h, {Color? tint}) =>
        c.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = tint ?? color);
    void circle(double x, double y, double r, {Color? tint}) =>
        c.drawCircle(Offset(x, y), r, Paint()..color = tint ?? color);
    if (backdrop) {
      c.drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [paper, Color.lerp(paper, accent, .45)!],
          ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
      );
      if (treatment == 1) {
        for (double x = -100; x < 150; x += 7) {
          line(
            x,
            0,
            x + 100,
            100,
            tint: accent.withValues(alpha: .22),
            width: .45,
          );
        }
      } else {
        circle(
          77,
          22,
          12,
          tint: Color.lerp(accent, const Color(0xffffcc86), .65),
        );
        line(8, 31, 28, 31, tint: paper, width: 2);
        line(14, 27, 37, 27, tint: paper, width: 2);
      }
    }
    // Keep architectural proportions regardless of the scene's aspect ratio.
    c.save();
    final ratio = rect.width / rect.height;
    if (ratio > 1) {
      c.translate(50 - 50 / ratio, 0);
      c.scale(1 / ratio, 1);
    }
    if (ratio < 1) {
      c.translate(0, 100 - 100 * ratio);
      c.scale(1, ratio);
    }
    switch (motif) {
      case PlaceMotif.kuwaitTowers:
        path(const [
          Offset(28, 89),
          Offset(34, 16),
          Offset(40, 89),
        ], close: true);
        circle(34, 49, 11);
        circle(34, 30, 6, tint: light);
        line(24, 47, 44, 47, tint: paper, width: 1);
        path(const [
          Offset(59, 89),
          Offset(64, 25),
          Offset(69, 89),
        ], close: true);
        circle(64, 54, 9, tint: light);
        line(56, 54, 72, 54, tint: color, width: 1);
        path(const [
          Offset(79, 89),
          Offset(82, 40),
          Offset(85, 89),
        ], close: true);
        line(17, 90, 91, 90);
      case PlaceMotif.redFort:
        box(13, 49, 74, 39, tint: light);
        box(10, 42, 19, 46);
        box(71, 42, 19, 46);
        for (double x = 10; x < 29; x += 7) {
          box(x, 36, 5, 8);
        }
        for (double x = 71; x < 90; x += 7) {
          box(x, 36, 5, 8);
        }
        for (double x = 31; x < 70; x += 8) {
          box(x, 44, 5, 7, tint: light);
        }
        c.drawRRect(
          RRect.fromRectAndCorners(
            const Rect.fromLTWH(43, 63, 14, 25),
            topLeft: const Radius.circular(7),
            topRight: const Radius.circular(7),
          ),
          fill,
        );
        for (final x in [18.0, 79.0]) {
          box(x, 53, 3, 7, tint: paper);
          box(x, 68, 3, 7, tint: paper);
        }
        line(7, 90, 94, 90);
        line(13, 94, 87, 94, tint: light);
      case PlaceMotif.burj:
        path(const [
          Offset(27, 91),
          Offset(27, 77),
          Offset(34, 77),
          Offset(34, 59),
          Offset(41, 59),
          Offset(41, 39),
          Offset(46, 39),
          Offset(46, 21),
          Offset(49, 21),
          Offset(50, 4),
          Offset(52, 21),
          Offset(55, 21),
          Offset(55, 44),
          Offset(61, 44),
          Offset(61, 65),
          Offset(67, 65),
          Offset(67, 80),
          Offset(74, 80),
          Offset(74, 91),
        ], close: true);
        for (double y = 46; y < 88; y += 5) {
          line(45, y, 53, y, tint: paper.withValues(alpha: .65), width: .8);
        }
        box(8, 74, 11, 17, tint: light);
        box(80, 68, 12, 23, tint: light);
        line(3, 92, 97, 92);
      case PlaceMotif.eiffel:
        final tower = Path()
          ..moveTo(50, 13)
          ..cubicTo(48, 43, 38, 72, 24, 91)
          ..lineTo(38, 91)
          ..quadraticBezierTo(50, 61, 62, 91)
          ..lineTo(76, 91)
          ..cubicTo(62, 72, 52, 43, 50, 13)
          ..close();
        c.drawPath(tower, fill);
        line(50, 7, 50, 17);
        box(33, 68, 34, 4);
        box(41, 45, 18, 3);
        for (var y = 49.0; y < 66; y += 5) {
          line(44, y, 55, y + 4, tint: paper, width: .8);
          line(56, y, 45, y + 4, tint: paper, width: .8);
        }
        line(13, 93, 88, 93);
        circle(14, 76, 8, tint: light);
        box(13, 80, 2, 12, tint: light);
      case PlaceMotif.towerBridge:
        box(17, 39, 17, 43);
        box(66, 39, 17, 43);
        for (final x in [17.0, 66.0]) {
          path([
            Offset(x - 2, 40),
            Offset(x + 3, 26),
            Offset(x + 8, 40),
          ], close: true);
          path([
            Offset(x + 9, 40),
            Offset(x + 14, 26),
            Offset(x + 19, 40),
          ], close: true);
          box(x + 6, 50, 5, 10, tint: paper);
          box(x + 6, 68, 5, 13, tint: paper);
        }
        box(31, 45, 38, 4);
        box(5, 80, 90, 4);
        final cable = Path()
          ..moveTo(0, 76)
          ..quadraticBezierTo(14, 69, 24, 48)
          ..quadraticBezierTo(50, 87, 75, 48)
          ..quadraticBezierTo(87, 72, 100, 76);
        c.drawPath(
          cable,
          stroke
            ..color = light
            ..strokeWidth = 2,
        );
        for (double x = 37; x < 65; x += 6) {
          line(x, 70, x, 80, tint: light, width: .7);
        }
      case PlaceMotif.operaHouse:
        for (var i = 0; i < 4; i++) {
          final x = 8.0 + i * 19, y = 37.0 + (i.isEven ? 0 : 12);
          final shell = Path()
            ..moveTo(x, 81)
            ..quadraticBezierTo(x + 4, y + 12, x + 31, y)
            ..quadraticBezierTo(x + 30, 67, x + 37, 81)
            ..close();
          c.drawPath(shell, Paint()..color = i.isEven ? color : light);
          line(x + 9, 77, x + 28, y + 9, tint: paper, width: .8);
        }
        box(7, 83, 89, 5);
        line(3, 92, 95, 92, tint: light);
      case PlaceMotif.coast:
        path(const [
          Offset(47, 30),
          Offset(47, 73),
          Offset(20, 73),
        ], close: true);
        path(
          const [Offset(51, 40), Offset(73, 73), Offset(51, 73)],
          close: true,
          tint: light,
        );
        path(const [
          Offset(17, 77),
          Offset(79, 77),
          Offset(68, 86),
          Offset(26, 86),
        ], close: true);
        line(48, 24, 48, 84);
      case PlaceMotif.desert:
        for (var i = 0; i < 3; i++) {
          final dune = Path()
            ..moveTo(0, 65 + i * 12)
            ..quadraticBezierTo(35, 30 + i * 15, 64, 64 + i * 12)
            ..quadraticBezierTo(84, 82 + i * 8, 100, 57 + i * 15)
            ..lineTo(100, 100)
            ..lineTo(0, 100)
            ..close();
          c.drawPath(dune, Paint()..color = Color.lerp(light, color, i * .35)!);
        }
      case PlaceMotif.park:
        for (final (x, y, r) in [
          (26.0, 49.0, 17.0),
          (64.0, 38.0, 23.0),
          (83.0, 66.0, 10.0),
        ]) {
          circle(x, y, r, tint: x == 64 ? color : light);
          line(x, y, x, 90, width: 2);
          line(x, y + 13, x - 6, y + 6, width: 1.4);
        }
        line(10, 92, 94, 92, tint: light);
      case PlaceMotif.cafe:
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(22, 44, 48, 34),
            const Radius.circular(9),
          ),
          fill,
        );
        c.drawOval(
          const Rect.fromLTWH(60, 48, 23, 23),
          stroke
            ..color = color
            ..strokeWidth = 4,
        );
        c.drawOval(const Rect.fromLTWH(23, 41, 46, 10), Paint()..color = light);
        c.drawOval(const Rect.fromLTWH(29, 44, 34, 5), fill);
        c.drawArc(
          const Rect.fromLTWH(15, 73, 68, 15),
          0,
          math.pi,
          false,
          stroke..strokeWidth = 3,
        );
        for (double x = 35; x < 65; x += 13) {
          c.drawPath(
            Path()
              ..moveTo(x, 33)
              ..cubicTo(x - 9, 23, x + 8, 23, x, 14),
            stroke..strokeWidth = 1.5,
          );
        }
      case PlaceMotif.museum:
        path(const [
          Offset(10, 43),
          Offset(50, 22),
          Offset(90, 43),
        ], close: true);
        for (double x = 22; x < 85; x += 18) {
          box(x, 48, 6, 34);
          box(x - 3, 47, 12, 3, tint: light);
        }
        box(13, 84, 76, 4);
        box(8, 91, 86, 3, tint: light);
      case PlaceMotif.market:
        box(17, 54, 66, 35);
        box(21, 60, 25, 19, tint: paper);
        box(60, 61, 15, 28, tint: paper);
        path(
          const [
            Offset(12, 50),
            Offset(23, 30),
            Offset(77, 30),
            Offset(88, 50),
          ],
          close: true,
          tint: light,
        );
        for (var i = 0; i < 6; i++) {
          c.drawArc(
            Rect.fromLTWH(12 + i * 12.7, 43, 12.7, 15),
            0,
            math.pi,
            true,
            Paint()..color = i.isEven ? color : light,
          );
        }
        box(10, 90, 80, 3, tint: light);
      case PlaceMotif.mountain:
        path(
          const [Offset(3, 88), Offset(37, 26), Offset(71, 88)],
          close: true,
          tint: light,
        );
        path(const [
          Offset(36, 88),
          Offset(65, 16),
          Offset(98, 88),
        ], close: true);
        path(
          const [
            Offset(55, 41),
            Offset(65, 16),
            Offset(76, 43),
            Offset(65, 35),
            Offset(62, 43),
          ],
          close: true,
          tint: paper,
        );
      case PlaceMotif.airport:
        c.save();
        c.translate(50, 51);
        c.rotate(.55);
        path(const [
          Offset(0, -34),
          Offset(5, -28),
          Offset(6, -5),
          Offset(32, 12),
          Offset(32, 18),
          Offset(5, 8),
          Offset(4, 28),
          Offset(14, 34),
          Offset(14, 38),
          Offset(0, 34),
          Offset(-14, 38),
          Offset(-14, 34),
          Offset(-4, 28),
          Offset(-5, 8),
          Offset(-32, 18),
          Offset(-32, 12),
          Offset(-6, -5),
          Offset(-5, -28),
        ], close: true);
        c.restore();
      case PlaceMotif.neighborhood:
        path(
          const [
            Offset(9, 30),
            Offset(33, 20),
            Offset(66, 31),
            Offset(91, 20),
            Offset(91, 80),
            Offset(66, 91),
            Offset(33, 80),
            Offset(9, 91),
          ],
          close: true,
          tint: light.withValues(alpha: .6),
        );
        line(33, 20, 33, 80, tint: paper);
        line(66, 31, 66, 91, tint: paper);
        final route = Path()
          ..moveTo(19, 73)
          ..cubicTo(60, 74, 28, 47, 60, 49)
          ..lineTo(77, 40);
        c.drawPath(
          route,
          stroke
            ..color = color
            ..strokeWidth = 2,
        );
        circle(19, 73, 3);
        circle(77, 40, 7);
        circle(77, 40, 2, tint: paper);
    }
    c.restore();
    if ([
      PlaceMotif.coast,
      PlaceMotif.operaHouse,
      PlaceMotif.towerBridge,
      PlaceMotif.kuwaitTowers,
    ].contains(motif)) {
      for (double y = 94; y < 100; y += 4) {
        c.drawPath(
          Path()
            ..moveTo(0, y)
            ..cubicTo(25, y - 4, 35, y + 4, 52, y)
            ..cubicTo(70, y - 4, 85, y + 4, 100, y),
          Paint()
            ..color = light
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8,
        );
      }
    }
    c.restore();
  }
}
