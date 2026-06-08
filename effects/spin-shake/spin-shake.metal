#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Spin & Shake — a punchy beat-style move: the frame whips back and forth in
// rotation while a high-frequency camera shake jitters it and a scale "punch"
// pumps in and out. CapCut-style "Spin & Shake", looped continuously.
//
//   * Reads the live video frame from inTex (texture 0) — the iChannel0 analogue.
//   * Aspect-corrected rotation (stays circular), with a slight overscan so the
//     shake/spin never drags the clamped edge into frame.
//   * `intensity` scales spin angle, shake amplitude, punch and overscan
//     together; at 0 the sample lands exactly on uv -> identity.
// ---------------------------------------------------------------------------

struct EffectUniforms {
    float time;
    float intensity;
    float width;
    float height;
    float offsetX;
    float offsetY;
};

kernel void fx_spin_shake(
    texture2d<float, access::sample> inTex  [[texture(0)]],
    texture2d<float, access::write>  outTex [[texture(1)]],
    constant EffectUniforms&         u      [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) { return; }
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 res    = float2(u.width, u.height);
    float2 uv     = (float2(gid) + float2(u.offsetX, u.offsetY)) / res;
    float  t      = u.time;
    float  k      = u.intensity;
    float  aspect = res.x / res.y;

    float2 p = uv - 0.5;
    p.x *= aspect;                       // square space so rotation stays circular

    // Whip rotation: a fast oscillation plus a slow sway.
    float ang = sin(t * 4.0) * 0.35 * k + sin(t * 1.3) * 0.10 * k;
    float ca  = cos(ang), sa = sin(ang);
    p = float2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

    // Scale punch + intensity-scaled overscan (overscan hides the clamped edge).
    float punch    = 1.0 - (0.5 + 0.5 * sin(t * 8.0)) * 0.08 * k;
    float overscan = 1.0 + 0.08 * k;
    p = p / overscan * punch;

    p.x /= aspect;                       // back to uv space

    // High-frequency camera shake.
    float2 shake = float2(
        sin(t * 43.0) + 0.5 * sin(t * 27.0),
        cos(t * 39.0) + 0.5 * sin(t * 23.0)
    ) * 0.01 * k;

    float2 suv = p + 0.5 + shake;
    float4 src = inTex.sample(s, suv);
    outTex.write(src, gid);
}
