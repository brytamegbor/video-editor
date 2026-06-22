#include <metal_stdlib>
using namespace metal;

// Parametric Glitch (gl-transitions, by Yoni Maltsman) — params: ampx =
// params.x, ampy = params.y. Full wrapped kernel; the kernel name MUST match
// the descriptor's `kernel` field.

struct TransitionUniforms {
    float progress; float ratio; float width; float height;
    float4 params;
};

// gl-transitions sample with a y-up uv (origin bottom-left). Metal textures are
// top-left origin, so these helpers flip v.
#define getFromColor(p) fromTex.sample(_s, float2((p).x, 1.0 - (p).y))
#define getToColor(p)   toTex.sample(_s, float2((p).x, 1.0 - (p).y))

static inline float4 _trBody(
    float2 uv, float progress, float ratio, float4 params, float2 resolution,
    texture2d<float, access::sample> fromTex,
    texture2d<float, access::sample> toTex,
    sampler _s)
{
    float ampx = params.x;
    float ampy = params.y;
    float4 from = getFromColor(uv);
    float4 to = getToColor(uv);
    float r = from.r;
    float g = from.g;
    float b = from.b;
    float sphere = r * r + g * g + b * b - 1.0;
    float spiralX = cos(sphere - uv.x / (progress + 0.01));
    float spiralY = sin(sphere - uv.y / (progress + 0.01));
    float2 st = uv;
    st.x = fract(ampx * st.x * spiralX);
    st.y = fract(ampy * st.y * spiralY);
    float2 diff = uv - st;
    from = getFromColor(uv + progress * diff);
    return mix(from, to, progress);
}

kernel void trx_parametric_glitch(
    texture2d<float, access::sample> fromTex [[texture(0)]],
    texture2d<float, access::sample> toTex   [[texture(1)]],
    texture2d<float, access::write>  outTex  [[texture(2)]],
    constant TransitionUniforms&     u       [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint w = outTex.get_width();
    uint h = outTex.get_height();
    if (gid.x >= w || gid.y >= h) { return; }
    constexpr sampler _s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = float2((float(gid.x) + 0.5) / float(w),
                       1.0 - (float(gid.y) + 0.5) / float(h));
    float4 c = _trBody(uv, u.progress, u.ratio, u.params,
                       float2(float(w), float(h)), fromTex, toTex, _s);
    outTex.write(c, gid);
}
