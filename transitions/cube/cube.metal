#include <metal_stdlib>
using namespace metal;

// Cube (gl-transitions, by gre) — params: persp = params.x, unzoom = params.y,
// reflection = params.z, floating = params.w. Full wrapped kernel; the kernel
// name MUST match the descriptor's `kernel` field.

struct TransitionUniforms {
    float progress; float ratio; float width; float height;
    float4 params;
};

// gl-transitions sample with a y-up uv (origin bottom-left). Metal textures are
// top-left origin, so these helpers flip v.
#define getFromColor(p) fromTex.sample(_s, float2((p).x, 1.0 - (p).y))
#define getToColor(p)   toTex.sample(_s, float2((p).x, 1.0 - (p).y))

static inline bool inBounds(float2 p) {
    return p.x > 0.0 && p.y > 0.0 && p.x < 1.0 && p.y < 1.0;
}

static inline float2 project(float2 p, float floating) {
    return p * float2(1.0, -1.2) + float2(0.0, -floating / 100.0);
}

// p      : the position
// persp  : the perspective in [0, 1]
// center : the xcenter in [0, 1] \ 0.5 excluded
static inline float2 xskew(float2 p, float persp, float center) {
    float x = mix(p.x, 1.0 - p.x, center);
    // Metal's distance() has no scalar overload, so abs(a - b) stands in for the
    // gl-transitions scalar distance(center, 0.5).
    float dc = abs(center - 0.5);
    return (
        (
            float2(x, (p.y - 0.5 * (1.0 - persp) * x) / (1.0 + (persp - 1.0) * x))
                - float2(0.5 - dc, 0.0)
        )
        * float2(0.5 / dc * (center < 0.5 ? 1.0 : -1.0), 1.0)
        + float2(center < 0.5 ? 0.0 : 1.0, 0.0)
    );
}

static inline float4 _trBody(
    float2 uv, float progress, float ratio, float4 params, float2 resolution,
    texture2d<float, access::sample> fromTex,
    texture2d<float, access::sample> toTex,
    sampler _s)
{
    float persp      = params.x;
    float unzoom     = params.y;
    float reflection = params.z;
    float floating   = params.w;

    float2 op = uv;
    float uz = unzoom * 2.0 * (0.5 - abs(0.5 - progress));
    float2 p = -uz * 0.5 + (1.0 + uz) * op;
    float2 fromP = xskew(
        (p - float2(progress, 0.0)) / float2(1.0 - progress, 1.0),
        1.0 - mix(progress, 0.0, persp),
        0.0);
    float2 toP = xskew(
        p / float2(progress, 1.0),
        mix(pow(progress, 2.0), 1.0, persp),
        1.0);

    if (inBounds(fromP)) {
        return getFromColor(fromP);
    } else if (inBounds(toP)) {
        return getToColor(toP);
    }

    // bgColor: dark backdrop with each face's floor reflection.
    float4 c = float4(0.0, 0.0, 0.0, 1.0);
    float2 pfr = project(fromP, floating);
    if (inBounds(pfr)) {
        c += mix(float4(0.0), getFromColor(pfr), reflection * mix(1.0, 0.0, pfr.y));
    }
    float2 pto = project(toP, floating);
    if (inBounds(pto)) {
        c += mix(float4(0.0), getToColor(pto), reflection * mix(1.0, 0.0, pto.y));
    }
    return c;
}

kernel void trx_cube(
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
