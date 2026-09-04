# The prop kit

Twenty-five baked sprites for the circuit and the power-ups, under `assets/props/`. One indexed PNG per prop, `props-meta.json` beside them, a SHA-256 `manifest.json` that `npm run check:props` holds the tree to, and `ui/parts/PropMeta.js` as the meta's layer-2 mirror. Made on 2026-09-04 from the maintainer's decisions across seven review rounds; the model is `src/tools/bake-props.py` and nothing else.

**Frozen assets.** A build agent places, scales, animates, tints and crops these; it never redraws one, edits a PNG, or adds a file under `assets/props/`. A prop that needs to change goes back through the bake with the maintainer looking at it. `npm run props` rebakes on the Mac; `npm run props -- --verify` proves the bake reproduces the committed bytes.

## How a sheet is laid out

- **Columns** are the views in `META[name].views` order. `R` and `L` are the prop standing on the right and left verge, seen from the road camera: the sun stays on the right, so a left-verge prop is a different render, not a mirror. `C` is a centred view for things that span the road or fly over it. A trailing digit is the animation frame (`R0`, `R1`...).
- **Rows** are scales 1, 0.5 and 0.25, packed from the left at each scale; `META[name].rows` holds each row's top edge.
- **Anchor**: `META[name].ground` is the ground point in cell pixels at scale 1 for a standing prop (bottom-centre, with a little room under it for the contact shadow); `null` for an effect sprite, which is centred.
- **Bounds**: `META[name].bounds[view]` is the opaque box at scale 1. Small props carry a transparent margin because the camera never comes closer than about half its stock distance; crop to the bounds when the margin matters.
- **Density**: FINE = 4 times the karts' pixels per world unit, so a prop drawn at the projection's size upscales about half as much as a kart near the camera. That is the maintainer's "a step finer than the cars."
- **Palette**: the fixed palette plus each prop's declared paint ramps, the same quantise, despeckle and sunward outline as the car sheets. Nothing is anti-aliased; scale with `smooth: false`.

## The kit

| Prop | World w × h | Views | Cell at 1.0 | Sheet | Anchor | Where it lives | Notes |
|---|---|---|---|---|---|---|---|
| `banner` | 3.2 × 2.2 | R0, L0 | 472×352 | 944×616 | ground | Sector 2 and straights | baked TURBO mark; the blank board for printed text is `billboard` |
| `billboard` | 3.8 × 3.0 | R0, L0 | 592×472 | 1184×826 | ground | Sector 11 | blank cream board: print the child's last three correct facts on it |
| `bridge` | 9.8 × 5.2 | C0 | 1408×792 | 1408×1386 | ground | Sector 6, spanning the road | wooden truss |
| `cone` | 0.7 × 0.9 | R0, L0 | 422×152 | 844×266 | ground | Anywhere, sparingly | filler |
| `crowd` | 4.2 × 2.1 | R0, R1, R2, R3, L0, L1, L2, L3 | 632×336 | 5056×588 | ground | Sector 1 and 12 behind the tyre walls | four frames: a wave of jumps and raised arms rolling along the rail; never two crowds in phase |
| `distanceBoard` | 1.3 × 1.9 | R0, R1, L0, L1 | 422×304 | 1688×532 | ground | Before every corner | frame 0 reads 200, frame 1 reads 100 |
| `drum` | 0.9 × 1.1 | R0, L0 | 422×184 | 844×322 | ground | Pit, quarry, scrapyard | filler |
| `gantry` | 9.8 × 5.2 | C0, C1 | 1464×800 | 2928×1400 | ground | Sector 1 and 12, spanning the road | start and finish; two frames flap the flags |
| `hayBale` | 1.4 × 0.8 | R0, L0 | 422×136 | 844×238 | ground | Corners, sectors 2 to 6 | soft furniture on the outside of a bend |
| `hubcap` | 0.7 × 0.7 | C0, C1, C2 | 422×112 | 1266×196 | centre | Effect: Pothole hit | three frames of a tumble, edge-on to face-on |
| `jetty` | 1.8 × 1.2 | R0, L0 | 608×200 | 1216×350 | ground | Sector 5, lake side | runs away from the road over the water the shader draws |
| `markerPost` | 0.3 × 1.3 | R0, L0 | 422×216 | 844×378 | ground | Both verges on straights, spaced | the smallest prop; crop to `bounds` |
| `oilSlick` | 2.2 × 0.3 | C0 | 424×72 | 424×126 | centre | Effect: Oil Slick card, under each rival | flat decal, foreshortened by the road camera |
| `overpass` | 9.8 × 4.8 | C0 | 1400×736 | 1400×1288 | ground | Sector 9, spanning the road | its shadow crosses the tarmac |
| `pileUp` | 3.0 × 1.6 | C0 | 624×288 | 624×504 | centre | Effect: Pile-Up card, on the road ahead of the victim | the wreck; draw smoke above it in QML |
| `pine` | 1.8 × 5.3 | R0, R1, L0, L1 | 504×896 | 2016×1568 | ground | Sectors 6 and 9 | two silhouettes from one model; frame 1 is taller and thinner |
| `pitBoard` | 2.0 × 2.0 | R0, L0 | 422×320 | 844×560 | ground | Sector 1 | the readout is a flat teal tone for the game to print the split on |
| `pothole` | 1.8 × 0.3 | C0 | 424×88 | 424×154 | centre | Effect: Pothole card, ahead of the victim | flat decal |
| `rockWall` | 6.5 × 3.8 | R0, L0 | 1336×592 | 2672×1036 | ground | Sector 4, both verges | the quarry; R and L are different banks |
| `rollerDoor` | 9.8 × 5.6 | C0, C1 | 1488×856 | 2976×1498 | ground | Sector 7, spanning the road | the garage; frame 1 has one lamp out, for the flicker |
| `scrapyard` | 3.6 × 2.6 | R0, L0 | 752×408 | 1504×714 | ground | Sector 10 | three dead kart shells; the hidden kart of the design's secrets can sit behind it |
| `tireWall` | 3.0 × 1.3 | R0, L0 | 432×424 | 864×742 | ground | Corners, every sector | the design's tyre wall; R and L verges |
| `towHook` | 0.9 × 0.9 | C0, C1 | 422×136 | 844×238 | centre | Effect: Tow Hook card | frame 0 open, frame 1 latched; the line is drawn in QML from the kart |
| `waterTower` | 2.8 × 6.8 | R0, L0 | 1296×1640 | 2592×2870 | ground | Sector 3, far side | landmark; visible from a long way |
| `wrench` | 1.4 × 1.4 | C0, C1, C2, C3 | 422×216 | 1688×378 | centre | Effect: Wrench card | four frames of a quarter turn; the projectile |

## What is deliberately not here

- **Smoke**, sparks, speed lines, the tow line, the Roll Cage outline, dust: drawn in QML. Hard-edged bakes read as gravel; soft shapes belong to Canvas and simple items.
- **Dunes, water, haze, the road surface**: the ground plane is the shader's; see the design's circuit section.
- **The hidden kart in the scrapyard**: one of the six car bodies from `assets/karts/`, placed behind the stack.

## Rebaking

```
npm run props                     the whole kit, Mac only, about two minutes
npm run props -- --only crowd     one prop; the meta keeps every other entry
npm run props -- --verify         the reproducibility gate
```

A change to `bake-props.py` must land in the same commit as the sheets it produces, or `check:props` fails in CI.
