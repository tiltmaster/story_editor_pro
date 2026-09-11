import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/src/video_trim_timeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('story_editor_pro');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9N8AAAAASUVORK5CYII=',
  );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('decoded filmstrip supports trimming and seeking in Arabic', (
    tester,
  ) async {
    var requests = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getVideoThumbnails');
      requests++;
      return List.generate(10, (_) => png);
    });
    var range = const RangeValues(0, 5000);
    var seek = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (context, update) => VideoTrimTimeline(
                    path: '/clip.mp4',
                    durationMs: 5000,
                    startMs: range.start.round(),
                    endMs: range.end.round(),
                    onChanged: (value) => update(() => range = value),
                    onSeek: (value) => seek = value,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(10));
    expect(find.byType(RangeSlider), findsNothing);
    await tester.drag(
      find.bySemanticsLabel('بداية المقطع'),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    expect(range.start, greaterThan(500));
    expect(range.end - range.start, greaterThanOrEqualTo(250));
    expect(seek, range.start.round());
    expect(requests, 1, reason: 'Dragging must not decode the filmstrip again');
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnail failure is retryable', (tester) async {
    var fail = true;
    messenger.setMockMethodCallHandler(channel, (_) async {
      if (fail) throw PlatformException(code: 'decode');
      return [png];
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoTrimTimeline(
            path: '/clip.mp4',
            durationMs: 1000,
            startMs: 0,
            endMs: 1000,
            onChanged: (_) {},
            onSeek: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reload frames'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Reload frames'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });
}
