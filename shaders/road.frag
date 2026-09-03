#version 440

// The garage circuit's ground plane, drawn analytically, one pixel at a time.
//
// There is no geometry here and there is no per-frame work in JavaScript. The
// fragment shader inverts the camera projection: for every pixel below the
// horizon it recovers the distance down the track and the lateral position on
// the floor, and then asks what is at that spot -- road, rumble strip, lane
// marking, or the garage's diagnostic grid. Curves, the horizon, the scroll
// and the fog are a handful of uniforms, so the road bends and rushes with no
// vertex buffer to rebuild and nothing for the CPU to do but set numbers.
//
// The same inversion is written out in QML in TrackView.qml (`groundV`,
// `laneU`, `spriteScale`) so the karts and the props land on the road this
// shader draws, and again in CanvasRoad.qml so the fallback draws the same
// picture. Those three have to agree; the comment at the top of TrackView.qml
// names the four lines that must match.
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
    float gridScale;    // spacing of the garage floor grid, world units
    float fogDensity;   // how fast the far end fades into the dark
    float glowAmount;   // strength of the work-light pools on the tarmac

    vec4 roadColor;
    vec4 roadAlt;
    vec4 rumbleColor;
    vec4 rumbleAlt;
    vec4 laneColor;
    vec4 groundColor;
    vec4 gridColor;
    vec4 skyColor;
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

void main()
{
    float u = qt_TexCoord0.x;
    float v = qt_TexCoord0.y;
    float dy = v - horizon;

    vec3 col;

    if (dy <= 0.0) {
        // Above the horizon: the far wall of the garage, and a band of warm
        // haze sitting on the horizon where the work lights are.
        // The warm half is kept to the bottom quarter of the wall; spread
        // over all of it, it reads as a sunset, and this game is indoors.
        float t = clamp(-dy / max(horizon, 0.001), 0.0, 1.0);
        col = mix(groundColor.rgb * 0.34, skyColor.rgb, clamp((t - 0.24) / 0.76, 0.0, 1.0));
        col += glowColor.rgb * exp(-t * 16.0) * 0.30;
    } else {
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

        vec3 road = mix(roadColor.rgb, roadAlt.rgb, band * 0.34);
        vec3 rumble = mix(rumbleColor.rgb, rumbleAlt.rgb, band);

        // The garage floor: a diagnostic grid, both ways, off the road.
        float gridX = lineMask(x, gridScale, 0.030);
        float gridZ = lineMask(s, gridScale, 0.030);
        vec3 floorCol = mix(groundColor.rgb, gridColor.rgb, max(gridX, gridZ) * 0.80);

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

        col = mix(floorCol, rumble, onRumble);
        col = mix(col, road, onRoad);
        col = mix(col, laneColor.rgb, marks * onRoad * 0.88);

        // Pools of amber where the work lights hang over the track.
        float pool = fract(s / (stripe * 12.0)) - 0.5;
        col += glowColor.rgb * exp(-pool * pool * 26.0) * glowAmount * onRoad;

        // Fog. Quadratic in distance so the near road stays crisp and the
        // vanishing point dissolves rather than ending at a hard line.
        float fog = exp(-fogDensity * z * z * 0.0011);
        col = mix(fogColor.rgb, col, clamp(fog, 0.0, 1.0));
    }

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
