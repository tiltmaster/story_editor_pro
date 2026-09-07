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

// Conservative skin-aware smoothing and material-look controls.
uniform float uBeauty;
uniform float uVhs;
uniform float uBloom;
uniform float uGrain;
uniform float uHalation;
uniform float uSplitTone;
uniform float uChroma;
uniform vec4 uFaceEyes;
uniform float uBeautyEyes;
uniform float uBeautySlim;

// Input backdrop image.
// When used with BackdropFilter, Flutter auto-binds the backdrop pixels here.
// Do NOT call setImageSampler() from Dart — the framework handles it.
uniform sampler2D uTexture;

out vec4 fragColor;

vec2 faceUv(vec2 uv) {
    if (uBeautyEyes <= 0.001 && uBeautySlim <= 0.001) return uv;
    vec2 metric = vec2(uSize.x / uSize.y, 1.0);
    vec2 p = uv * metric;
    vec2 l = uFaceEyes.xy * metric;
    vec2 r = uFaceEyes.zw * metric;
    float d = distance(l, r);
    if (d < 0.015) return uv;
    vec2 axis = (r - l) / d;
    vec2 down = vec2(-axis.y, axis.x);
    vec2 delta = p - l;
    float w = max(0.0, 1.0 - length(delta) / (d * 0.48));
    p -= delta * (0.24 * uBeautyEyes * w * w);
    delta = p - r;
    w = max(0.0, 1.0 - length(delta) / (d * 0.48));
    p -= delta * (0.24 * uBeautyEyes * w * w);
    delta = p - ((l + r) * 0.5 + down * d * 0.65);
    float x = dot(delta, axis);
    float y = dot(delta, down);
    vec2 q = vec2(x / (d * 1.15), y / (d * 1.5));
    w = max(0.0, 1.0 - dot(q, q));
    p += axis * x * (0.18 * uBeautySlim * w * w * smoothstep(-0.15, 0.35, y / d));
    return clamp(p / metric, vec2(0.0), vec2(1.0));
}

void main() {
    vec2 uv  = faceUv(FlutterFragCoord().xy / uSize);
    vec4 tex = texture(uTexture, uv);
    vec3 source = tex.rgb;

    // Lightweight analog/chroma character. This deliberately uses the current
    // pixel only: authored PNG/vector overlays provide the spatial detail
    // without multiplying camera texture reads on every frame.
    if (uVhs > 0.001 || uChroma > 0.001) {
        vec2 virtualFrag = uv * vec2(720.0, 1280.0);
        float band = virtualFrag.y / 64.0;
        float bandIndex = floor(band);
        float bandMix = smoothstep(0.0, 1.0, fract(band));
        float noiseA = fract(sin(bandIndex * 91.3458) * 47453.5453) - 0.5;
        float noiseB = fract(sin((bandIndex + 1.0) * 91.3458) * 47453.5453) - 0.5;
        float bandNoise = mix(noiseA, noiseB, bandMix);
        float sourceLuma = dot(source, vec3(0.2126, 0.7152, 0.0722));
        source = mix(source, vec3(sourceLuma), 0.08 * uVhs);
        source += vec3(0.018, 0.002, -0.014) * bandNoise * uVhs;
        float edge = distance(uv, vec2(0.5));
        source += vec3(0.012, -0.004, -0.010) *
            (0.35 + edge) * uChroma;
    }

    if (uBeauty > 0.001) {
        // Edge-aware bilateral smoothing; no full-frame blur or skin whitening.
        vec3 original = tex.rgb;
        vec3 total = original;
        float totalWeight = 1.0;
        vec3 n0 = texture(uTexture, clamp(uv + vec2(1.0000, 0.0000) * vec2(5.5 / 720.0, 5.5 / 1280.0), vec2(0.0), vec2(1.0))).rgb;
        vec3 diff0 = n0 - original;
        float w0 = exp(-dot(diff0, diff0) * 48.0);
        total += n0 * w0; totalWeight += w0;
        vec3 n1 = texture(uTexture, clamp(uv + vec2(-1.0000, 0.0000) * vec2(5.5 / 720.0, 5.5 / 1280.0), vec2(0.0), vec2(1.0))).rgb;
        vec3 diff1 = n1 - original;
        float w1 = exp(-dot(diff1, diff1) * 48.0);
        total += n1 * w1; totalWeight += w1;
        vec3 n2 = texture(uTexture, clamp(uv + vec2(0.0000, 1.0000) * vec2(5.5 / 720.0, 5.5 / 1280.0), vec2(0.0), vec2(1.0))).rgb;
        vec3 diff2 = n2 - original;
        float w2 = exp(-dot(diff2, diff2) * 48.0);
        total += n2 * w2; totalWeight += w2;
        vec3 n3 = texture(uTexture, clamp(uv + vec2(0.0000, -1.0000) * vec2(5.5 / 720.0, 5.5 / 1280.0), vec2(0.0), vec2(1.0))).rgb;
        vec3 diff3 = n3 - original;
        float w3 = exp(-dot(diff3, diff3) * 48.0);
        total += n3 * w3; totalWeight += w3;
        vec3 n4 = texture(uTexture, clamp(uv + vec2(0.7070, 0.7070) * vec2(5.5 / 720.0, 5.5 / 1280.0), vec2(0.0), vec2(1.0))).rgb;
        vec3 diff4 = n4 - original;
        float w4 = exp(-dot(diff4, diff4) * 48.0);
        total += n4 * w4; totalWeight += w4;
        vec3 n5 = texture(uTexture, clamp(uv + vec2(-0.7070, 0.7070) * vec2(5.5 / 720.0, 5.5 / 1280.0), vec2(0.0), vec2(1.0))).rgb;
        vec3 diff5 = n5 - original;
        float w5 = exp(-dot(diff5, diff5) * 48.0);
        total += n5 * w5; totalWeight += w5;
        vec3 n6 = texture(uTexture, clamp(uv + vec2(0.7070, -0.7070) * vec2(5.5 / 720.0, 5.5 / 1280.0), vec2(0.0), vec2(1.0))).rgb;
        vec3 diff6 = n6 - original;
        float w6 = exp(-dot(diff6, diff6) * 48.0);
        total += n6 * w6; totalWeight += w6;
        vec3 n7 = texture(uTexture, clamp(uv + vec2(-0.7070, -0.7070) * vec2(5.5 / 720.0, 5.5 / 1280.0), vec2(0.0), vec2(1.0))).rgb;
        vec3 diff7 = n7 - original;
        float w7 = exp(-dot(diff7, diff7) * 48.0);
        total += n7 * w7; totalWeight += w7;
        float luma = dot(original, vec3(0.2126, 0.7152, 0.0722));
        float cb = 0.5 + dot(original, vec3(-0.168736, -0.331264, 0.5));
        float cr = 0.5 + dot(original, vec3(0.5, -0.418688, -0.081312));
        float skin = smoothstep(0.49, 0.55, cr) * (1.0 - smoothstep(0.67, 0.77, cr))
            * smoothstep(0.20, 0.30, cb) * (1.0 - smoothstep(0.51, 0.58, cb))
            * smoothstep(0.015, 0.10, luma);
        source += (total / totalWeight - original) * skin * uBeauty * 0.95;
    }

    // Single-pixel highlight shaping replaces the former four-tap glow pass.
    if (uBloom > 0.001 || uHalation > 0.001) {
        float highlight = smoothstep(
            0.62,
            0.94,
            dot(source, vec3(0.2126, 0.7152, 0.0722))
        );
        source += source * highlight * (0.16 * uBloom);
        source += highlight * vec3(0.055, 0.016, -0.008) * uHalation;
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

    if (abs(uSplitTone) > 0.001) {
        float amount = abs(uSplitTone);
        float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
        float shadows = 1.0 - smoothstep(0.12, 0.58, luma);
        float highlights = smoothstep(0.52, 0.92, luma);
        vec3 warmShadow = vec3(-0.022, 0.012, 0.030);
        vec3 warmHighlight = vec3(0.070, 0.030, -0.018);
        vec3 coolShadow = vec3(0.035, -0.010, 0.055);
        vec3 coolHighlight = vec3(0.008, 0.028, 0.042);
        vec3 split = uSplitTone > 0.0
            ? warmShadow * shadows + warmHighlight * highlights
            : coolShadow * shadows + coolHighlight * highlights;
        color += split * amount;
    }

    if (uGrain > 0.001) {
        // Bound the hash domain so the same expression is safe even on a
        // mediump-only fragment implementation.
        vec2 grainCell = mod(
            floor(uv * vec2(720.0, 1280.0) * 0.72),
            vec2(64.0)
        );
        float grain = fract(sin(dot(grainCell,
            vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
        float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
        color += vec3(grain * (0.020 + (1.0 - luma) * 0.018) * uGrain);
    }

    // Vignette: radial darkening — identical to Android GLSL
    if (uVignette > 0.001) {
        float dist = distance(uv, vec2(0.5));
        color *= (1.0 - smoothstep(0.35, 0.82, dist) * uVignette);
    }

    fragColor = vec4(clamp(color, 0.0, 1.0), tex.a);
}
