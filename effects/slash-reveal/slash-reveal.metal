#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Slash Reveal — a bright blade slashes the frame along the bottom-left -> top-
// right "/" diagonal, cutting the top layer open to reveal what's beneath. The
// revealed (beneath) side is an offset mirror of the frame; a hot streak rides
// the cut. CapCut-style "Slash" reveal, looped (cut opens, then seals, repeat).
//
//   * Reads the live video frame from inTex (texture 0) — the iChannel0 analogue.
//   * `n` is the slash normal chosen so the seam reads as "/" on screen even
//     though Metal's grid is y-down (gid.y = 0 at the top).
//   * `intensity` cross-fades the whole reveal in; at 0 the frame is untouched.
// ---------------------------------------------------------------------------

struct EffectUniforms {
    float time;
    float intensity;
    float width;
    float height;
    float offsetX;
    float offsetY;
};

kernel void fx_slash_reveal(
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

    // Seam runs bottom-left -> top-right ("/"); `n` is its normal. On Metal's
    // y-down grid that screen diagonal corresponds to normal (-1,-1).
    float2 n = normalize(float2(-1.0, -1.0));
    float  d = dot(uv - 0.5, n);                 // signed distance from centre

    // Sweep the cut across and back so the loop never pops. Starts fully closed
    // (all top layer), opens to fully revealed, then seals.
    float tri = abs(fract(t * 0.5) * 2.0 - 1.0); // 1 -> 0 -> 1
    float sp  = (tri * 2.0 - 1.0) * 0.72;        // +0.72 (closed) .. -0.72 (open)

    float px = 1.0 / res.y;
    float aa = 1.5 * px;

    float4 srcN   = inTex.sample(s, uv);
    float  reveal = smoothstep(sp - aa, sp + aa, d);            // 1 = cut open here

    // What's beneath: an offset horizontal mirror of the frame.
    float2 bUV     = clamp(float2(1.0 - uv.x, uv.y) - n * 0.015, 0.0, 1.0);
    float3 beneath = inTex.sample(s, bUV).rgb;

    float3 col = mix(srcN.rgb, beneath, reveal);

    // Hot blade streak riding the cut.
    float streak = smoothstep(0.02, 0.0, abs(d - sp));
    col += float3(1.0, 0.96, 0.9) * streak * (0.75 + 0.25 * sin(t * 22.0));

    float3 outc = mix(srcN.rgb, col, k);
    outTex.write(float4(outc, srcN.a), gid);
}
