import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';
import 'package:story_editor_pro/src/camera_effects.dart';

void main() {
  test(
    'nearby selection retains POI identity separately from legacy ID and GPS',
    () {
      final venue = const CameraNearbyPlace(
        id: 'overture:venue',
        name: 'Cafe',
        distanceMeters: 42,
        latitude: 29.3,
        longitude: 47.9,
        legacyPlaceId: 'legacy-uuid',
      );
      final normalized = normalizeNearbyCameraPlaces([venue]).single;
      final selected = const CameraEffects().copyWith(
        placeName: normalized.name,
        placeStyle: 'postcard',
        nearbyPlace: normalized,
      );
      final snapshot = selected.captureMetadata!;
      expect(snapshot.place!.id, 'overture:venue');
      expect(snapshot.place!.legacyPlaceId, 'legacy-uuid');
      expect(snapshot.place!.hasCoordinates, isTrue);
      expect(snapshot.toJson().toString(), isNot(contains('29.3')));
      expect(snapshot.toJson().toString(), isNot(contains('legacy-uuid')));
      expect(selected.copyWith(placeStyle: 'none').captureMetadata, isNull);
      final city = selected
          .copyWith(placeName: 'Kuwait')
          .captureMetadata!
          .place!;
      expect(city.source, 'camera_city');
      expect(city.id, isNull);
      expect(city.hasCoordinates, isFalse);
      expect(snapshot.place!.id, 'overture:venue');
    },
  );

  test('descriptors are immutable bounded snapshots without image paths', () {
    final values = [
      const StoryCaptureSticker(type: 'image', value: '/secret/a.png'),
    ];
    final metadata = StoryCaptureMetadata(stickers: values);
    values.clear();
    expect(metadata.stickers, hasLength(1));
    expect(() => metadata.stickers.clear(), throwsUnsupportedError);
    expect(metadata.toJson()['stickers'], [
      {'type': 'image'},
    ]);
    expect(metadata.toJson().containsKey('audience'), isFalse);
    expect(metadata.toJson(isPrivate: true)['audience'], 'connections');
  });

  testWidgets(
    'actual editor export preserves selected place and current rendered text',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      StoryShareResult? published;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Camera')),
        ),
      );
      final image = File('assets/word_art/habibi.png').absolute;
      await tester.runAsync(
        () => precacheImage(FileImage(image), navigator.currentContext!),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => StoryEditorConfigProvider(
            config: const StoryEditorConfig(
              storyCanvasWidth: 200,
              storyCanvasHeight: 350,
            ),
            child: StoryEditorScreen(
              imagePath: image.path,
              isFromGallery: true,
              initialCaptureMetadata: StoryCaptureMetadata(
                place: const StoryCapturePlace(
                  source: 'camera_nearby',
                  id: 'overture:venue',
                  label: 'Selected cafe',
                  latitude: 29.3,
                  longitude: 47.9,
                ),
              ),
              initialTextOverlay: TextOverlay(
                text: 'Visible caption',
                color: Colors.white,
                textStyle: const TextStyle(),
                offset: const Offset(20, 100),
              ),
              onShare: (result) => published = result,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-share')));
      for (var i = 0; i < 50 && published == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(published, isNotNull);
      expect(published!.shareTarget, ShareTarget.story);
      expect(published!.story.captureMetadata!.place!.id, 'overture:venue');
      expect(
        published!.story.captureMetadata!.stickers.map((s) => s.value),
        contains('Visible caption'),
      );
      expect(published!.story.file.existsSync(), isTrue);
      // Delete only this test's explicitly returned temporary export.
      final output = published!.story.file;
      addTearDown(() async {
        if (await output.exists()) await output.delete();
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
