import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Media type for story result
enum StoryMediaType {
  image,
  video,
}

/// Share target type
enum ShareTarget {
  story,
  closeFriends,
}

/// Close friend model for sharing stories
class CloseFriend {
  /// Unique identifier
  final String id;

  /// Display name
  final String name;

  /// Profile image URL (optional)
  final String? avatarUrl;

  /// Custom data for your app
  final Map<String, dynamic>? extra;

  const CloseFriend({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.extra,
  });

  /// Create from JSON
  factory CloseFriend.fromJson(Map<String, dynamic> json) {
    return CloseFriend(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (extra != null) 'extra': extra,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloseFriend && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CloseFriend(id: $id, name: $name)';
}

/// Result returned when story is shared
class StoryShareResult {
  /// The saved story file
  final StoryResult story;

  /// Share target (story or close friends)
  final ShareTarget shareTarget;

  /// Selected close friends (only if shareTarget is closeFriends)
  final List<CloseFriend> selectedFriends;

  const StoryShareResult({
    required this.story,
    required this.shareTarget,
    this.selectedFriends = const [],
  });

  /// Whether shared to public story
  bool get isPublicStory => shareTarget == ShareTarget.story;

  /// Whether shared to close friends
  bool get isCloseFriends => shareTarget == ShareTarget.closeFriends;

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'story': story.toJson(),
      'shareTarget': shareTarget == ShareTarget.story ? 'story' : 'closeFriends',
      'selectedFriends': selectedFriends.map((f) => f.toJson()).toList(),
    };
  }

  @override
  String toString() {
    return 'StoryShareResult(shareTarget: $shareTarget, friends: ${selectedFriends.length})';
  }
}

/// Result model returned when a story is completed
/// Contains file info and helper methods for API uploads
class StoryResult {
  /// Full file path: /data/user/0/.../story_123.png
  final String filePath;

  /// File name only: story_123.png
  final String fileName;

  /// Media type: image or video
  final StoryMediaType mediaType;

  /// File size in bytes
  final int fileSize;

  /// Creation timestamp
  final DateTime createdAt;

  /// Image/video width in pixels
  final int? width;

  /// Image/video height in pixels
  final int? height;

  /// Duration in milliseconds (for video only)
  final int? durationMs;

  const StoryResult({
    required this.filePath,
    required this.fileName,
    required this.mediaType,
    required this.fileSize,
    required this.createdAt,
    this.width,
    this.height,
    this.durationMs,
  });

  /// Get the File object
  File get file => File(filePath);

  /// Check if file exists
  bool get exists => file.existsSync();

  /// Get file bytes (sync)
  Uint8List get bytes => file.readAsBytesSync();

  /// Get file bytes (async)
  Future<Uint8List> readBytes() => file.readAsBytes();

  /// Get base64 encoded string (for API uploads)
  String get base64 => base64Encode(bytes);

  /// Get base64 encoded string (async)
  Future<String> readBase64() async {
    final data = await file.readAsBytes();
    return base64Encode(data);
  }

  /// Get MIME type
  String get mimeType {
    if (mediaType == StoryMediaType.video) {
      if (fileName.endsWith('.mp4')) return 'video/mp4';
      if (fileName.endsWith('.mov')) return 'video/quicktime';
      return 'video/mp4';
    } else {
      if (fileName.endsWith('.png')) return 'image/png';
      if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg')) return 'image/jpeg';
      return 'image/png';
    }
  }

  /// Get file extension
  String get extension {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  /// Get human-readable file size
  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Get duration formatted (for video)
  String? get durationFormatted {
    if (durationMs == null) return null;
    final seconds = durationMs! ~/ 1000;
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  /// Convert to JSON map (for API uploads)
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'fileName': fileName,
      'mediaType': mediaType == StoryMediaType.image ? 'image' : 'video',
      'mimeType': mimeType,
      'fileSize': fileSize,
      'fileSizeFormatted': fileSizeFormatted,
      'createdAt': createdAt.toIso8601String(),
      'createdAtTimestamp': createdAt.millisecondsSinceEpoch,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'durationMs': durationMs,
      if (durationMs != null) 'durationFormatted': durationFormatted,
    };
  }

  /// Create from file path
  static Future<StoryResult> fromFile(
    String filePath, {
    StoryMediaType? mediaType,
    int? width,
    int? height,
    int? durationMs,
  }) async {
    final file = File(filePath);
    final stat = await file.stat();
    final fileName = filePath.split('/').last;

    // Auto-detect media type from extension if not provided
    final detectedType = mediaType ?? _detectMediaType(fileName);

    return StoryResult(
      filePath: filePath,
      fileName: fileName,
      mediaType: detectedType,
      fileSize: stat.size,
      createdAt: stat.modified,
      width: width,
      height: height,
      durationMs: durationMs,
    );
  }

  /// Detect media type from file name
  static StoryMediaType _detectMediaType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    if (['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'].contains(ext)) {
      return StoryMediaType.video;
    }
    return StoryMediaType.image;
  }

  @override
  String toString() {
    return 'StoryResult(filePath: $filePath, mediaType: $mediaType, fileSize: $fileSizeFormatted)';
  }
}
