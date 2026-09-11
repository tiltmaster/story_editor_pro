# Place artwork

The camera renders one transparent PNG for a selected place, style, variant,
language and date. Android Canvas and iOS Core Image composite that same PNG
into preview, photos and video. Moving, scaling and rotating send only the
transform; they do not regenerate the image or restart face tracking.

## Selection and coverage

Provider category takes priority, followed by recognizable English/Arabic venue
terms. Thus “Paris Cafe” receives coffee artwork. Otherwise, exact city aliases
or the provider's locality select a curated landmark. A conflicting ISO country
code prevents an incorrect city match (for example Paris, US). The device's
locale country is never used as location evidence. Unknown areas receive an
abstract neighborhood map. This is a curated vector system, not an AI model
claiming to recognize every landmark worldwide.

There are six landmark motifs and nine venue/area motifs. Each can appear in
three stamp treatments, three boarding-pass layouts and three location badges.
The illustrations are original vector drawings inspired by these local forms:

| Area | Motif | Reference |
| --- | --- | --- |
| Al Jahra | Red Fort walls and towers | [Jahra Governorate](https://jahra.gov.kw/%D8%B9%D9%86-%D9%85%D8%AD%D8%A7%D9%81%D8%B8%D8%A9-%D8%A7%D9%84%D8%AC%D9%87%D8%B1%D8%A7%D8%A1/%D9%84%D9%85%D8%AD%D8%A9-%D8%AA%D8%A7%D8%B1%D9%8A%D8%AE%D9%8A%D8%A9/) |
| Kuwait City | Kuwait Towers | [Kuwait Towers](https://www.restaurants.kuwaittowers.com/) |
| Dubai | Stepped Burj Khalifa silhouette | [Visit Dubai](https://www.visitdubai.com/en/places-to-visit/burj-khalifa) |
| Paris | Eiffel Tower lattice | [Eiffel Tower](https://www.toureiffel.paris/en/the-monument) |
| London | Tower Bridge | [Visit London](https://www.visitlondon.com/things-to-do/place/3901803-tower-bridge) |
| Sydney | Opera House roof shells | [Sydney Opera House](https://www.sydneyoperahouse.com/our-story/the-spherical-solution) |

Additional motifs: sailboat/coast, dunes, trees/park, coffee, museum colonnade,
market awning, mountain peaks, airplane and neighborhood map. These are category
illustrations, not claims that a particular building exists at the venue.
No tourism photography, airline logos, fabricated flight numbers or external
image downloads are used. Ticket stripes are decorative, not scannable codes.

## Provider integration

Existing `nearbyPlacesResolver` callbacks continue to work unchanged. For more
reliable artwork, carry verified metadata from the existing venue provider:

```dart
CameraNearbyPlace(
  id: venue.id,
  name: venue.localizedName,
  distanceMeters: venue.distanceMeters,
  identity: CameraPlaceIdentity(
    locality: venue.city,
    countryCode: venue.isoCountryCode,
    kind: CameraPlaceKind.cafe, // Map the provider's category, not a guess.
  ),
)
```

Default city reverse geocoding preserves locality and ISO country in the same
request that resolves the display name. Coordinates are not retained in the
artwork identity. Venue normalization preserves identity while validating IDs,
names and distances. Legacy injected string-only city resolvers use exact name
and venue-term matching.

## Transform contract

The canonical frame is upright 1080 × 1920. Rotation is clockwise radians around
the sticker center. Flutter clamps scale and position using the rotated bounding
box, with margins on all sides. Android rotates before final mirror compensation;
iOS negates the angle for Core Image's bottom-left origin, then compensates for
the mirror. Arabic typography is rasterized upright and is never independently
flipped. Style changes retain position, angle and scale subject to the new
artwork's frame bounds.

Tap the sticker to cycle styles. Drag to move. Pinch and twist to resize and
rotate. Camera zoom/swipe handling and sticker gestures remain sibling hit targets
so the camera cannot intercept a sticker drag.
