# Camera effects review and implementation

Reviewed 5 September 2026. The working tree already contained substantial camera,
export, shader, and AR edits; those were reviewed and extended in place.

## Reference project

`H:/ShortVideo_1.3.1.5_20251211_114454_flutter/flutter/nvshortvideo` exposes a
Flutter control layer over Meishe's native SDK. In particular:

- `lib/src/video_config/config/nv_capture_config.dart` configures independent
  beauty, makeup, prop, matting, filter, speed and timer tools.
- `lib/src/video_config/config/nv_beauty_config.dart` distinguishes skin,
  shape, micro-shape and adjustment controls.
- Android `VideoEditPlugin.java` initializes `NvModuleManager`, its SDK license,
  and its models. iOS `VideoEditPlugin.swift` imports `NvShortVideoCore`.
- The advanced processing is in native frameworks and model assets; the Dart
  configuration is not itself an implementation of these effects.

The useful architecture is a native frame pipeline with independent effect
controls. The implementation here extends the existing CameraX/AVFoundation
and MediaPipe/Vision pipeline. It does not depend on the reference SDK's license,
frameworks, or remote material service.

## Findings corrected

| Finding in the existing working tree | Change |
| --- | --- |
| One carousel choice couples the color look and native lens | Added an Effects panel with independent Looks, Beauty, Lenses and Places controls |
| The beauty uniform is present, but smoothing is disabled | Added adjustable eight-neighbor bilateral smoothing, preserving high-contrast edges and limiting processing through a skin-color mask |
| Native location decoration uses the locale's country | Place frames use explicitly entered names or a user-triggered position/reverse-geocoding request; locale is only for language/date formatting |
| Face tracking prepares after camera startup even when unused | Capability discovery follows the first frame; the model loads when a face lens is chosen |
| Asynchronous lens selection can race the shutter | Serialized effect commands; capture awaits applied settings and explicit face-model readiness |
| Android authored graphics ignore frame rotation | Artwork is composed in upright coordinates, then CameraX applies its sensor transform |
| Beauty needs to survive all output routes | Added the independent beauty value to photo callbacks, collage tiles, editor rendering, video export, boomerang and no-editor output |

## Available effects

- Existing color presets remain available with adjustable intensity.
- Beauty: Off, Natural (28%), Soft (50%), Polished (75%), and continuous smoothing.
  This is pixel-based skin smoothing, not facial reshaping or makeup segmentation.
  It does not lighten skin. The mask can also affect similarly colored surfaces.
- Tracked face artwork: Classic Glasses, Stardust (animated stars and cheek
  highlights), Heart Halo (animated hearts), and Sun Freckles.
- Place designs: Postcard, Editorial and Passport. Names are bounded to 64
  Unicode code points. Long names are fitted into the native design.
- Native time/date designs continue to work alongside tracked face artwork and
  place frames. Graphics are captured into the source media, not added only in
  the preview. Animation uses camera-frame timestamps.

Color grading and beauty share one Flutter GPU pass in the preview. The color
and smoothing calculations are carried into Android OpenGL and iOS Core Image
video export. Native artwork is composed before this pass. Each frame therefore
receives the same ordering: captured scene and native artwork, then pixel effects.
Photos remain full-resolution captures. iOS pools output buffers and caches
small face sprites and static location artwork; Android draws vectors onto its
existing CameraX overlay surface. Faces disappear when tracking is lost or stale.

## Integration

Open the existing `StoryCameraScreen`, then tap **Effects** above the shutter.
Select a look, a Beauty amount, a Lens and optionally a Place; each layer is
retained while editing the others. Reset clears all layers. No external service
key or runtime asset download is needed for the bundled face artwork.

Android location permissions are in the plugin manifest. An iOS host must include:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Show your city in a camera place frame when you choose Use my location.</string>
```

The included host has this entry. Location is never requested during camera
startup. Permission, disabled-service, timeout and geocoder failures leave manual
place entry available. Names and coordinates are not stored by these new controls.

The current native dependencies require Android API 24+ and iOS 15+.
Flutter GPU image filters require Impeller; unsupported renderers do not expose
the Beauty control. Camera initialization retains the existing native prewarm,
first-frame reporting, session reuse and Flutter-camera fallback.

## Verification and limits

Local validation completed: Flutter analyzer reports no issues; all 72 Flutter
tests and 34 Android JVM tests pass. Android debug and release APK builds succeed. The
actual effects panel was rendered for visual QA, including its selected states. Full build/test results are recorded in `build/effects-tests.log`
and `build/effects-android-build.log`; release build output is in
`build/effects-android-release.log`. The iOS test suite includes stacked lens
validation and location-only operation without face preparation. iOS compilation
and tests require the existing macOS/Xcode CI job or a Mac; this Windows workspace
cannot execute them. Device testing is deferred to the user; no physical camera was tested during development.

Before release, verify on physical Android and iPhone hardware:

1. Cold/warm camera first-frame time, lens preparation time, sustained frame rate,
   thermal behavior and memory with all layers enabled.
2. Front/back camera switching and mirrored/unmirrored text in preview, full-size
   photos and recorded video; test portrait capture and device rotation.
3. Face loss/reacquisition, different skin tones and lighting, and long Arabic
   and Latin place names. Check the captured face-art position as well as preview.
4. Video, collage, boomerang, editor and direct callback exports; location denial;
   navigation, background/resume and repeated opening of the camera.

This does **not** establish 90% Snapchat capability parity or a measured 10x
visual/performance improvement. Current artwork tracks one face. Dense face-mesh
makeup, facial reshaping, expression triggers, segmentation/background replacement,
multi-face AR, world tracking and Snapchat's lens catalog are not implemented.
Those are substantive remaining capabilities, not supplied by a carousel or by
copying the reference project's Dart configuration.

## API references checked

- [CameraX Frame orientation and cropping](https://developer.android.com/reference/androidx/camera/effects/Frame)
- [Flutter GPU image-filter requirements](https://api.flutter.dev/flutter/dart-ui/ImageFilter/ImageFilter.shader.html)
- [Snap Camera Kit scope](https://developers.snap.com/camera-kit/getting-started/what-is-camera-kit)
- [Camera Kit integration requirements](https://developers.snap.com/camera-kit/integrate-sdk/ios/ios-configuration)

## Arabic and RTL follow-up

- The host now enables Flutter's Arabic Material/Widgets/Cupertino localizations,
  so Arabic device language selects Arabic text and RTL layout. Android declares
  RTL support. The iOS project registers Arabic and bundles Arabic camera,
  microphone, library and location permission descriptions.
- Added `StoryEditorStrings.arabic()` for camera, settings, editor and filter
  labels. The default configuration follows Arabic automatically; explicit host
  translations remain under host control. Effect status/error labels are localized.
- Tabs, chips, slider direction, input caret and leading alignment follow RTL.
  Percentages use `intl` locale data, including bidi marks. No Latin letter
  spacing is forced on the Arabic heading. Tests use a real Arabic locale rather
  than English text inside a manually reversed layout.
- Location lookup requests the current app locale. Manual names preserve Arabic
  diacritics and mixed Arabic/Latin text. Editorial place frames align to the
  right for Arabic. Native labels and dates use the selected language; switching
  locale with the camera open reapplies native composition settings.
- Android uses cached `StaticLayout` instances with first-strong bidirectional
  resolution and font padding for Arabic marks. iOS uses system Arabic glyphs
  and natural paragraph direction. Text direction remains independent of the
  selfie camera's mirroring transform.

Follow-up verification: 72 Flutter tests and 34 Android JVM tests pass. Arabic
panel screenshots were rendered and visually reviewed in `build/qa/effects-ar-*.png`.
Coverage includes 320-pixel-wide RTL layout with 1.3x text, mixed Arabic/English
place input with an open keyboard, locale switching without losing layers,
localized geocoding, and preserving custom host copy. Logs are in
`build/effects-rtl-tests.log`, `build/effects-rtl-native-tests.log` and
`build/effects-rtl-release.log`. Native font shaping in actual captured media
still needs the user's Android/iPhone check; iOS cannot be compiled on this host.

References: [Flutter internationalization](https://docs.flutter.dev/ui/internationalization)
and [Android StaticLayout text direction and font padding](https://developer.android.com/reference/android/text/StaticLayout.Builder).

On this Windows host, Java's local socket initialization initially failed.
Using `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=H:\story_editor_pro\build\java-tmp`
for the build process resolved it. This is a local build-environment setting,
not a change required in shipped apps.
