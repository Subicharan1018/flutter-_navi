#version 460 core
#include <flutter/runtime_effect.glsl>

// Living artwork field.
//
// Draws the cover itself — three slowly counter-rotating, flow-warped copies
// sampled from a 64px texture — so the background is made of the album's own
// pixels rather than a generic gradient. Rendered at ~1/6 resolution and
// upscaled by the host widget: the content is deliberately soft, so the low
// resolution is invisible and the GPU cost is ~36x lower than full-res.

uniform vec2  uSize;      // render-target size in px
uniform float uTime;      // seconds; frozen while paused
uniform float uMix;       // 0 = artA (outgoing song), 1 = artB (current song)
uniform vec4  uDeep;      // palette.deep (rgb), a unused
uniform float uDim;       // 0..1 extra darkening (queue / lyrics open)
uniform float uEnergy;    // 0..1: 1 while music plays, 0 paused — the room's light

uniform sampler2D uArtA;
uniform sampler2D uArtB;

out vec4 fragColor;

vec2 rot(vec2 p, float a) {
    float c = cos(a), s = sin(a);
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Mirror-repeat so rotated/zoomed copies never sample a hard texture edge.
vec2 mirrorUv(vec2 uv) {
    return 1.0 - abs(1.0 - mod(uv, 2.0));
}

vec3 tap(vec2 uv) {
    vec2 m = mirrorUv(uv);
    return mix(texture(uArtA, m).rgb, texture(uArtB, m).rgb, uMix);
}

// Five-tap soft sample: the field should read as the cover's light and
// colour, never as a recognisable (pixelated) picture.
vec3 art(vec2 uv) {
    const float r = 0.055;
    return (tap(uv) * 2.0
          + tap(uv + vec2( r,  r)) + tap(uv + vec2(-r,  r))
          + tap(uv + vec2( r, -r)) + tap(uv + vec2(-r, -r))) / 6.0;
}

void main() {
    vec2 frag = FlutterFragCoord().xy;
    vec2 uv = frag / uSize;
    float aspect = uSize.x / uSize.y;
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
    float t = uTime;

    // Low-frequency flow: two sine waves bend the sampling space like slow
    // liquid. Cheap (4 trig) and smooth at any resolution.
    vec2 flow = vec2(
        sin(p.y * 2.3 + t * 0.21) + sin(p.x * 1.7 - t * 0.13),
        cos(p.x * 2.1 - t * 0.17) + cos(p.y * 1.5 + t * 0.11)
    ) * 0.085;

    // Three layered copies at different scales and opposite rotations.
    // Zoomed in (scale < 1 samples a smaller region) so shapes in the cover
    // dissolve into broad fields of colour.
    vec3 a = art(rot(p + flow, t * 0.045) * 0.55 + 0.5);
    vec3 b = art(rot(p * 0.8 - flow * 1.3, -t * 0.031 + 1.7) * 0.7 + 0.5);
    vec3 c = art(rot(p * 0.5 + flow * 0.6, t * 0.019 + 3.1) * 0.9 + 0.5);

    vec3 col = mix(a, b, 0.45 + 0.25 * sin(t * 0.07 + p.x * 1.3));
    // Screen-blend the large slow layer for soft luminous highlights.
    col = 1.0 - (1.0 - col) * (1.0 - c * 0.42);

    // Vibrancy: lift saturation around luma so colours read rich, not muddy;
    // richer still while the music plays.
    float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(luma), col, 1.38 + 0.24 * uEnergy);

    // Tone: compress highlights so white covers don't blow out white type.
    col = col / (1.0 + col * 0.55);

    // Legibility: deepen toward the palette's deep tone at the top edge and,
    // more strongly, across the lower half where the controls live.
    float lower = smoothstep(0.42, 1.0, uv.y);
    float upper = smoothstep(0.18, 0.0, uv.y);
    // The room's light: playing opens up the region behind the cover only
    // (it fades out before the title, so text contrast is never reduced);
    // pausing dims the whole field.
    float behindCover = smoothstep(0.56, 0.30, uv.y);
    float light = -0.10 * uEnergy * behindCover + 0.20 * (1.0 - uEnergy);
    float shade = 0.18 + lower * 0.42 + upper * 0.18 + uDim * 0.38 + light;
    col = mix(col, uDeep.rgb * 0.55, clamp(shade, 0.0, 0.92));

    // Gentle vignette so the field sits behind the content.
    float vig = smoothstep(1.25, 0.35, length(p * vec2(0.9, 1.0)));
    col *= mix(0.72, 1.0, vig);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
