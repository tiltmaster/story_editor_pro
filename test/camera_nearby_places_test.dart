import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:story_editor_pro/story_editor_pro.dart';
import 'package:story_editor_pro/src/camera_effects.dart';
import 'package:story_editor_pro/src/camera_effects_panel.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('nearby results reject malformed distances, deduplicate and sort', () {
    final places = normalizeNearbyCameraPlaces([
      const CameraNearbyPlace(id: 'b', name: ' Beach ', distanceMeters: 200),
      const CameraNearbyPlace(id: 'a', name: 'مقهى', distanceMeters: 10),
      const CameraNearbyPlace(id: 'b', name: 'Beach', distanceMeters: 250),
      const CameraNearbyPlace(id: 'c', name: 'Outside', distanceMeters: 4000),
      const CameraNearbyPlace(id: 'd', name: '', distanceMeters: 4),
      const CameraNearbyPlace(
        id: 'e',
        name: 'Invalid',
        distanceMeters: double.nan,
      ),
    ]);
    expect(places.map((p) => p.name), ['مقهى', 'Beach']);
  });

  testWidgets('venue retains its style and Arabic name across categories', (
    tester,
  ) async {
    final session = _NearbySession();
    CameraEffects latest = const CameraEffects();
    await tester.pumpWidget(
      MaterialApp(
        home: StoryEditorConfigProvider(
          config: const StoryEditorConfig(),
          child: Scaffold(
            body: CameraEffectsPanel(
              effects: latest,
              lookId: 'none',
              lookStrength: 1,
              supportedFaceLenses: const {},
              supportsPlaces: true,
              supportsBeauty: true,
              locationSession: session,
              onChanged: (effects, _, __) => latest = effects,
            ),
          ),
        ),
      ),
    );
    Future<void> tap(String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    await tap('effects-tab-3');
    await tap('camera-nearby-places');
    await tester.tap(find.text('مقهى البحر'));
    await tester.pumpAndSettle();
    expect(latest.placeName, 'مقهى البحر');
    await tap('effects-card-place-editorial');
    await tap('effects-tab-0');
    await tap('effects-tab-3');
    expect(latest.placeName, 'مقهى البحر');
    expect(latest.placeStyle, 'editorial');
    await tap('camera-nearby-places');
    await tester.tap(find.text('Garden'));
    await tester.pumpAndSettle();
    await tap('effects-card-place-stamp');
    await tap('camera-nearby-places');
    await tester.tap(find.text('مقهى البحر'));
    await tester.pumpAndSettle();
    expect(latest.placeStyle, 'editorial');
    expect(tester.takeException(), isNull);
  });
}

class _NearbySession extends CameraPlaceSession {
  _NearbySession() : super(resolver: (_) async => 'Kuwait City');
  @override
  bool get supportsNearby => true;
  @override
  Future<List<CameraNearbyPlace>> nearby({
    required String localeIdentifier,
  }) async => const [
    CameraNearbyPlace(id: 'cafe', name: 'مقهى البحر', distanceMeters: 40),
    CameraNearbyPlace(id: 'garden', name: 'Garden', distanceMeters: 160),
  ];
}
