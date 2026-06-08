#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Canvas Flip — the whole frame rotates in 3D about its vertical axis like a
// card, with real perspective foreshortening. The back face shows the frame
// mirrored; the gaps revealed as the card turns edge-on show a dim mirrored
// copy behind. CapCut-style "Canvas Flip", looped as a continuous spin.
//
//   * Reads the live video frame from inTex (texture 0) — the iChannel0 analogue.
//   * Mirrored backing: back face = horizontally mirrored frame; bg = dim mirror.
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

kernel void fx_canvas_flip(
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

    float2 p = uv - 0.5;

    // Rotate the card about its vertical (Y) axis and project with perspective.
    // Invert the projection: given screen p.x, solve for the card-local x (lx).
    float a  = t * 1.2;                 // continuous spin
    float ca = cos(a), sa = sin(a);
    float kp = 0.8;                     // perspective strength

    float denom = ca - p.x * sa * kp;   // -> 0 at the silhouette edge
    float lx    = p.x / denom;          // card-local x  (-0.5..0.5 on card)
    float Z     = lx * sa;
    float ly    = p.y * (1.0 + Z * kp); // card-local y

    bool onCard = (abs(lx) <= 0.5) && (abs(ly) <= 0.5);
    bool back   = ca < 0.0;

    float texU = lx + 0.5;
    float texV = ly + 0.5;
    if (back) { texU = 1.0 - texU; }    // mirror the back face

    float3 card = inTex.sample(s, float2(texU, texV)).rgb;
    float3 bg   = inTex.sample(s, float2(1.0 - uv.x, uv.y)).rgb * 0.25;  // dim mirror behind
    float3 flip = onCard ? card : bg;

    float4 srcN = inTex.sample(s, uv);
    float3 outc = mix(srcN.rgb, flip, k);
    outTex.write(float4(outc, srcN.a), gid);
}
