## 1.7.0

- Added native person segmentation and compositing for Studio, Sunset, Night and background blur. Models run locally only when selected; preview, photos and recordings use the native compositor.
- Added measured mouth-open reactions to hearts and wink reactions to butterflies, with hysteresis and cooldown in native preview/photo/video artwork.
- Added real focus metering, exposure compensation, device zoom limits, photo flash and recording torch handling on Android/iOS.
- Added slide-to-lock recording, double-tap camera switching, directly tappable look bubbles, persistent lens favorites, remembered effects categories, and category reset with Undo.
- Corrected preview aspect fitting and touch-to-camera coordinate mapping; condensed the side rail and localized tool labels and recording guidance for Arabic/RTL.
- Added chronological editor undo/redo, unsaved capture protection and recoverable video loading errors.
- Fixed saved-video mute, smart stickers and media crop/position; Share now returns only after export succeeds and the file exists.

## 1.6.0

### Camera changes after Galaxy S23 Ultra feedback
- Replaced the modal effects sheet with a compact camera tray and side control; the shutter stays accessible. Arabic/RTL and small-screen layouts are covered by widget tests.
- Location styles fetch the current city with permission-aware lookup and session caching; removed manual location entry.
- Corrected Android viewport cropping and duplicate selfie mirroring, and iOS portrait/photo orientation and face-art scaling.
- Removed the Classic Glasses lens and added tracked neon contours and animated butterfly crowns.
- Added independent eye enlargement and face contour controls, strengthened skin smoothing, and baked tracked shaping into photos/video before editing or boomerang reversal.
- Removed the Android frame queue, unnecessary overlay synchronization, repeated live thumbnail textures, and startup gallery cache clearing. Face tracking loads on demand.
- Added native recording-start timestamps and bounded pose timelines; stale/lost faces stop reshaping.

Android builds and local checks are covered in the camera review. Real-device FPS and iOS execution still require hardware/Mac validation.

## 1.4.0

### Added
- Native Android and iOS camera pipeline for preview, photo, video, audio, and AR compositing
- On-device face-tracked Classic Glasses lens using MediaPipe and a project-owned Blender asset
- English and Arabic label support for the AR lens

### Fixed
- Filter slider geometry and snapping are locked to the existing interaction contract
- Timer status no longer changes the shutter circle anchor
- Native camera lifecycle resume falls back safely if reopening fails
- Interactive camera and editor controls no longer add unintended halo shadows

### Changed
- Native camera prewarming is adopted by the capture route without reopening the camera
- Startup telemetry exposes the 700ms warm-start target without collecting media data
- Location, time, date, battery, and speed smart tags have stronger visual hierarchy
- Camera and editor labels have improved English and Arabic coverage and RTL behavior
- Legacy package-camera prewarm getters are deprecated in favor of `takeNativePrepared`

---

## 1.0.3

### Added
- **Feature toggles** - Camera toolbar features can now be enabled/disabled via `StoryEditorConfig`:
  - `enableBoomerang` - Boomerang mode button
  - `enableCollage` - Collage/layout mode button
  - `enableHandsFree` - Hands-free recording button
  - `enableGradientTextEditor` - Gradient text editor button
  - All default to `true` for backward compatibility

---

## 1.0.2

### Added
- **Native video overlay export** - Video save/share now composites text, drawing, and image overlays directly onto video using native APIs (no FFmpeg dependency)
  - Android: OpenGL/EGL GPU pipeline with `MediaCodec` + `MediaMuxer`
  - iOS: `AVMutableComposition` + `AVVideoCompositionCoreAnimationTool` + `AVAssetExportSession`
- `VideoOverlayExportService` - Flutter-to-native bridge for video overlay compositing
- `TextureRenderer.kt` - Android EGL context and GLSL shader management for GPU-accelerated video processing
- `VideoOverlayProcessor.kt` / `VideoOverlayProcessor.swift` - Native video+overlay compositing pipelines
- Overlay-only `RepaintBoundary` (`_overlayRepaintKey`) for capturing transparent PNG overlays for video export
- Saving/Sharing progress indicator overlay with localized text (`editorSaving` / `editorSharing` strings)
- `_isSharing` flag to distinguish save vs share operations in UI
- Remove background button in text overlay color picker (reset to no background)

### Fixed
- **Text overlays not visible in exported images** - Text overlays are now rendered inside `RepaintBoundary` for correct capture during save/share
- **Drawing overlays rendering order** - Drawings now render on top of text and image overlays consistently
- **Text overlay padding consistency** - Unified padding (`horizontal: 28, vertical: 16`) across editor preview, export, and text input modes
- **Text overlay width calculation** - Consistent `maxWidth` calculation across all rendering contexts
- **Interactive overlays blocked during export** - All gesture layers disabled when `_isSaving = true` to prevent modifications during export
- **Drag-to-trash animation** - Export overlay now mirrors drag-to-trash scale/opacity animation for visual consistency

### Changed
- Adaptive `pixelRatio` for video overlay capture (clamped 1.0-2.0) instead of fixed 3.0 to optimize performance
- Audio preserved via single-pass passthrough muxing (no temp file, no double I/O)
- Overlay aspect ratio handling: cover+center crop to match video dimensions

---

## 1.0.1

### Added
- `shareButtonColor` config in `StoryEditorTheme` for customizing share button color
- `userProfileImageUrl` parameter for "Your Story" profile picture
- Close button (X) in text editing mode to return to editor
- All close friends are now selected by default in share modal

### Fixed
- Back button in drawing mode now returns to editor instead of camera
- Text editing close button now properly closes the modal

### Updated
- Updated all dependencies to latest versions:
  - `flutter_svg`: ^2.2.3
  - `video_player`: ^2.10.1
  - `path_provider`: ^2.1.5
  - `camera`: ^0.11.3
  - `permission_handler`: ^12.0.1
  - `photo_manager`: ^3.8.3
  - `shared_preferences`: ^2.5.4

---

## 1.0.0

Initial release with full feature set:

### Camera
- Photo and video capture
- Front/back camera switching
- Flash control (on/off/auto)
- Pinch-to-zoom support
- Gallery integration

### Recording Modes
- **Normal** - Tap for photo, hold for video
- **Boomerang** - Instagram-style looping videos
- **Collage** - Multi-photo layouts (2, 4, 6 grid)
- **Hands-Free** - Timer-based recording (3, 5, 10, 15 sec)

### Editor
- Drawing tools with 6 brush types (normal, marker, glow, chalk, arrow, eraser)
- Text overlays with customizable fonts and colors
- Gradient text editor for creating text-based stories
- Undo support for drawings

### Sharing
- Close friends selection UI
- Share to story or close friends
- `StoryShareResult` with file info and selected friends

### Customization
- `StoryEditorConfigProvider` for global configuration
- Customizable strings (localization support)
- Customizable theme (colors, icons)
- Customizable fonts and gradients
- Settings persistence with SharedPreferences
