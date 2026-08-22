import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing $start');
  expect(
    endIndex,
    greaterThan(startIndex),
    reason: 'Missing $end after $start',
  );
  return source.substring(startIndex, endIndex);
}

void main() {
  test('camera and editor action controls remain shadow-free', () {
    final cameraSource = File(
      'lib/src/story_camera_screen.dart',
    ).readAsStringSync();
    final editorSource = File(
      'lib/src/story_editor_screen.dart',
    ).readAsStringSync();

    final actionSections = <String>[
      _section(
        cameraSource,
        'Widget _buildFilterSelector()',
        'Widget _buildFilterBubblePreview',
      ),
      _section(
        cameraSource,
        'Widget _buildIconButton(',
        'Widget _buildZoomIndicator()',
      ),
      _section(
        editorSource,
        'Widget _buildBottomControls()',
        'void _showShareSheet()',
      ),
      _section(editorSource, 'Widget _buildControlButton(', 'void _undo()'),
    ];

    for (final section in actionSections) {
      expect(section, isNot(contains('boxShadow:')));
      expect(section, isNot(contains('elevation:')));
    }
  });

  test('media, text-legibility, and smart-tag shadows remain available', () {
    final cameraSource = File(
      'lib/src/story_camera_screen.dart',
    ).readAsStringSync();
    final editorSource = File(
      'lib/src/story_editor_screen.dart',
    ).readAsStringSync();
    final smartTagSource = File(
      'lib/src/overlays/smart_stickers.dart',
    ).readAsStringSync();

    expect(
      _section(
        cameraSource,
        'Widget _buildPendingTextIndicator()',
        'Widget _buildNormalModeBody()',
      ),
      contains('boxShadow:'),
    );
    expect(
      _section(
        editorSource,
        'List<Widget> _buildTextOverlaysForExport()',
        'List<Widget> _buildTextOverlays()',
      ),
      contains('boxShadow:'),
    );
    expect(smartTagSource, contains('boxShadow:'));
  });
}
