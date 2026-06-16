// ---------------------------------------------------------------------------
// Vertical Scroll (GLSL) — mirrors vertical-scroll.metal. The live frame is
// tiled into a single scrolling lane that pans up/down (or left/right) with an
// ease-in-out cycle. Adapted from the "Vertical Scroll" Shadertoy.
//
// Host-provided uniforms (GL analogue of the Metal EffectUniforms):
//   uniform sampler2D iChannel0;   // input video frame (the live clip)
//   uniform vec3      iResolution; // viewport px (.xy used)
//   uniform float     iTime;       // elapsed seconds (drives the loop)
//   uniform float     iIntensity;  // 0..1 strength; 0 == untouched frame
// Entry point: void mainImage(out vec4 fragColor, in vec2 fragCoord)
// (Delete the iIntensity line below if your host already injects it.)
// ---------------------------------------------------------------------------
uniform float iIntensity;

// vertical scroll: 1 / horizontal scroll: 0
#define SCROLL_DIRECTION 1
//#define FIX_CENTER

#define PI 3.14159265358979323846
#define TILE_WIDTH 0.7   // relative tile width; smaller = thinner columns

float map(float value, float low1, float high1, float low2, float high2) {
    return low2 + (value - low1) * (high2 - low2) / (high1 - low1);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float padding   = 0.015;
    float aspect    = 16.0 / 9.0;
    float cycleTime = mod(iTime, 2.0) / 2.0;
    float time      = 3.0 * cos((cycleTime + 1.0) * PI) / 2.0 + 0.5;

    vec2 uv = (1.5 * fragCoord - iResolution.xy) / iResolution.y;
    uv.y *= aspect;       // fix aspect ratio
    uv.x /= TILE_WIDTH;   // tile width (smaller = thinner columns)

    #if (SCROLL_DIRECTION == 0)
        float rows = 1.;
        // calc row index to offset x of every other row
        float rowIndex = floor(uv.y * rows);
        float oddEven  = mod(rowIndex, 2.);

        // create grid coords & set color
        vec2 uvRepeat = fract(uv * rows);
        if (oddEven == 1.) {
            #ifdef FIX_CENTER
                uvRepeat = fract(vec2(0.5, 0.) + uv * rows);
            #else
                uvRepeat = fract(vec2(time, 0.) + uv * rows); // scroll override
            #endif
        } else {
            uvRepeat = fract(vec2(-time, 0.) + uv * rows); // scroll override
        }

        // add padding and only draw once per cell
        uvRepeat *= 1. + padding * 2.;
        uvRepeat -= padding;
    #else
        float columns = 1.;
        // calc column index to offset y of every other column
        float columnIndex = floor(uv.x * columns);
        float oddEven     = mod(columnIndex, 2.);

        // create grid coords & set color
        vec2 uvRepeat = fract(uv * columns);
        if (oddEven == 1.) {
            #ifdef FIX_CENTER
                uvRepeat = fract(vec2(0., 0.5) + uv * columns);
            #else
                uvRepeat = fract(vec2(0., -time) + uv * columns); // scroll override
            #endif
        } else {
            uvRepeat = fract(vec2(0., time) + uv * columns); // scroll override
        }

        // add padding and only draw once per cell
        uvRepeat *= 1. + padding * 2.;
        uvRepeat -= padding;
    #endif

    // antialias the cell edges so tiles blend smoothly
    float alphaX       = 1.0;
    float alphaY       = 1.0;
    float center       = 0.5;
    float repeatThresh = 0.51; // push out a little so we don't cut texture off
    float aa           = (repeatThresh - center) * 0.5;
    float centerDistX  = distance(center, uvRepeat.x);
    float centerDistY  = distance(center, uvRepeat.y);
    if (centerDistX > repeatThresh - aa) alphaX = map(centerDistX, repeatThresh - aa, repeatThresh + aa, 1., 0.);
    if (centerDistY > repeatThresh - aa) alphaY = map(centerDistY, repeatThresh - aa, repeatThresh + aa, 1., 0.);
    float alpha = min(alphaX, alphaY);

    vec4 tile = texture(iChannel0, uvRepeat);
    tile = mix(vec4(1.), tile, alpha); // tiles sit on a white gutter

    vec4 clean = texture(iChannel0, fragCoord / iResolution.xy);
    vec3 outc  = mix(clean.rgb, tile.rgb, iIntensity);
    fragColor = vec4(outc, clean.a);
}
