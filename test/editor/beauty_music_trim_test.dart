import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  group('authored camera looks', () {
    test('preserves legacy positions and appends production presets', () {
      expect(StoryEditorFilters.presets.first.id, StoryEditorFilters.none);
      expect(
        StoryEditorFilters.presets
            .skip(26)
            .map((preset) => preset.id)
            .toList(),
        ['softbeauty', 'cleanglow', 'vhs1993', 'kuwaitgold'],
      );
    });

    test('beauty and VHS effects are scoped to their authored presets', () {
      expect(StoryEditorFilters.beautyStrength('softbeauty', 1), closeTo(0.42, 0.001));
      expect(StoryEditorFilters.beautyStrength('none', 1), 0);
      expect(StoryEditorFilters.vhsStrength('vhs1993', 1), closeTo(0.72, 0.001));
      expect(StoryEditorFilters.addsVhsTimestamp('vhs1993'), isTrue);
      expect(StoryEditorFilters.addsVhsTimestamp('kuwaitgold'), isFalse);
    });
  });

  test('music result serializes metadata without playback credentials', () {
    final result = StoryResult(
      filePath: '/private/story.mp4',
      fileName: 'story.mp4',
      mediaType: StoryMediaType.video,
      fileSize: 128,
      createdAt: DateTime.utc(2026),
      music: const StoryEditorMusicSelection(
        id: 'track-1',
        title: 'Safe title',
        artist: 'Artist',
        startMs: 1500,
        durationMs: 12000,
      ),
    );

    final json = result.toJson();
    expect(json['music'], {
      'id': 'track-1',
      'title': 'Safe title',
      'artist': 'Artist',
      'startMs': 1500,
      'durationMs': 12000,
    });
    expect(json.toString(), isNot(contains('url')));
    expect(json.toString(), isNot(contains('token')));
  });

  group('video trim validation', () {
    test('accepts full and bounded ranges', () {
      expect(() => VideoOverlayExportService.validateTrimRange(0, 0), returnsNormally);
      expect(() => VideoOverlayExportService.validateTrimRange(250, 5000), returnsNormally);
    });

    test('rejects negative and reversed ranges before native export', () {
      expect(() => VideoOverlayExportService.validateTrimRange(-1, 1000), throwsArgumentError);
      expect(() => VideoOverlayExportService.validateTrimRange(1000, 1000), throwsArgumentError);
      expect(() => VideoOverlayExportService.validateTrimRange(2000, 1000), throwsArgumentError);
    });
  });
}
