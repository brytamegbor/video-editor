// ---------------------------------------------------------------------------
// Tile Scroller (GLSL) — mirrors tile-scroller.metal. The frame is tiled into a
// rotating grid whose rows scroll in opposite directions, with breathing row
// count and padding. Adapted from the "Tile Scroller" Shadertoy.
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

vec2 rotateCoord(vec2 uv, float rads) {
    uv *= mat2(cos(rads), sin(rads), -sin(rads), cos(rads));
    return uv;
}

float map(float value, float low1, float high1, float low2, float high2) {
    return low2 + (value - low1) * (high2 - low2) / (high1 - low1);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float rows    = 1.0 + 0.5 * sin(iTime);
    float padding = 0.4 + 0.8 * cos(iTime);
    float aspect  = 16.0 / 9.0;

    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
    uv = rotateCoord(uv, 0.2 * sin(iTime));
    uv.y *= aspect; // fix aspect ratio

    // calc row index to offset x of every other row
    float rowIndex = floor(uv.y * rows);
    float oddEven  = mod(rowIndex, 2.0);

    // create grid coords; scroll alternating rows in opposite directions
    vec2 uvRepeat;
    if (oddEven == 1.0) {
        uvRepeat = fract(vec2(iTime, 0.0) + uv * rows);
    } else {
        uvRepeat = fract(vec2(-iTime, 0.0) + uv * rows);
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
    float centerDistX  = distance(center, uvRepeat.x);
    float centerDistY  = distance(center, uvRepeat.y);
    if (centerDistX > repeatThresh - aa) alphaX = map(centerDistX, repeatThresh - aa, repeatThresh + aa, 1.0, 0.0);
    if (centerDistY > repeatThresh - aa) alphaY = map(centerDistY, repeatThresh - aa, repeatThresh + aa, 1.0, 0.0);
    float alpha = min(alphaX, alphaY);

    vec4 tile = texture(iChannel0, uvRepeat);
    tile = mix(vec4(1.0), tile, alpha); // tiles sit on a white gutter

    vec4 clean = texture(iChannel0, fragCoord / iResolution.xy);
    vec3 outc  = mix(clean.rgb, tile.rgb, iIntensity);
    fragColor = vec4(outc, clean.a);
}
