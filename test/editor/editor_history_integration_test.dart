import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  testWidgets(
    'Undo removes newer text before an older drawing and Redo restores both',
    (tester) async {
      await _openEditor(tester);
      await tester.tap(find.byTooltip('Draw'));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(100, 230), const Offset(70, 40));
      await tester.pumpAndSettle();
      expect(_drawingCount(tester), 1);
      await tester.tap(find.byTooltip('Done drawing'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add text'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Later text');
      await tester.tap(find.byTooltip('Done text'));
      await tester.pumpAndSettle();
      expect(find.text('Later text'), findsWidgets);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Later text'), findsNothing);
      expect(_drawingCount(tester), 1);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(_drawingCount(tester), 0);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      expect(_drawingCount(tester), 1);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      expect(find.text('Later text'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'moving and deleting an image are separate chronological undo actions',
    (tester) async {
      await _openEditor(
        tester,
        overlay: ImageOverlay(
          imagePath: File('assets/props/crown.png').absolute.path,
          offset: const Offset(35, 160),
          scale: .22,
        ),
      );
      final overlay = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is FileImage &&
            (w.image as FileImage).file.path.endsWith('crown.png'),
      );
      final initial = tester.getTopLeft(overlay);
      await tester.drag(overlay, const Offset(65, 45));
      await tester.pumpAndSettle();
      final moved = tester.getTopLeft(overlay);
      expect((moved - initial).distance, greaterThan(30));
      await tester.tap(overlay);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(overlay, findsNothing);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(overlay), moved);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(overlay), initial);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(overlay), moved);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small Arabic editor protects an unsaved capture and Keep editing preserves it',
    (tester) async {
      await _openEditor(tester, arabic: true, fromGallery: false);
      await tester.tap(find.byTooltip('إغلاق'));
      await tester.pumpAndSettle();
      expect(find.text('تجاهل هذا التعديل؟'), findsOneWidget);
      await tester.tap(find.text('متابعة التعديل'));
      await tester.pumpAndSettle();
      expect(find.byType(StoryEditorScreen), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      final undo = tester.getRect(find.byTooltip('تراجع'));
      expect(undo.width, greaterThanOrEqualTo(48));
      expect(undo.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byTooltip('إغلاق'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تجاهل'));
      await tester.pumpAndSettle();
      expect(find.byType(StoryEditorScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('untouched gallery media closes without a discard prompt', (
    tester,
  ) async {
    await _openEditor(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(StoryEditorScreen), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'smart sticker style and movement restore without mutating older history',
    (tester) async {
      await _openEditor(tester);
      await tester.tap(find.byTooltip('Add sticker'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == 'Time',
        ),
      );
      await tester.pumpAndSettle();
      final clock = find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontSize == 64,
      );
      expect(clock, findsOneWidget);
      final initial = tester.getTopLeft(clock);
      await tester.tap(clock);
      await tester.pumpAndSettle();
      expect(clock, findsNothing);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(clock, findsOneWidget);
      await tester.drag(clock, const Offset(-45, 75));
      await tester.pumpAndSettle();
      expect((tester.getTopLeft(clock) - initial).distance, greaterThan(30));
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(clock), initial);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(clock, findsNothing);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(clock), initial);
      expect(tester.takeException(), isNull);
    },
  );
}

int _drawingCount(WidgetTester tester) {
  final paint = tester
      .widgetList<CustomPaint>(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is DrawingPainter,
        ),
      )
      .first;
  return (paint.painter as DrawingPainter).paths.length;
}

Future<void> _openEditor(
  WidgetTester tester, {
  bool arabic = false,
  bool fromGallery = true,
  ImageOverlay? overlay,
}) async {
  tester.view.physicalSize = arabic
      ? const Size(320, 568)
      : const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      locale: Locale(arabic ? 'ar' : 'en'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const Scaffold(body: Text('Camera')),
    ),
  );
  await tester.runAsync(() async {
    await precacheImage(
      FileImage(File('assets/word_art/habibi.png').absolute),
      navigator.currentContext!,
    );
    if (overlay != null) {
      await precacheImage(
        FileImage(File(overlay.imagePath)),
        navigator.currentContext!,
      );
    }
  });
  navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => StoryEditorConfigProvider(
        config: const StoryEditorConfig(),
        child: StoryEditorScreen(
          imagePath: File('assets/word_art/habibi.png').absolute.path,
          isFromGallery: fromGallery,
          initialImageOverlay: overlay,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () async => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}
