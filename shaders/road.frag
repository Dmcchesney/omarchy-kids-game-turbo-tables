#version 440

// The circuit's ground plane, drawn analytically, one pixel at a time.
//
// There is no geometry here and there is no per-frame work in JavaScript. The
// fragment shader inverts the camera projection: for every pixel below the
// horizon it recovers the distance down the track and the lateral position on
// the floor, and then asks what is at that spot -- road, rumble strip, lane
// marking, or the floor's diagnostic grid. Curves, the horizon, the scroll
// and the fog are a handful of uniforms, so the road bends and rushes with no
// vertex buffer to rebuild and nothing for the CPU to do but set numbers.
//
// GOLDEN HOUR. Above the horizon this shader draws NOTHING: the sky is
// ui/parts/SunsetSky.qml, an item behind this plane, and the plane blends
// over it. Below the horizon the floor is near-black purple with a neon
// magenta grid, fading with distance INTO THE HORIZON GLOW, and the sun's
// foot spills a warm elliptical glow across the far floor and the road. The
// tarmac fogs slower than the floor, so the road stays a legible ribbon out
// to the vanishing point instead of dissolving into the ground at z = 30.
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
    float gridScale;    // spacing of the floor grid, world units
    float fogDensity;   // how fast the far end fades into the dusk
    float surfaceFog;   // fraction of fogDensity the tarmac and kerbs take
    float glowAmount;   // strength of the sun's glow on the floor, 0..1
    float gridAlpha;    // how strongly the grid lines show over the ground
    float sunU;         // the sun's centre, 0..1 across the plane
    float glowRx;       // half-width of the sun-foot glow, fraction of width
    float glowRy;       // depth of the sun-foot glow below the horizon, fraction of height

    vec4 roadColor;
    vec4 roadAlt;
    vec4 rumbleColor;
    vec4 rumbleAlt;
    vec4 laneColor;
    vec4 groundColor;
    vec4 gridColor;
    vec4 skyColor;      // unused by this pass; kept so the uniform block matches CanvasRoad
    vec4 fogColor;
    vec4 glowColor;
};

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

    // Invert the projection. v = horizon + focal * camHeight / (2 z), so
    // z = focal * camHeight / (2 (v - horizon)); and the lateral world
    // position follows from the same focal length, corrected for the
    // curve, which is what makes the road bend away.
    float z = (focal * camHeight) / (2.0 * dy);
    float x = ((u - 0.5) * 2.0 * aspect) * z / focal - curve * z * z;
    float s = z + travel;
    float ax = abs(x);

    // Alternating bands down the track, the rumble strips' rhythm and the
    // reason a still frame still reads as speed once it moves.
    float band = step(0.5, fract(s / stripe));

    // How much fine detail survives at this distance. Between the horizon
    // and about y = 480 the road is four internal pixels wide, and a hard
    // black-and-cream zebra blown up by a nearest-neighbour filter there
    // reads as speckle rather than as fog. So the alternations dissolve
    // toward their own average with distance and the far road resolves
    // into a smooth dark ribbon that still shows which way it bends.
    float detail = smoothstep(52.0, 16.0, z);
    float softBand = mix(0.5, band, detail);

    vec3 road = mix(roadColor.rgb, roadAlt.rgb, softBand * 0.34);
    vec3 rumble = mix(rumbleColor.rgb, rumbleAlt.rgb, softBand);

    // The floor grid, both ways, off the road, in three octaves: the finer
    // two fade in as the floor comes toward the eye, so the bottom of the
    // frame -- where a racer sells speed -- is never an empty black.
    float fine = smoothstep(12.0, 4.5, z) * 0.72;
    float finer = smoothstep(4.6, 2.2, z) * 0.55;
    float g0 = max(lineMask(x, gridScale, 0.030), lineMask(s, gridScale, 0.030));
    float g1 = max(lineMask(x, gridScale * 0.25, 0.030),
                   lineMask(s, gridScale * 0.25, 0.030));
    float g2 = max(lineMask(x, gridScale * 0.0625, 0.030),
                   lineMask(s, gridScale * 0.0625, 0.030));
    float grid = max(g0, max(g1 * fine, g2 * finer * 0.85));
    vec3 floorCol = mix(groundColor.rgb, gridColor.rgb, grid * gridAlpha);

    float onRumble = insideMask(ax, roadHalf + rumbleHalf);
    float onRoad = insideMask(ax, roadHalf);

    // Lane markings: a dashed centre line and two solid inner edge lines.
    // The dash period is four rumble bands, so the centre line reads as a
    // dashed line rather than as another zebra.
    float dash = step(0.45, fract(s / (stripe * 2.0)));
    float centre = insideMask(ax, roadHalf * 0.030) * dash;
    float inner = abs(ax - roadHalf * 0.88);
    float edgeLine = insideMask(inner, roadHalf * 0.016);
    float marks = clamp(max(centre, edgeLine), 0.0, 1.0);

    vec3 col = mix(floorCol, rumble, onRumble);
    col = mix(col, road, onRoad);
    col = mix(col, laneColor.rgb, marks * onRoad * 0.88 * detail);

    // Dusk, INTO THE GLOW, AND THE ROAD SURVIVES IT.
    //
    // Quadratic in distance so the near floor stays crisp and the vanishing
    // point dissolves rather than ending at a hard line. Two things changed
    // here in round four, and both are the same defect:
    //
    //   * `fogColor` is now the horizon glow rather than a purple darker than
    //     the ground. The design says the floor is "the diagnostic grid in
    //     neon over near-black purple, FADING INTO THE GLOW" -- the far floor
    //     was fading into something darker than what it started from, so the
    //     distance read as a hole rather than as a sunset.
    //   * the tarmac and its kerbs fog at `surfaceFog` of the floor's rate.
    //     With one density the road reached the fog's colour at the same
    //     distance the floor did, so past about twenty world units the road
    //     and the ground either side of it were the same number: measured on
    //     the shipped frame, the road's luminance was within 7 of the floor's
    //     from z = 30 outward, which is a child not being able to see where
    //     the road goes. A slower fog on the surface keeps a dark ribbon with
    //     bright kerbs all the way to where it leaves the frame.
    //
    // This is a picture rule, not physics, and it is the same rule the genre
    // has always used: the road is the thing the eye must follow.
    float surface = max(onRumble, onRoad);
    float fogFloor = exp(-fogDensity * z * z * 0.0011);
    float fogRoad = exp(-fogDensity * surfaceFog * z * z * 0.0011);
    float fog = mix(fogFloor, fogRoad, surface);
    col = mix(fogColor.rgb, col, clamp(fog, 0.0, 1.0));

    // The sun's foot: a warm ellipse spilling down from the horizon under the
    // disc, over floor and road alike. This is what "the grid fades into the
    // horizon glow" means in pixels.
    vec2 gd = vec2((u - sunU) / glowRx, dy / glowRy);
    col = mix(col, glowColor.rgb, glowFall(length(gd)) * glowAmount);

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
