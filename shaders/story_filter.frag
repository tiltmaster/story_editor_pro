#include <flutter/runtime_effect.glsl>

// Canvas size in pixels — required to derive UV from FragCoord.
uniform vec2  uSize;

// Colour matrix rows in 0-1 normalised space.
// Implements the identical formula to Android GLSL and iOS CIColorMatrix:
//   R' = dot(uMatRow0, color.rgb) + uBias
//   G' = dot(uMatRow1, color.rgb) + uBias
//   B' = dot(uMatRow2, color.rgb) + uBias
uniform vec3  uMatRow0;
uniform vec3  uMatRow1;
uniform vec3  uMatRow2;
uniform float uBias;

// S-curve strength 0-1.
// Uses smoothstep mix — IDENTICAL to the Android GLSL export shader.
// Calibrated to match iOS CIToneCurve (d = sCurve × 0.094).
uniform float uSCurve;

// Vignette opacity 0-1.
// Radial darkening — IDENTICAL to the Android GLSL export shader.
uniform float uVignette;

// Input backdrop image.
// When used with BackdropFilter, Flutter auto-binds the backdrop pixels here.
// Do NOT call setImageSampler() from Dart — the framework handles it.
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 uv  = FlutterFragCoord().xy / uSize;
    vec4 tex = texture(uTexture, uv);

    // Colour matrix (same formula as Android GLSL + iOS CIColorMatrix)
    vec3 color = vec3(
        dot(uMatRow0, tex.rgb) + uBias,
        dot(uMatRow1, tex.rgb) + uBias,
        dot(uMatRow2, tex.rgb) + uBias
    );

    // S-curve: smoothstep blend — identical to Android GLSL
    if (uSCurve > 0.001) {
        vec3 curved = color * color * (3.0 - 2.0 * color);
        color = mix(color, curved, uSCurve);
    }

    // Vignette: radial darkening — identical to Android GLSL
    if (uVignette > 0.001) {
        float dist = distance(uv, vec2(0.5));
        color *= (1.0 - smoothstep(0.35, 0.82, dist) * uVignette);
    }

    fragColor = vec4(clamp(color, 0.0, 1.0), tex.a);
}
