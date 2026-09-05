#version 440

// The circuit's ground plane, drawn analytically, one pixel at a time.
//
// There is no geometry here and there is no per-frame work in JavaScript. The
// fragment shader inverts the camera projection: for every pixel below the
// horizon it recovers the distance down the track and the lateral position on
// the floor, and then asks what is at that spot -- terrain, road, kerb, kart
// line, water, or the pit's diagnostic grid. Curves, the horizon, the scroll
// and the haze are a handful of uniforms, so the road bends and rushes with no
// vertex buffer to rebuild and nothing for the CPU to do but set numbers.
//
// GOLDEN HOUR. Above the horizon this shader draws NOTHING: the sky is
// ui/parts/SunsetSky.qml, an item behind this plane, and the plane blends
// over it.
//
// PIECE T -- THE GROUND IS TERRAIN, NOT A GRID.
//
// Design v4, The circuit, "One shader change that does most of the work":
// ground palette by sector, two octaves of value noise, ATMOSPHERIC
// PERSPECTIVE ("the single biggest step toward the bar"), road craft (crown,
// tyre lines, kerbs only inside corners, the start grid, skid marks at corner
// exits), the lake with the sun reflected in it, and heat shimmer near the sun.
// All of it is here. The diagnostic grid survives only at the pit, sectors 1
// and 12, which is sectors 0 and 11 in this file's indexing.
//
// THE TABLES BELOW ARE A MIRROR, NOT A SOURCE. `ui/parts/Terrain.js` holds the
// sector palettes, the sector curve table, the lattice sizes and the integer
// hash; this file repeats them because GLSL cannot read a .js, and
// `npm run check:terrain` compares the two number by number and fails the build
// when they drift. That check exists because "the fallback draws the same
// picture" has been asserted three times in this project and measured false
// twice.
//
// THE NOISE IS BLOCKS. `hashCell` is a 32-bit integer hash that wraps
// identically in GLSL's `uint` and in JavaScript's `Math.imul`, evaluated on a
// world-space lattice and FLAT inside a cell. So the ground is made of the same
// pixels the road is, the fallback can fill exactly the same blocks with quads,
// and nothing here is a smooth gradient floating over a blocky world.
//
// The same inversion is written out in QML in TrackView.qml (`vAt`, `uAt`,
// `sizeAt`) so the karts and the props land on the road this shader draws,
// and again in CanvasRoad.qml so the fallback draws the same picture. Those
// three have to agree; the comment at the top of TrackView.qml names the four
// lines that must match.
//
// Baked with:  qsb --qt6 -o shaders/road.frag.qsb shaders/road.frag
// The .qsb is committed. It is a Qt shader container, not an executable.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;

    // Where the eye is and how wide it sees.
    float horizon;      // horizon line, 0..1 down the plane. Hills move it.
    float camHeight;    // eye height above the road, in world units
    float focal;        // 1 / tan(fov / 2)
    float aspect;       // plane width / plane height

    // Where the road is.
    float travel;       // distance travelled, world units, always increasing
    float curve;        // lateral bend, applied as curve * z * z
    float roadHalf;     // half the road's width, world units
    float rumbleHalf;   // width of one rumble strip, world units
    float stripe;       // length of one rumble band, world units
    float gridScale;    // spacing of the pit's floor grid, world units
    float fogDensity;   // how fast the far end fades into the dusk
    float surfaceFog;   // fraction of fogDensity the tarmac and kerbs take
    float glowAmount;   // strength of the sun's glow on the floor, 0..1
    float gridAlpha;    // how strongly the grid lines show over the ground
    float sunU;         // the sun's centre, 0..1 across the plane
    float glowRx;       // half-width of the sun-foot glow, fraction of width
    float glowRy;       // depth of the sun-foot glow below the horizon, fraction of height

    // ------------------------------------------------------------- piece T
    float sectorLength; // world units per sector; twelve of them make a lap
    float clock;        // seconds of race time, for ripples and shimmer
    float shimmer;      // heat haze over the far road, 0..1
    float texelU;       // one plane pixel across, in u -- the shimmer's step
    float nightfall;    // 0 at lap 1, 1 at lap 12: how far the sun has set

    vec4 roadColor;
    vec4 roadAlt;
    vec4 rumbleColor;
    vec4 rumbleAlt;
    vec4 laneColor;
    vec4 groundColor;
    vec4 gridColor;
    vec4 skyColor;      // unused by this pass; kept so the uniform block matches CanvasRoad
    vec4 fogColor;      // THE HAZE. Every surface lerps toward it by distance.
    vec4 glowColor;
    vec4 waterColor;    // the lake, away from the reflection
    vec4 waterLit;      // the sun's column on the water
};

// ---------------------------------------------------- Terrain.js, mirrored
// Checked against ui/parts/Terrain.js by npm run check:terrain.
const float SECTOR_CURVE[12] = float[12](
    0.00, 0.10, -0.45, -1.00, -0.80, -0.20,
    0.00, 0.55, 1.00, 0.62, 0.15, -0.10);

const vec3 SOIL[12] = vec3[12](
    vec3(0.2353, 0.0706, 0.1569),
    vec3(0.2824, 0.1255, 0.1725),
    vec3(0.3059, 0.1255, 0.1569),
    vec3(0.2902, 0.1412, 0.2039),
    vec3(0.2275, 0.0863, 0.1882),
    vec3(0.2000, 0.0902, 0.1882),
    vec3(0.2392, 0.1176, 0.1804),
    vec3(0.4196, 0.2275, 0.2039),
    vec3(0.2275, 0.1020, 0.1647),
    vec3(0.2627, 0.1255, 0.1647),
    vec3(0.4824, 0.2902, 0.3059),
    vec3(0.2353, 0.0706, 0.1569));

const vec3 SCRUB[12] = vec3[12](
    vec3(0.2902, 0.1020, 0.1882),
    vec3(0.3608, 0.1961, 0.1882),
    vec3(0.4196, 0.2275, 0.1725),
    vec3(0.4000, 0.2235, 0.2902),
    vec3(0.3020, 0.1412, 0.2510),
    vec3(0.1412, 0.0784, 0.1569),
    vec3(0.3255, 0.1804, 0.2353),
    vec3(0.5686, 0.3412, 0.2471),
    vec3(0.2902, 0.1490, 0.2118),
    vec3(0.3882, 0.2000, 0.1647),
    vec3(0.5882, 0.3765, 0.3608),
    vec3(0.2902, 0.1020, 0.1882));

// [grid, water, wind, scrubAmount] per sector.
const vec4 FLAGS[12] = vec4[12](
    vec4(1.0, 0.0, 0.0, 0.22),
    vec4(0.0, 0.0, 0.0, 0.72),
    vec4(0.0, 0.0, 0.0, 1.00),
    vec4(0.0, 0.0, 0.0, 0.66),
    vec4(0.0, 1.0, 0.0, 0.54),
    vec4(0.0, 0.0, 0.0, 0.88),
    vec4(0.0, 0.0, 0.0, 0.40),
    vec4(0.0, 0.0, 1.0, 0.58),
    vec4(0.0, 0.0, 0.0, 0.62),
    vec4(0.0, 0.0, 0.0, 0.94),
    vec4(0.0, 0.0, 0.0, 0.30),
    vec4(1.0, 0.0, 0.0, 0.22));

const float COARSE = 2.0;
const float FINE = 0.5;
const float RUT = 1.0;

// The integer hash. Every operation is 32-bit and wrapping, so this is the
// same number JavaScript's Math.imul chain produces for the same cell.
float hashCell(float cx, float cy)
{
    uint h = uint(int(cx)) * 374761393u + uint(int(cy)) * 668265263u;
    h = (h ^ (h >> 13u)) * 1274126177u;
    h = h ^ (h >> 16u);
    return float(h >> 16u) / 65536.0;
}

float blockNoise(float x, float s, float size)
{
    return hashCell(floor(x / size), floor(s / size));
}

// ---------------------------------------------------------------- helpers
// An anti-aliased line mask: 1 on the line, 0 off it, and the transition is
// exactly one pixel wide however far away the line is. Without the derivative
// term the floor grid turns into a moire storm at the horizon, which is the
// single most obvious way a shader road looks wrong.
float lineMask(float coord, float period, float halfWidth)
{
    float scaled = coord / period;
    float w = fwidth(scaled);
    float d = abs(fract(scaled - 0.5) - 0.5);
    return 1.0 - smoothstep(halfWidth * w, halfWidth * w + w, d);
}

// An anti-aliased edge: 1 inside `edge`, 0 outside it.
float insideMask(float value, float edge)
{
    float w = fwidth(value) + 1e-5;
    return 1.0 - smoothstep(edge - w, edge + w, value);
}

// The sun-foot glow's falloff over its normalised radius: piecewise linear
// through the same three stops CanvasRoad's radial gradient uses, so the two
// renderers agree to the pixel.
float glowFall(float d)
{
    if (d >= 1.0)
        return 0.0;
    if (d < 0.5)
        return mix(0.55, 0.18, d / 0.5);
    return mix(0.18, 0.0, (d - 0.5) / 0.5);
}

int wrapSector(int i)
{
    int n = i - (i / 12) * 12;
    return n < 0 ? n + 12 : n;
}

// Terrain.js `sectorMix`: which sector, and how far into the crossfade.
void sectorMix(float s, out int a, out int b, out float t)
{
    float circuit = sectorLength * 12.0;
    float p = mod(mod(s, circuit) + circuit, circuit) / sectorLength;
    float i = floor(p);
    float f = p - i;
    a = wrapSector(int(i));
    b = wrapSector(int(i) + 1);
    t = smoothstep(0.84, 1.0, f);
}

// Terrain.js `curveNormAt`: the normalised bend at a point down the track.
float curveNormAt(float s)
{
    float circuit = sectorLength * 12.0;
    float p = mod(mod(s, circuit) + circuit, circuit) / sectorLength;
    float i = floor(p);
    float f = p - i;
    float sm = f * f * (3.0 - 2.0 * f);
    return mix(SECTOR_CURVE[wrapSector(int(i))], SECTOR_CURVE[wrapSector(int(i) + 1)], sm);
}

void main()
{
    float u = qt_TexCoord0.x;
    float v = qt_TexCoord0.y;
    float dy = v - horizon;

    if (dy <= 0.0) {
        // Above the horizon: the sky item behind this plane shows through.
        fragColor = vec4(0.0);
        return;
    }

    // HEAT SHIMMER, AND IT IS A WHOLE-ROW DISPLACEMENT ON PURPOSE.
    //
    // Design v4, Life: "Heat shimmer over the road near the sun, a small
    // distortion in the shader." A per-pixel warp would be free here and
    // impossible in CanvasRoad, which fills quads -- and "the fallback draws
    // the same picture" is a gate on this piece. So the shimmer displaces a
    // ROW, by a whole plane pixel at a time, in a band a tenth of the frame
    // deep under the horizon. The fallback slides the same band by the same
    // integer, and the two frames stay identical.
    float band = smoothstep(0.085, 0.006, dy);
    float wobble = sin(v * 190.0 + clock * 2.6) * 0.55 + sin(v * 71.0 - clock * 1.7) * 0.45;
    u += floor(shimmer * band * wobble * 1.6 + 0.5) * texelU;

    // Invert the projection. v = horizon + focal * camHeight / (2 z), so
    // z = focal * camHeight / (2 (v - horizon)); and the lateral world
    // position follows from the same focal length, corrected for the
    // curve, which is what makes the road bend away.
    float z = (focal * camHeight) / (2.0 * dy);
    float x = ((u - 0.5) * 2.0 * aspect) * z / focal - curve * z * z;
    float s = z + travel;
    float ax = abs(x);

    int secA, secB;
    float secT;
    sectorMix(s, secA, secB, secT);
    vec4 flags = mix(FLAGS[secA], FLAGS[secB], secT);

    // Alternating bands down the track, the rumble strips' rhythm and the
    // reason a still frame still reads as speed once it moves.
    float zebra = step(0.5, fract(s / stripe));

    // How much fine detail survives at this distance. Between the horizon
    // and about y = 480 the road is four internal pixels wide, and a hard
    // black-and-cream zebra blown up by a nearest-neighbour filter there
    // reads as speckle rather than as fog. So the alternations dissolve
    // toward their own average with distance and the far road resolves
    // into a smooth dark ribbon that still shows which way it bends.
    float detail = smoothstep(52.0, 16.0, z);
    float softBand = mix(0.5, zebra, detail);

    // ------------------------------------------------------------ terrain
    // Two octaves of blocks, the fine one fading out with distance, then ruts
    // running parallel to the road. Terrain.js `groundAt`, per pixel.
    vec3 soil = mix(SOIL[secA], SOIL[secB], secT);
    vec3 scrub = mix(SCRUB[secA], SCRUB[secB], secT);
    float ff = smoothstep(22.0, 6.0, z);
    float coarse = blockNoise(x, s, COARSE);
    float fine = blockNoise(x, s, FINE);
    float mask = clamp((coarse * 0.78 + fine * 0.22 * ff - 0.42) / 0.30, 0.0, 1.0) * flags.w;
    vec3 floorCol = mix(soil, scrub, mask);
    float rut = blockNoise(x, s * 0.24, RUT);
    floorCol *= 0.90 + 0.20 * rut + 0.10 * (fine - 0.5) * ff;

    // THE DUNES' WIND LINES. Long diagonal ridges across the sand, drawn as
    // blocks on the same lattice so they belong to the ground rather than
    // being ruled over it.
    if (flags.z > 0.001) {
        float wind = blockNoise(x + s * 0.4, s * 0.10, COARSE);
        floorCol *= 1.0 + flags.z * (wind - 0.5) * 0.34;
    }

    // ------------------------------------------------------- the pit floor
    // The diagnostic grid, both ways, in three octaves -- and ONLY where the
    // sector table says it belongs, which the design limits to the pit.
    if (flags.x > 0.001) {
        float fineOct = smoothstep(12.0, 4.5, z) * 0.72;
        float finerOct = smoothstep(4.6, 2.2, z) * 0.55;
        float g0 = max(lineMask(x, gridScale, 0.030), lineMask(s, gridScale, 0.030));
        float g1 = max(lineMask(x, gridScale * 0.25, 0.030),
                       lineMask(s, gridScale * 0.25, 0.030));
        float g2 = max(lineMask(x, gridScale * 0.0625, 0.030),
                       lineMask(s, gridScale * 0.0625, 0.030));
        float grid = max(g0, max(g1 * fineOct, g2 * finerOct * 0.85));
        floorCol = mix(floorCol, gridColor.rgb, grid * gridAlpha * flags.x);
    }

    // ----------------------------------------------------------- the lake
    // Design v4: "in the lake sector the plane beside the road is water, and
    // the sun reflects in it as a stretched, rippling column. It is the bar's
    // own image, and it is ten lines of shader."
    //
    // The water is on the RIGHT, because the sun is: a reflection is a column
    // under the disc, so the lake has to be under it or there is nothing to
    // reflect. The column is in SCREEN u -- that is what a reflection is -- and
    // the ripples break it into horizontal rungs that stretch with distance.
    float shore = roadHalf + rumbleHalf + 2.6;
    float water = flags.y * step(shore, x);
    if (water > 0.001) {
        float ripple = sin(s * 2.7 - clock * 1.9) * 0.5 + sin(s * 6.1 + clock * 1.1) * 0.5;
        float rungs = step(0.0, ripple);
        vec3 lake = mix(waterColor.rgb, waterColor.rgb * 1.18, rungs);
        float column = clamp(1.0 - abs(u - sunU) / 0.075, 0.0, 1.0);
        column *= column;
        // The rungs cut the column into a ladder rather than a smooth beam,
        // and the ladder widens toward the eye.
        float ladder = column * (0.45 + 0.55 * rungs);
        lake = mix(lake, waterLit.rgb, ladder);
        floorCol = mix(floorCol, lake, water * smoothstep(shore, shore + 1.1, x));
    }

    float onRumble = insideMask(ax, roadHalf + rumbleHalf);
    float onRoad = insideMask(ax, roadHalf);

    // ------------------------------------------------------- the road craft
    vec3 road = mix(roadColor.rgb, roadAlt.rgb, softBand * 0.34);

    // Patches: worn tarmac, on a lattice four times the coarse one so a patch
    // is a slab rather than gravel.
    float wear = blockNoise(x, s, COARSE * 3.0);
    road *= 0.94 + 0.12 * wear;

    // A CROWN. The centre of the road is a little proud of its edges, so the
    // tarmac has a surface instead of being a flat fill.
    float crown = 1.0 - (ax / roadHalf) * (ax / roadHalf);
    road *= 0.88 + 0.20 * crown;

    // TWO TYRE LINES PER LANE. Four dark tracks, at the wheel spacing of a
    // kart in each of the two lanes, polished a shade darker than the tarmac
    // either side of them.
    float track0 = insideMask(abs(ax - roadHalf * 0.30), roadHalf * 0.055);
    float track1 = insideMask(abs(ax - roadHalf * 0.70), roadHalf * 0.055);
    road *= 1.0 - 0.16 * max(track0, track1) * detail;

    // SKID MARKS AT CORNER EXITS. Where the bend is unwinding -- the curve's
    // magnitude a few units back is bigger than a few units ahead -- two dark
    // arcs run off toward the OUTSIDE of the corner just left, which is where
    // a car that ran wide put them.
    float cHere = curveNormAt(s);
    float cAhead = curveNormAt(s + 7.0);
    float exiting = clamp((abs(cHere) - abs(cAhead)) * 7.0, 0.0, 1.0)
                    * smoothstep(0.30, 0.62, abs(cHere));
    if (exiting > 0.002) {
        float side = cHere > 0.0 ? -1.0 : 1.0;   // outside of the bend
        float drift = 0.34 + 0.34 * clamp((abs(cHere) - 0.3) / 0.7, 0.0, 1.0);
        float m0 = insideMask(abs(x - side * roadHalf * drift), roadHalf * 0.075);
        float m1 = insideMask(abs(x - side * roadHalf * (drift + 0.30)), roadHalf * 0.060);
        road *= 1.0 - 0.30 * max(m0, m1) * exiting * detail;
    }

    // ------------------------------------------------------------ the kerbs
    // Design v4: "kerbs only inside corners (driven by the curve value)".
    // Positive curve bends the road right, so the inside of the bend is the
    // right verge. Where there is no kerb the strip is a dirt shoulder in the
    // sector's own soil, a shade darker than the verge behind it -- so a
    // straight has an edge without a fairground zebra on it.
    float bend = smoothstep(0.22, 0.72, abs(cHere));
    float kerbHere = (x > 0.0) == (cHere > 0.0) ? bend : 0.0;
    vec3 zebraCol = mix(rumbleColor.rgb, rumbleAlt.rgb, softBand);
    vec3 shoulder = soil * 0.72;
    vec3 rumble = mix(shoulder, zebraCol, kerbHere);

    // ------------------------------------------------------- the start grid
    // The chequered grid on the tarmac at the pit, which the child crosses at
    // the start of every lap. Three world units of it, eight squares across.
    float gp = mod(mod(s, sectorLength * 12.0) + sectorLength * 12.0, sectorLength * 12.0);
    float inGrid = step(2.0, gp) * step(gp, 5.0) * detail;
    if (inGrid > 0.001) {
        float cx = floor((x + roadHalf) / (roadHalf * 0.25));
        float cy = floor((gp - 2.0) / 0.75);
        float chequer = mod(cx + cy, 2.0);
        road = mix(road, mix(roadColor.rgb * 0.55, rumbleAlt.rgb, chequer), inGrid * 0.88);
    }

    vec3 col = mix(floorCol, rumble, onRumble);
    col = mix(col, road, onRoad);

    // Lane markings: a dashed centre line and two solid inner edge lines.
    // The dash period is four rumble bands, so the centre line reads as a
    // dashed line rather than as another zebra.
    float dash = step(0.45, fract(s / (stripe * 2.0)));
    float centre = insideMask(ax, roadHalf * 0.030) * dash;
    float inner = abs(ax - roadHalf * 0.88);
    float edgeLine = insideMask(inner, roadHalf * 0.016);
    float marks = clamp(max(centre, edgeLine), 0.0, 1.0);
    col = mix(col, laneColor.rgb, marks * onRoad * 0.88 * detail * (1.0 - inGrid));

    // ------------------------------------------- ATMOSPHERIC PERSPECTIVE
    //
    // Every ground, kerb and road colour lerps toward the sky's own colour at
    // the horizon with distance -- design v4 calls this "the single biggest
    // step toward the bar". `fogColor` is that colour, and TrackView drives it
    // from the same sunset the sky is painted from, so as the sun sets over
    // twelve laps the whole world's distance goes with it.
    //
    // Quadratic in distance so the near floor stays crisp and the vanishing
    // point dissolves rather than ending at a hard line. The tarmac and its
    // kerbs take `surfaceFog` of the floor's rate: with one density the road
    // reached the haze's colour at the same distance the floor did, so past
    // about twenty world units the road and the ground either side of it were
    // the same number -- measured on the shipped frame, within 7 of 255 from
    // z = 30 outward, which is a child not being able to see where the road
    // goes. A slower haze on the surface keeps a dark ribbon with bright kerbs
    // all the way to where it leaves the frame. This is a picture rule, not
    // physics, and it is the rule the genre has always used: the road is the
    // thing the eye must follow.
    float surface = max(onRumble, onRoad);
    float fogFloor = exp(-fogDensity * z * z * 0.0011);
    float fogRoad = exp(-fogDensity * surfaceFog * z * z * 0.0011);
    float fog = mix(fogFloor, fogRoad, surface);
    col = mix(fogColor.rgb, col, clamp(fog, 0.0, 1.0));

    // The sun's foot: a warm ellipse spilling down from the horizon under the
    // disc, over floor and road alike. This is what "the grid fades into the
    // horizon glow" means in pixels. It dims as the sun sets.
    vec2 gd = vec2((u - sunU) / glowRx, dy / glowRy);
    col = mix(col, glowColor.rgb, glowFall(length(gd)) * glowAmount * (1.0 - 0.45 * nightfall));

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
