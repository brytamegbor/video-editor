#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Flip Page — a page sweeps diagonally across the frame, wrapping around a
// rolling cylinder so the current frame peels off and reveals the frame
// underneath. Looped as a continuous page-turn.
//
// Adapted from "Flip Page" by Lucian Stanculescu (2019), free to use.
//
//   * Reads the live video frame from inTex (texture 0) — the iChannel0 analogue.
//   * The page wraps around a cylinder of radius PAGE_R * width travelling across
//     the frame; the back face of the curl shows the wrapped, dimmed content.
//   * `intensity` cross-fades the flip in; at 0 the frame is untouched.
// ---------------------------------------------------------------------------

struct EffectUniforms {
    float time;
    float intensity;
    float width;
    float height;
    float offsetX;
    float offsetY;
};

constant float PAGE_R   = 0.3;          // radius of rolling cylinder (fraction of width)
constant float PAGE_REP = 3.0;          // seconds per page-turn loop
constant float PI       = 3.141592653;

kernel void fx_flip_page(
    texture2d<float, access::sample> inTex  [[texture(0)]],
    texture2d<float, access::write>  outTex [[texture(1)]],
    constant EffectUniforms&         u      [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) { return; }
    constexpr sampler smp(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 res = float2(u.width, u.height);
    float  k   = u.intensity;

    float R    = PAGE_R * res.x;           // radius of rolling cylinder (px)
    float v    = 1.5 * res.x / PAGE_REP;   // sweep speed
    float time = fract(u.time / PAGE_REP); // 0..1 progress through the loop

    float2 s   = float2(gid) + float2(u.offsetX, u.offsetY); // pixel coordinates
    float2 dir = normalize(float2(5.0, 1.0));                // direction of movement
    float2 o   = float2(time * PAGE_REP * v, 0.0);           // origin of cylinder

    float  d = dot(s - o, dir); // signed distance to generator of cylinder
    float2 h = s - dir * d;     // projection on generator

    bool  onCylinder = fabs(d) < R;
    float angle      = onCylinder ? asin(d / R) : 0.0;
    bool  neg        = d < 0.0;

    float a0 = PI + angle;
    float a  = onCylinder ? (neg ? -angle : (PI + angle)) : 0.0; // angle

    float  l = R * a;       // length of arc
    float2 p = h - dir * l; // unwrapped point from cylinder to plane
    bool   outside = any(p < float2(0.0)) || any(p > res);

    bool previous = (!onCylinder || outside) && neg;
    bool page     = !onCylinder || outside;

    float4 color;
    if (page) color = inTex.sample(smp, s / res);
    else      color = inTex.sample(smp, p / res);
    color *= (previous ? mix(0.1, 1.0, time) : 1.0);

    l = R * a0;       // length of arc (back face of the curl)
    p = h - dir * l;  // unwrapped point from cylinder to plane
    outside = any(p < float2(0.0)) || any(p > res);
    color = (outside || !onCylinder) ? color : inTex.sample(smp, p / res);

    float4 srcN = inTex.sample(smp, s / res);
    float3 outc = mix(srcN.rgb, color.rgb, k);
    outTex.write(float4(outc, srcN.a), gid);
}
