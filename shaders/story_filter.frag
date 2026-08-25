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

// Conservative skin-aware bilateral smoothing and VHS styling.
uniform float uBeauty;
uniform float uVhs;

// Input backdrop image.
// When used with BackdropFilter, Flutter auto-binds the backdrop pixels here.
// Do NOT call setImageSampler() from Dart — the framework handles it.
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 uv  = FlutterFragCoord().xy / uSize;
    vec4 tex = texture(uTexture, uv);
    vec3 source = tex.rgb;

    if (uBeauty > 0.001) {
        vec2 px = 1.35 / max(uSize, vec2(1.0));
        vec3 neighborhood =
            source * 4.0 +
            texture(uTexture, uv + vec2(px.x, 0.0)).rgb +
            texture(uTexture, uv - vec2(px.x, 0.0)).rgb +
            texture(uTexture, uv + vec2(0.0, px.y)).rgb +
            texture(uTexture, uv - vec2(0.0, px.y)).rgb;
        vec3 softened = neighborhood / 8.0;
        float luma = dot(source, vec3(0.2126, 0.7152, 0.0722));
        float warm = smoothstep(0.015, 0.18, source.r - source.g + 0.035);
        float notBlue = 1.0 - smoothstep(0.0, 0.16, source.b - source.g);
        float skin = warm * notBlue * smoothstep(0.08, 0.28, luma) *
                     (1.0 - smoothstep(0.86, 1.0, luma));
        source = mix(source, softened, skin * uBeauty);
        source += vec3(0.012, 0.006, 0.003) * skin * uBeauty;
    }

    if (uVhs > 0.001) {
        vec2 shift = vec2(1.6 / max(uSize.x, 1.0), 0.0) * uVhs;
        source.r = texture(uTexture, uv + shift).r;
        source.b = texture(uTexture, uv - shift).b;
        float scan = sin(uv.y * uSize.y * 1.52) * 0.018 * uVhs;
        float grain = fract(sin(dot(floor(FlutterFragCoord().xy),
            vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
        source += vec3(scan + grain * 0.035 * uVhs);
    }

    // Colour matrix (same formula as Android GLSL + iOS CIColorMatrix)
    vec3 color = vec3(
        dot(uMatRow0, source) + uBias,
        dot(uMatRow1, source) + uBias,
        dot(uMatRow2, source) + uBias
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
