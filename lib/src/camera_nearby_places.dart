/// A real nearby venue. Names are never generated or inferred from coordinates.
class CameraNearbyPlace {
  const CameraNearbyPlace({
    required this.id,
    required this.name,
    required this.distanceMeters,
  });
  final String id;
  final String name;
  final double distanceMeters;
}

typedef CameraNearbyResolver =
    Future<List<CameraNearbyPlace>> Function(
      double latitude,
      double longitude,
      String localeIdentifier,
    );

/// Validate provider results without inventing place labels or distances.
List<CameraNearbyPlace> normalizeNearbyCameraPlaces(
  Iterable<CameraNearbyPlace> input,
) {
  final places = input
      .where(
        (p) =>
            p.id.isNotEmpty &&
            p.name.trim().isNotEmpty &&
            p.distanceMeters.isFinite &&
            p.distanceMeters >= 0 &&
            p.distanceMeters <= 3000,
      )
      .toList();
  places.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  final ids = <String>{};
  return places
      .where((p) => ids.add(p.id))
      .take(30)
      .map(
        (p) => CameraNearbyPlace(
          id: p.id,
          name: String.fromCharCodes(p.name.trim().runes.take(64)),
          distanceMeters: p.distanceMeters,
        ),
      )
      .toList(growable: false);
}
