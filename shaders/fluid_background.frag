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

// FIX BUG-8: Replace array indexing with explicit selection now that the
// uniforms are flat. An ivec4 swizzle-based approach or a simple if-chain
// both work; the if-chain below is the most portable across GPU drivers.
vec4 getColor(int idx) {
    if (idx == 0) return mix(u_colorPrev0, u_color0, u_tColor);
    if (idx == 1) return mix(u_colorPrev1, u_color1, u_tColor);
    if (idx == 2) return mix(u_colorPrev2, u_color2, u_tColor);
                  return mix(u_colorPrev3, u_color3, u_tColor);
}

float blobWeight(vec2 uv, vec2 centre, float r) {
    vec2 aspect = vec2(u_resolution.x / u_resolution.y, 1.0);
    float d = length((uv - centre) * aspect) / r;
    return exp(-d * d * 2.8);
}

// ── Main Rendering ────────────────────────────────────────────────────────────

void main() {
    vec2 fc = FlutterFragCoord().xy;
    vec2 uv = fc / u_resolution;

    float t = u_time;

    float warpAmt = 0.014;
    vec2 warpUV = uv + warpAmt * vec2(
        fbm(uv * 2.3 + vec2(t * 0.0035,  t * 0.0025)),
        fbm(uv * 2.3 + vec2(t * 0.0025,  t * 0.0045 + 3.14))
    );

    vec3 col = mix(getColor(0).rgb, vec3(0.0), 0.74);

    float tau = 6.28318;
    #define S(x) (sin(x) * 0.5 + 0.5)
    #define C(x) (cos(x) * 0.5 + 0.5)

    {
        vec4 c = getColor(0);
        vec2 ctr = vec2(0.10 + 0.40 * S(t * tau * 0.023), 0.05 + 0.38 * C(t * tau * 0.019 + 0.8));
        col += c.rgb * blobWeight(warpUV, ctr, 0.72) * c.a;
    }
    {
        vec4 c = getColor(1);
        vec2 ctr = vec2(0.60 + 0.38 * C(t * tau * 0.031 + 1.2), 0.05 + 0.42 * S(t * tau * 0.025 + 2.1));
        col += c.rgb * blobWeight(warpUV, ctr, 0.68) * c.a * 0.95;
    }
    {
        vec4 c = getColor(2);
        vec2 ctr = vec2(0.05 + 0.42 * S(t * tau * 0.036 + 3.0), 0.55 + 0.42 * C(t * tau * 0.026 + 0.5));
        col += c.rgb * blobWeight(warpUV, ctr, 0.78) * c.a * 0.90;
    }
    {
        vec4 c = getColor(3);
        vec2 ctr = vec2(0.58 + 0.38 * C(t * tau * 0.019 + 1.7), 0.58 + 0.38 * S(t * tau * 0.034 + 2.8));
        col += c.rgb * blobWeight(warpUV, ctr, 0.70) * c.a * 0.88;
    }
    {
        vec4 c = getColor(0);
        vec2 ctr = vec2(0.38 + 0.28 * S(t * tau * 0.014 + 0.3), 0.32 + 0.32 * C(t * tau * 0.028 + 1.4));
        col += c.rgb * blobWeight(warpUV, ctr, 0.58) * c.a * 0.65;
    }

    #undef S
    #undef C

    col = 1.0 - exp(-col * 0.95);

    vec2 vUV = uv - vec2(0.5, 0.42);
    vUV.x *= u_resolution.x / u_resolution.y;
    float vDist  = length(vUV) / 0.88;
    float vAlpha = smoothstep(0.30, 1.0, vDist) * 0.38;
    col = mix(col, vec3(0.0), vAlpha);

    float scrY  = smoothstep(0.50, 1.0, uv.y);
    col = mix(col, vec3(0.0), scrY * 0.66);

    float topScr = smoothstep(0.18, 0.0, uv.y) * 0.16;
    col = mix(col, vec3(0.0), topScr);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}