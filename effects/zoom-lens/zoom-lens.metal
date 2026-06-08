#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Zoom Lens — a breathing lens that rhythmically magnifies the live frame from
// its centre, with barrel distortion + chromatic aberration toward the edges so
// it reads like real glass. CapCut-style "Zoom Lens" effect.
//
//   * Reads the live video frame from inTex (texture 0) — the iChannel0 analogue.
//   * Continuous loop: the zoom pulses from `iTime`; `intensity` scales how far
//     it pushes in. At intensity 0 the math collapses to identity (untouched).
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

kernel void fx_zoom_lens(
    texture2d<float, access::sample> inTex  [[texture(0)]],
    texture2d<float, access::write>  outTex [[texture(1)]],
    constant EffectUniforms&         u      [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) { return; }
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 res = float2(u.width, u.height);
    float2 uv  = (float2(gid) + float2(u.offsetX, u.offsetY)) / res;
    float  t   = u.time;
    float  k   = u.intensity;

    float2 c = uv - 0.5;
    float  r = length(c);

    // Pulsing magnification: 0 -> in -> 0, looping. `lens` < 1 samples a smaller
    // region (zoom in); the r*r term curves it like a lens (barrel).
    float pulse = 0.5 - 0.5 * cos(t * 3.0);          // 0..1
    float zoom  = pulse * 0.35 * k;
    float lens  = 1.0 - zoom * (1.0 + r * r * 1.5);

    // Chromatic aberration grows with the zoom and toward the rim.
    float ca = zoom * 0.06 * (0.3 + r);

    float3 col;
    col.r       = inTex.sample(s, 0.5 + c * (lens - ca)).r;
    float4 g    = inTex.sample(s, 0.5 + c * lens);
    col.g       = g.g;
    col.b       = inTex.sample(s, 0.5 + c * (lens + ca)).b;

    // Subtle edge vignette while the lens is pushed in.
    col *= 1.0 - zoom * r * 0.8;

    outTex.write(float4(col, g.a), gid);
}
