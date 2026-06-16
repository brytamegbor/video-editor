#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Vertical Scroll — the live frame is tiled into a single scrolling lane that
// pans vertically with an ease-in-out cycle. Adapted from the "Vertical Scroll"
// Shadertoy to magic_edit's single live-frame contract.
//
// Porting notes (Shadertoy -> our contract):
//   * iChannel0 -> inTex (texture 0); iResolution -> (u.width, u.height);
//     iTime -> u.time. fragCoord includes the (offsetX, offsetY) tile origin.
//   * The source guards a horizontal variant behind SCROLL_DIRECTION; the
//     shader's default (and its name) is vertical, so only that path is ported.
//     The FIX_CENTER static-offset branch (disabled by default) is omitted too.
//   * GLSL mod(x, 2.0) is floor-based (always >= 0); fmod is sign-of-x, so the
//     odd/even column test uses a floor-based glslMod for negative indices.
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

constant float PI = 3.14159265358979323846;
constant float TILE_WIDTH  = 0.45; // relative tile width; smaller = thinner columns
constant float TILE_HEIGHT = 0.6;  // relative tile height; smaller = shorter rows

inline float mapRange(float value, float low1, float high1, float low2, float high2) {
    return low2 + (value - low1) * (high2 - low2) / (high1 - low1);
}

// floor-based modulo, matching GLSL mod().
inline float glslMod(float x, float y) {
    return x - y * floor(x / y);
}

kernel void fx_vertical_scroll(
    texture2d<float, access::sample> inTex  [[texture(0)]],
    texture2d<float, access::write>  outTex [[texture(1)]],
    constant EffectUniforms&         u      [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) { return; }
    constexpr sampler smp(coord::normalized, address::repeat, filter::linear);

    float2 res = float2(u.width, u.height);
    float2 fragCoord = float2(gid) + float2(u.offsetX, u.offsetY);

    float padding   = 0.015;
    float aspect    = 16.0 / 9.0;
    float cycleTime = glslMod(u.time, 2.0) / 2.0;
    float time      = 3.0 * cos((cycleTime + 1.0) * PI) / 2.0 + 0.5;

    float2 uv = (1.5 * fragCoord - res) / res.y;
    uv.y *= aspect;       // fix aspect ratio
    uv.x /= TILE_WIDTH;   // tile width  (smaller = thinner columns)
    uv.y /= TILE_HEIGHT;  // tile height (smaller = shorter rows)

    // vertical scroll (SCROLL_DIRECTION == 1)
    float columns     = 1.0;
    float columnIndex = floor(uv.x * columns);
    float oddEven     = glslMod(columnIndex, 2.0);

    float2 uvRepeat;
    if (oddEven == 1.0) {
        uvRepeat = fract(float2(0.0, -time) + uv * columns); // scroll override
    } else {
        uvRepeat = fract(float2(0.0, time) + uv * columns);  // scroll override
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
