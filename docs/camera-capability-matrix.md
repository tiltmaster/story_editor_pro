# Independent camera capability comparison

Implementation updated 11 September 2026 against Snapchat's documented camera and creation
workflows. This is an implementation and verification ledger, not a percentage
inferred from the number of filters. Android and iOS use our CameraX /
AVFoundation pipeline, MediaPipe / Vision analysis and native compositors;
there is no Camera Kit dependency or Snap account requirement.

## Familiar capture workflow

Snapchat documents tap for a photo, hold for video, double-tap or a flip button
to switch cameras, and a flash button. These interactions are implemented here.
See [Snapchat's capture instructions](https://help.snapchat.com/hc/en-us/articles/7012326414612-How-do-I-create-a-Snap).

| Interaction | Implementation / evidence |
| --- | --- |
| Tap photo / hold video | One anchored shutter; native photo/video paths on both platforms. |
| Release to finish / slide to lock | Recording gesture survives asynchronous encoder startup; localized lock guidance; tap the locked shutter to stop. Gesture tests cover RTL and LTR. |
| Double-tap or button to flip | Same camera switching path; controls and selected effect orientation refresh after switching. |
| Pinch and hold-slide zoom | Native camera reports its actual range; operations await camera acknowledgement. |
| Tap to focus | Visible reticle; cover-crop and mirror compensation in Dart, sensor-coordinate mapping natively. Geometry tests cover portrait/rotation/crop. |
| Brightness | Compact exposure slider, actual EV limits and Android EV-step snapping. |
| Flash | Photo off/on/auto and recording torch; torch is shut down on stop, failure and teardown. |
| Timer / looping capture | Timed hands-free video and boomerang; tools use the side rail, with compact timer choices. |
| Photo/video gallery import | Existing gallery permission and picker flow. |

## Effects

Snapchat distinguishes face and world lenses from color filters. Its lens
carousel leads directly to the same photo/video shutter.
[Source](https://help.snapchat.com/hc/en-us/articles/7012348332052-How-do-I-use-Lenses-on-Snapchat).

| Capability | Current implementation | Limit |
| --- | --- | --- |
| Browsable lenses | Lenses open first; category and scroll position persist; local favorites pin actual effects. | Bundled catalog, no remote creator marketplace. |
| Layered effects | Independent look, smoothing, eye/contour shaping, face artwork, person background and real-city frame. | One face-art selection and one background at a time. |
| Beautification | Pixel smoothing plus tracked eye enlargement and face contour in preview and saved media. | No dense facial makeup/hair recoloring or age transformations. |
| Face artwork | Celestial, hearts, freckles, neon contour and butterflies; retired glasses unavailable. | Single tracked face; no 3D character/face replacement. |
| Expression reactions | Mouth-open hearts and wink-driven butterflies, using measured geometry and cooldown. | Two authored reactions, not a general lens-scripting ecosystem. |
| Person backgrounds | On-device confidence masks: Studio, generated photographic Sunset/Night, blurred source background, and gallery photos/looping videos. Last valid matte stays visible between inferences; capture requires recent tracking. | Generated assets are 941 × 1672, not native 4K. Rapid movement can expose matte lag. Custom video decoding is capped at 10 fps and its audio is muted. |
| Location frames | Permission-aware current location, localized city and host-provided nearby venues with remembered styles. | Nearby venues require a host resolver; coverage depends on its place catalog. |
| Readable output | Native text/canvas orientation plus single final mirror; Arabic shaping in native graphics. | Device acceptance includes both mirror settings and saved photos/video. |
| World lenses / object anchors | Not implemented. | Requires a separate world-tracking engine and authored 3D content. |
| Multiple tracked people | Not implemented. | Current face effects track one face. |

## Editing and completion

Snapchat's current timeline includes multiple clips, splitting, speed, timed
captions/stickers and music layers. Those are separate capabilities from a
single-clip trim control.
[Source](https://help.snapchat.com/hc/en-us/articles/41614255962132-How-do-I-edit-videos-with-Timeline-Editor).

| Capability | Implementation / limit |
| --- | --- |
| Text, drawing, image/emoji/smart stickers | Existing movable layers with Arabic support; baked into photos/video, including animated GIF layers. |
| Trim and mute | Decoded single-clip filmstrip with in/out handles, seeking and mute; either edit alone triggers native export. |
| Position and scale | Preview and native video export share scale and normalized translation; artwork stays in canvas space. |
| Undo / redo | Chronological snapshots across drawing, text, stickers, placement, crop, trim, mute and music selection; grouped gesture transactions. |
| Save / share result | Export is awaited; failure retains the editor and edits; callback receives an existing file and actual byte size. Social upload is the host application's responsibility. |
| Music | Host selection metadata exists; this does not yet mix an audio track into video. |
| Multi-clip timeline / timed layers / speed | Not implemented. |
| Dual camera / optical-lens selection / dedicated stabilization controls | Not implemented; hardware zoom bounds do not imply optical-lens switching. |

Snapchat also documents Director Mode, Dual Camera, Ultra Wide, Green Screen,
Camera Speed and Multi Snap. These remain explicit comparison items rather than
being counted as color presets.
[Source](https://help.snapchat.com/hc/en-us/sections/5686253109524-Taking-Snaps).

## Verification boundary

Automated checks cover Flutter interactions/RTL layout, native control geometry,
expression thresholds, mask composition and export transformations. CI compiles
Android and iOS and executes native tests; the local APK is excluded from Git.
Release-specific results belong in `camera-effects-review.md`.

Connected S23 Ultra checks confirmed readable Analog Tape text in preview and
captured photos, retained frame borders, GPS-backed nearby venue selection and
photographic person backgrounds. Broader physical-device acceptance remains:
cold/warm startup and FPS,
exposure/focus on real hardware, mask edges during movement, actual expression
triggers, preview/photo/video consistency, front/back switching, Arabic place
names, audio and repeated background/resume. Desktop tests cannot certify these
camera qualities or user comprehension.

The core capture gestures have direct counterparts and automated coverage.
Overall 90% Snapchat camera/creation parity requires closing the explicitly
missing capabilities above and defining a weighted acceptance benchmark; it
must not be represented by relabeling existing presets or passing build checks.
