#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Tile Scroller — the live frame is tiled into a rotating grid whose rows
// scroll in opposite directions, with a breathing row count and gutter padding.
// Adapted from the "Tile Scroller" Shadertoy to magic_edit's single live-frame
// contract.
//
// Porting notes (Shadertoy -> our contract):
//   * iChannel0 -> inTex (texture 0); iResolution -> (u.width, u.height);
//     iTime -> u.time. fragCoord includes the (offsetX, offsetY) tile origin.
//   * GLSL `uv *= mat2(c,s,-s,c)` is a row-vector * column-major matrix, i.e.
//     (c*x + s*y, -s*x + c*y) — done explicitly in rotateCoord below.
//   * GLSL mod(x, 2.0) is floor-based (always >= 0); fmod is sign-of-x, so the
//     odd/even row test uses a floor-based glslMod for negative row indices.
//   * GLSL distance(scalar, scalar) -> fabs(a - b).
//   * `u.intensity` cross-fades from the clean clip to the full effect.
// ---------------------------------------------------------------------------

struct EffectUniforms {
    float time;
    float intensity;
    float width;
    float height;
    float offsetX;
    float offsetY;
};

// GLSL `uv * mat2(cos,sin,-sin,cos)` (row vector * column-major matrix).
inline float2 rotateCoord(float2 uv, float rads) {
    float c = cos(rads), s = sin(rads);
    return float2(c * uv.x + s * uv.y, -s * uv.x + c * uv.y);
}

inline float mapRange(float value, float low1, float high1, float low2, float high2) {
    return low2 + (value - low1) * (high2 - low2) / (high1 - low1);
}

// floor-based modulo, matching GLSL mod().
inline float glslMod(float x, float y) {
    return x - y * floor(x / y);
}

kernel void fx_tile_scroller(
    texture2d<float, access::sample> inTex  [[texture(0)]],
    texture2d<float, access::write>  outTex [[texture(1)]],
    constant EffectUniforms&         u      [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) { return; }
    constexpr sampler smp(coord::normalized, address::repeat, filter::linear);

    float2 res = float2(u.width, u.height);
    float2 fragCoord = float2(gid) + float2(u.offsetX, u.offsetY);

    float rows    = 1.0 + 0.5 * sin(u.time);
    float padding = 0.4 + 0.8 * cos(u.time);
    float aspect  = 16.0 / 9.0;

    float2 uv = (2.0 * fragCoord - res) / res.y;
    uv = rotateCoord(uv, 0.2 * sin(u.time));
    uv.y *= aspect; // fix aspect ratio

    // calc row index to offset x of every other row
    float rowIndex = floor(uv.y * rows);
    float oddEven  = glslMod(rowIndex, 2.0);

    // create grid coords; scroll alternating rows in opposite directions
    float2 uvRepeat;
    if (oddEven == 1.0) {
        uvRepeat = fract(float2(u.time, 0.0) + uv * rows);
    } else {
        uvRepeat = fract(float2(-u.time, 0.0) + uv * rows);
    }

    // add padding and only draw once per cell
    uvRepeat *= 1.0 + padding * 2.0;
    uvRepeat -= padding;

    // antialias the cell edges so tiles blend smoothly
    float alphaX       = 1.0;
    float alphaY       = 1.0;
    float center       = 0.5;
    float repeatThresh = 0.51; // push out a little so we don't cut texture off
    float aa           = (repeatThresh - center) * 0.5;
    float centerDistX  = fabs(center - uvRepeat.x);
    float centerDistY  = fabs(center - uvRepeat.y);
    if (centerDistX > repeatThresh - aa) alphaX = mapRange(centerDistX, repeatThresh - aa, repeatThresh + aa, 1.0, 0.0);
    if (centerDistY > repeatThresh - aa) alphaY = mapRange(centerDistY, repeatThresh - aa, repeatThresh + aa, 1.0, 0.0);
    float alpha = min(alphaX, alphaY);

    float4 tile = inTex.sample(smp, uvRepeat);
    tile = mix(float4(1.0), tile, alpha); // tiles sit on a white gutter

    float4 clean = inTex.sample(smp, fragCoord / res);
    float3 outc  = mix(clean.rgb, tile.rgb, u.intensity);
    outTex.write(float4(outc, clean.a), gid);
}
