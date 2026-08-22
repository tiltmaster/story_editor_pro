import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
