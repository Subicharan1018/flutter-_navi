#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2  u_resolution;
uniform float u_time;

// FIX BUG-8: Flutter's runtime_effect does not support array uniforms.
// Each element is declared as a separate uniform.
uniform vec4  u_color0;
uniform vec4  u_color1;
uniform vec4  u_color2;
uniform vec4  u_color3;

uniform vec4  u_colorPrev0;
uniform vec4  u_colorPrev1;
uniform vec4  u_colorPrev2;
uniform vec4  u_colorPrev3;

uniform float u_tColor;

out vec4 fragColor;

// ── PRNG & Noise Helpers ──────────────────────────────────────────────────────

float hash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.50;
    vec2  s = vec2(1.0);
    for (int i = 0; i < 3; i++) {
        v += a * noise(p * s);
        s *= 2.1;
        a *= 0.48;
    }
    return v;
}

// ── Color & Math Helpers ──────────────────────────────────────────────────────

vec4 getColor(int idx) {
    if (idx == 0) return mix(u_colorPrev0, u_color0, u_tColor);
    if (idx == 1) return mix(u_colorPrev1, u_color1, u_tColor);
    if (idx == 2) return mix(u_colorPrev2, u_color2, u_tColor);
                  return mix(u_colorPrev3, u_color3, u_tColor);
}

void main() {
    vec2 fc = FlutterFragCoord().xy;
    vec2 uv = fc / u_resolution;

    float t = u_time * 0.15;

    // Multi-octave continuous domain warping (Liquid Navier-Stokes style)
    vec2 q = vec2(
        fbm(uv * 1.5 + vec2(t * 0.25, t * 0.18)),
        fbm(uv * 1.5 + vec2(t * 0.18 + 2.4, t * 0.22 + 4.1))
    );

    vec2 r = vec2(
        fbm(uv * 1.8 + 2.5 * q + vec2(1.7, 9.2) + vec2(t * 0.20, -t * 0.15)),
        fbm(uv * 1.8 + 2.5 * q + vec2(8.3, 2.8) + vec2(-t * 0.18, t * 0.22))
    );

    float f = fbm(uv * 1.2 + 3.0 * r + vec2(t * 0.10, t * 0.12));

    // Continuous 4-way silky harmonic color interpolation (Zero circular balls)
    vec3 c0 = getColor(0).rgb;
    vec3 c1 = getColor(1).rgb;
    vec3 c2 = getColor(2).rgb;
    vec3 c3 = getColor(3).rgb;

    // Seamless spatial blending
    vec3 colTop = mix(c0, c1, clamp(r.x * 1.2 + uv.x * 0.5, 0.0, 1.0));
    vec3 colBot = mix(c2, c3, clamp(q.y * 1.2 + uv.x * 0.5, 0.0, 1.0));
    vec3 col = mix(colTop, colBot, clamp(f * 1.3 + uv.y * 0.4, 0.0, 1.0));

    // Fluid illumination highlights
    col += c1 * (f * f * 0.35);
    col += c0 * (r.x * r.y * 0.25);

    // Apple Music smooth filmic exposure
    col = vec3(1.0) - exp(-col * 1.15);

    // Subtle edge softening
    vec2 vUV = (uv - 0.5) * vec2(u_resolution.x / u_resolution.y, 1.0);
    float vDist = length(vUV);
    float vAlpha = smoothstep(0.40, 1.3, vDist) * 0.25;
    col = mix(col, col * 0.60, vAlpha);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}