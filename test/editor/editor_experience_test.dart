import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/src/widgets/editor_control_button.dart';
import 'package:story_editor_pro/src/widgets/editor_directionality.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  group('editor locale behavior', () {
    test('detects Arabic and English content direction independently', () {
      expect(editorTextDirection('مرحبا بالعالم'), TextDirection.rtl);
      expect(editorTextDirection('Hello world'), TextDirection.ltr);
      expect(editorTextDirection('2026-08-22'), TextDirection.ltr);
    });

    test('maps every AR preset id to injected localized labels', () {
      const strings = StoryEditorStrings(
        cameraFilterArGolden: 'ذهبي',
        cameraFilterArFrost: 'صقيع',
        cameraFilterArNeon: 'نيون',
        cameraFilterArNoir: 'أبيض وأسود',
        cameraFilterArPrism: 'طيف',
        cameraFilterArRetro: 'ريترو',
        cameraFilterArStargaze: 'نجوم',
      );

      expect(strings.filterNameForPreset('ar_golden'), 'ذهبي');
      expect(strings.filterNameForPreset('ar_frost'), 'صقيع');
      expect(strings.filterNameForPreset('ar_neon'), 'نيون');
      expect(strings.filterNameForPreset('ar_noir'), 'أبيض وأسود');
      expect(strings.filterNameForPreset('ar_prism'), 'طيف');
      expect(strings.filterNameForPreset('ar_retro'), 'ريترو');
      expect(strings.filterNameForPreset('ar_stargaze'), 'نجوم');
    });
  });

  group('remote sticker security policy', () {
    test('only allows public HTTPS sticker URLs', () {
      expect(
        RemoteStickerSecurityPolicy.allowsUrl(
          'https://cdn.example.com/stickers/hello.webp',
        ),
        isTrue,
      );
      expect(
        RemoteStickerSecurityPolicy.allowsUrl('http://cdn.example.com/a.png'),
        isFalse,
      );
      expect(
        RemoteStickerSecurityPolicy.allowsUrl('https://127.0.0.1/a.png'),
        isFalse,
      );
      expect(
        RemoteStickerSecurityPolicy.allowsUrl('https://192.168.1.8/a.png'),
        isFalse,
      );
      expect(
        RemoteStickerSecurityPolicy.allowsUrl('file:///tmp/a.png'),
        isFalse,
      );
      expect(
        RemoteStickerSecurityPolicy.allowsAddress(InternetAddress('10.0.0.8')),
        isFalse,
      );
      expect(
        RemoteStickerSecurityPolicy.allowsAddress(
          InternetAddress('93.184.216.34'),
        ),
        isTrue,
      );
    });

    test('rejects bodies over the download limit', () {
      expect(
        () => RemoteStickerSecurityPolicy.enforceSize(
          RemoteStickerSecurityPolicy.maxDownloadBytes + 1,
        ),
        throwsFormatException,
      );
      expect(
        () => RemoteStickerSecurityPolicy.enforceSize(
          RemoteStickerSecurityPolicy.maxDownloadBytes,
        ),
        returnsNormally,
      );
    });

    test('pins only fully public DNS resolutions', () {
      expect(
        RemoteStickerSecurityPolicy.requirePublicResolution(<InternetAddress>[
          InternetAddress('93.184.216.34'),
        ]).address,
        '93.184.216.34',
      );
      expect(
        () => RemoteStickerSecurityPolicy.requirePublicResolution(
          <InternetAddress>[
            InternetAddress('93.184.216.34'),
            InternetAddress('169.254.169.254'),
          ],
        ),
        throwsFormatException,
      );
    });

    test('accepts only supported raster signatures', () {
      expect(
        RemoteStickerSecurityPolicy.detectFormat(
          Uint8List.fromList(const <int>[
            0x89,
            0x50,
            0x4e,
            0x47,
            0x0d,
            0x0a,
            0x1a,
            0x0a,
          ]),
        ),
        RemoteStickerImageFormat.png,
      );
      expect(
        () => RemoteStickerSecurityPolicy.detectFormat(
          Uint8List.fromList('<svg/>'.codeUnits),
        ),
        throwsFormatException,
      );
    });

    test('rejects oversized dimensions and animation work', () {
      expect(
        () => RemoteStickerSecurityPolicy.enforceImageBounds(
          width: RemoteStickerSecurityPolicy.maxDimension + 1,
          height: 1,
          frameCount: 1,
        ),
        throwsFormatException,
      );
      expect(
        () => RemoteStickerSecurityPolicy.enforceImageBounds(
          width: 1024,
          height: 1024,
          frameCount: RemoteStickerSecurityPolicy.maxFrameCount,
        ),
        throwsFormatException,
      );
    });

    test('inspects a safe image before rendering', () async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final metadata = await inspectRemoteStickerImage(bytes);
      expect(metadata.width, 1);
      expect(metadata.height, 1);
      expect(metadata.frameCount, 1);
    });
  });

  testWidgets('editor control exposes a 48dp semantic target', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorControlButton(
            label: 'Smart tags',
            icon: Icons.auto_awesome,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(EditorControlButton));
    expect(semantics.label, 'Smart tags');
    expect(
      tester.getSize(find.byType(EditorControlButton)),
      const Size(48, 48),
    );

    await tester.tap(find.byType(EditorControlButton));
    expect(pressed, isTrue);
  });

  testWidgets('smart sticker renderer supports Arabic location content', (
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
