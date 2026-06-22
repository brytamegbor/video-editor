#include <metal_stdlib>
using namespace metal;

// Rolls (gl-transitions, by Mark Craig) — params: type = params.x, RotDown =
// params.y. Full wrapped kernel; the kernel name MUST match the descriptor's
// `kernel` field.

struct TransitionUniforms {
    float progress; float ratio; float width; float height;
    float4 params;
};

// gl-transitions sample with a y-up uv (origin bottom-left). Metal textures are
// top-left origin, so these helpers flip v.
#define getFromColor(p) fromTex.sample(_s, float2((p).x, 1.0 - (p).y))
#define getToColor(p)   toTex.sample(_s, float2((p).x, 1.0 - (p).y))

#define M_PI 3.14159265358979323846

static inline float4 _trBody(
    float2 uv, float progress, float ratio, float4 params, float2 resolution,
    texture2d<float, access::sample> fromTex,
    texture2d<float, access::sample> toTex,
    sampler _s)
{
    int type = params.x;
    bool RotDown = params.y;
    float theta, c1, s1;
    float2 iResolution = float2(ratio, 1.0);
    float2 uvi;
    // I used if/else instead of switch in case it's an old GPU
    if (type == 0) { theta = (RotDown ? M_PI : -M_PI) / 2.0 * progress; uvi.x = 1.0 - uv.x; uvi.y = uv.y; }
    else if (type == 1) { theta = (RotDown ? M_PI : -M_PI) / 2.0 * progress; uvi = uv; }
    else if (type == 2) { theta = (RotDown ? -M_PI : M_PI) / 2.0 * progress; uvi.x = uv.x; uvi.y = 1.0 - uv.y; }
    else if (type == 3) { theta = (RotDown ? -M_PI : M_PI) / 2.0 * progress; uvi = 1.0 - uv; }
    c1 = cos(theta); s1 = sin(theta);
    float2 uv2;
    uv2.x = (uvi.x * iResolution.x * c1 - uvi.y * iResolution.y * s1);
    uv2.y = (uvi.x * iResolution.x * s1 + uvi.y * iResolution.y * c1);
    if ((uv2.x >= 0.0) && (uv2.x <= iResolution.x) && (uv2.y >= 0.0) && (uv2.y <= iResolution.y))
    {
        uv2 /= iResolution;
        if (type == 0) { uv2.x = 1.0 - uv2.x; }
        else if (type == 2) { uv2.y = 1.0 - uv2.y; }
        else if (type == 3) { uv2 = 1.0 - uv2; }
        return(getFromColor(uv2));
    }
    return(getToColor(uv));
}

kernel void trx_rolls(
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
