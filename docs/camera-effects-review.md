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

## Galaxy S23 Ultra follow-up — 7 September 2026

The user reported 2–5 seconds of low FPS at startup, subtle smoothing,
half-width/mirrored place artwork, mirrored carousel text, poor glasses quality,
and an obstructive effects sheet. This update addresses those code paths.

| Report | Implementation |
| --- | --- |
| Startup stutter | Android uses a zero-depth overlay queue, skips canvas synchronization with no artwork, and attaches analysis only for tracked effects. Flutter loads its shader on first effect interaction, uses static material swatches instead of multiple live camera textures, defers gallery work and avoids clearing the gallery cache at startup. |
| Half-screen/mirrored graphics | Fixed the Android display viewport independently of mutable sensor dimensions; disabled CameraX's implicit preview mirror and compensated artwork using the actual frame transform. iOS normalizes portrait dimensions and photo EXIF orientation. |
| Unnoticeable beauty | Increased bilateral smoothing radius and strength. Added independent tracked Eyes and Contour controls with bounded inverse warps. |
| Obstructive controls | Effects are opened from the side rail in a 192-pixel inline tray above the shutter. Back closes the tray first; unrelated rail tools collapse while it is open. |
| Manual location | Choosing Places automatically requests the current city with permission-aware position/reverse-geocoding. No editable location field. Successful city names are cached in memory for the open camera session. |
| Poor glasses | Removed the glasses renderer and bundled mesh assets; legacy public identifiers remain for source compatibility but are unavailable. |

## Available effects

- Independent color looks with intensity, skin smoothing, eye enlargement and
  face contour adjustment. Smoothing uses a skin-color mask and can also affect
  similarly colored surfaces; it does not whiten the skin.
- Five single-face artworks: Stardust, Heart Halo, Sun Freckles, Neon Contour,
  and animated Butterflies. Neon follows detected face-oval landmarks on both
  platforms; the iOS Vision path uses its detected open jaw contour. These are
  landmark effects, not a shared dense 3D face mesh.
- Postcard, Editorial and Passport city frames; bounded Unicode city names,
  native Arabic shaping, localized dates and natural text direction.
- Looks, beauty, one face lens and one place design can be stacked.

Color and beauty preview processing stays on the GPU. Only four normalized eye
coordinates cross the native channel at up to 15Hz when tracking is active.
Face-shape samples expire after 250ms or explicit tracking loss. Photos freeze
their capture pose (iOS re-detects the full-resolution photo); video samples are
relative to native recording start. iOS supplies its exact first writer sample;
Android supplies CameraX's Start callback, which may differ by a few frames from
the first encoded sample. Moving-face output alignment needs a device check.

Shape is baked once before the editor or boomerang reversal so it survives every
output route. This adds an export pass after shaped video recording; it is not
native live-recording pixel deformation. Later editing applies color/smoothing
and stickers. Native artwork is already baked into the camera frames.

## Integration and Arabic

Open `StoryCameraScreen` and tap the sparkle icon on the side rail. The four
tabs are Looks, Beauty, Lenses and Places. Reset clears every layer. No service
key or remote lens download is needed for the bundled artwork.

Android requires API24+, iOS15+, and Flutter GPU filters require Impeller.
Unsupported renderers do not offer working-looking beauty controls. Hosts must
enable Flutter localizations (including Arabic), Android RTL support and native
permission descriptions. The plugin provides `StoryEditorStrings.arabic()`;
explicit host translations remain under host control.

Android location permissions are in the plugin manifest. iOS hosts need:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Show your current city when you select a camera place frame.</string>
```

Location is requested only when Places is selected. Denial, disabled services,
timeout and geocoder failure display a localized retry message; they never
substitute a made-up location. Coordinates are discarded after geocoding.
Tabs, controls, percentages, place labels and navigation follow Arabic/RTL.

## Validation and remaining limits

Local validation: 83 Flutter tests and 41 Android JVM tests pass; Dart analysis
reports no issues. Checks include actual shader
pixel rendering, small Arabic camera-layout tests, Android JVM tests and a
release APK build. Results are recorded in `build/s23-flutter-tests.log`,
`build/s23-native-tests.log` and `build/s23-release.log`.
The expanded 24-test iOS suite covers orientation, pixel warp, artwork, recording and
pose timelines; it cannot be run in this Windows workspace. Use the repository's
macOS/Xcode quality gate before shipping iOS changes.

The user will test the rebuilt APK. No new device FPS, startup, thermal or
tracking-quality measurements are claimed by desktop tests. Check:

1. Cold and warm startup; front/back switches with effects off and stacked.
2. Readable place/date text in preview, photo and video, with either mirror mode.
3. Smooth/Eyes/Contour at 0%, 50% and 100%, moving faces, face loss and reacquisition.
4. Shaped video and boomerang output, audio, Arabic long city names, denied
   location, background/resume and repeated camera entry.

That 1.6.0 review did not cover segmentation or expression-triggered effects.
Version 1.7.0 adds both below. The maintained [capability comparison](camera-capability-matrix.md)
separates implemented capture workflows from remaining camera/creation capabilities
and physical-device acceptance; no visual-quality multiplier is inferred from builds.

## Independent engine and UX follow-up — 8 September 2026

- True on-device person segmentation: the bundled, pinned Google Selfie Segmenter
  on Android and Vision person segmentation on iOS. Studio, Sunset, Night and
  real background blur composite behind the person before lens artwork. No model
  download or segmentation initialization occurs with background effects off.
- Inference uses a dedicated worker and drops work while busy. Android masks
  expire after 250 ms; iOS masks after 350 ms. Camera/style changes invalidate
  old results. iOS full-resolution photos get a fresh accurate Vision mask after
  EXIF orientation normalization; Android uses the shared CameraX capture overlay.
- Hearts react to a measured mouth opening; butterflies react to a wink.
  Independent normalized face geometry drives these effects, with hysteresis,
  cooldown and missing-face resets. The reactions are part of recorded pixels.
- Native focus metering, device zoom ranges, exposure compensation and torch
  lifecycle now back the camera controls. Flutter fits the upright camera crop
  without stretching it and reverses only the axis clipped by cover fitting when
  mapping taps. Native code maps the normalized point to the sensor.
- Tap/hold capture, slide to lock, double-tap camera switching and direct taps on
  look bubbles use familiar camera interactions. Effects remain directly on the
  side; More reveals labeled extra modes. Small-screen Arabic rendering exposed
  and eliminated rail overflow and overlapping filter names.
- Lens favorites persist locally. The panel remembers category and scroll
  position; category reset offers Undo. Location and background preparation
  provide localized status and retry guidance.
- Editor history now tracks actual edits chronologically with redo. Mute, smart
  stickers and media scale/translation are preserved in saved video. Sharing
  waits for an existing finished file; export failure retains the edits. Unsaved
  capture protection, video-load retry and Arabic labels complete the flow.

Local release checks: Flutter analyzer clean, all 108 Flutter tests passed,
and all 61 Android JVM tests passed. The 41 iOS tests are linked into the
macOS CI host, including the new segmentation and expression suites.
The reproducible native and Flutter checks are in the repository's test suites.
The release APK and visual-check captures remain in ignored `build/` output.
Device startup/FPS, moving mask boundaries, camera focus/torch behavior and
preview-versus-recorded quality remain the user's agreed physical-device checks.

## API references checked

- [CameraX Frame orientation and cropping](https://developer.android.com/reference/androidx/camera/effects/Frame)
- [Flutter GPU image-filter requirements](https://api.flutter.dev/flutter/dart-ui/ImageFilter/ImageFilter.shader.html)
- [Snap Camera Kit scope](https://developers.snap.com/camera-kit/getting-started/what-is-camera-kit)
- [Camera Kit integration requirements](https://developers.snap.com/camera-kit/integrate-sdk/ios/ios-configuration)

## Repository hygiene

The local `example/` app and APK/AAB/IPA outputs are excluded from Git. CI creates
a disposable integration host using `tool/ci/create_host.py`; it refuses to
overwrite the existing local app. Only reusable source, assets, docs and tests
are versioned. Java's local socket workaround for this Windows build uses
`JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=H:\story_editor_pro\build\java-tmp`;
consuming applications do not need that setting.
