import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/src/camera_effects.dart';
import 'package:story_editor_pro/src/camera_place_gesture.dart';
import 'package:story_editor_pro/src/place_sticker_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('nine distinct sticker designs rasterize in English and Arabic', () async {
    // Local design review uses installed fonts; CI still checks raster geometry.
    for (final entry in {
      'sans-serif': 'arial.ttf',
      'Georgia': 'georgia.ttf',
    }.entries) {
      final font = File('C:/Windows/Fonts/${entry.value}');
      if (font.existsSync()) {
        final loader = FontLoader(entry.key)
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await loader.load();
      }
    }
    final output = Directory('build/sticker-review')
      ..createSync(recursive: true);
    for (final name in [
      'Al Jahra',
      'Dubai',
      'Paris',
      'London',
      'Sydney',
      'Marina Beach',
      'Garden Park',
      'Paris Cafe',
      'Old Souq',
      'City Museum',
      'Desert Dunes',
      'Mountain',
      'Airport',
      'Unknown Quarter',
    ]) {
      for (final style in ['postcard', 'stamp', 'editorial']) {
        final bytes = await renderPlaceSticker(
          style: style,
          name: name,
          variant: 0,
          language: 'en',
          date: DateTime(2026, 9, 11),
        );
        File('${output.path}/$name-$style.png').writeAsBytesSync(bytes);
      }
    }
    for (final language in ['en', 'ar']) {
      for (final style in ['postcard', 'stamp', 'editorial']) {
        final variants = <String>{};
        for (var variant = 0; variant < 3; variant++) {
          final bytes = await renderPlaceSticker(
            style: style,
            name: language == 'ar' ? 'مدينة الكويت' : 'Kuwait City',
            variant: variant,
            language: language,
            date: DateTime(2026, 9, 11),
          );
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, placeStickerSize(style).width);
          expect(frame.image.height, placeStickerSize(style).height);
          final rgba = await frame.image.toByteData();
          expect(
            rgba!.getUint8(3),
            0,
            reason: 'Sticker corners remain transparent',
          );
          variants.add(bytes.toString());
          File(
            '${output.path}/$style-$variant-$language.png',
          ).writeAsBytesSync(bytes);
          frame.image.dispose();
          codec.dispose();
        }
        expect(variants.length, 3);
      }
    }
  });

  test(
    'rotated bounds keep every sticker inside the capture for a full turn',
    () {
      for (final style in ['postcard', 'stamp', 'editorial']) {
        for (var degrees = -180; degrees <= 180; degrees += 5) {
          final angle = degrees * math.pi / 180;
          final e = CameraEffects(placeStyle: style).copyWith(
            placeRotation: angle,
            placeScale: 1.6,
            placeX: 0,
            placeY: 1,
          );
          final size =
              rotatedPlaceStickerSize(style, e.placeRotation) * e.placeScale;
          expect(e.placeX - size.width / 2160, greaterThanOrEqualTo(.014));
          expect(e.placeY + size.height / 3840, lessThanOrEqualTo(.986));
          expect(e.placeX + size.width / 2160, lessThanOrEqualTo(.986));
        }
      }
      final invalid = const CameraEffects().copyWith(placeRotation: double.nan);
      expect(invalid.placeRotation, 0);
    },
  );

  testWidgets(
    'two fingers rotate the sticker without mirroring or changing layers',
    (tester) async {
      var effects = const CameraEffects(
        placeStyle: 'postcard',
        placeName: 'الجهراء',
        beauty: .4,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 360,
              height: 640,
              child: StatefulBuilder(
                builder: (context, setState) => CameraPlaceGesture(
                  effects: effects,
                  onCycle: () {},
                  onChanged: (e) => setState(() => effects = e),
                ),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(
        find.byKey(const ValueKey('camera-place-sticker')),
      );
      final a = await tester.startGesture(
        center + const Offset(-30, 0),
        pointer: 1,
      );
      final b = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await tester.pump();
      await a.moveTo(center + const Offset(-35, -20));
      await b.moveTo(center + const Offset(35, 20));
      await tester.pump();
      await a.moveTo(center + const Offset(-35, -30));
      await b.moveTo(center + const Offset(35, 30));
      await tester.pump();
      expect(effects.placeRotation, greaterThan(.25));
      expect(effects.placeScale, greaterThan(1));
      expect(effects.beauty, .4);
      await a.up();
      await b.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'changing to a wider ticket keeps the full sticker inside the frame',
    () {
      final stamp = const CameraEffects(
        placeStyle: 'postcard',
        placeX: .18,
        placeY: .88,
      );
      final ticket = stamp.copyWith(placeStyle: 'stamp', placeScale: 1.6);
      expect(
        ticket.placeX - 680 * ticket.placeScale / 2160,
        greaterThanOrEqualTo(.014),
      );
      expect(
        ticket.placeY + 240 * ticket.placeScale / 3840,
        lessThanOrEqualTo(.986),
      );
    },
  );

  testWidgets('RTL sticker taps cycle and drag preserves all layers', (
    tester,
  ) async {
    var effects = const CameraEffects(
      placeStyle: 'stamp',
      placeName: 'الكويت',
      beauty: .5,
      backgroundStyle: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: SizedBox(
              width: 360,
              height: 640,
              child: StatefulBuilder(
                builder: (context, setState) => CameraPlaceGesture(
                  effects: effects,
                  onChanged: (e) => setState(() => effects = e),
                  onCycle: () => setState(
                    () => effects = effects.copyWith(
                      placeVariant: effects.placeVariant + 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final sticker = find.byKey(const ValueKey('camera-place-sticker'));
    await tester.tap(sticker);
    await tester.pump();
    expect(effects.placeVariant, 1);
    await tester.drag(sticker, const Offset(25, -100));
    await tester.pump();
    expect(effects.placeX, greaterThan(.5));
    expect(effects.placeY, lessThan(.6));
    expect(effects.beauty, .5);
    expect(effects.backgroundStyle, 2);
    await tester.drag(sticker, const Offset(500, 900));
    await tester.pump();
    final rect = tester.getRect(sticker);
    final viewport = tester.getRect(find.byType(CameraPlaceGesture));
    expect(rect.right, lessThan(viewport.right));
    expect(rect.bottom, lessThan(viewport.bottom));
    expect(tester.takeException(), isNull);
  });
}
