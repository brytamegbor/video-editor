#include <metal_stdlib>
using namespace metal;

// Scaleddown (gl-transitions, by Thibaut Foussard) — params: direction =
// (params.x, params.y), scale = params.z. Full wrapped kernel; the kernel name
// MUST match the descriptor's `kernel` field.

struct TransitionUniforms {
    float progress; float ratio; float width; float height;
    float4 params;
};

// gl-transitions sample with a y-up uv (origin bottom-left). Metal textures are
// top-left origin, so these helpers flip v.
#define getFromColor(p) fromTex.sample(_s, float2((p).x, 1.0 - (p).y))
#define getToColor(p)   toTex.sample(_s, float2((p).x, 1.0 - (p).y))

#define PI acos(-1.0)
static inline float parabola(float x) {
    float y = pow(sin(x * PI), 1.);
    return y;
}

static inline float4 _trBody(
    float2 uv, float progress, float ratio, float4 params, float2 resolution,
    texture2d<float, access::sample> fromTex,
    texture2d<float, access::sample> toTex,
    sampler _s)
{
    float2 direction = float2(params.x, params.y);
    float scale = params.z;
    float easedProgress = pow(sin(progress  * PI / 2.), 3.);
    float2 p = uv + easedProgress * sign(direction);
    float2 f = fract(p);

    float s = 1. - (1. - (1. / scale)) * parabola(progress);
    f = (f - 0.5) * s  + 0.5;

    float mixer = step(0.0, p.y) * step(p.y, 1.0) * step(0.0, p.x) * step(p.x, 1.0);
    float4 col = mix(getToColor(f), getFromColor(f), mixer);

    float border = step(0., f.x) * step(0., (1. - f.x)) * step(0., f.y) * step(0., 1. - f.y);
    col *= border;

    return col;
}

kernel void trx_scaleddown(
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
