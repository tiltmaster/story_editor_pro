import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test(
    'camera route holds its lease until active initialization is disposed',
    () {
      final source = File(
        'lib/src/story_camera_screen.dart',
      ).readAsStringSync();
      final disposal = _section(
        source,
        'void dispose() {',
        'void _onFilterScroll()',
      );

      expect(disposal, contains('_routeDisposing = true;'));
      expect(disposal, contains('await initialization;'));
      expect(disposal, contains("'Flutter camera'"));
      expect(disposal, contains("'Native AR'"));
      expect(disposal, contains("'Native camera'"));
      expect(disposal, contains('await Future.wait<void>'));
      expect(disposal, contains('_cameraRouteLease.release();'));
      expect(
        disposal.indexOf('await initialization;'),
        lessThan(disposal.indexOf('_cameraRouteLease.release();')),
      );
    },
  );

  test('native and fallback creation stop after route disposal', () {
    final source = File('lib/src/story_camera_screen.dart').readAsStringSync();
    final initialization = _section(
      source,
      'Future<void> _initializeCameraOnce()',
      'void _reportPreviewReady(',
    );

    expect(
      RegExp(
        r'_routeDisposing \|\| !mounted',
      ).allMatches(initialization).length,
      greaterThanOrEqualTo(8),
    );
    expect(initialization, contains('final cameras ='));
    expect(initialization, contains('final controller = CameraController('));
    expect(initialization, contains('await controller.dispose();'));
  });
}
