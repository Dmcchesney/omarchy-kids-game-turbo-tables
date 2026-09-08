// npm run perf -- the instrument.
//
// WHY THIS FILE EXISTS.
//
// The only performance number this project has ever had came from
// `dev/Harness.qml --measure`, which counts `FrameAnimation` ticks. It returns
// 62.5-62.8 fps at 480x270, at 1366x768, at 1920x1080 and at 3840x2160, with and
// without a screenful of effects. A number that does not move when the work
// changes by 64x is not measuring the work. It is measuring the animation
// driver's cadence, and every performance claim made from it is void.
//
// The reason it cannot move is worth stating exactly, because it is the trap any
// replacement would fall into as well: Qt Quick's animation driver paces the
// render loop at the refresh rate, so the loop renders sixty frames a second
// whether a frame costs 0.008 ms or 4 ms, and stops doing so only when a frame
// costs more than 16 ms. Below saturation a frame-rate reading carries no
// information about cost at all. `--measure` was reading the metronome.
//
// WHAT THIS MEASURES INSTEAD.
//
// `dev/Perf.qml` takes the metronome away: it dirties the whole window from
// inside `afterRendering`, which schedules the next frame immediately instead of
// at the driver's next beat, and QT_QPA_UPDATE_IDLE_TIME=0 stops the platform
// rate-limiting those requests. The loop is then limited by the cost of a frame
// and by nothing else -- an empty 480x270 window reaches 124,000 frames a second
// -- so TIME PER FRAME IS A COST.
//
// The time is taken from OUTSIDE the application, by subtraction:
//
//     cost of a frame = (time of a run of N frames - time of a run of M frames)
//                       / (N - M)
//
// Both runs launch the same binary, compile the same QML, populate the same font
// families, load the same sheets, settle for the same 700 ms and render the same
// warm-up frames. The only difference between them is N-M rendered frames, so
// that is all that survives the subtraction. Nothing in dev/Perf.qml has to hold
// a clock -- which is as well, since `check:readme` forbids one in any .qml file
// here, and a millisecond-resolution clock could not have timed a frame that
// costs eight microseconds anyway.
//
// TWO NUMBERS, NOT ONE, AND THEY ARE NOT REDUNDANT.
//
//   wall ms/frame   elapsed time per frame. Latency, on THIS machine, with its
//                   eight performance cores.
//   cpu ms/frame    user+system CPU per frame. Total work, in core-milliseconds.
//
// They differ by up to 2.6x, because Qt's software raster engine spreads a large
// fill across eight worker threads here (`ps -M` on a live run shows them at 16%
// each). That is not measurement error and neither number is the "right" one:
// on the weak single- or dual-core machine this game is aimed at, today's CPU
// figure is tomorrow's latency. **Optimise against cpu ms/frame.** Their ratio
// is reported as `cpu/wall`, and a change that improves wall without improving
// CPU has moved work sideways onto cores the target machine does not have.
//
// THE INSTRUMENT HAS A FLOOR AND IT IS NOT ZERO. Forcing a full redraw costs one
// window-sized blend per frame. `--screen none` measures exactly that -- an empty
// window, the pacemaker, nothing else -- and the tables below carry a "net of
// floor" column so that a screen's own cost is never confused with the cost of
// asking.
//
// COMMANDS
//
//   npm run perf -- run --screen TrackView --size 1920x1080 [--gc] [--phases]
//   npm run perf -- noise --screen TrackView --size 1920x1080 --repeat 7
//   npm run perf -- falsify            the battery: does it move with the load?
//   npm run perf -- baseline           every screen, at the sizes that matter
//
// `--out <path>` writes the markdown as well as printing it. Anything this file
// does not recognise is passed through to dev/Perf.qml, so `--travel`, `--lap`,
// `--inject`, `--warmup`, `--field` and `--settings` work here as in the harness.
//
// EVERY Qt PROCESS IS HEADLESS: QT_QPA_PLATFORM=offscreen, QT_QUICK_BACKEND=
// software, and `-platform offscreen` passed explicitly, on every invocation
// without exception. Nothing here can open a window on this Mac.

import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");

// ---------------------------------------------------------------------------
// Running one measured process
// ---------------------------------------------------------------------------

/** The three variables that keep Qt off the maintainer's display, plus the one
 *  that stops the platform plugin rate-limiting update requests. Without
 *  QT_QPA_UPDATE_IDLE_TIME the uncapped loop tops out near 740 fps, which would
 *  have silently become the ceiling of every reading on a cheap screen. */
const QT_ENV: Record<string, string> = {
  QT_QPA_PLATFORM: "offscreen",
  QT_QUICK_BACKEND: "software",
  QT_QPA_UPDATE_IDLE_TIME: "0",
  // The harness and the screens both log to stderr; keep Qt's own noise down so
  // a parse failure is visible rather than buried.
  QT_LOGGING_RULES: "qt.qpa.fonts=false",
};

/** zsh's `time`, which reports CPU to the millisecond. `/usr/bin/time` on this
 *  Mac reports two decimal places of a second, ten times coarser, and the whole
 *  CPU signal rests on that resolution. */
const TIMEFMT = "PERF-TIME real=%*E user=%*U sys=%*S maxrssKB=%M";

function shellQuote(word: string): string {
  return `'${word.replaceAll("'", `'\\''`)}'`;
}

export type QmlReport = {
  screen: string;
  width: number;
  height: number;
  pixels: number;
  framesTarget: number;
  framesRendered: number;
  rawRenders: number;
  reachedTarget: boolean;
  animationTicks: number;
  spin: number;
  alloc: number;
  pace: string;
  redraw: string;
  windowSeconds: number;
  achievedFps: number;
  wallMsPerFrame: number;
  cadenceMeanMs: number;
  cadenceMinMs: number;
  cadenceMaxMs: number;
  census?: Census;
  error?: string;
};

export type Census = {
  items: number;
  drawn: number;
  hidden: number;
  images: number;
  canvases: number;
  shaderEffects: number;
  shaderEffectSources: number;
  texts: number;
  layers: number;
  layerPixels: number;
  textureBytes: number;
  hiddenTextureBytes: number;
  distinctTextures: number;
  topTextures: { source: string; px: string; bytes: number; drawn: boolean }[];
  topTypes: { type: string; n: number }[];
};

export type RunCost = {
  realSeconds: number;
  cpuSeconds: number;
  maxRssMB: number;
};

type OneRun = { report: QmlReport | null; cost: RunCost; stderr: string };

/** One headless run of dev/Perf.qml, timed from outside. */
function runPerfQml(args: string[], extraEnv: Record<string, string> = {}): OneRun {
  const command = [
    "qml", "-platform", "offscreen", "-I", "dev/imports", "dev/Perf.qml", "--", ...args,
  ].map(shellQuote).join(" ");
  const result = spawnSync("zsh", ["-c", `time ( ${command} )`], {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    env: { ...process.env, ...QT_ENV, ...extraEnv, TIMEFMT },
  });
  const text = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;

  let report: QmlReport | null = null;
  const line = text.split("\n").find((entry) => entry.includes("perf-json: "));
  if (line) {
    try {
      report = JSON.parse(line.slice(line.indexOf("perf-json: ") + "perf-json: ".length));
    } catch {
      report = null;
    }
  }

  const timing = /PERF-TIME real=([\d.]+) user=([\d.]+) sys=([\d.]+) maxrssKB=(\d+)/.exec(text);
  const cost: RunCost = timing
    ? {
        realSeconds: Number(timing[1]),
        cpuSeconds: Number(timing[2]) + Number(timing[3]),
        maxRssMB: Number(timing[4]) / 1024,
      }
    : { realSeconds: 0, cpuSeconds: 0, maxRssMB: 0 };

  return { report, cost, stderr: text };
}

/** The one-minute load average. IT IS PART OF EVERY READING, not a footnote.
 *  This tree is worked by several agents at once and the maintainer uses the
 *  machine while the loop runs; the load average was FIFTY when the first noise
 *  floor was taken, and that is the whole of why five identical runs of the track
 *  spread from 2.2 to 4.8 ms. A cost measured on a machine with fifty runnable
 *  threads is not comparable with one measured on a quiet machine, so the number
 *  that says which it was travels with the measurement. */
function loadAverage(): number {
  const result = spawnSync("sysctl", ["-n", "vm.loadavg"], { encoding: "utf8" });
  const found = /([\d.]+)/.exec(result.stdout ?? "");
  return found ? Number(found[1]) : 0;
}

/** dev/Harness.qml's `--measure`, run unchanged, so the report can show the old
 *  signal beside the new one on the same load ladder. Read-only use: this file
 *  never edits the harness. */
function runHarnessMeasure(screen: string, size: string, ms: number): number | null {
  const command = [
    "qml", "-platform", "offscreen", "-I", "dev/imports", "dev/Harness.qml", "--",
    "--screen", screen, "--size", size, "--measure", String(ms),
  ].map(shellQuote).join(" ");
  const result = spawnSync("zsh", ["-c", command], {
    cwd: root, encoding: "utf8", maxBuffer: 16 * 1024 * 1024,
    env: { ...process.env, ...QT_ENV },
  });
  const text = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
  const found = /measured \d+ frames in \d+ ms = ([\d.]+) fps/.exec(text);
  return found ? Number(found[1]) : null;
}

// ---------------------------------------------------------------------------
// One measurement: the pilot, the pair, and the two numbers that must agree
// ---------------------------------------------------------------------------

export type Measurement = {
  label: string;
  screen: string;
  size: string;
  pixels: number;
  frames: number;
  wallMsPerFrame: number;
  cpuMsPerFrame: number;
  appMsPerFrame: number;
  fps: number;
  cpuOverWall: number;
  loadAverage: number;
  maxRssMB: number;
  cadenceMeanMs: number;
  reachedTarget: boolean;
  census: Census | null;
  gcRunsPer1000Frames: number | null;
  phases: { polishMs: number; syncMs: number; renderMs: number; frames: number } | null;
  note: string;
};

const LOW_WINDOW_MS = 300;
const HIGH_WINDOW_MS = 1500;
const DEFAULT_ARMS = 4;
const FRAME_CAP = "4000000";

export type MeasureOptions = {
  label?: string;
  screen: string;
  size: string;
  passthrough?: string[];
  /** Length of the measured window, in milliseconds. Default 2500. */
  windowMs?: number;
  gc?: boolean;
  phases?: boolean;
  /** How many times each arm is run; the cheapest is kept. Default 3. */
  arms?: number;
};

// ---------------------------------------------------------------------------
// WHAT IS HELD FIXED, AND WHY IT IS THE TIME AND NOT THE FRAMES
//
// The first version of this held the FRAME COUNT fixed, on the reasoning that
// two runs of 600 frames did the same work. True, and useless: 600 frames of the
// track is two and a half seconds and 600 frames of an empty window is five
// milliseconds, so the cheap measurements were over before the machine settled
// and five identical runs of the track spread 25 per cent. The frame count is
// what varies between screens; holding it fixed is holding the wrong end.
//
// So the WINDOW is fixed -- 2500 ms of counting on every run of every screen --
// and the frame count is the reading. Two numbers come out of it:
//
//   wall ms/frame   window / frames, both measured INSIDE the application, so
//                   process start-up, font population and the settle are not in
//                   it at all and cannot vary into it.
//   cpu ms/frame    the process's user+system CPU, differenced between a short
//                   window and a long one and divided by the extra frames. The
//                   difference is what removes start-up here; CPU has no
//                   in-application clock to read it from.
//
// Each arm is run several times and the CHEAPEST is kept. Interference is
// one-sided -- nothing another program does can make our frame cheaper -- so the
// minimum is the least-contaminated estimate, where the mean would enshrine the
// interference and the median would average it in.
// ---------------------------------------------------------------------------

export function measure(options: MeasureOptions): Measurement {
  const passthrough = options.passthrough ?? [];
  const highWindow = options.windowMs ?? HIGH_WINDOW_MS;
  const base = ["--screen", options.screen, "--size", options.size,
                "--frames", FRAME_CAP, ...passthrough];
  const lowArgs = [...base, "--window-ms", String(LOW_WINDOW_MS), "--census", "off"];
  const highArgs = [...base, "--window-ms", String(highWindow)];

  const arms = Math.max(1, options.arms ?? DEFAULT_ARMS);
  let load = loadAverage();
  let low: OneRun | null = null;
  let high: OneRun | null = null;
  let bestLowCpu = Infinity, bestHighCpu = -Infinity;
  let bestWall = Infinity;
  let lowFrames = 0, highFrames = 0;
  let peakRss = 0;

  for (let arm = 0; arm < arms; arm++) {
    const thisLow = runPerfQml(arm === 0 ? lowArgs : [...lowArgs]);
    const thisHigh = runPerfQml(arm === 0 ? highArgs : [...highArgs, "--census", "off"]);
    if (!thisLow.report || thisLow.report.error || !thisHigh.report || thisHigh.report.error) {
      if (arm === 0)
        return failed(options, `dev/Perf.qml did not report: ${thisHigh.report?.error ?? thisLow.report?.error ?? "no perf-json line"}`);
      continue;
    }
    if (arm === 0) { low = thisLow; high = thisHigh; }
    peakRss = Math.max(peakRss, thisHigh.cost.maxRssMB);
    // The cheapest low arm and the cheapest high arm are not necessarily from
    // the same pass, and they do not have to be: each is an independent estimate
    // of "what this run costs when nothing is interfering".
    if (thisLow.cost.cpuSeconds < bestLowCpu) {
      bestLowCpu = thisLow.cost.cpuSeconds;
      lowFrames = thisLow.report.framesRendered;
    }
    const cpuPerFrameHere = (thisHigh.cost.cpuSeconds - thisLow.cost.cpuSeconds);
    void cpuPerFrameHere;
    if (bestHighCpu < 0 || thisHigh.cost.cpuSeconds < bestHighCpu) {
      bestHighCpu = thisHigh.cost.cpuSeconds;
      highFrames = thisHigh.report.framesRendered;
    }
    if (thisHigh.report.wallMsPerFrame > 0 && thisHigh.report.wallMsPerFrame < bestWall)
      bestWall = thisHigh.report.wallMsPerFrame;
    load = Math.min(load, loadAverage());
  }
  if (!low || !high) return failed(options, "no arm completed");

  const deltaFrames = highFrames - lowFrames;
  const cpuMsPerFrame = deltaFrames > 0
    ? (1000 * (bestHighCpu - bestLowCpu)) / deltaFrames : 0;
  const wall = Number.isFinite(bestWall) ? bestWall : 0;
  // NOT an error term. CPU above wall means more than one core was busy: on this
  // Mac Qt's software raster engine spreads a large fill across eight worker
  // threads, and `ps -M` on a live run shows them at 16 per cent each. The two
  // numbers answer two different questions and both are needed:
  //
  //   wall ms/frame  how long a frame took HERE, on eight cores. Latency, on
  //                  this machine, which is not the target machine.
  //   cpu ms/frame   how much work a frame is, in core-milliseconds. On a weak
  //                  single- or dual-core machine this is what becomes the
  //                  latency, so it is the number to optimise against.
  //
  // Their ratio is the parallelism the frame happened to get. A change that
  // lowers wall but not CPU has moved work sideways onto cores the target
  // machine does not have.
  const cpuOverWall = wall > 0 ? cpuMsPerFrame / wall : 0;
  const appMsPerFrame = wall;

  let gcRuns: number | null = null;
  if (options.gc) {
    // Qt's own garbage-collector log. Producing it costs CPU, so it is never
    // enabled during a run whose CPU time is being used as a number.
    const run = runPerfQml(
      [...base, "--window-ms", String(highWindow), "--census", "off"],
      { QT_LOGGING_RULES: "qt.qpa.fonts=false;qt.qml.gc.allocatorStats=true" },
    );
    const count = (run.stderr.match(/========== GC ==========/g) ?? []).length;
    const frames = run.report?.framesRendered ?? 0;
    gcRuns = frames > 0 ? (1000 * count) / frames : null;
  }

  let phases: Measurement["phases"] = null;
  if (options.phases) {
    // Qt's own renderloop timing, which splits a frame into polish, sync, render
    // and swap. It reports whole milliseconds per phase, TRUNCATED, so on a frame
    // costing 0.8 ms every phase reads 0 and the sum reads 0. It is a LOWER
    // BOUND, useful only on expensive frames, and it is labelled as one.
    const run = runPerfQml(
      [...base, "--window-ms", String(Math.min(highWindow, 1500)), "--census", "off"],
      { QT_LOGGING_RULES: "qt.qpa.fonts=false;qt.scenegraph.time.renderloop=true" },
    );
    let polish = 0, sync = 0, render = 0, frames = 0;
    const pattern = /renderloop in \d+ms, polish=(\d+), sync=(\d+), render=(\d+)/g;
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(run.stderr)) !== null) {
      polish += Number(match[1]); sync += Number(match[2]); render += Number(match[3]); frames += 1;
    }
    if (frames > 0)
      phases = { polishMs: polish / frames, syncMs: sync / frames, renderMs: render / frames, frames };
  }

  return {
    label: options.label ?? `${options.screen} ${options.size}`,
    screen: options.screen,
    size: options.size,
    pixels: high.report!.pixels,
    frames: highFrames,
    wallMsPerFrame: Number(wall.toFixed(5)),
    cpuMsPerFrame: Number(cpuMsPerFrame.toFixed(5)),
    appMsPerFrame: Number(appMsPerFrame.toFixed(5)),
    fps: wall > 0 ? Number((1000 / wall).toFixed(0)) : 0,
    cpuOverWall: Number(cpuOverWall.toFixed(2)),
    loadAverage: Number(load.toFixed(1)),
    maxRssMB: Number(peakRss.toFixed(1)),
    cadenceMeanMs: high.report!.cadenceMeanMs,
    reachedTarget: highFrames > 0,
    census: high.report!.census ?? null,
    gcRunsPer1000Frames: gcRuns === null ? null : Number(gcRuns.toFixed(2)),
    phases,
    note: "",
  };
}

function failed(options: MeasureOptions, note: string): Measurement {
  return {
    label: options.label ?? `${options.screen} ${options.size}`,
    screen: options.screen, size: options.size, pixels: 0, frames: 0,
    wallMsPerFrame: 0, cpuMsPerFrame: 0, appMsPerFrame: 0, fps: 0, cpuOverWall: 0, loadAverage: loadAverage(), maxRssMB: 0,
    cadenceMeanMs: 0, reachedTarget: false, census: null,
    gcRunsPer1000Frames: null, phases: null, note,
  };
}

// ---------------------------------------------------------------------------
// Statistics. A number with no spread beside it is an anecdote.
// ---------------------------------------------------------------------------

export type Spread = { n: number; median: number; min: number; max: number; sd: number; rsdPct: number };

export function spread(values: number[]): Spread {
  const sorted = [...values].sort((a, b) => a - b);
  const n = sorted.length;
  const median = n === 0 ? 0
    : n % 2 === 1 ? sorted[(n - 1) / 2]!
    : (sorted[n / 2 - 1]! + sorted[n / 2]!) / 2;
  const mean = values.reduce((sum, value) => sum + value, 0) / Math.max(1, n);
  const variance = values.reduce((sum, value) => sum + (value - mean) ** 2, 0) / Math.max(1, n - 1);
  const sd = n > 1 ? Math.sqrt(variance) : 0;
  return {
    n, median, min: sorted[0] ?? 0, max: sorted[n - 1] ?? 0,
    sd: Number(sd.toFixed(5)),
    rsdPct: mean > 0 ? Number(((100 * sd) / mean).toFixed(2)) : 0,
  };
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

const out: string[] = [];
function say(line = ""): void {
  out.push(line);
  console.log(line);
}

function table(headers: string[], rows: string[][]): void {
  say(`| ${headers.join(" | ")} |`);
  say(`| ${headers.map(() => "---").join(" | ")} |`);
  for (const row of rows) say(`| ${row.join(" | ")} |`);
}

const mb = (bytes: number): string => `${(bytes / (1024 * 1024)).toFixed(1)} MB`;

function measurementRows(items: Measurement[]): string[][] {
  return items.map((item) => [
    item.label,
    item.pixels ? item.pixels.toLocaleString("en-GB") : "-",
    String(item.frames),
    item.cpuMsPerFrame.toFixed(4),
    item.wallMsPerFrame.toFixed(4),
    item.cpuOverWall ? `${item.cpuOverWall.toFixed(2)}x` : "-",
    item.fps ? item.fps.toLocaleString("en-GB") : "-",
    item.loadAverage.toFixed(1),
    item.maxRssMB.toFixed(0),
    item.census ? mb(item.census.textureBytes) : "-",
    item.note || (item.reachedTarget ? "" : "frame target not reached"),
  ]);
}

const MEASURE_HEADERS = [
  "what", "pixels", "frames", "**cpu ms/frame**", "wall ms/frame", "cpu/wall",
  "fps (uncapped)", "load avg", "peak RSS MB", "decoded textures", "note",
];

/** The instrument's own cost at a given window size, measured once per size and
 *  remembered. It is the cost of an empty window being asked to redraw itself
 *  completely, which is what every other reading has added to it. */
const floors = new Map<string, Measurement>();
function floorFor(size: string): Measurement {
  const known = floors.get(size);
  if (known) return known;
  const taken = measure({ label: `instrument floor ${size}`, screen: "none", size });
  floors.set(size, taken);
  return taken;
}

/** The same rows again with the floor taken off, because "this screen costs
 *  2.3 ms" and "this screen costs 1.9 ms and measuring it costs 0.4 ms" are
 *  different claims and only the second one is true. */
function netTable(items: Measurement[]): void {
  const rows = items
    .filter((item) => item.screen !== "none" && item.wallMsPerFrame > 0)
    .map((item) => {
      const floor = floorFor(item.size);
      return [
        item.label,
        item.wallMsPerFrame.toFixed(4),
        floor.wallMsPerFrame.toFixed(4),
        Math.max(0, item.wallMsPerFrame - floor.wallMsPerFrame).toFixed(4),
        item.cpuMsPerFrame.toFixed(4),
        floor.cpuMsPerFrame.toFixed(4),
        Math.max(0, item.cpuMsPerFrame - floor.cpuMsPerFrame).toFixed(4),
      ];
    });
  if (rows.length === 0) return;
  say();
  table(["what", "wall", "floor", "**wall net**", "cpu", "floor", "**cpu net**"], rows);
}

function censusBlock(item: Measurement): void {
  const census = item.census;
  if (!census) return;
  say();
  say(`**Scene census — ${item.label}**`);
  say();
  say(`- items ${census.items} (${census.drawn} drawn, ${census.hidden} not drawn)`);
  say(`- Text ${census.texts} · Canvas ${census.canvases} · ShaderEffect ${census.shaderEffects}`
    + ` · ShaderEffectSource ${census.shaderEffectSources} · layer.enabled ${census.layers}`
    + (census.layerPixels ? ` (${census.layerPixels.toLocaleString("en-GB")} offscreen px)` : ""));
  say(`- images ${census.images} in ${census.distinctTextures} distinct decodes,`
    + ` **${mb(census.textureBytes)} resident decoded RGBA**`
    + (census.hiddenTextureBytes ? `, of which ${mb(census.hiddenTextureBytes)} is not drawn` : ""));
  if (census.topTextures.length > 0) {
    say(`- heaviest decodes: `
      + census.topTextures.slice(0, 5).map((t) => `${t.source} ${t.px} = ${mb(t.bytes)}`).join(" · "));
  }
  say(`- most numerous types: ` + census.topTypes.slice(0, 8).map((t) => `${t.type} ${t.n}`).join(" · "));
}

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

const argv = process.argv.slice(2);
const command = argv[0] && !argv[0].startsWith("--") ? argv[0] : "run";

/** Options this file understands; everything else goes to dev/Perf.qml. */
const OWN = new Set(["--screen", "--size", "--frames", "--repeat", "--out", "--budget-ms", "--arms"]);

function option(name: string, fallback: string): string {
  const at = argv.indexOf(name);
  return at >= 0 && at + 1 < argv.length ? argv[at + 1]! : fallback;
}
function flag(name: string): boolean {
  return argv.includes(name);
}
function passthrough(): string[] {
  const rest: string[] = [];
  for (let i = 1; i < argv.length; i++) {
    const word = argv[i]!;
    if (!word.startsWith("--")) continue;
    if (OWN.has(word) || word === "--gc" || word === "--phases") {
      if (OWN.has(word)) i += 1;
      continue;
    }
    rest.push(word);
    if (i + 1 < argv.length && !argv[i + 1]!.startsWith("--")) {
      rest.push(argv[i + 1]!);
      i += 1;
    }
  }
  return rest;
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

// PIECE M -- TWO OPTIONS THAT WERE ACCEPTED AND DID NOTHING.
//
// `--frames N` and `--budget-ms N` were parsed here and handed to `measure()`
// as `frames` and `budgetMs`. `MeasureOptions` has neither field, and
// `measure()` reads neither: it builds its argument list with the constant
// `FRAME_CAP` and with `HIGH_WINDOW_MS`. So both flags were silently ignored,
// and a run that asked for a hundred frames got the same four-million-frame cap
// as every other run and reported a number the caller believed was about a
// hundred frames.
//
// They are not wired up, because the frame count IS NOT A KNOB ON THIS
// INSTRUMENT and making it one would break the thing the block above this
// function explains at length: the WINDOW is what is held fixed and the frame
// count is the READING. `--frames` asks to hold the reading fixed, which is the
// design this file was rewritten to get away from; `--budget-ms` is the window
// under another name, and its old default (2500) does not even agree with
// `HIGH_WINDOW_MS` (1500), so honouring it would quietly change the length of
// every measurement anybody has ever taken with this tool.
//
// So they fail, loudly, and say why. A flag that does nothing is worse than a
// flag that does not exist: it produces numbers somebody trusts for a reason
// that was never true.
const REFUSED: { flag: string; why: string }[] = [
  {
    flag: "--frames",
    why: "the frame count is this instrument's READING, not its input: the window is what is held fixed."
      + " Use --arms to run more passes, or --size to change how much work a frame is.",
  },
  {
    flag: "--budget-ms",
    why: "the measured window is fixed at HIGH_WINDOW_MS so that two screens are comparable."
      + " Changing it per run makes two numbers in one report incomparable.",
  },
];

function refuseIgnoredOptions(): void {
  for (const { flag: name, why } of REFUSED) {
    if (!argv.includes(name)) continue;
    console.error(`perf: ${name} is not supported, and was silently ignored until piece M.\n  ${why}`);
    process.exit(2);
  }
}

function commandRun(): void {
  refuseIgnoredOptions();
  const screen = option("--screen", "Garage");
  const size = option("--size", "480x270");
  const item = measure({
    screen, size, passthrough: passthrough(),
    gc: flag("--gc"), phases: flag("--phases"),
    arms: Number(option("--arms", String(DEFAULT_ARMS))),
  });
  say(`## ${item.label}`);
  say();
  table(MEASURE_HEADERS, measurementRows([item]));
  netTable([item]);
  if (item.gcRunsPer1000Frames !== null)
    say(`\nGC runs per 1000 frames: **${item.gcRunsPer1000Frames}**`);
  if (item.phases)
    say(`\nQt renderloop split over ${item.phases.frames} frames (whole-ms truncation, so a LOWER BOUND):`
      + ` polish ${item.phases.polishMs.toFixed(2)} ms · sync ${item.phases.syncMs.toFixed(2)} ms`
      + ` · render ${item.phases.renderMs.toFixed(2)} ms`);
  censusBlock(item);
}

function commandNoise(): void {
  refuseIgnoredOptions();
  const screen = option("--screen", "TrackView");
  const size = option("--size", "1920x1080");
  const repeat = Number(option("--repeat", "7"));
  const rest = passthrough();
  const items: Measurement[] = [];
  for (let i = 0; i < repeat; i++)
    items.push(measure({
      label: `${screen} ${size} #${i + 1}`, screen, size, passthrough: rest,
      arms: Number(option("--arms", String(DEFAULT_ARMS))),
    }));

  say(`## Noise floor — ${screen} at ${size}, ${repeat} identical runs`);
  say();
  table(MEASURE_HEADERS, measurementRows(items));
  say();
  const wall = spread(items.map((item) => item.wallMsPerFrame));
  const cpu = spread(items.map((item) => item.cpuMsPerFrame));
  const rss = spread(items.map((item) => item.maxRssMB));
  table(
    ["signal", "median", "min", "max", "sd", "relative sd", "a change must exceed"],
    [
      ["wall ms/frame", wall.median.toFixed(4), wall.min.toFixed(4), wall.max.toFixed(4),
        wall.sd.toFixed(4), `${wall.rsdPct}%`, `${(3 * wall.rsdPct).toFixed(1)}%`],
      ["cpu ms/frame", cpu.median.toFixed(4), cpu.min.toFixed(4), cpu.max.toFixed(4),
        cpu.sd.toFixed(4), `${cpu.rsdPct}%`, `${(3 * cpu.rsdPct).toFixed(1)}%`],
      ["peak RSS MB", rss.median.toFixed(1), rss.min.toFixed(1), rss.max.toFixed(1),
        rss.sd.toFixed(2), `${rss.rsdPct}%`, `${(3 * rss.rsdPct).toFixed(1)}%`],
    ],
  );
  say();
  say(`"a change must exceed" is three relative standard deviations: a later round that moves a`);
  say(`number by less than that has measured this machine's mood, not its own change.`);
}

/** The battery. An instrument nobody has tried to break is not an instrument. */
function commandFalsify(): void {
  refuseIgnoredOptions();
  const screen = option("--screen", "TrackView");
  say(`# Falsification — does the instrument move with the load?`);
  say();
  say(`Every prediction below is written before the run, and a signal that fails its`);
  say(`prediction is discarded rather than explained.`);

  // 1. The floor.
  say();
  say(`## 1. The floor: what measuring costs when there is nothing to measure`);
  say();
  const floor = [
    measure({ label: "empty window 480x270", screen: "none", size: "480x270" }),
    measure({ label: "empty window 1920x1080", screen: "none", size: "1920x1080" }),
  ];
  table(MEASURE_HEADERS, measurementRows(floor));

  // 2. Known work, in known amounts: the only unambiguous test.
  say();
  say(`## 2. Inserted work — \`--spin n\` burns n iterations of arithmetic per frame`);
  say();
  say(`PREDICTION: wall and cpu ms/frame rise linearly in n, with the same slope, because`);
  say(`the inserted work is pure CPU and is the only thing changing. A signal that does not`);
  say(`is measuring something other than the cost of the frame.`);
  say();
  const spins = [0, 20000, 40000, 80000, 160000];
  const spinRuns = spins.map((n) => measure({
    label: `${screen} 480x270 spin=${n}`, screen, size: "480x270",
    passthrough: n > 0 ? ["--spin", String(n)] : [],
  }));
  table(MEASURE_HEADERS, measurementRows(spinRuns));
  say();
  const zero = spinRuns[0]!;
  table(
    ["spin", "wall ms/frame", "rise over spin=0", "ms per 10k iterations", "linear?"],
    spinRuns.map((item, index) => {
      const rise = item.wallMsPerFrame - zero.wallMsPerFrame;
      const per10k = spins[index]! > 0 ? (rise / spins[index]!) * 10000 : 0;
      return [
        String(spins[index]), item.wallMsPerFrame.toFixed(4), rise.toFixed(4),
        spins[index]! > 0 ? per10k.toFixed(4) : "-",
        spins[index]! > 0 ? "compare this column: it should be constant" : "-",
      ];
    }),
  );

  // 3. Pixels.
  say();
  say(`## 3. Resolution — the same scene over a 28x range of pixels`);
  say();
  say(`PREDICTION: cost rises with pixel count. Not proportionally: a scene has a fixed`);
  say(`per-frame cost (traversal, sync, per-item setup) that does not care how big the`);
  say(`window is, so the curve should be an affine one, not a straight multiple.`);
  say();
  const sizes = ["480x270", "960x540", "1366x768", "1920x1080", "2560x1440"];
  const sizeRuns = sizes.map((size) => measure({ label: `${screen} ${size}`, screen, size }));
  table(MEASURE_HEADERS, measurementRows(sizeRuns));
  say();
  const small = sizeRuns[0]!;
  table(
    ["size", "pixels", "x pixels vs 480x270", "wall ms/frame", "x cost vs 480x270", "ns per pixel"],
    sizeRuns.map((item) => [
      item.size, item.pixels.toLocaleString("en-GB"),
      `${(item.pixels / small.pixels).toFixed(1)}x`,
      item.wallMsPerFrame.toFixed(4),
      `${(item.wallMsPerFrame / small.wallMsPerFrame).toFixed(1)}x`,
      ((item.wallMsPerFrame * 1e6) / item.pixels).toFixed(1),
    ]),
  );

  // 4. The old signal, on the same ladder.
  say();
  say(`## 4. The signal being replaced, on the ladder it should have moved on`);
  say();
  say(`\`dev/Harness.qml --measure 2000\`, run unchanged at each size.`);
  say();
  const oldRows = sizes.map((size) => {
    const fps = runHarnessMeasure(screen, size, 2000);
    const item = sizeRuns[sizes.indexOf(size)]!;
    return [
      size,
      fps === null ? "no reading" : fps.toFixed(1),
      item.wallMsPerFrame.toFixed(4),
      `${(item.wallMsPerFrame / small.wallMsPerFrame).toFixed(1)}x`,
    ];
  });
  table(["size", "old --measure fps", "new wall ms/frame", "x cost vs 480x270"], oldRows);

  // 5. Allocation.
  say();
  say(`## 5. Allocation — \`--alloc n\` makes n short-lived objects per frame`);
  say();
  say(`PREDICTION: garbage collections per 1000 frames rises with n. If it does not, the`);
  say(`GC-run count is not a measure of allocation pressure and must be discarded.`);
  say();
  const allocs = [0, 100, 500, 2500];
  const allocRuns = allocs.map((n) => measure({
    label: `${screen} 480x270 alloc=${n}`, screen, size: "480x270",
    passthrough: n > 0 ? ["--alloc", String(n)] : [], gc: true,
  }));
  table(
    ["alloc per frame", "wall ms/frame", "cpu ms/frame", "GC runs / 1000 frames", "peak RSS MB"],
    allocRuns.map((item, index) => [
      String(allocs[index]), item.wallMsPerFrame.toFixed(4), item.cpuMsPerFrame.toFixed(4),
      item.gcRunsPer1000Frames === null ? "-" : item.gcRunsPer1000Frames.toFixed(2),
      item.maxRssMB.toFixed(0),
    ]),
  );

  // 6. Real content, not synthetic.
  say();
  say(`## 6. Real scenes — the same measurement across screens of different weight`);
  say();
  const scenes = ["none", "Settings", "Results", "Garage", "TrackView"];
  const sceneRuns = scenes.map((name) => measure({ label: name, screen: name, size: "1920x1080" }));
  table(MEASURE_HEADERS, measurementRows(sceneRuns));
  netTable(sceneRuns);
}

function commandBaseline(): void {
  refuseIgnoredOptions();
  say(`# Baseline — the game as it stands`);
  say();
  say(`Taken with \`npm run perf -- baseline\`. Every figure is wall milliseconds per`);
  say(`rendered frame with the render loop uncapped and the whole window invalidated`);
  say(`every frame, on this Mac, software-rendered, offscreen. It is NOT a frame rate the`);
  say(`game will show a child: it is the cost of drawing one frame of that picture, which`);
  say(`is the thing a later round can move and be judged on.`);

  // `Store` and `Theme` are singletons, not screens; `Minimap` and `CanvasRoad` are
  // parts of the race view and are measured inside it.
  const screens = ["Garage", "Settings", "Picker", "Countdown", "Results", "Race", "TrackView"];
  say();
  say(`## Every screen at 480x270, the internal resolution`);
  say();
  const internal = screens.map((name) => measure({ label: name, screen: name, size: "480x270" }));
  table(MEASURE_HEADERS, measurementRows(internal));
  netTable(internal);

  say();
  say(`## The race, at the resolutions that matter`);
  say();
  const raceSizes = ["480x270", "1366x768", "1920x1080", "2560x1440"];
  const race: Measurement[] = [];
  for (const size of raceSizes) race.push(measure({ label: `TrackView ${size}`, screen: "TrackView", size }));
  for (const size of raceSizes) race.push(measure({ label: `Race ${size}`, screen: "Race", size }));
  table(MEASURE_HEADERS, measurementRows(race));
  netTable(race);

  for (const item of [...internal, ...race].filter((entry) => entry.census))
    censusBlock(item);
}

// ---------------------------------------------------------------------------

switch (command) {
  case "run": commandRun(); break;
  case "noise": commandNoise(); break;
  case "falsify": commandFalsify(); break;
  case "baseline": commandBaseline(); break;
  default:
    console.error(`unknown command "${command}". Try: run | noise | falsify | baseline`);
    process.exit(2);
}

const outPath = option("--out", "");
if (outPath) {
  const absolute = resolve(root, outPath);
  mkdirSync(dirname(absolute), { recursive: true });
  writeFileSync(absolute, `${out.join("\n")}\n`, "utf8");
  console.error(`written: ${absolute}`);
}
