# Camera 1.8 verification

The camera and photo editor use a portrait story canvas rather than stretching to each screen's available height. This keeps baked effect frames within the displayed capture.

Android CameraX output mirror mode is off. Its overlay frame `isMirroring` metadata must not be treated as an additional output mirror. Authored text compensates only for the requested Flutter selfie presentation mirror. iOS already uses that contract. Hosts explicitly passing `mirrorFrontCameraPreview: false` retain their explicit choice; Niero's local integration now requests `true` and prewarms the front camera.

The effects carousel retains one GlobalKey across subtree movement; scroll reads require a single attached position. Regression checks repeatedly tap focus and open/close controls in a 320px Arabic camera layout.

Nearby venue results come from `StoryEditorConfig.nearbyPlacesResolver`, supplied by the host's existing places backend. Niero is wired to its authenticated map service, with its existing category-search fallback. The plugin does not contact a new public places provider. Without a host venue resolver, Places continues to use native geocoding for the current city. Venue requests are lazy, deduplicated and cached per locale for ten minutes; invalid distances and duplicate IDs are removed. Selecting a venue never fabricates a name, and styles are remembered for the camera session.

Scene source dimensions and generation provenance are documented in `assets/ar/backgrounds/README.md`. Both scenes are smaller than the requested native 4K resolution.

Device screenshots and captures remain in ignored local build directories and are not published.
