#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Mosaic — ported from the GL-transitions "Mosaic" shader (Xaychru, MIT,
// https://gist.github.com/Xaychru/130bb7b7affedbda9df5) to magic_edit's single
// live-frame contract.
//
// Porting notes (GL-transitions -> our contract):
//   * GL transitions need TWO clips (getFromColor / getToColor) + a `progress`
//     uniform. We only have one live frame (inTex / iChannel0), so both the
//     "from" and "to" sample the same clip — it becomes a self-contained mosaic
//     shuffle instead of a clip-to-clip wipe.
//   * `progress` is looped from u.time. This transition is the identity at BOTH
//     progress 0 and 1, so a plain sawtooth loops seamlessly (no ping-pong).
//   * `mod(rp, 1.0)` -> fract(rp) (identical for modulus 1, and fract is
//     floor-based so it's correct for the negative tile coords this shader uses).
//   * endx/endy uniforms -> constants (the shader's documented defaults).
//   * `u.intensity` fades from the clean clip to the full effect.
// ---------------------------------------------------------------------------

struct EffectUniforms {
    float time;
    float intensity;
    float width;
    float height;
    float offsetX;
    float offsetY;
};

constant float MPI   = 3.14159265358979323;
constant int   END_X = 2;
constant int   END_Y = -1;

inline float rand2(float2 v) {
    return fract(sin(dot(v, float2(12.9898, 78.233))) * 43758.5453);
}
// Matches GLSL mat2(c,-s,s,c) * v (column-major).
inline float2 rot2(float2 v, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * v.x + s * v.y, -s * v.x + c * v.y);
}
inline float cosInterp(float x) {
    return -cos(x * MPI) / 2.0 + 0.5;
}

kernel void fx_mosaic(
    texture2d<float, access::sample> inTex  [[texture(0)]],
    texture2d<float, access::write>  outTex [[texture(1)]],
    constant EffectUniforms&         u      [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) { return; }
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 res = float2(u.width, u.height);
    float2 uv  = (float2(gid) + float2(u.offsetX, u.offsetY)) / res;

    float progress = fract(u.time * 0.32);

    // --- transition() body, ported ---
    float2 p   = uv - 0.5;
    float2 rp  = p;
    float  rpr = progress * 2.0 - 1.0;
    float  z   = -(rpr * rpr * 2.0) + 3.0;
    float  az  = abs(z);
    rp *= az;
    float ci = cosInterp(progress);
    rp += mix(float2(0.5, 0.5),
              float2(float(END_X) + 0.5, float(END_Y) + 0.5),
              ci * ci);                       // POW2(CosInterpolation(progress))

    float2 mrp = fract(rp);                   // mod(rp, 1.0)
    float2 crp = rp;
    bool onEnd = int(floor(crp.x)) == END_X && int(floor(crp.y)) == END_Y;
    if (!onEnd) {
        float ang = float(int(rand2(floor(crp)) * 4.0)) * 0.5 * MPI;
        mrp = float2(0.5) + rot2(mrp - float2(0.5), ang);
    }

    // getFromColor == getToColor == the single live clip.
    float4 tileCol = inTex.sample(s, mrp);

    float4 clean = inTex.sample(s, uv);
    float3 outc  = mix(clean.rgb, tileCol.rgb, u.intensity);
    outTex.write(float4(outc, clean.a), gid);
}
