/// Optional facts supplied by reverse geocoding or a nearby-place provider.
/// These describe the selected place, never the user's language or device region.
enum CameraPlaceKind {
  unknown,
  city,
  coast,
  desert,
  park,
  cafe,
  museum,
  market,
  mountain,
  airport,
}

class CameraPlaceIdentity {
  const CameraPlaceIdentity({
    this.locality = '',
    this.countryCode = '',
    this.kind = CameraPlaceKind.unknown,
  });
  final String locality;
  final String countryCode;
  final CameraPlaceKind kind;
  String get cacheKey =>
      '${locality.trim().toLowerCase()}|${countryCode.trim().toUpperCase()}|${kind.name}';
  @override
  bool operator ==(Object other) =>
      other is CameraPlaceIdentity && cacheKey == other.cacheKey;
  @override
  int get hashCode => cacheKey.hashCode;
}

enum PlaceMotif {
  neighborhood,
  kuwaitTowers,
  redFort,
  burj,
  eiffel,
  towerBridge,
  operaHouse,
  coast,
  desert,
  park,
  cafe,
  museum,
  market,
  mountain,
  airport,
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[\u064B-\u065F\u0670\u0640]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]+'), ' ')
    .trim();

/// Curated landmarks use city identity, not a substring in a business name.
/// Unknown areas receive an abstract neighborhood map, not an invented landmark.
PlaceMotif resolvePlaceMotif(
  String name, [
  CameraPlaceIdentity identity = const CameraPlaceIdentity(),
]) {
  final n = _normalize(name);
  final locality = _normalize(identity.locality);
  final country = identity.countryCode.trim().toUpperCase();
  bool word(List<String> terms) =>
      terms.any((term) => ' $n '.contains(' ${_normalize(term)} '));
  if (identity.kind != CameraPlaceKind.unknown &&
      identity.kind != CameraPlaceKind.city) {
    return switch (identity.kind) {
      CameraPlaceKind.coast => PlaceMotif.coast,
      CameraPlaceKind.desert => PlaceMotif.desert,
      CameraPlaceKind.park => PlaceMotif.park,
      CameraPlaceKind.cafe => PlaceMotif.cafe,
      CameraPlaceKind.museum => PlaceMotif.museum,
      CameraPlaceKind.market => PlaceMotif.market,
      CameraPlaceKind.mountain => PlaceMotif.mountain,
      CameraPlaceKind.airport => PlaceMotif.airport,
      _ => PlaceMotif.neighborhood,
    };
  }
  if (word(['cafe', 'café', 'coffee', 'مقهى', 'كافيه', 'قهوة'])) {
    return PlaceMotif.cafe;
  }
  if (word(['beach', 'coast', 'marina', 'شاطئ', 'شاطي', 'ساحل', 'مارينا'])) {
    return PlaceMotif.coast;
  }
  if (word(['park', 'garden', 'حديقة', 'منتزه'])) {
    return PlaceMotif.park;
  }
  if (word(['museum', 'متحف'])) {
    return PlaceMotif.museum;
  }
  if (word(['market', 'souq', 'souk', 'سوق'])) {
    return PlaceMotif.market;
  }
  if (word(['airport', 'مطار'])) {
    return PlaceMotif.airport;
  }
  if (word(['desert', 'dunes', 'صحراء', 'كثبان'])) {
    return PlaceMotif.desert;
  }
  if (word(['mountain', 'جبل', 'جبال'])) {
    return PlaceMotif.mountain;
  }
  bool city(String code, List<String> aliases) =>
      (country.isEmpty || country == code) &&
      aliases.map(_normalize).any((alias) => n == alias || locality == alias);
  if (city('KW', [
    'Al Jahra',
    'Jahra',
    'Al Jahra Governorate',
    'Jahra Governorate',
    'محافظة الجهراء',
    'الجهراء',
    'القصر الاحمر',
    'Red Palace',
  ])) {
    return PlaceMotif.redFort;
  }
  if (city('KW', [
    'Kuwait City',
    'Kuwait',
    'مدينة الكويت',
    'الكويت',
    'ابراج الكويت',
    'Kuwait Towers',
  ])) {
    return PlaceMotif.kuwaitTowers;
  }
  if (city('AE', ['Dubai', 'دبي', 'Burj Khalifa', 'برج خليفة'])) {
    return PlaceMotif.burj;
  }
  if (city('FR', ['Paris', 'باريس', 'Eiffel Tower', 'برج ايفل'])) {
    return PlaceMotif.eiffel;
  }
  if (city('GB', ['London', 'لندن', 'Tower Bridge', 'جسر البرج'])) {
    return PlaceMotif.towerBridge;
  }
  if (city('AU', [
    'Sydney',
    'سيدني',
    'Sydney Opera House',
    'دار اوبرا سيدني',
  ])) {
    return PlaceMotif.operaHouse;
  }
  return PlaceMotif.neighborhood;
}
