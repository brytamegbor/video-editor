#include <metal_stdlib>
using namespace metal;

// Burn (gl-transitions, by liubailin2020) — params: burnColor.rgb =
// (params.x, params.y, params.z). Full wrapped kernel; the kernel name MUST
// match the descriptor's `kernel` field.

struct TransitionUniforms {
    float progress; float ratio; float width; float height;
    float4 params;
};

// gl-transitions sample with a y-up uv (origin bottom-left). Metal textures are
// top-left origin, so these helpers flip v.
#define getFromColor(p) fromTex.sample(_s, float2((p).x, 1.0 - (p).y))
#define getToColor(p)   toTex.sample(_s, float2((p).x, 1.0 - (p).y))

static inline float _rand(float2 st) {
    return fract(sin(dot(st, float2(12.9898, 78.233))) * 43758.5453123);
}

// Based on Morgan McGuire @morgan3d — https://www.shadertoy.com/view/4dS3Wd
static inline float _noise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);
    float a = _rand(i);
    float b = _rand(i + float2(1.0, 0.0));
    float c = _rand(i + float2(0.0, 1.0));
    float d = _rand(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) +
           (c - a) * u.y * (1.0 - u.x) +
           (d - b) * u.x * u.y;
}

#define OCTAVES 4
static inline float _fbm(float2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < OCTAVES; i++) {
        value += amplitude * _noise(st);
        st *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

static inline float4 _trBody(
    float2 uv, float progress, float ratio, float4 params, float2 resolution,
    texture2d<float, access::sample> fromTex,
    texture2d<float, access::sample> toTex,
    sampler _s)
{
    float3 burnColor = float3(params.x, params.y, params.z);
    if (progress <= 0.0) return getFromColor(uv);
    if (progress >= 1.0) return getToColor(uv);
    float4 from = getFromColor(uv);
    float4 to = getToColor(uv);
    float n = _fbm(uv * 4.0);
    float l = smoothstep(progress, progress + 0.05, n);
    float edge = (1.0 - l) * l * 5.0;
    return mix(to, from, l) + float4(burnColor, 0.0) * edge;
}

kernel void trx_burn(
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
