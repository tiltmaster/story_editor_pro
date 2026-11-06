import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:story_editor_pro/story_editor_pro.dart';
import 'package:story_editor_pro/src/camera_effects_panel.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final rtl in [false, true]) {
    testWidgets('image drag deletes at the rendered trash on tall canvas rtl=$rtl', (tester) async {
      await openEditor(tester, rtl: rtl);
      final image = find.byWidgetPredicate((w) => w is Image && w.image is FileImage &&
          (w.image as FileImage).file.path.endsWith('crown.png'));
      final start = tester.getCenter(image);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(25, 30)); await tester.pump();
      final trash = find.byKey(const ValueKey('editor-trash-target'));
      expect(trash, findsOneWidget);
      final target = tester.getCenter(trash);
      expect(target.dy, lessThan(800), reason: 'Trash belongs to the canvas, not the full screen');
      await gesture.moveTo(target); await tester.pump();
      await gesture.up(); await tester.pumpAndSettle();
      expect(image, findsNothing);
      await tester.tap(find.byTooltip('Undo')); await tester.pumpAndSettle();
      expect(image, findsOneWidget);
      await tester.tap(find.byTooltip('Redo')); await tester.pumpAndSettle();
      expect(image, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('smart stickers can be dragged onto the visible bin and restored', (tester) async {
    await openEditor(tester);
    await tester.tap(find.byTooltip('Add sticker')); await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Time'));
    await tester.pumpAndSettle();
    final clock=find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 64);
    expect(clock,findsOneWidget);
    final gesture=await tester.startGesture(tester.getCenter(clock));
    await gesture.moveBy(const Offset(-25,30)); await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('editor-trash-target'))));
    await tester.pump(); await gesture.up(); await tester.pumpAndSettle();
    expect(clock,findsNothing);
    await tester.tap(find.byTooltip('Undo')); await tester.pumpAndSettle();
    expect(clock,findsOneWidget); expect(tester.takeException(),isNull);
  });
  testWidgets('photo contrast is baked into the shared image pixels', (tester) async {
    final dir=Directory.systemTemp.createTempSync('niero-contrast-');
    addTearDown(() => dir.deleteSync(recursive:true));
    final input=await tester.runAsync(() async {
      final recorder=ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0,0,200,350),Paint()..color=const Color(0xFF404040));
      final picture=recorder.endRecording(); final image=await picture.toImage(200,350);
      final png=await image.toByteData(format:ui.ImageByteFormat.png);
      image.dispose();picture.dispose();
      return File('${dir.path}/source.png')..writeAsBytesSync(png!.buffer.asUint8List());
    });
    StoryShareResult? exported;
    await openEditor(tester,imagePath:input!.path,onShare:(value)=>exported=value);
    await tester.tap(find.byTooltip('Filters and adjustments')); await tester.pumpAndSettle();
    final slider=tester.widget<Slider>(find.byKey(const ValueKey('editor-contrast')));
    slider.onChanged!(.5);slider.onChangeEnd!(.5);await tester.pump();
    await tester.tap(find.byTooltip('Filters and adjustments'));await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-share')));
    for(var i=0;i<50 && exported==null;i++) {
      await tester.pump(const Duration(milliseconds:50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:20)));
    }
    expect(exported,isNotNull);
    final output=exported!.story.file;
    addTearDown(() { if(output.existsSync()) output.deleteSync(); });
    await tester.runAsync(() async {
      final codec=await ui.instantiateImageCodec(await output.readAsBytes());
      final frame=await codec.getNextFrame();
      final pixels=await frame.image.toByteData(format:ui.ImageByteFormat.rawRgba);
      final center=((frame.image.height ~/ 2)*frame.image.width+(frame.image.width ~/ 2))*4;
      expect(pixels!.getUint8(center),closeTo(96,2));
      frame.image.dispose();codec.dispose();
    });
    expect(tester.takeException(),isNull);
  });
  testWidgets('photo contrast applies to the rendered image and can undo or reset', (tester) async {
    await openEditor(tester);
    await tester.tap(find.byTooltip('Filters and adjustments')); await tester.pumpAndSettle();
    expect(find.byType(CameraEffectsPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('effects-tab-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('effects-tab-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('effects-tab-2')), findsNothing,
        reason: 'Live face tracking is not falsely offered for a captured image');
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('editor-contrast')));
    slider.onChanged!(.6); slider.onChangeEnd!(.6); await tester.pump();
    expect(find.byKey(const ValueKey('editor-image-contrast')), findsOneWidget);
    await tester.tap(find.byTooltip('Reset contrast')); await tester.pump();
    expect(find.byKey(const ValueKey('editor-image-contrast')), findsNothing);
    await tester.tap(find.byTooltip('Undo')); await tester.pump();
    expect(find.byKey(const ValueKey('editor-image-contrast')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
Future<void> openEditor(WidgetTester tester, {bool rtl = false, String? imagePath, ValueChanged<StoryShareResult>? onShare}) async {
  tester.view.physicalSize = const Size(400, 900); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const SizedBox()));
  final background = File(imagePath ?? 'assets/word_art/habibi.png').absolute;
  final crown = File('assets/props/crown.png').absolute;
  await tester.runAsync(() async {
    await precacheImage(FileImage(background), nav.currentContext!);
    await precacheImage(FileImage(crown), nav.currentContext!);
  });
  nav.currentState!.push(MaterialPageRoute<void>(builder: (_) =>
    Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: StoryEditorConfigProvider(config: const StoryEditorConfig(),
        child: StoryEditorScreen(imagePath: background.path, isFromGallery: true, onShare:onShare,
          initialImageOverlay: ImageOverlay(imagePath: crown.path,
            offset: const Offset(35, 220), scale: .22))))));
  await tester.pumpAndSettle();
}
