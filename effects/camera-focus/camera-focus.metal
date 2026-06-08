#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Camera Focus — draws a phone-camera autofocus reticle over the live frame: a
// square of four corner brackets with a dot in the middle, centred, doing a
// brief "lock" animation (snaps in from slightly larger, then settles) on a
// loop. CapCut-style "Camera Focus".
//
//   * Reads the live video frame from inTex (texture 0) — the iChannel0 analogue.
//   * All overlay geometry is built from SDF-style masks with a fixed pixel AA
//     width (compute kernels have no derivatives, so no fwidth).
//   * `intensity` is the reticle's opacity; at 0 the frame is untouched.
// ---------------------------------------------------------------------------

struct EffectUniforms {
    float time;
    float intensity;
    float width;
    float height;
    float offsetX;
    float offsetY;
};

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

    float4 base = inTex.sample(s, uv);

    // Centre on the frame, aspect-corrected so the reticle is square (1 unit = height).
    float  aspect = res.x / res.y;
    float2 p = (uv - 0.5);
    p.x *= aspect;

    float px = 1.0 / res.y;
    float aa = 1.2 * px;

    // Autofocus "lock": each cycle the frame snaps in from 1.26x to 1.0x and holds.
    float ph    = fract(t / 2.2);
    float lock  = pow(1.0 - clamp(ph / 0.35, 0.0, 1.0), 2.0);   // 1 -> 0
    float scale = 1.0 + 0.26 * lock;

    float h        = 0.16 * scale;        // square half-size
    float legLen   = h * 0.32;            // corner bracket leg length
    float lineHalf = 1.6 * px;            // half line thickness

    // Four corner brackets: draw the square's edges, but only the segments near
    // each corner (an L at each of the 4 corners).
    float dV = abs(abs(p.x) - h);         // distance to vertical edges
    float dH = abs(abs(p.y) - h);         // distance to horizontal edges
    float lineV = 1.0 - smoothstep(lineHalf, lineHalf + aa, dV);
    float lineH = 1.0 - smoothstep(lineHalf, lineHalf + aa, dH);

    float legY = smoothstep(h - legLen - aa, h - legLen + aa, abs(p.y)) *
                 (1.0 - smoothstep(h + lineHalf, h + lineHalf + aa, abs(p.y)));
    float legX = smoothstep(h - legLen - aa, h - legLen + aa, abs(p.x)) *
                 (1.0 - smoothstep(h + lineHalf, h + lineHalf + aa, abs(p.x)));

    float bracket = max(lineV * legY, lineH * legX);

    // Centre dot.
    float dotR  = 0.012;
    float dotM  = 1.0 - smoothstep(dotR, dotR + aa, length(p));

    float reticle = max(bracket, dotM);

    // Brighten on the lock snap for a crisp "focus confirmed" feel.
    float  glow      = 0.65 + 0.35 * lock;
    float3 lineColor = float3(1.0, 0.97, 0.85);

    float3 col  = mix(base.rgb, lineColor, reticle * glow);
    float3 outc = mix(base.rgb, col, k);
    outTex.write(float4(outc, base.a), gid);
}
