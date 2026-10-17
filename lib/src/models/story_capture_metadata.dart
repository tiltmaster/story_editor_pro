/// Semantic descriptors for pixels already rendered into an exported capture.
/// Device coordinates and local/remote media paths never enter public JSON.
class StoryCapturePlace {
  const StoryCapturePlace({
    required this.source,
    required this.label,
    this.id,
    this.latitude,
    this.longitude,
    this.legacyPlaceId,
  });
  final String source;
  final String label;
  final String? id;
  final double? latitude;
  final double? longitude;

  /// Host-owned legacy place identity, distinct from an external POI ID.
  final String? legacyPlaceId;
  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;
  Map<String, Object> toJson() => {
    'source': source,
    'label': _bounded(label, 120),
    if (id?.trim().isNotEmpty == true) 'id': _bounded(id!, 160),
  };
}

class StoryCaptureSticker {
  const StoryCaptureSticker({required this.type, this.variant, this.value});
  final String type;
  final int? variant;
  final String? value;
  Map<String, Object> toJson() => {
    'type': type,
    if (variant != null) 'variant': variant!.clamp(0, 20),
    if (value?.trim().isNotEmpty == true &&
        type != 'image' &&
        type != 'drawing')
      'value': _bounded(value!, 160),
  };
}

class StoryCaptureMetadata {
  StoryCaptureMetadata({
    this.place,
    Iterable<StoryCaptureSticker> stickers = const [],
  }) : stickers = List.unmodifiable(stickers.take(32));
  final StoryCapturePlace? place;
  final List<StoryCaptureSticker> stickers;
  Map<String, Object> toJson({bool? isPrivate}) => {
    'version': 1,
    if (isPrivate != null) 'audience': isPrivate ? 'connections' : 'public',
    if (place != null && place!.label.trim().isNotEmpty)
      'place': place!.toJson(),
    'stickers': stickers.map((item) => item.toJson()).toList(growable: false),
  };
}

String _bounded(String value, int length) =>
    String.fromCharCodes(value.trim().runes.take(length));
