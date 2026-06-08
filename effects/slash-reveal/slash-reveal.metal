#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Slash Reveal — a bright diagonal slash sweeps across the frame; ahead of the
// cut the image is reflected across the moving slash line (a mirror seam),
// behind it the true frame shows through, with a hot light streak riding the
// edge. CapCut-style "Slash" reveal, looped back and forth.
//
//   * Reads the live video frame from inTex (texture 0) — the iChannel0 analogue.
//   * Mirrored backing: the hidden side is the frame reflected across the slash.
//   * Continuous loop: a triangle wave sweeps the slash so it never pops.
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

    // Slash geometry: a line at -30deg; `nrm` is its normal, `proj` the signed
    // distance of this pixel from the frame centre along that normal.
    float  ang  = -0.5235988;                     // radians(-30)
    float2 dir  = float2(cos(ang), sin(ang));
    float2 nrm  = float2(-dir.y, dir.x);
    float  proj = dot(uv - 0.5, nrm);

    // Sweep the slash position across the frame and back (triangle wave -> no pop).
    float tri = 1.0 - abs(fract(t * 0.5) * 2.0 - 1.0);   // 0..1..0
    float sp  = (tri * 2.0 - 1.0) * 0.5;                 // -0.5..0.5..-0.5

    float  side = step(sp, proj);                        // 1 ahead of the cut
    float2 mir  = clamp(uv - 2.0 * (proj - sp) * nrm, 0.0, 1.0);  // reflect across slash

    float4 srcN = inTex.sample(s, uv);
    float3 mC   = inTex.sample(s, mir).rgb;
    float3 col  = mix(srcN.rgb, mC, side);

    // Hot light streak riding the cut.
    float streak = smoothstep(0.05, 0.0, abs(proj - sp));
    col += float3(1.0, 0.95, 0.9) * streak * (0.7 + 0.3 * sin(t * 25.0));

    float3 outc = mix(srcN.rgb, col, k);
    outTex.write(float4(outc, srcN.a), gid);
}
