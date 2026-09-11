import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/src/place_identity.dart';
import 'package:story_editor_pro/src/camera_nearby_places.dart';

void main() {
  test('landmarks use actual city and country, including Arabic aliases', () {
    expect(resolvePlaceMotif('Al Jahra'), PlaceMotif.redFort);
    expect(resolvePlaceMotif('الجَهْرَاء'), PlaceMotif.redFort);
    expect(resolvePlaceMotif('مدينة الكويت'), PlaceMotif.kuwaitTowers);
    expect(resolvePlaceMotif('دبي'), PlaceMotif.burj);
    expect(resolvePlaceMotif('Paris'), PlaceMotif.eiffel);
    expect(resolvePlaceMotif('London'), PlaceMotif.towerBridge);
    expect(resolvePlaceMotif('Sydney'), PlaceMotif.operaHouse);
    expect(
      resolvePlaceMotif('Paris', const CameraPlaceIdentity(countryCode: 'US')),
      PlaceMotif.neighborhood,
    );
    expect(resolvePlaceMotif('London Road'), PlaceMotif.neighborhood);
    expect(
      resolvePlaceMotif(
        'Unknown Quarter',
        const CameraPlaceIdentity(locality: 'Al Jahra', countryCode: 'KW'),
      ),
      PlaceMotif.redFort,
    );
  });
  test('venue identity wins over city names and locality', () {
    expect(resolvePlaceMotif('Paris Cafe'), PlaceMotif.cafe);
    expect(resolvePlaceMotif('قهوة باريس'), PlaceMotif.cafe);
    expect(resolvePlaceMotif('Jahra Beach'), PlaceMotif.coast);
    expect(
      resolvePlaceMotif(
        'Hidden Garden',
        const CameraPlaceIdentity(
          kind: CameraPlaceKind.museum,
          locality: 'Paris',
          countryCode: 'FR',
        ),
      ),
      PlaceMotif.museum,
    );
    expect(resolvePlaceMotif('حديقة الشهيد'), PlaceMotif.park);
    expect(resolvePlaceMotif('سوق المباركية'), PlaceMotif.market);
    expect(resolvePlaceMotif('مطار الكويت'), PlaceMotif.airport);
    expect(resolvePlaceMotif('أبراج مجهولة'), PlaceMotif.neighborhood);
  });
  test(
    'nearby normalization retains provider identity without retaining coordinates',
    () {
      const identity = CameraPlaceIdentity(
        locality: 'Kuwait City',
        countryCode: 'KW',
        kind: CameraPlaceKind.cafe,
      );
      final values = normalizeNearbyCameraPlaces([
        const CameraNearbyPlace(
          id: 'a',
          name: '  Coffee  ',
          distanceMeters: 12,
          identity: identity,
        ),
      ]);
      expect(values.single.name, 'Coffee');
      expect(values.single.identity, identity);
      expect(
        resolvePlaceMotif(values.single.name, values.single.identity),
        PlaceMotif.cafe,
      );
    },
  );
}
