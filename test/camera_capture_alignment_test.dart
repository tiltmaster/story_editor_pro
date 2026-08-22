import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

Widget _host({Widget? status, TextDirection direction = TextDirection.ltr}) {
  return MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: Center(
          child: AnchoredShutterControl(
            status: status,
            shutter: const SizedBox(width: 72, height: 72),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('timer label never moves the shutter anchor', (tester) async {
    await tester.pumpWidget(_host());
    final idleCenter = tester.getCenter(
      find.byKey(AnchoredShutterControl.shutterAnchorKey),
    );

    await tester.pumpWidget(
      _host(status: const Text('00:03', textDirection: TextDirection.ltr)),
    );
    await tester.pump();
    final timerCenter = tester.getCenter(
      find.byKey(AnchoredShutterControl.shutterAnchorKey),
    );

    expect(timerCenter, idleCenter);
  });

  testWidgets('shutter anchor remains physical-center in Arabic RTL', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        direction: TextDirection.rtl,
        status: const Text('يبدأ بعد ٣ ثوانٍ'),
      ),
    );

    final controlCenter = tester.getCenter(find.byType(AnchoredShutterControl));
    final shutterCenter = tester.getCenter(
      find.byKey(AnchoredShutterControl.shutterAnchorKey),
    );
    expect(shutterCenter, controlCenter);
  });

  testWidgets(
    'smart shutter distinguishes tap and hold without duplicate end',
    (tester) async {
      var photos = 0;
      var videoStarts = 0;
      var videoEnds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SmartShutterButton(
              onPhoto: () => photos++,
              onVideoStart: () => videoStarts++,
              onVideoEnd: () => videoEnds++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SmartShutterButton));
      await tester.pump();
      expect((photos, videoStarts, videoEnds), (1, 0, 0));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SmartShutterButton)),
      );
      await tester.pump(const Duration(milliseconds: 310));
      expect(videoStarts, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect((photos, videoStarts, videoEnds), (1, 1, 1));
    },
  );

  test('startup target is capped at 700ms', () {
    const withinBudget = CameraStartupMetrics(
      usedPrewarm: true,
      controllerInitialization: Duration(milliseconds: 500),
      screenWaitForController: Duration(milliseconds: 100),
      routeToPreviewReady: Duration(milliseconds: 700),
    );
    const outsideBudget = CameraStartupMetrics(
      usedPrewarm: false,
      controllerInitialization: Duration(milliseconds: 701),
      screenWaitForController: Duration(milliseconds: 701),
      routeToPreviewReady: Duration(milliseconds: 701),
    );

    expect(withinBudget.metWarmTarget, isTrue);
    expect(outsideBudget.metWarmTarget, isFalse);
  });

  test('unified camera rail preserves every look and seven AR effects', () {
    final presets = CameraFilterRailCatalog.presets;
    expect(presets, hasLength(StoryEditorFilters.presets.length + 7));
    expect(
      presets.take(StoryEditorFilters.presets.length).map((item) => item.id),
      StoryEditorFilters.presets.map((item) => item.id),
    );
    expect(
      presets.skip(StoryEditorFilters.presets.length).map((item) => item.id),
      StoryEditorFilters.arPresets.map((item) => item.id),
    );
  });
}
