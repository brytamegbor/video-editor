#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Camera Focus — a rack-focus / focus-pull: the live frame drifts out of focus
// and back, looping. The defocus is a real disc-bokeh blur (golden-angle taps)
// that blooms highlights, plus a touch of focus "breathing" (lenses zoom a hair
// as they refocus). CapCut-style "Camera Focus".
//
//   * Reads the live video frame from inTex (texture 0) — the iChannel0 analogue.
//   * Continuous loop driven by `iTime`; `intensity` scales the max blur radius.
//     At intensity 0 every tap collapses onto the same pixel -> identity.
// ---------------------------------------------------------------------------

struct EffectUniforms {
    float time;
    float intensity;
    float width;
    float height;
    float offsetX;
    float offsetY;
};

constant int kTaps = 24;

kernel void fx_camera_focus(
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

    float focus = 0.5 - 0.5 * cos(t * 1.3);     // 0 (sharp) .. 1 (soft), looping
    float blur  = focus * 0.025 * k;            // bokeh radius in uv units

    // Focus breathing: a slight zoom while defocused.
    float  breath = 1.0 - focus * 0.03 * k;
    float2 cuv    = (uv - 0.5) * breath + 0.5;

    float  bokeh = step(0.0001, blur);          // gate the highlight bloom
    float3 col   = float3(0.0);
    float  total = 0.0;
    for (int i = 0; i < kTaps; i++) {
        float fi  = float(i);
        float ang = fi * 2.399963229;           // golden angle -> even disc
        float rad = sqrt((fi + 0.5) / float(kTaps)) * blur;
        float2 off = float2(cos(ang), sin(ang)) * rad;

        float3 tcol = inTex.sample(s, cuv + off).rgb;
        float  luma = max(tcol.r, max(tcol.g, tcol.b));
        float  w    = 1.0 + smoothstep(0.6, 1.0, luma) * 3.0 * bokeh;  // highlights bloom
        col   += tcol * w;
        total += w;
    }
    col /= total;

    float a = inTex.sample(s, uv).a;
    outTex.write(float4(col, a), gid);
}
