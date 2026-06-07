#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Octgrams — ported from the Shadertoy GLSL to a Metal compute kernel that fits
// magic_edit's effect contract. Host THIS file at the descriptor's `metalUrl`.
//
// Key porting changes vs. the original GLSL:
//   * GLSL types  -> Metal types   (vec3->float3, mat2->float2x2, etc.)
//   * mainImage() -> a compute kernel with the exact required signature.
//   * Shadertoy uniforms map to our EffectUniforms:
//        fragCoord   = float2(gid) + tile offset
//        iResolution = float2(u.width, u.height)
//        iTime       = u.time
//   * GLSL `mod` reimplemented (Metal's fmod truncates toward zero, which
//     breaks the negative-coordinate domain repetition `mod(pos-2,4)-2`).
//   * The shader is a full-screen *generator* (it never read the input frame),
//     so the final write BLENDS it over the video frame by `u.intensity` — that
//     way the clip still shows through and the intensity slider does something.
//   * The `gTime` GLSL global is passed as a function argument instead.
// ---------------------------------------------------------------------------

// MUST stay byte-compatible with MetalEffectProcessor.EffectUniforms:
// six 32-bit floats, 24-byte stride, in this exact order.
struct EffectUniforms {
    float time;
    float intensity;
    float width;
    float height;
    float offsetX;
    float offsetY;
};

// GLSL-style mod: x - y * floor(x/y). Needed because `pos` goes negative.
inline float3 gmod(float3 x, float y) {
    return x - y * floor(x / y);
}

// GLSL mat2(c,s,-s,c) is column-major with columns (c,s) and (-s,c);
// float2x2(c,s,-s,c) is the same, so `v * rot(a)` matches the GLSL row-vector
// multiply `pos.xy *= rot(a)`.
inline float2x2 rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(c, s, -s, c);
}

inline float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// NOTE: the original `box` mutated `pos` after computing `base`, but `result`
// only depends on `base`, so those lines were dead and are dropped here
// (visually identical).
inline float box(float3 pos, float scale) {
    pos *= scale;
    float base = sdBox(pos, float3(0.4, 0.4, 0.1)) / 1.5;
    return -base;
}

float box_set(float3 pos, float gTime) {
    float3 o = pos;
    float k = 2.0 - abs(sin(gTime * 0.4)) * 1.5;
    float wob = sin(gTime * 0.4) * 2.5;

    pos = o; pos.y += wob; pos.xy = pos.xy * rot(0.8);
    float box1 = box(pos, k);
    pos = o; pos.y -= wob; pos.xy = pos.xy * rot(0.8);
    float box2 = box(pos, k);
    pos = o; pos.x += wob; pos.xy = pos.xy * rot(0.8);
    float box3 = box(pos, k);
    pos = o; pos.x -= wob; pos.xy = pos.xy * rot(0.8);
    float box4 = box(pos, k);
    pos = o; pos.xy = pos.xy * rot(0.8);
    float box5 = box(pos, 0.5) * 6.0;
    pos = o;
    float box6 = box(pos, 0.5) * 6.0;

    return max(max(max(max(max(box1, box2), box3), box4), box5), box6);
}

inline float map(float3 pos, float gTime) {
    return box_set(pos, gTime);
}

kernel void fx_octgrams(
    texture2d<float, access::sample> inTex  [[texture(0)]],
    texture2d<float, access::write>  outTex [[texture(1)]],
    constant EffectUniforms&         u      [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) { return; }
    constexpr sampler s(coord::pixel, address::clamp_to_edge, filter::linear);

    float2 fragCoord   = float2(gid) + float2(u.offsetX, u.offsetY);
    float2 iResolution = float2(u.width, u.height);
    float  iTime       = u.time;

    float2 p = (fragCoord * 2.0 - iResolution) / min(iResolution.x, iResolution.y);
    float3 ro = float3(0.0, -0.2, iTime * 4.0);
    float3 ray = normalize(float3(p, 1.5));
    ray.xy = ray.xy * rot(sin(iTime * 0.03) * 5.0);
    ray.yz = ray.yz * rot(sin(iTime * 0.05) * 0.2);

    float t = 0.1;
    float ac = 0.0;
    for (int i = 0; i < 99; i++) {
        float3 pos = ro + ray * t;
        pos = gmod(pos - 2.0, 4.0) - 2.0;
        float gTime = iTime - float(i) * 0.01;
        float d = map(pos, gTime);
        d = max(abs(d), 0.01);
        ac += exp(-d * 23.0);
        t += d * 0.55;
    }

    float3 col = float3(ac * 0.02);
    col += float3(0.0, 0.2 * abs(sin(iTime)), 0.5 + sin(iTime) * 0.2);

    // Blend the generated pattern over the actual video frame by intensity.
    float4 src  = inTex.sample(s, fragCoord);
    float3 outc = mix(src.rgb, col, u.intensity);
    outTex.write(float4(outc, src.a), gid);
}
