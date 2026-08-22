#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;
uniform float uEffect;
uniform float uQuality;
uniform sampler2D uTexture;

out vec4 fragColor;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float gridLine(vec2 p, vec2 cells, float width) {
    vec2 f = abs(fract(p * cells) - 0.5);
    return 1.0 - smoothstep(width, width + 0.035, min(f.x, f.y));
}

void main() {
    vec2 safeSize = max(uSize, vec2(1.0));
    vec2 uv = FlutterFragCoord().xy / safeSize;
    vec4 tex = texture(uTexture, uv);
    vec3 original = tex.rgb;
    vec3 color = original;
    float effect = floor(uEffect + 0.5);

    if (effect == 1.0) {
        // Golden hour: warm grade plus a slowly drifting optical flare.
        color = vec3(
            dot(color, vec3(1.08, 0.06, 0.00)),
            dot(color, vec3(0.02, 1.01, 0.00)),
            dot(color, vec3(0.00, 0.03, 0.88))
        );
        vec2 flareCenter = vec2(0.18 + sin(uTime * 0.35) * 0.03, 0.20);
        float flare = 1.0 - smoothstep(0.0, 0.58, distance(uv, flareCenter));
        color += vec3(1.0, 0.54, 0.16) * flare * 0.28;
    } else if (effect == 2.0) {
        // Polar frost: cool grade and procedural ice at the frame edges.
        color = color * vec3(0.90, 1.02, 1.18) + vec3(0.01, 0.025, 0.05);
        float edge = smoothstep(0.38, 0.72, distance(uv, vec2(0.5)));
        float crystal = hash21(floor(uv * (18.0 + uQuality * 10.0)));
        color += vec3(0.48, 0.80, 1.0) * edge * crystal * 0.24;
    } else if (effect == 3.0) {
        // Neon pulse: cyan/magenta grade with a moving perspective-like grid.
        color = pow(max(color, vec3(0.0)), vec3(0.88));
        color *= vec3(0.96, 1.08, 1.18);
        vec2 gridUv = vec2(uv.x, uv.y + uTime * 0.025);
        float grid = gridLine(gridUv, vec2(8.0, 14.0), 0.055);
        vec3 gridColor = mix(vec3(1.0, 0.08, 0.74), vec3(0.0, 0.94, 1.0), uv.x);
        color += gridColor * grid * 0.22;
    } else if (effect == 4.0) {
        // Film noir: high-contrast monochrome with deterministic moving grain.
        float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
        luma = smoothstep(0.12, 0.88, luma);
        float grain = hash21(FlutterFragCoord().xy + floor(uTime * 18.0)) - 0.5;
        color = vec3(luma + grain * 0.10);
        float vignette = smoothstep(0.34, 0.78, distance(uv, vec2(0.5)));
        color *= 1.0 - vignette * 0.48;
    } else if (effect == 5.0) {
        // Prism pop: chromatic separation. Used only on the high quality tier.
        vec2 direction = normalize(uv - vec2(0.5) + vec2(0.0001));
        float pulse = 0.0035 + 0.0015 * sin(uTime * 1.4);
        float red = texture(uTexture, clamp(uv + direction * pulse, 0.0, 1.0)).r;
        float blue = texture(uTexture, clamp(uv - direction * pulse, 0.0, 1.0)).b;
        color = vec3(red, color.g, blue) * vec3(1.04, 1.0, 1.06);
    } else if (effect == 6.0) {
        // Retro scan: analog color response, scanlines, and a rolling highlight.
        color = color * vec3(1.08, 0.98, 0.90) + vec3(0.018, 0.005, 0.012);
        float scan = sin((FlutterFragCoord().y + uTime * 35.0) * 1.45) * 0.5 + 0.5;
        color *= 0.88 + scan * 0.12;
        float roll = 1.0 - smoothstep(0.0, 0.055, abs(fract(uv.y + uTime * 0.08) - 0.5));
        color += vec3(0.07, 0.035, 0.08) * roll;
    } else if (effect == 7.0) {
        // Stargaze: purple night grade and a procedural twinkling star field.
        color *= vec3(0.92, 0.91, 1.12);
        vec2 cells = vec2(18.0, 32.0);
        vec2 cellId = floor(uv * cells);
        vec2 cellUv = fract(uv * cells);
        vec2 starPos = vec2(hash21(cellId), hash21(cellId + 17.3));
        float starSeed = hash21(cellId + 53.1);
        float star = 1.0 - smoothstep(0.02, 0.12, distance(cellUv, starPos));
        star *= step(0.82, starSeed);
        star *= 0.55 + 0.45 * sin(uTime * (1.2 + starSeed) + starSeed * 15.0);
        color += mix(vec3(0.62, 0.48, 1.0), vec3(1.0), starSeed) * star;
    }

    color = mix(original, clamp(color, 0.0, 1.0), clamp(uIntensity, 0.0, 1.0));
    fragColor = vec4(color, tex.a);
}
