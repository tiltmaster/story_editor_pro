import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  group('StoryEditorConfig', () {
    test('default config should have correct values', () {
      const config = StoryEditorConfig();

      expect(config.maxVideoRecordingSeconds, 60);
      expect(config.maxBoomerangSeconds, 4);
      expect(config.defaultHandsFreeDelay, 3);
      expect(config.handsFreeDelayOptions, [3, 5, 10, 15]);
      expect(config.defaultGradientBalance, 0.5);
    });

    test('default strings should be in English', () {
      const strings = StoryEditorStrings();

      expect(strings.cameraStory, 'Story');
      expect(strings.editorShare, 'Share');
      expect(strings.editorCloseFriends, 'Close Friends');
    });

    test('default theme should have correct primary color', () {
      const theme = StoryEditorTheme();

      expect(theme.primaryColor, const Color(0xFFC13584));
      expect(theme.backgroundColor, const Color(0xFF121212));
    });
  });

  group('CloseFriend', () {
    test('should create with required fields', () {
      const friend = CloseFriend(
        id: '123',
        name: 'John Doe',
        avatarUrl: 'https://example.com/avatar.jpg',
      );

      expect(friend.id, '123');
      expect(friend.name, 'John Doe');
      expect(friend.avatarUrl, 'https://example.com/avatar.jpg');
    });

    test('avatarUrl should be optional', () {
      const friend = CloseFriend(id: '1', name: 'Test');

      expect(friend.avatarUrl, isNull);
    });
  });

  group('GradientPreset', () {
    test('isSolid should return true for same colors', () {
      final solid = GradientPreset(
        colors: [const Color(0xFF000000), const Color(0xFF000000)],
        name: 'Black',
      );

      expect(solid.isSolid, true);
    });

    test('isSolid should return false for different colors', () {
      final gradient = GradientPreset(
        colors: [const Color(0xFF667EEA), const Color(0xFF764BA2)],
        name: 'Purple',
      );

      expect(gradient.isSolid, false);
    });
  });
}
