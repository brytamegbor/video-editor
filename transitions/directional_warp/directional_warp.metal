#include <metal_stdlib>
using namespace metal;

// Directional Warp (gl-transitions, by pschroen) — params: direction.xy =
// (params.x, params.y), smoothness = params.z. Full wrapped kernel; the kernel
// name MUST match the descriptor's `kernel` field.

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
    float2 direction = float2(params.x, params.y);
    float smoothness = max(0.0001, params.z);
    float2 center = float2(0.5, 0.5);
    float2 v = normalize(direction);
    v /= abs(v.x) + abs(v.y);
    float d = v.x * center.x + v.y * center.y;
    float m = 1.0 - smoothstep(-smoothness, 0.0,
        v.x * uv.x + v.y * uv.y - (d - 0.5 + progress * (1.0 + smoothness)));
    return mix(getFromColor((uv - 0.5) * (1.0 - m) + 0.5),
               getToColor((uv - 0.5) * m + 0.5), m);
}

kernel void trx_directional_warp(
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
