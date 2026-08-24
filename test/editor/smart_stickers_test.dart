import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  testWidgets('enhanced location tag renders Arabic content in RTL', (
    tester,
  ) async {
    final sticker = SmartStickerOverlay(
      type: SmartStickerType.location,
      data: const {'name': 'مدينة الكويت'},
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(child: buildSmartStickerContent(sticker)),
          ),
        ),
      ),
    );

    expect(find.text('مدينة الكويت'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full emoji picker remains a full-width multi-column grid', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showStickerDrawer(context),
              child: const Text('Open stickers'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open stickers'));
    await tester.pump(const Duration(milliseconds: 300));
    final allEmojiAction = tester.widget<InkWell>(
      find.ancestor(of: find.text('All'), matching: find.byType(InkWell)).first,
    );
    allEmojiAction.onTap!();
    await tester.pump(const Duration(milliseconds: 300));

    final picker = tester.widget<EmojiPicker>(find.byType(EmojiPicker));
    expect(picker.config.emojiViewConfig.columns, 8);
    expect(tester.getSize(find.byType(EmojiPicker)).width, 360);
    expect(tester.takeException(), isNull);
  });
}
