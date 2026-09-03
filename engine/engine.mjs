var __defProp = Object.defineProperty;
var __getOwnPropSymbols = Object.getOwnPropertySymbols;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __propIsEnum = Object.prototype.propertyIsEnumerable;
var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
var __spreadValues = (a, b) => {
  for (var prop in b || (b = {}))
    if (__hasOwnProp.call(b, prop))
      __defNormalProp(a, prop, b[prop]);
  if (__getOwnPropSymbols)
    for (var prop of __getOwnPropSymbols(b)) {
      if (__propIsEnum.call(b, prop))
        __defNormalProp(a, prop, b[prop]);
    }
  return a;
};

// src/engine/rng.ts
function rotl(value, shift) {
  return (value << shift | value >>> 32 - shift) >>> 0;
}
function splitmix32(state) {
  const next = state + 2654435769 >>> 0;
  let z = next;
  z = Math.imul(z ^ z >>> 16, 569420461) >>> 0;
  z = Math.imul(z ^ z >>> 15, 1935289751) >>> 0;
  z = (z ^ z >>> 15) >>> 0;
  return { value: z, state: next };
}
function hashLabel(label) {
  let hash = 2166136261;
  for (let index = 0; index < label.length; index++) {
    hash = (hash ^ label.charCodeAt(index)) >>> 0;
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  return hash >>> 0;
}
function createRng(seed) {
  let state = seed >>> 0;
  const words = [];
  for (let index = 0; index < 4; index++) {
    const stepped = splitmix32(state);
    state = stepped.state;
    words.push(stepped.value);
  }
  const rng = { a: words[0], b: words[1], c: words[2], d: words[3] };
  if ((rng.a | rng.b | rng.c | rng.d) === 0) rng.a = 1;
  return rng;
}
function forkRng(seed, label) {
  return createRng((seed >>> 0 ^ hashLabel(label)) >>> 0);
}
function cloneRng(rng) {
  return { a: rng.a, b: rng.b, c: rng.c, d: rng.d };
}
function nextUint32(rng) {
  const result = Math.imul(rotl(Math.imul(rng.b, 5) >>> 0, 7), 9) >>> 0;
  const t = rng.b << 9 >>> 0;
  rng.c = (rng.c ^ rng.a) >>> 0;
  rng.d = (rng.d ^ rng.b) >>> 0;
  rng.b = (rng.b ^ rng.c) >>> 0;
  rng.a = (rng.a ^ rng.d) >>> 0;
  rng.c = (rng.c ^ t) >>> 0;
  rng.d = rotl(rng.d, 11);
  return result;
}
function nextFloat(rng) {
  return nextUint32(rng) / 4294967296;
}
function nextInt(rng, bound) {
  if (bound <= 1) return 0;
  const limit = 4294967296 - 4294967296 % bound;
  let value = nextUint32(rng);
  while (value >= limit) value = nextUint32(rng);
  return value % bound;
}
function shuffle(rng, values) {
  const result = values.slice();
  for (let index = result.length - 1; index > 0; index--) {
    const swap = nextInt(rng, index + 1);
    const held = result[index];
    result[index] = result[swap];
    result[swap] = held;
  }
  return result;
}

// src/engine/history.ts
var FACT_HISTORY_WINDOW = 3;
function newFactRecord(fact) {
  return { fact, attempts: 0, correct: 0, lastThree: [] };
}
function cloneFactRecord(record) {
  return {
    fact: record.fact,
    attempts: record.attempts,
    correct: record.correct,
    lastThree: record.lastThree.slice()
  };
}
function cloneFactHistory(history) {
  return history.map(cloneFactRecord);
}
function factRecordOf(history, fact) {
  for (const record of history) if (record.fact === fact) return record;
  return null;
}
function recordFactOutcome(history, fact, outcome) {
  let record = factRecordOf(history, fact);
  if (record === null) {
    record = newFactRecord(fact);
    let at = history.length;
    for (let index = 0; index < history.length; index++) {
      if (history[index].fact > fact) {
        at = index;
        break;
      }
    }
    history.splice(at, 0, record);
  }
  record.attempts += 1;
  if (outcome === "correct") record.correct += 1;
  record.lastThree.push(outcome);
  while (record.lastThree.length > FACT_HISTORY_WINDOW) record.lastThree.shift();
  return record;
}
function recentSuccesses(record) {
  if (record === null) return 0;
  let count = 0;
  for (const outcome of record.lastThree) if (outcome === "correct") count += 1;
  return count;
}
function compareByFactHistory(history, left, right) {
  if (left === right) return 0;
  const leftRecord = factRecordOf(history, left);
  const rightRecord = factRecordOf(history, right);
  const leftRecent = recentSuccesses(leftRecord);
  const rightRecent = recentSuccesses(rightRecord);
  if (leftRecent !== rightRecent) return leftRecent - rightRecent;
  const leftAttempts = leftRecord === null ? 0 : leftRecord.attempts;
  const rightAttempts = rightRecord === null ? 0 : rightRecord.attempts;
  const leftCorrect = leftRecord === null ? 0 : leftRecord.correct;
  const rightCorrect = rightRecord === null ? 0 : rightRecord.correct;
  const leftRatio = leftCorrect * rightAttempts;
  const rightRatio = rightCorrect * leftAttempts;
  if (leftRatio !== rightRatio) return leftRatio - rightRatio;
  if (leftAttempts !== rightAttempts) return rightAttempts - leftAttempts;
  return 0;
}
function orderByFactHistory(facts, history) {
  const decorated = facts.map((fact, position) => ({ fact, position }));
  decorated.sort((left, right) => {
    const byHistory = compareByFactHistory(history, left.fact, right.fact);
    if (byHistory !== 0) return byHistory;
    return left.position - right.position;
  });
  return decorated.map((entry) => entry.fact);
}

// src/engine/deck.ts
var QUESTIONS_PER_LAP = 12;
var TABLE_MIN = 1;
var TABLE_MAX = 12;
var PRESET_TABLES = {
  "2-5": [2, 3, 4, 5],
  "2-10": [2, 3, 4, 5, 6, 7, 8, 9, 10],
  "1-12": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
};
var TABLE_NAMES = [
  "",
  "THE ONES",
  "THE TWOS",
  "THE THREES",
  "THE FOURS",
  "THE FIVES",
  "THE SIXES",
  "THE SEVENS",
  "THE EIGHTS",
  "THE NINES",
  "THE TENS",
  "THE ELEVENS",
  "THE TWELVES"
];
function packFact(left, right) {
  return left * 100 + right;
}
function factLeft(fact) {
  return Math.floor(fact / 100);
}
function factRight(fact) {
  return fact % 100;
}
function factAnswer(fact) {
  return factLeft(fact) * factRight(fact);
}
function factLabel(fact) {
  return factLeft(fact) + " \xD7 " + factRight(fact);
}
function tableName(table) {
  var _a;
  return (_a = TABLE_NAMES[table]) != null ? _a : "";
}
function tableFacts(table) {
  const facts = [];
  for (let right = 1; right <= QUESTIONS_PER_LAP; right++) facts.push(packFact(table, right));
  return facts;
}
function tablesForPreset(preset, chosen) {
  if (preset !== "choose") return PRESET_TABLES[preset].slice();
  const unique = [];
  for (const table of chosen != null ? chosen : []) {
    const value = Math.floor(table);
    if (value < TABLE_MIN || value > TABLE_MAX) continue;
    if (unique.indexOf(value) === -1) unique.push(value);
  }
  unique.sort((left, right) => left - right);
  return unique.length > 0 ? unique : PRESET_TABLES["1-12"].slice();
}
function questionCountForPreset(preset, chosen) {
  return tablesForPreset(preset, chosen).length * QUESTIONS_PER_LAP;
}
function lapDeck(seed, lapIndex, table) {
  return shuffle(forkRng(seed, "deck:" + lapIndex + ":" + table), tableFacts(table));
}
function extraQuestions(seed, racerId, lapIndex, drawIndex, table, missed, history = []) {
  const label = "extra:" + racerId + ":" + lapIndex + ":" + drawIndex;
  const sortedMissed = missed.slice().sort((left, right) => left - right);
  const shuffledMissed = shuffle(forkRng(seed, label + ":missed"), sortedMissed);
  const fromMissed = orderByFactHistory(shuffledMissed, history);
  const fromTable = shuffle(forkRng(seed, label + ":table"), tableFacts(table));
  return fromMissed.concat(fromTable);
}

// src/engine/cards.ts
var CARD_SCHEDULE = [
  "nitro",
  "oilSlick",
  "wrench",
  "pothole",
  "rollCage",
  "pileUp",
  "turbo",
  "towHook"
];
var CARDS = {
  nitro: {
    scope: "self",
    questionDelta: -4,
    tier: "common",
    bellringerName: "FuelBoost",
    label: "Nitro",
    stallMs: 0
  },
  oilSlick: {
    scope: "aoe",
    questionDelta: 3,
    tier: "common",
    bellringerName: "GravityWell",
    label: "Oil Slick",
    stallMs: 0
  },
  wrench: {
    scope: "targeted",
    questionDelta: 5,
    tier: "uncommon",
    bellringerName: "Lightning",
    label: "Wrench",
    stallMs: 3e3
  },
  pothole: {
    scope: "targeted",
    questionDelta: 8,
    tier: "rare",
    bellringerName: "BlackHole",
    label: "Pothole",
    stallMs: 2e3
  },
  rollCage: {
    scope: "self",
    questionDelta: 0,
    tier: "uncommon",
    bellringerName: "Shield",
    label: "Roll Cage",
    stallMs: 0
  },
  pileUp: {
    scope: "targeted",
    questionDelta: 15,
    tier: "legendary",
    bellringerName: "Supernova",
    label: "Pile-Up",
    stallMs: 2e3
  },
  turbo: {
    scope: "self",
    questionDelta: -10,
    tier: "rare",
    bellringerName: "Turbo",
    label: "Turbo",
    stallMs: 0
  },
  towHook: {
    scope: "targeted",
    questionDelta: 0,
    tier: "legendary",
    bellringerName: "Wormhole",
    label: "Tow Hook",
    stallMs: 0
  }
};
var HAND_SIZE = 3;
var QUESTIONS_NEEDED_FLOOR = 1;
function isCard(value) {
  return Object.prototype.hasOwnProperty.call(CARDS, value);
}
function cardByBellringerName(name) {
  for (const card of CARD_SCHEDULE) {
    if (CARDS[card].bellringerName === name) return card;
  }
  return null;
}
function dealHand(schedule2, cursor) {
  const hand = [];
  let next = cursor;
  let scanned = 0;
  while (hand.length < HAND_SIZE && scanned < schedule2.length) {
    const candidate = schedule2[(next % schedule2.length + schedule2.length) % schedule2.length];
    next += 1;
    scanned += 1;
    if (hand.indexOf(candidate) === -1) hand.push(candidate);
  }
  return { hand, cursor: next };
}
function applyFloor(questionsNeeded, delta) {
  return Math.max(QUESTIONS_NEEDED_FLOOR, questionsNeeded + delta);
}

// src/engine/streak.ts
var STREAK_THRESHOLD = 12;
var BELLRINGER_STREAK_THRESHOLD = 15;
var CHARGE_SEGMENTS = 12;
var CHARGE_GLOW_FROM = 9;
function nextStreak(streak, effect) {
  if (effect === "reset") return 0;
  if (effect === "build") return streak + 1;
  return streak;
}
function shouldDealHand(streak, threshold, handSize) {
  return streak >= threshold && handSize === 0;
}
function chargeSegments(streak, threshold) {
  const ratio = threshold <= 0 ? 1 : streak / threshold;
  return Math.min(CHARGE_SEGMENTS, Math.floor(ratio * CHARGE_SEGMENTS));
}
function chargeReady(streak, threshold) {
  return streak >= threshold;
}

// src/engine/progress.ts
function positionTriple(position) {
  return {
    lapsComplete: position.lapsComplete,
    correctInLap: position.correctInLap,
    questionsNeededThisLap: position.questionsNeededThisLap
  };
}
function swapPositions(left, right) {
  const held = positionTriple(left);
  left.lapsComplete = right.lapsComplete;
  left.correctInLap = right.correctInLap;
  left.questionsNeededThisLap = right.questionsNeededThisLap;
  right.lapsComplete = held.lapsComplete;
  right.correctInLap = held.correctInLap;
  right.questionsNeededThisLap = held.questionsNeededThisLap;
}
function effectiveProgress(position, questionsPerLap = QUESTIONS_PER_LAP) {
  const needed = position.questionsNeededThisLap > 0 ? position.questionsNeededThisLap : questionsPerLap;
  return position.lapsComplete * questionsPerLap + position.correctInLap - (needed - questionsPerLap);
}
function raceLength(totalLaps, questionsPerLap = QUESTIONS_PER_LAP) {
  return totalLaps * questionsPerLap;
}
function progressFraction(position, totalLaps, questionsPerLap = QUESTIONS_PER_LAP) {
  const length = raceLength(totalLaps, questionsPerLap);
  if (length <= 0) return 0;
  const value = effectiveProgress(position, questionsPerLap) / length;
  return Math.max(0, Math.min(1, value));
}

// src/engine/rank.ts
function compareRacers(left, right, questionsPerLap = QUESTIONS_PER_LAP) {
  if (left.finished !== right.finished) return left.finished ? -1 : 1;
  if (left.finished && right.finished && left.finishTimeMs !== right.finishTimeMs) {
    return left.finishTimeMs - right.finishTimeMs;
  }
  if (!left.finished) {
    const leftProgress = effectiveProgress(left, questionsPerLap);
    const rightProgress = effectiveProgress(right, questionsPerLap);
    if (leftProgress !== rightProgress) return rightProgress - leftProgress;
  }
  if (left.correctCount !== right.correctCount) return right.correctCount - left.correctCount;
  if (left.pitCrewCount !== right.pitCrewCount) return left.pitCrewCount - right.pitCrewCount;
  return left.seat - right.seat;
}
function rankRacers(racers, questionsPerLap = QUESTIONS_PER_LAP) {
  const ordered = racers.slice().sort((left, right) => compareRacers(left, right, questionsPerLap));
  return ordered.map((racer, index) => ({
    id: racer.id,
    place: index + 1,
    finished: racer.finished,
    finishTimeMs: racer.finishTimeMs,
    effectiveProgress: effectiveProgress(racer, questionsPerLap),
    correctCount: racer.correctCount,
    pitCrewCount: racer.pitCrewCount
  }));
}
function positionOrder(racers, questionsPerLap = QUESTIONS_PER_LAP) {
  const ordered = racers.slice().sort((left, right) => compareRacers(left, right, questionsPerLap));
  const ids = [];
  for (const racer of ordered) ids.push(racer.id);
  return ids;
}
function placeOf(racers, racerId, questionsPerLap = QUESTIONS_PER_LAP) {
  const order = positionOrder(racers, questionsPerLap);
  return order.indexOf(racerId) + 1;
}
var PODIUM_SIZE = 3;
function resultsBoard(racers, racerId, questionsPerLap = QUESTIONS_PER_LAP) {
  const ranked = rankRacers(racers, questionsPerLap);
  const own = ranked.find((entry) => entry.id === racerId);
  const place = own === void 0 ? 0 : own.place;
  return {
    place,
    total: ranked.length,
    headline: headlineForPlace(place),
    podium: ranked.slice(0, PODIUM_SIZE)
  };
}
function headlineForPlace(place) {
  if (place === 1) return "VICTORY LAP";
  if (place === 2 || place === 3) return "PODIUM FINISH";
  return "RACE COMPLETE";
}
function ordinal(place) {
  const tens = place % 100;
  if (tens >= 11 && tens <= 13) return place + "th";
  const ones = place % 10;
  if (ones === 1) return place + "st";
  if (ones === 2) return place + "nd";
  if (ones === 3) return place + "rd";
  return place + "th";
}

// src/engine/events.ts
var SIGNAL_CATALOG = ["goodLuck", "niceRun", "soClose", "goodGame"];
var EVENT_ORDER = {
  correct: 0,
  wrong: 0,
  reveal: 0,
  pitCrew: 0,
  cardUsed: 0,
  hit: 1,
  blocked: 1,
  swap: 1,
  lapComplete: 2,
  finished: 3,
  handDealt: 4,
  signal: 5,
  passed: 6,
  passedBy: 6
};
function isEventOrdered(events) {
  let seen = -1;
  for (const event of events) {
    const rank = EVENT_ORDER[event.type];
    if (rank < seen) return false;
    seen = rank;
  }
  return true;
}

// src/engine/race.ts
var NEXT_FACT_MS = 250;
var SPUTTER_MS = 500;
var REVEAL_MS = 1500;
var CALLOUT_MS = 1600;
var SETTLE_MS = 15e3;
function newRacer(config, seat, questionsPerLap) {
  var _a;
  return {
    id: config.id,
    seat,
    kind: (_a = config.kind) != null ? _a : "rival",
    lapsComplete: 0,
    correctInLap: 0,
    questionsNeededThisLap: questionsPerLap,
    finished: false,
    finishTimeMs: 0,
    place: 0,
    streak: 0,
    bestStreak: 0,
    hand: [],
    rollCages: 0,
    correctCount: 0,
    wrongCount: 0,
    pitCrewCount: 0,
    revealCount: 0,
    attemptCount: 0,
    stalledUntilMs: 0,
    entry: "",
    wrongOnCurrentFact: 0,
    currentFact: -1,
    currentFromPitLane: false,
    queue: [],
    queueDraws: 0,
    answersThisLap: 0,
    pitLane: [],
    missed: [],
    factHistory: [],
    cardsUsed: []
  };
}
function createRace(config) {
  var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m;
  const preset = (_a = config.preset) != null ? _a : "1-12";
  const tables = tablesForPreset(preset, config.chosenTables);
  const mode = (_b = config.mode) != null ? _b : "grandPrix";
  const racers = config.racers.map((racer, seat) => newRacer(racer, seat, QUESTIONS_PER_LAP));
  const humanId = (_g = (_f = (_d = config.humanId) != null ? _d : (_c = racers.find((racer) => racer.kind === "human")) == null ? void 0 : _c.id) != null ? _f : (_e = racers[0]) == null ? void 0 : _e.id) != null ? _g : "";
  const state = {
    version: 1,
    seed: config.seed >>> 0,
    mode,
    preset,
    tables,
    questionsPerLap: QUESTIONS_PER_LAP,
    totalLaps: tables.length,
    streakThreshold: (_h = config.streakThreshold) != null ? _h : STREAK_THRESHOLD,
    powerupsEnabled: (_i = config.powerupsEnabled) != null ? _i : mode === "grandPrix",
    revealAfterWrong: mode === "practice" ? 1 : 2,
    schedule: ((_j = config.schedule) != null ? _j : CARD_SCHEDULE).slice(),
    cardCursor: 0,
    settleMs: (_k = config.settleMs) != null ? _k : SETTLE_MS,
    status: "countdown",
    startedAtMs: (_l = config.startedAtMs) != null ? _l : 0,
    nowMs: (_m = config.startedAtMs) != null ? _m : 0,
    settleUntilMs: 0,
    finishedCount: 0,
    humanId,
    racers
  };
  if (config.factHistory !== void 0) {
    const human = racerById(state, humanId);
    if (human !== null) human.factHistory = cloneFactHistory(config.factHistory);
  }
  for (const racer of state.racers) refreshQuestion(state, racer);
  return state;
}
function factHistoryOf(state) {
  const human = racerById(state, state.humanId);
  return human === null ? [] : cloneFactHistory(human.factHistory);
}
function factHistoryEntry(racer, fact) {
  return factRecordOf(racer.factHistory, fact);
}
function cloneRacer(racer) {
  return {
    id: racer.id,
    seat: racer.seat,
    kind: racer.kind,
    lapsComplete: racer.lapsComplete,
    correctInLap: racer.correctInLap,
    questionsNeededThisLap: racer.questionsNeededThisLap,
    finished: racer.finished,
    finishTimeMs: racer.finishTimeMs,
    place: racer.place,
    streak: racer.streak,
    bestStreak: racer.bestStreak,
    hand: racer.hand.slice(),
    rollCages: racer.rollCages,
    correctCount: racer.correctCount,
    wrongCount: racer.wrongCount,
    pitCrewCount: racer.pitCrewCount,
    revealCount: racer.revealCount,
    attemptCount: racer.attemptCount,
    stalledUntilMs: racer.stalledUntilMs,
    entry: racer.entry,
    wrongOnCurrentFact: racer.wrongOnCurrentFact,
    currentFact: racer.currentFact,
    currentFromPitLane: racer.currentFromPitLane,
    queue: racer.queue.slice(),
    queueDraws: racer.queueDraws,
    answersThisLap: racer.answersThisLap,
    pitLane: racer.pitLane.map((entry) => ({
      fact: entry.fact,
      lap: entry.lap,
      dueAtAnswer: entry.dueAtAnswer
    })),
    missed: racer.missed.slice(),
    factHistory: cloneFactHistory(racer.factHistory),
    cardsUsed: racer.cardsUsed.map((used) => ({
      card: used.card,
      targetId: used.targetId,
      at: used.at
    }))
  };
}
function cloneState(state) {
  return {
    version: state.version,
    seed: state.seed,
    mode: state.mode,
    preset: state.preset,
    tables: state.tables.slice(),
    questionsPerLap: state.questionsPerLap,
    totalLaps: state.totalLaps,
    streakThreshold: state.streakThreshold,
    powerupsEnabled: state.powerupsEnabled,
    revealAfterWrong: state.revealAfterWrong,
    schedule: state.schedule.slice(),
    cardCursor: state.cardCursor,
    settleMs: state.settleMs,
    status: state.status,
    startedAtMs: state.startedAtMs,
    nowMs: state.nowMs,
    settleUntilMs: state.settleUntilMs,
    finishedCount: state.finishedCount,
    humanId: state.humanId,
    racers: state.racers.map(cloneRacer)
  };
}
function racerById(state, racerId) {
  for (const racer of state.racers) if (racer.id === racerId) return racer;
  return null;
}
function humanRacer(state) {
  var _a;
  return (_a = racerById(state, state.humanId)) != null ? _a : state.racers[0];
}
function currentTable(state, racer) {
  var _a;
  return (_a = state.tables[racer.lapsComplete]) != null ? _a : 0;
}
function currentTableName(state, racer) {
  return tableName(currentTable(state, racer));
}
function isStalled(racer, now) {
  return now < racer.stalledUntilMs;
}
function racerProgress(state, racer) {
  return effectiveProgress(racer, state.questionsPerLap);
}
function raceOrder(state) {
  return positionOrder(state.racers, state.questionsPerLap);
}
function accuracyPercent(racer) {
  if (racer.attemptCount === 0) return 0;
  return Math.round(racer.correctCount / racer.attemptCount * 100);
}
function fillQueue(state, racer) {
  const table = currentTable(state, racer);
  if (table === 0) {
    racer.queue = [];
    return;
  }
  if (racer.queueDraws === 0) {
    racer.queue = lapDeck(state.seed, racer.lapsComplete, table);
  } else {
    racer.queue = extraQuestions(
      state.seed,
      racer.id,
      racer.lapsComplete,
      racer.queueDraws,
      table,
      racer.missed,
      racer.factHistory
    );
  }
  racer.queueDraws += 1;
}
function pickPitLaneEntry(racer) {
  let best = null;
  let bestCarriedOver = false;
  for (const entry of racer.pitLane) {
    const carriedOver = entry.lap < racer.lapsComplete;
    const dueThisLap = entry.lap === racer.lapsComplete && racer.answersThisLap >= entry.dueAtAnswer;
    if (!carriedOver && !dueThisLap) continue;
    if (best === null) {
      best = entry;
      bestCarriedOver = carriedOver;
      continue;
    }
    if (carriedOver !== bestCarriedOver) {
      if (carriedOver) {
        best = entry;
        bestCarriedOver = true;
      }
      continue;
    }
    const byHistory = compareByFactHistory(racer.factHistory, entry.fact, best.fact);
    if (byHistory < 0) {
      best = entry;
      bestCarriedOver = carriedOver;
      continue;
    }
    if (byHistory > 0) continue;
    if (entry.dueAtAnswer < best.dueAtAnswer) {
      best = entry;
      bestCarriedOver = carriedOver;
      continue;
    }
    if (entry.dueAtAnswer === best.dueAtAnswer && entry.fact < best.fact) {
      best = entry;
      bestCarriedOver = carriedOver;
    }
  }
  return best;
}
function refreshQuestion(state, racer) {
  const previousFact = racer.currentFact;
  if (racer.finished) {
    racer.currentFact = -1;
    racer.currentFromPitLane = false;
  } else {
    const entry = pickPitLaneEntry(racer);
    if (entry !== null) {
      racer.currentFact = entry.fact;
      racer.currentFromPitLane = true;
    } else {
      if (racer.queue.length === 0) fillQueue(state, racer);
      racer.currentFact = racer.queue.length > 0 ? racer.queue[0] : -1;
      racer.currentFromPitLane = false;
    }
  }
  if (racer.currentFact !== previousFact) {
    racer.wrongOnCurrentFact = 0;
    racer.entry = "";
  }
}
function consumeQuestion(racer) {
  if (racer.currentFromPitLane) {
    for (let index = 0; index < racer.pitLane.length; index++) {
      if (racer.pitLane[index].fact === racer.currentFact) {
        racer.pitLane.splice(index, 1);
        break;
      }
    }
  } else if (racer.queue.length > 0 && racer.queue[0] === racer.currentFact) {
    racer.queue.shift();
  }
  racer.answersThisLap += 1;
  racer.wrongOnCurrentFact = 0;
  racer.entry = "";
}
function startLap(racer) {
  racer.queue = [];
  racer.queueDraws = 0;
  racer.answersThisLap = 0;
  racer.wrongOnCurrentFact = 0;
  racer.entry = "";
}
function rememberMissed(racer, fact) {
  if (racer.missed.indexOf(fact) === -1) racer.missed.push(fact);
}
function fileOutcome(racer, fact, outcome) {
  if (fact < 0) return;
  recordFactOutcome(racer.factHistory, fact, outcome);
}
function advanceLaps(state, racer, at, events) {
  while (racer.correctInLap >= racer.questionsNeededThisLap && !racer.finished) {
    const table = currentTable(state, racer);
    racer.correctInLap -= racer.questionsNeededThisLap;
    racer.lapsComplete += 1;
    racer.questionsNeededThisLap = state.questionsPerLap;
    startLap(racer);
    events.push({
      type: "lapComplete",
      at,
      racerId: racer.id,
      lapsComplete: racer.lapsComplete,
      table,
      surplus: racer.correctInLap
    });
    if (racer.lapsComplete >= state.totalLaps) {
      racer.finished = true;
      racer.finishTimeMs = at;
      racer.correctInLap = 0;
      state.finishedCount += 1;
      racer.place = state.finishedCount;
      events.push({
        type: "finished",
        at,
        racerId: racer.id,
        place: racer.place,
        finishTimeMs: at
      });
    }
  }
}
function applyQuestionDelta(state, attacker, victim, card, at, events) {
  const definition = CARDS[card];
  victim.questionsNeededThisLap = applyFloor(
    victim.questionsNeededThisLap,
    definition.questionDelta
  );
  const stallMs = attacker.id === victim.id ? 0 : definition.stallMs;
  if (stallMs > 0) victim.stalledUntilMs = at + stallMs;
  events.push({
    type: "hit",
    at,
    racerId: victim.id,
    fromId: attacker.id,
    card,
    questionDelta: definition.questionDelta,
    questionsNeededThisLap: victim.questionsNeededThisLap,
    stallMs
  });
  advanceLaps(state, victim, at, events);
  refreshQuestion(state, victim);
}
function dealIfCharged(state, racer, at, events) {
  if (!state.powerupsEnabled) return;
  if (racer.finished) return;
  if (!shouldDealHand(racer.streak, state.streakThreshold, racer.hand.length)) return;
  const schedule2 = state.schedule.length > 0 ? state.schedule : CARD_SCHEDULE;
  const dealt = dealHand(schedule2, state.cardCursor);
  state.cardCursor = dealt.cursor;
  racer.hand = dealt.hand;
  racer.streak = 0;
  events.push({
    type: "handDealt",
    at,
    racerId: racer.id,
    hand: dealt.hand.slice(),
    cursorAfter: dealt.cursor
  });
}
function canAnswer(state, racer, at) {
  if (state.status !== "racing" && state.status !== "settling") return false;
  if (racer.finished) return false;
  if (racer.currentFact < 0) return false;
  if (isStalled(racer, at)) return false;
  return true;
}
function answerCorrect(state, racer, at, events) {
  const fact = racer.currentFact;
  racer.attemptCount += 1;
  racer.correctCount += 1;
  racer.correctInLap += 1;
  racer.streak += 1;
  if (racer.streak > racer.bestStreak) racer.bestStreak = racer.streak;
  fileOutcome(racer, fact, "correct");
  consumeQuestion(racer);
  events.push({
    type: "correct",
    at,
    racerId: racer.id,
    fact,
    answer: factAnswer(fact),
    streak: racer.streak,
    correctInLap: racer.correctInLap,
    questionsNeededThisLap: racer.questionsNeededThisLap
  });
  advanceLaps(state, racer, at, events);
  dealIfCharged(state, racer, at, events);
  refreshQuestion(state, racer);
}
function answerWrong(state, racer, given, at, events) {
  const fact = racer.currentFact;
  racer.attemptCount += 1;
  racer.wrongCount += 1;
  racer.streak = 0;
  racer.wrongOnCurrentFact += 1;
  racer.entry = "";
  rememberMissed(racer, fact);
  if (racer.wrongOnCurrentFact < state.revealAfterWrong) {
    fileOutcome(racer, fact, "wrong");
    events.push({
      type: "wrong",
      at,
      racerId: racer.id,
      fact,
      given,
      wrongOnThisFact: racer.wrongOnCurrentFact,
      sputterMs: SPUTTER_MS
    });
    return;
  }
  fileOutcome(racer, fact, "reveal");
  racer.revealCount += 1;
  racer.correctInLap += 1;
  const lap = racer.lapsComplete;
  consumeQuestion(racer);
  racer.pitLane.push({ fact, lap, dueAtAnswer: racer.answersThisLap + 3 });
  events.push({ type: "reveal", at, racerId: racer.id, fact, answer: factAnswer(fact), revealMs: REVEAL_MS });
  advanceLaps(state, racer, at, events);
  refreshQuestion(state, racer);
}
function answerPitCrew(state, racer, at, events) {
  const fact = racer.currentFact;
  racer.attemptCount += 1;
  racer.pitCrewCount += 1;
  racer.correctInLap += 1;
  fileOutcome(racer, fact, "pitCrew");
  consumeQuestion(racer);
  events.push({ type: "pitCrew", at, racerId: racer.id, fact, answer: factAnswer(fact) });
  advanceLaps(state, racer, at, events);
  refreshQuestion(state, racer);
}
function submitAnswer(state, racer, value, at, events) {
  if (!canAnswer(state, racer, at)) return;
  if (value === factAnswer(racer.currentFact)) answerCorrect(state, racer, at, events);
  else answerWrong(state, racer, value, at, events);
}
function attackOne(state, attacker, victim, card, at, events) {
  if (victim.rollCages > 0) {
    victim.rollCages -= 1;
    events.push({
      type: "blocked",
      at,
      racerId: victim.id,
      fromId: attacker.id,
      card,
      rollCagesLeft: victim.rollCages
    });
    return;
  }
  if (card === "towHook") {
    swapPositions(attacker, victim);
    startLap(attacker);
    startLap(victim);
    refreshQuestion(state, attacker);
    refreshQuestion(state, victim);
    events.push({ type: "swap", at, racerId: attacker.id, withId: victim.id });
    return;
  }
  applyQuestionDelta(state, attacker, victim, card, at, events);
}
function playCard(state, racer, index, targetId, at, events) {
  if (!state.powerupsEnabled) return;
  if (state.status !== "racing" && state.status !== "settling") return;
  if (racer.finished) return;
  if (index < 0 || index >= racer.hand.length) return;
  const card = racer.hand[index];
  const definition = CARDS[card];
  let target = null;
  if (definition.scope === "targeted") {
    if (targetId === "" || targetId === racer.id) return;
    target = racerById(state, targetId);
    if (target === null || target.finished) return;
  } else if (targetId !== "") {
    return;
  }
  const discarded = [];
  for (let held = 0; held < racer.hand.length; held++) {
    if (held !== index) discarded.push(racer.hand[held]);
  }
  racer.hand = [];
  racer.cardsUsed.push({ card, targetId, at });
  events.push({ type: "cardUsed", at, racerId: racer.id, card, targetId, discarded });
  if (card === "rollCage") {
    racer.rollCages += 1;
    return;
  }
  if (definition.scope === "self") {
    applyQuestionDelta(state, racer, racer, card, at, events);
    return;
  }
  if (definition.scope === "aoe") {
    for (const victim of state.racers) {
      if (victim.id === racer.id || victim.finished) continue;
      attackOne(state, racer, victim, card, at, events);
    }
    return;
  }
  attackOne(state, racer, target, card, at, events);
}
function typeDigit(state, racer, value, at, events) {
  if (!canAnswer(state, racer, at)) return;
  if (value < 0 || value > 9) return;
  if (racer.entry === "" && value === 0) return;
  const expected = String(factAnswer(racer.currentFact));
  if (racer.entry.length >= expected.length) return;
  racer.entry += String(value);
  if (racer.entry.length === expected.length) {
    const typed = Number(racer.entry);
    submitAnswer(state, racer, typed, at, events);
  }
}
function allFinished(state) {
  if (state.racers.length === 0) return false;
  for (const racer of state.racers) if (!racer.finished) return false;
  return true;
}
function advanceStatus(state, at) {
  if (state.status === "countdown" || state.status === "finished") return;
  const human = humanRacer(state);
  if (state.status === "racing" && human.finished) {
    if (state.mode === "grandPrix" && state.settleMs > 0 && !allFinished(state)) {
      state.status = "settling";
      state.settleUntilMs = at + state.settleMs;
    } else {
      state.status = "finished";
    }
  }
  if (state.status === "settling" && (allFinished(state) || at >= state.settleUntilMs)) {
    state.status = "finished";
  }
  if (state.status === "racing" && allFinished(state)) state.status = "finished";
}
function passEvents(state, before, at, events) {
  const after = raceOrder(state);
  const humanId = state.humanId;
  const beforeHuman = before.indexOf(humanId);
  const afterHuman = after.indexOf(humanId);
  if (beforeHuman < 0 || afterHuman < 0) return;
  for (const racer of state.racers) {
    if (racer.id === humanId) continue;
    const wasAhead = before.indexOf(racer.id) < beforeHuman;
    const isAhead = after.indexOf(racer.id) < afterHuman;
    if (wasAhead && !isAhead)
      events.push({ type: "passed", at, racerId: humanId, otherId: racer.id, calloutMs: CALLOUT_MS });
    else if (!wasAhead && isAhead)
      events.push({
        type: "passedBy",
        at,
        racerId: humanId,
        otherId: racer.id,
        calloutMs: CALLOUT_MS
      });
  }
}
function step(state, input, now) {
  var _a, _b;
  const next = cloneState(state);
  const events = [];
  const at = now > next.nowMs ? now : next.nowMs;
  next.nowMs = at;
  const before = raceOrder(next);
  if (input.kind === "start") {
    if (next.status === "countdown") {
      next.status = "racing";
      next.startedAtMs = at;
    }
  } else if (input.kind !== "tick") {
    const racerId = (_a = input.racerId) != null ? _a : next.humanId;
    const racer = racerById(next, racerId);
    if (racer !== null) {
      if (input.kind === "digit") typeDigit(next, racer, input.value, at, events);
      else if (input.kind === "backspace") {
        if (canAnswer(next, racer, at)) racer.entry = racer.entry.slice(0, -1);
      } else if (input.kind === "submit") {
        if (racer.entry !== "") submitAnswer(next, racer, Number(racer.entry), at, events);
      } else if (input.kind === "answer") submitAnswer(next, racer, input.value, at, events);
      else if (input.kind === "hint") {
        if (canAnswer(next, racer, at)) answerPitCrew(next, racer, at, events);
      } else if (input.kind === "useCard")
        playCard(next, racer, input.index, (_b = input.targetId) != null ? _b : "", at, events);
    }
  }
  advanceStatus(next, at);
  passEvents(next, before, at, events);
  return { state: next, events };
}
function replay(config, script) {
  let state = createRace(config);
  const events = [];
  for (const entry of script) {
    const result = step(state, entry.input, entry.at);
    state = result.state;
    for (const event of result.events) events.push(event);
  }
  return { state, events };
}

// src/engine/rivals.ts
var RIVAL_PROFILES = {
  bolt: {
    personality: "bolt",
    label: "Bolt",
    temperament: "fast, sloppy",
    accuracyPercent: 84,
    thinkTimeMeanMs: 2800,
    thinkTimeSpreadMs: 900
  },
  piston: {
    personality: "piston",
    label: "Piston",
    temperament: "steady",
    accuracyPercent: 91,
    thinkTimeMeanMs: 3400,
    thinkTimeSpreadMs: 700
  },
  gasket: {
    personality: "gasket",
    label: "Gasket",
    temperament: "careful, slow",
    accuracyPercent: 96,
    thinkTimeMeanMs: 4600,
    thinkTimeSpreadMs: 1e3
  }
};
var RIVAL_ORDER = ["bolt", "piston", "gasket"];
var RIVAL_LEVELS = {
  rookie: { level: "rookie", label: "ROOKIE", thinkTimeScale: 1.5, accuracyDelta: -8 },
  pro: { level: "pro", label: "PRO", thinkTimeScale: 1, accuracyDelta: 0 },
  champion: { level: "champion", label: "CHAMPION", thinkTimeScale: 0.75, accuracyDelta: 3 }
};
var RIVAL_LEVEL_ORDER = ["rookie", "pro", "champion"];
var RUBBER_BAND_LIMIT = 0.15;
var RIVAL_FLOOR_MS = 1500;
var RIVAL_PACE_WINDOW = 12;
var POLICY_INTERVAL = 3;
var HALF_LAP = QUESTIONS_PER_LAP / 2;
var NICE_RUN_CHANCE = 1 / 3;
var BOOST_CARDS = ["turbo", "nitro"];
var ATTACK_CARDS = ["pileUp", "pothole", "wrench", "oilSlick", "towHook"];
function isAttackCard(card) {
  return ATTACK_CARDS.indexOf(card) !== -1;
}
function rivalTuning(personality, level) {
  const profile = RIVAL_PROFILES[personality];
  const adjust = RIVAL_LEVELS[level];
  const accuracy = profile.accuracyPercent + adjust.accuracyDelta;
  return {
    personality,
    level,
    accuracyPercent: accuracy < 0 ? 0 : accuracy > 100 ? 100 : accuracy,
    thinkTimeMeanMs: Math.round(profile.thinkTimeMeanMs * adjust.thinkTimeScale),
    thinkTimeSpreadMs: Math.round(profile.thinkTimeSpreadMs * adjust.thinkTimeScale)
  };
}
function rubberBandScale(childPaceMs2, meanMs) {
  if (childPaceMs2 <= 0 || meanMs <= 0) return 1;
  const ratio = childPaceMs2 / meanMs;
  if (ratio > 1 + RUBBER_BAND_LIMIT) return 1 + RUBBER_BAND_LIMIT;
  if (ratio < 1 - RUBBER_BAND_LIMIT) return 1 - RUBBER_BAND_LIMIT;
  return ratio;
}
function drawThinkTime(rng, meanMs, spreadMs, scale) {
  const centre = meanMs * scale;
  const spread = spreadMs * scale;
  const wobble = nextFloat(rng) + nextFloat(rng) - 1;
  const drawnMs = Math.round(centre + spread * wobble);
  return { drawnMs, thinkMs: drawnMs < RIVAL_FLOOR_MS ? RIVAL_FLOOR_MS : drawnMs };
}
function drawThinkTimeMs(rng, meanMs, spreadMs, scale) {
  return drawThinkTime(rng, meanMs, spreadMs, scale).thinkMs;
}
function drawsCorrect(rng, accuracyPercent2) {
  return nextFloat(rng) * 100 < accuracyPercent2;
}
function drawWrongAnswer(rng, fact) {
  const answer = factAnswer(fact);
  const left = factLeft(fact);
  const right = factRight(fact);
  const candidates = [
    answer + left,
    answer - left,
    answer + right,
    answer - right,
    answer + 1,
    answer - 1
  ];
  const start = nextInt(rng, candidates.length);
  for (let index = 0; index < candidates.length; index++) {
    const value = candidates[(start + index) % candidates.length];
    if (value > 0 && value !== answer) return value;
  }
  return answer + 1;
}
function cloneMind(mind) {
  return {
    id: mind.id,
    personality: mind.personality,
    level: mind.level,
    accuracyPercent: mind.accuracyPercent,
    thinkTimeMeanMs: mind.thinkTimeMeanMs,
    thinkTimeSpreadMs: mind.thinkTimeSpreadMs,
    rng: cloneRng(mind.rng),
    nextAnswerAtMs: mind.nextAnswerAtMs,
    lastDrawnThinkMs: mind.lastDrawnThinkMs,
    lastThinkMs: mind.lastThinkMs,
    lastScale: mind.lastScale,
    answersTaken: mind.answersTaken,
    answersSincePolicy: mind.answersSincePolicy,
    lastHandAttackedHuman: mind.lastHandAttackedHuman
  };
}
function cloneRivals(rivals) {
  return {
    humanId: rivals.humanId,
    minds: rivals.minds.map(cloneMind),
    childGaps: rivals.childGaps.slice(),
    childLastAnswerAtMs: rivals.childLastAnswerAtMs,
    childAnswers: rivals.childAnswers,
    childLapMistakes: rivals.childLapMistakes,
    niceRunLaps: rivals.niceRunLaps.slice(),
    sentGoodGame: rivals.sentGoodGame,
    rng: cloneRng(rivals.rng)
  };
}
function createRivals(state, configs) {
  const rivals = {
    humanId: state.humanId,
    minds: [],
    childGaps: [],
    childLastAnswerAtMs: 0,
    childAnswers: 0,
    childLapMistakes: 0,
    niceRunLaps: [],
    sentGoodGame: false,
    rng: forkRng(state.seed, "rivals:signals")
  };
  for (const config of configs) {
    const tuning = rivalTuning(config.personality, config.level);
    const mind = {
      id: config.id,
      personality: config.personality,
      level: config.level,
      accuracyPercent: tuning.accuracyPercent,
      thinkTimeMeanMs: tuning.thinkTimeMeanMs,
      thinkTimeSpreadMs: tuning.thinkTimeSpreadMs,
      rng: forkRng(state.seed, "rival:" + config.id + ":" + config.personality + ":" + config.level),
      nextAnswerAtMs: state.startedAtMs,
      lastDrawnThinkMs: 0,
      lastThinkMs: 0,
      lastScale: 1,
      answersTaken: 0,
      answersSincePolicy: 0,
      lastHandAttackedHuman: false
    };
    schedule(rivals, mind, state.startedAtMs);
    rivals.minds.push(mind);
  }
  return rivals;
}
function mindOf(rivals, racerId) {
  for (const mind of rivals.minds) if (mind.id === racerId) return mind;
  return null;
}
function childPaceMs(rivals) {
  if (rivals.childGaps.length === 0) return 0;
  let total = 0;
  for (const gap of rivals.childGaps) total += gap;
  return total / rivals.childGaps.length;
}
function schedule(rivals, mind, fromMs) {
  const scale = rubberBandScale(childPaceMs(rivals), mind.thinkTimeMeanMs);
  const drawn = drawThinkTime(mind.rng, mind.thinkTimeMeanMs, mind.thinkTimeSpreadMs, scale);
  mind.lastScale = scale;
  mind.lastDrawnThinkMs = drawn.drawnMs;
  mind.lastThinkMs = drawn.thinkMs;
  mind.nextAnswerAtMs = fromMs + drawn.thinkMs;
}
function standings(state) {
  const rows = [];
  for (const racer of state.racers) {
    rows.push({
      id: racer.id,
      progress: effectiveProgress(racer, state.questionsPerLap),
      finished: racer.finished
    });
  }
  return rows;
}
function lastPlaceIds(state) {
  const rows = standings(state);
  if (rows.length === 0) return [];
  let lowest = rows[0].progress;
  for (const row of rows) if (row.progress < lowest) lowest = row.progress;
  const ids = [];
  for (const row of rows) if (row.progress === lowest) ids.push(row.id);
  return ids;
}
function mayAttack(state, mind, victimId, last) {
  if (victimId === mind.id) return false;
  const victim = racerById(state, victimId);
  if (victim === null || victim.finished) return false;
  if (last.indexOf(victimId) !== -1) return false;
  if (victimId === state.humanId && mind.lastHandAttackedHuman) return false;
  return true;
}
function aoeVictims(state, attackerId) {
  const ids = [];
  for (const racer of state.racers) {
    if (racer.id === attackerId || racer.finished) continue;
    ids.push(racer.id);
  }
  return ids;
}
function handIndexOf(racer, card) {
  return racer.hand.indexOf(card);
}
function choosePlay(state, mind) {
  const racer = racerById(state, mind.id);
  if (racer === null || racer.finished || racer.hand.length === 0) return null;
  if (!state.powerupsEnabled) return null;
  const order = positionOrder(state.racers, state.questionsPerLap);
  const own = effectiveProgress(racer, state.questionsPerLap);
  const leaderId = order.length > 0 ? order[0] : "";
  const leader = leaderId === "" ? null : racerById(state, leaderId);
  const leaderProgress = leader === null ? own : effectiveProgress(leader, state.questionsPerLap);
  if (leaderProgress - own > HALF_LAP) {
    for (let index = 0; index < racer.hand.length; index++) {
      const card = racer.hand[index];
      if (BOOST_CARDS.indexOf(card) !== -1) return { index, card, targetId: "", rule: "boost" };
    }
  }
  const place = order.indexOf(mind.id) + 1;
  if (racer.rollCages === 0 && (place === 1 || place === 2)) {
    const index = handIndexOf(racer, "rollCage");
    if (index >= 0) return { index, card: "rollCage", targetId: "", rule: "rollCage" };
  }
  const last = lastPlaceIds(state);
  for (let index = 0; index < racer.hand.length; index++) {
    const card = racer.hand[index];
    if (!isAttackCard(card)) continue;
    if (CARDS[card].scope === "aoe") {
      const victims = aoeVictims(state, mind.id);
      if (victims.length === 0) continue;
      let legal = true;
      for (const victimId of victims) {
        if (!mayAttack(state, mind, victimId, last)) {
          legal = false;
          break;
        }
      }
      if (legal) return { index, card, targetId: "", rule: "attack" };
      continue;
    }
    const targetId = chooseTarget(state, mind, order, last);
    if (targetId !== "") return { index, card, targetId, rule: "attack" };
  }
  return null;
}
function chooseTarget(state, mind, order, last) {
  const leaderId = order.length > 0 ? order[0] : "";
  if (leaderId !== "" && leaderId !== mind.id && mayAttack(state, mind, leaderId, last)) {
    return leaderId;
  }
  const ownIndex = order.indexOf(mind.id);
  if (ownIndex >= 0) {
    for (let index = ownIndex + 1; index < order.length; index++) {
      const candidate = order[index];
      if (mayAttack(state, mind, candidate, last)) return candidate;
    }
  }
  return "";
}
function rivalObserve(rivals, state, events) {
  const next = cloneRivals(rivals);
  const signals = observeInto(next, state, events);
  return { rivals: next, signals };
}
function observeInto(rivals, state, events) {
  const signals = [];
  for (const event of events) {
    if (event.type === "correct" || event.type === "reveal" || event.type === "pitCrew") {
      if (event.racerId === rivals.humanId) recordChildAnswer(rivals, state, event.at);
      if (event.racerId === rivals.humanId && event.type === "reveal") rivals.childLapMistakes += 1;
      continue;
    }
    if (event.type === "wrong") {
      if (event.racerId === rivals.humanId) rivals.childLapMistakes += 1;
      continue;
    }
    if (event.type === "lapComplete" && event.racerId === rivals.humanId) {
      const clean = rivals.childLapMistakes === 0;
      const lap = event.lapsComplete;
      rivals.childLapMistakes = 0;
      if (clean && rivals.niceRunLaps.indexOf(lap) === -1) {
        rivals.niceRunLaps.push(lap);
        if (nextFloat(rivals.rng) < NICE_RUN_CHANCE) {
          const speaker = pickSpeaker(rivals, state);
          if (speaker !== null) signals.push(signalEvent(speaker.id, "niceRun", event.at));
        }
      }
      continue;
    }
    if (event.type === "finished" && event.racerId === rivals.humanId) {
      if (rivals.sentGoodGame) continue;
      const speaker = pickSpeaker(rivals, state);
      if (speaker === null) continue;
      rivals.sentGoodGame = true;
      signals.push(signalEvent(speaker.id, "goodGame", event.at));
    }
  }
  return signals;
}
function signalEvent(racerId, signal, at) {
  return { type: "signal", at, racerId, signal };
}
function recordChildAnswer(rivals, state, at) {
  const since = rivals.childLastAnswerAtMs > 0 ? rivals.childLastAnswerAtMs : state.startedAtMs;
  const gap = at - since;
  rivals.childGaps.push(gap > 0 ? gap : 0);
  while (rivals.childGaps.length > RIVAL_PACE_WINDOW) rivals.childGaps.shift();
  rivals.childLastAnswerAtMs = at;
  rivals.childAnswers += 1;
}
function pickSpeaker(rivals, state) {
  const racing = [];
  for (const mind of rivals.minds) {
    const racer = racerById(state, mind.id);
    if (racer !== null && !racer.finished) racing.push(mind);
  }
  if (racing.length === 0) for (const mind of rivals.minds) racing.push(mind);
  if (racing.length === 0) return null;
  return racing[nextInt(rivals.rng, racing.length)];
}
function mergeSignals(events, signals) {
  const out = [];
  if (signals.length === 0) {
    for (const event of events) out.push(event);
    return out;
  }
  let placed = false;
  for (const event of events) {
    if (!placed && (event.type === "passed" || event.type === "passedBy")) {
      for (const signal of signals) out.push(signal);
      placed = true;
    }
    out.push(event);
  }
  if (!placed) for (const signal of signals) out.push(signal);
  return out;
}
var MAX_ACTIONS_PER_STEP = 4096;
function rivalStep(state, rivals, now) {
  let next = state;
  const minds = cloneRivals(rivals);
  const events = [];
  const answers = [];
  const plays = [];
  if (next.status !== "racing" && next.status !== "settling") {
    if (next.status === "countdown") {
      for (const mind of minds.minds) {
        if (mind.nextAnswerAtMs < now) mind.nextAnswerAtMs = now;
      }
    }
    return { state: next, rivals: minds, events, answers, plays };
  }
  let guard = 0;
  for (; ; ) {
    if (++guard > MAX_ACTIONS_PER_STEP) break;
    for (const mind2 of minds.minds) {
      const racer2 = racerById(next, mind2.id);
      if (racer2 === null) continue;
      if (mind2.nextAnswerAtMs < racer2.stalledUntilMs) mind2.nextAnswerAtMs = racer2.stalledUntilMs;
    }
    const mind = dueMind(next, minds, now);
    if (mind === null) break;
    const at = mind.nextAnswerAtMs;
    const racer = racerById(next, mind.id);
    const fact = racer.currentFact;
    const handBefore = racer.hand.length;
    const correct = drawsCorrect(mind.rng, mind.accuracyPercent);
    const value = correct ? factAnswer(fact) : drawWrongAnswer(mind.rng, fact);
    const applied = step(next, { kind: "answer", racerId: mind.id, value }, at);
    next = applied.state;
    const signals = observeInto(minds, next, applied.events);
    for (const event of mergeSignals(applied.events, signals)) events.push(event);
    mind.answersTaken += 1;
    mind.answersSincePolicy += 1;
    answers.push({
      at,
      racerId: mind.id,
      fact,
      correct,
      value,
      thinkMs: mind.lastThinkMs,
      drawnThinkMs: mind.lastDrawnThinkMs,
      scale: mind.lastScale
    });
    schedule(minds, mind, at);
    const after = racerById(next, mind.id);
    const handAfter = after.hand.length;
    const dealt = handBefore === 0 && handAfter > 0;
    if (handAfter > 0 && (dealt || mind.answersSincePolicy >= POLICY_INTERVAL)) {
      mind.answersSincePolicy = 0;
      const choice = choosePlay(next, mind);
      if (choice !== null) {
        const before = standings(next);
        const played = step(
          next,
          {
            kind: "useCard",
            racerId: mind.id,
            index: choice.index,
            targetId: choice.targetId === "" ? void 0 : choice.targetId
          },
          at
        );
        next = played.state;
        const playSignals = observeInto(minds, next, played.events);
        for (const event of mergeSignals(played.events, playSignals)) events.push(event);
        const victimIds = victimsOf(played.events, mind.id);
        const attackedHuman = isAttackCard(choice.card) && victimIds.indexOf(next.humanId) !== -1;
        plays.push({
          at,
          racerId: mind.id,
          card: choice.card,
          targetId: choice.targetId,
          rule: choice.rule,
          victimIds,
          standingsBefore: before,
          previousHandAttackedHuman: mind.lastHandAttackedHuman,
          attackedHuman
        });
        mind.lastHandAttackedHuman = attackedHuman;
      }
    }
  }
  return { state: next, rivals: minds, events, answers, plays };
}
function dueMind(state, rivals, now) {
  let best = null;
  let bestSeat = 0;
  for (const mind of rivals.minds) {
    const racer = racerById(state, mind.id);
    if (racer === null || racer.finished) continue;
    if (racer.currentFact < 0) continue;
    if (mind.nextAnswerAtMs > now) continue;
    if (best === null || mind.nextAnswerAtMs < best.nextAnswerAtMs) {
      best = mind;
      bestSeat = racer.seat;
      continue;
    }
    if (mind.nextAnswerAtMs === best.nextAnswerAtMs && racer.seat < bestSeat) {
      best = mind;
      bestSeat = racer.seat;
    }
  }
  return best;
}
function victimsOf(events, attackerId) {
  const ids = [];
  for (const event of events) {
    if (event.type === "hit" || event.type === "blocked") {
      if (event.fromId !== attackerId) continue;
      if (event.racerId === attackerId) continue;
      if (ids.indexOf(event.racerId) === -1) ids.push(event.racerId);
      continue;
    }
    if (event.type === "swap" && event.racerId === attackerId) {
      if (ids.indexOf(event.withId) === -1) ids.push(event.withId);
    }
  }
  return ids;
}
function nextRivalDeadline(state, rivals) {
  let soonest = -1;
  for (const mind of rivals.minds) {
    const racer = racerById(state, mind.id);
    if (racer === null || racer.finished) continue;
    const at = mind.nextAnswerAtMs < racer.stalledUntilMs ? racer.stalledUntilMs : mind.nextAnswerAtMs;
    if (soonest < 0 || at < soonest) soonest = at;
  }
  return soonest;
}

// src/engine/ghost.ts
function emptyTimeline() {
  return { samples: [] };
}
function cloneTimeline(timeline) {
  return {
    samples: timeline.samples.map((sample) => ({ atMs: sample.atMs, progress: sample.progress }))
  };
}
function cloneRecord(record) {
  return {
    preset: record.preset,
    timeMs: record.timeMs,
    correct: record.correct,
    attempted: record.attempted,
    timeline: cloneTimeline(record.timeline)
  };
}
var ANSWER_EVENTS = ["correct", "reveal", "pitCrew"];
function recordStep(timeline, state, events, racerId) {
  const next = cloneTimeline(timeline);
  let at = -1;
  for (const event of events) {
    if (event.racerId !== racerId) continue;
    if (ANSWER_EVENTS.indexOf(event.type) === -1) continue;
    at = event.at;
  }
  if (at < 0) return next;
  const racer = state.racers.find((entry) => entry.id === racerId);
  if (racer === void 0) return next;
  const progress = effectiveProgress(racer, state.questionsPerLap);
  const atMs = at - state.startedAtMs;
  const last = next.samples.length > 0 ? next.samples[next.samples.length - 1] : null;
  if (last !== null && last.atMs === atMs) {
    last.progress = progress;
    return next;
  }
  next.samples.push({ atMs: atMs < 0 ? 0 : atMs, progress });
  return next;
}
function timelineFromEvents(events, racerId, startedAtMs, questionsPerLap = QUESTIONS_PER_LAP) {
  const timeline = emptyTimeline();
  let lapsComplete = 0;
  let correctInLap = 0;
  let need = questionsPerLap;
  for (const event of events) {
    if (event.racerId !== racerId) continue;
    if (event.type === "hit") {
      need = event.questionsNeededThisLap;
      continue;
    }
    if (event.type === "lapComplete") {
      lapsComplete = event.lapsComplete;
      correctInLap = event.surplus;
      need = questionsPerLap;
      continue;
    }
    if (ANSWER_EVENTS.indexOf(event.type) === -1) continue;
    correctInLap += 1;
    const progress = lapsComplete * questionsPerLap + correctInLap - (need - questionsPerLap);
    const atMs = event.at - startedAtMs;
    timeline.samples.push({ atMs: atMs < 0 ? 0 : atMs, progress });
  }
  return timeline;
}
function ghostProgressAt(timeline, atMs) {
  const samples = timeline.samples;
  if (samples.length === 0) return 0;
  if (atMs <= samples[0].atMs) {
    const first = samples[0];
    if (first.atMs <= 0) return first.progress;
    const fraction2 = atMs <= 0 ? 0 : atMs / first.atMs;
    return first.progress * fraction2;
  }
  const last = samples[samples.length - 1];
  if (atMs >= last.atMs) return last.progress;
  let low = 0;
  let high = samples.length - 1;
  while (high - low > 1) {
    const middle = low + high >> 1;
    if (samples[middle].atMs <= atMs) low = middle;
    else high = middle;
  }
  const before = samples[low];
  const after = samples[high];
  const span = after.atMs - before.atMs;
  if (span <= 0) return after.progress;
  const fraction = (atMs - before.atMs) / span;
  return before.progress + (after.progress - before.progress) * fraction;
}
function ghostReachedAt(timeline, progress) {
  for (const sample of timeline.samples) if (sample.progress >= progress) return sample.atMs;
  return -1;
}
function ghostLead(timeline, atMs, progress) {
  return ghostProgressAt(timeline, atMs) - progress;
}
function isCleanMode(state) {
  return state.mode === "timeTrial" || state.mode === "ghost";
}
function isRecordEligible(state) {
  if (!isCleanMode(state)) return false;
  if (state.powerupsEnabled) return false;
  for (const racer of state.racers) if (racer.cardsUsed.length > 0) return false;
  const human = state.racers.find((racer) => racer.id === state.humanId);
  if (human === void 0) return false;
  return human.finished;
}
function recordFromRace(state, timeline) {
  if (!isRecordEligible(state)) return null;
  const human = state.racers.find((racer) => racer.id === state.humanId);
  if (human === void 0) return null;
  return {
    preset: state.preset,
    timeMs: human.finishTimeMs - state.startedAtMs,
    correct: human.correctCount,
    attempted: human.attemptCount,
    timeline: cloneTimeline(timeline)
  };
}
function beatsRecord(previous, candidate) {
  if (previous === null) return true;
  return candidate.timeMs < previous.timeMs;
}
function bestRecord(previous, candidate) {
  return beatsRecord(previous, candidate) ? cloneRecord(candidate) : cloneRecord(previous);
}
function updateRecord(previous, candidate) {
  const updated = beatsRecord(previous, candidate);
  return { record: updated ? cloneRecord(candidate) : cloneRecord(previous), updated };
}

// src/engine/save.ts
var SAVE_VERSION = 1;
var KART_BODIES = 6;
var PAINT_SWATCHES = 8;
var KART_NUMBER_MIN = 1;
var KART_NUMBER_MAX = 99;
function defaultSettings() {
  return {
    sound: true,
    reducedMotion: false,
    scanlines: false,
    kart: 1,
    paint: 1,
    number: 1,
    rivalLevel: "pro",
    streakThreshold: STREAK_THRESHOLD
  };
}
function emptySave() {
  return { version: SAVE_VERSION, settings: defaultSettings(), records: {}, facts: [] };
}
function cloneSettings(settings) {
  return {
    sound: settings.sound,
    reducedMotion: settings.reducedMotion,
    scanlines: settings.scanlines,
    kart: settings.kart,
    paint: settings.paint,
    number: settings.number,
    rivalLevel: settings.rivalLevel,
    streakThreshold: settings.streakThreshold
  };
}
function cloneSave(file) {
  const records = {};
  for (const key of recordKeys(file.records)) {
    const record = file.records[key];
    records[key] = {
      preset: record.preset,
      timeMs: record.timeMs,
      correct: record.correct,
      attempted: record.attempted,
      timeline: cloneTimeline(record.timeline)
    };
  }
  return {
    version: file.version,
    settings: cloneSettings(file.settings),
    records,
    facts: cloneFactHistory(file.facts)
  };
}
function recordKeys(records) {
  const keys = [];
  for (const key in records) {
    if (Object.prototype.hasOwnProperty.call(records, key)) keys.push(key);
  }
  keys.sort();
  return keys;
}
function recordKey(preset, tables) {
  if (preset !== "choose") return preset;
  const sorted = tables.slice().sort((left, right) => left - right);
  const unique = [];
  for (const table of sorted) if (unique.indexOf(table) === -1) unique.push(table);
  return "choose:" + unique.join("-");
}
function recordKeyOf(state) {
  return recordKey(state.preset, state.tables);
}
var FIXED_PRESETS = ["2-5", "2-10", "1-12"];
var CHOOSE_KEY = /^choose:(?:[1-9]|1[0-2])(?:-(?:[1-9]|1[0-2]))*$/;
function isRecordKey(key) {
  if (FIXED_PRESETS.indexOf(key) !== -1) return true;
  if (!CHOOSE_KEY.test(key)) return false;
  let previous = 0;
  for (const part of key.slice("choose:".length).split("-")) {
    const table = Number(part);
    if (!(table > previous)) return false;
    previous = table;
  }
  return true;
}
var FORBIDDEN_KEY_WORDS = [
  "date",
  "dates",
  "day",
  "days",
  "week",
  "weeks",
  "month",
  "months",
  "year",
  "years",
  "calendar",
  "timestamp",
  "epoch",
  "iso",
  "utc",
  "clock",
  "created",
  "updated",
  "modified",
  "played",
  "session",
  "sessions",
  "streakhistory",
  "history",
  "birthday",
  "today",
  "yesterday",
  "since",
  "when",
  "seen",
  "visit",
  "visits"
];
function keyWords(key) {
  const spaced = key.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/[_\-.:]+/g, " ");
  const words = [];
  for (const word of spaced.split(" ")) if (word.length > 0) words.push(word.toLowerCase());
  return words;
}
function dateLikeKeys(value, path = "") {
  const found = [];
  if (value === null || typeof value !== "object") return found;
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index++) {
      for (const hit of dateLikeKeys(value[index], path + "[" + index + "]")) found.push(hit);
    }
    return found;
  }
  const record = value;
  for (const key in record) {
    if (!Object.prototype.hasOwnProperty.call(record, key)) continue;
    const here = path === "" ? key : path + "." + key;
    for (const word of keyWords(key)) {
      if (FORBIDDEN_KEY_WORDS.indexOf(word) !== -1) {
        found.push(here);
        break;
      }
    }
    for (const hit of dateLikeKeys(record[key], here)) found.push(hit);
  }
  return found;
}
var SETTINGS_KEYS = [
  "sound",
  "reducedMotion",
  "scanlines",
  "kart",
  "paint",
  "number",
  "rivalLevel",
  "streakThreshold"
];
var FILE_KEYS = ["version", "settings", "records", "facts"];
var RECORD_KEYS = ["preset", "timeMs", "correct", "attempted", "timeline"];
var TIMELINE_KEYS = ["samples"];
var SAMPLE_KEYS = ["atMs", "progress"];
var FACT_KEYS = ["fact", "attempts", "correct", "lastThree"];
var OUTCOMES = ["correct", "wrong", "reveal", "pitCrew"];
function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function isWholeNumber(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value;
}
function unknownKeys(value, allowed, path, issues) {
  for (const key in value) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
    if (allowed.indexOf(key) === -1)
      issues.push({ path: path === "" ? key : path + "." + key, problem: "unknown key" });
  }
  for (const key of allowed) {
    if (!Object.prototype.hasOwnProperty.call(value, key))
      issues.push({ path: path === "" ? key : path + "." + key, problem: "missing key" });
  }
}
function checkRange(value, low, high, path, issues) {
  if (!isWholeNumber(value)) {
    issues.push({ path, problem: "expected a whole number" });
    return;
  }
  if (value < low || value > high)
    issues.push({ path, problem: "expected " + low + ".." + high + ", got " + value });
}
function checkBoolean(value, path, issues) {
  if (typeof value !== "boolean") issues.push({ path, problem: "expected a boolean" });
}
function validateSettings(value, issues) {
  if (!isPlainObject(value)) {
    issues.push({ path: "settings", problem: "expected an object" });
    return;
  }
  unknownKeys(value, SETTINGS_KEYS, "settings", issues);
  checkBoolean(value.sound, "settings.sound", issues);
  checkBoolean(value.reducedMotion, "settings.reducedMotion", issues);
  checkBoolean(value.scanlines, "settings.scanlines", issues);
  checkRange(value.kart, 1, KART_BODIES, "settings.kart", issues);
  checkRange(value.paint, 1, PAINT_SWATCHES, "settings.paint", issues);
  checkRange(value.number, KART_NUMBER_MIN, KART_NUMBER_MAX, "settings.number", issues);
  if (typeof value.rivalLevel !== "string" || RIVAL_LEVEL_ORDER.indexOf(value.rivalLevel) === -1)
    issues.push({ path: "settings.rivalLevel", problem: "expected rookie, pro or champion" });
  checkRange(value.streakThreshold, 1, 144, "settings.streakThreshold", issues);
}
function validateTimeline(value, path, issues) {
  if (!isPlainObject(value)) {
    issues.push({ path, problem: "expected an object" });
    return;
  }
  unknownKeys(value, TIMELINE_KEYS, path, issues);
  const samples = value.samples;
  if (!Array.isArray(samples)) {
    issues.push({ path: path + ".samples", problem: "expected an array" });
    return;
  }
  let previous = -1;
  for (let index = 0; index < samples.length; index++) {
    const at = path + ".samples[" + index + "]";
    const sample = samples[index];
    if (!isPlainObject(sample)) {
      issues.push({ path: at, problem: "expected an object" });
      continue;
    }
    unknownKeys(sample, SAMPLE_KEYS, at, issues);
    checkRange(sample.atMs, 0, 864e5, at + ".atMs", issues);
    checkRange(sample.progress, 0, 1e5, at + ".progress", issues);
    if (isWholeNumber(sample.atMs)) {
      if (sample.atMs < previous)
        issues.push({ path: at + ".atMs", problem: "timeline runs backwards" });
      previous = sample.atMs;
    }
  }
}
function validateRecords(value, issues) {
  if (!isPlainObject(value)) {
    issues.push({ path: "records", problem: "expected an object" });
    return;
  }
  for (const key in value) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
    const at = "records." + key;
    if (!isRecordKey(key)) {
      issues.push({ path: at, problem: "unknown key" });
      continue;
    }
    const record = value[key];
    if (!isPlainObject(record)) {
      issues.push({ path: at, problem: "expected an object" });
      continue;
    }
    unknownKeys(record, RECORD_KEYS, at, issues);
    const preset = record.preset;
    const presetOk = typeof preset === "string" && (Object.prototype.hasOwnProperty.call(PRESET_TABLES, preset) || preset === "choose");
    if (!presetOk) issues.push({ path: at + ".preset", problem: "not a preset" });
    else if (recordKeyMatchesPreset(key, preset) === false)
      issues.push({ path: at + ".preset", problem: "does not match the key it is filed under" });
    checkRange(record.timeMs, 0, 864e5, at + ".timeMs", issues);
    checkRange(record.correct, 0, 1e5, at + ".correct", issues);
    checkRange(record.attempted, 0, 1e5, at + ".attempted", issues);
    if (isWholeNumber(record.correct) && isWholeNumber(record.attempted) && record.correct > record.attempted)
      issues.push({ path: at + ".correct", problem: "more correct than attempted" });
    validateTimeline(record.timeline, at + ".timeline", issues);
  }
}
function recordKeyMatchesPreset(key, preset) {
  if (preset === "choose") return key.indexOf("choose:") === 0;
  return key === preset;
}
function validateFacts(value, issues) {
  if (!Array.isArray(value)) {
    issues.push({ path: "facts", problem: "expected an array" });
    return;
  }
  let previous = -1;
  for (let index = 0; index < value.length; index++) {
    const at = "facts[" + index + "]";
    const record = value[index];
    if (!isPlainObject(record)) {
      issues.push({ path: at, problem: "expected an object" });
      continue;
    }
    unknownKeys(record, FACT_KEYS, at, issues);
    const fact = record.fact;
    if (!isWholeNumber(fact)) issues.push({ path: at + ".fact", problem: "expected a whole number" });
    else {
      const left = Math.floor(fact / 100);
      const right = fact % 100;
      if (left < TABLE_MIN || left > TABLE_MAX || right < 1 || right > 12)
        issues.push({ path: at + ".fact", problem: "not a fact in 1x1..12x12" });
      if (fact <= previous) issues.push({ path: at + ".fact", problem: "facts must ascend" });
      previous = fact;
    }
    checkRange(record.attempts, 0, 1e5, at + ".attempts", issues);
    checkRange(record.correct, 0, 1e5, at + ".correct", issues);
    if (isWholeNumber(record.attempts) && isWholeNumber(record.correct) && record.correct > record.attempts)
      issues.push({ path: at + ".correct", problem: "more correct than attempts" });
    const lastThree = record.lastThree;
    if (!Array.isArray(lastThree)) {
      issues.push({ path: at + ".lastThree", problem: "expected an array" });
      continue;
    }
    if (lastThree.length > FACT_HISTORY_WINDOW)
      issues.push({ path: at + ".lastThree", problem: "more than " + FACT_HISTORY_WINDOW + " outcomes" });
    else if (isWholeNumber(record.attempts)) {
      const expected = record.attempts < FACT_HISTORY_WINDOW ? record.attempts : FACT_HISTORY_WINDOW;
      if (lastThree.length !== expected)
        issues.push({
          path: at + ".lastThree",
          problem: "expected " + expected + " outcomes for " + record.attempts + " attempts, got " + lastThree.length
        });
    }
    for (let slot = 0; slot < lastThree.length; slot++) {
      if (typeof lastThree[slot] !== "string" || OUTCOMES.indexOf(lastThree[slot]) === -1)
        issues.push({ path: at + ".lastThree[" + slot + "]", problem: "not an outcome" });
    }
  }
}
function validateSave(value) {
  const issues = [];
  if (!isPlainObject(value)) {
    return { ok: false, issues: [{ path: "", problem: "expected an object" }], file: null };
  }
  unknownKeys(value, FILE_KEYS, "", issues);
  if (value.version !== SAVE_VERSION)
    issues.push({
      path: "version",
      problem: "expected " + SAVE_VERSION + ", got " + JSON.stringify(value.version)
    });
  validateSettings(value.settings, issues);
  validateRecords(value.records, issues);
  validateFacts(value.facts, issues);
  for (const key of dateLikeKeys(value)) issues.push({ path: key, problem: "date-like key" });
  if (issues.length > 0) return { ok: false, issues, file: null };
  return { ok: true, issues, file: cloneSave(value) };
}
var MIGRATIONS = {};
function migrateSave(value) {
  if (!isPlainObject(value))
    return { raw: null, from: 0, to: SAVE_VERSION, steps: [], problem: "not an object" };
  const version = value.version;
  if (!isWholeNumber(version) || version < 1)
    return { raw: null, from: 0, to: SAVE_VERSION, steps: [], problem: "no usable version" };
  if (version > SAVE_VERSION)
    return {
      raw: null,
      from: version,
      to: SAVE_VERSION,
      steps: [],
      problem: "written by a newer build (version " + version + ")"
    };
  let raw = __spreadValues({}, value);
  const steps = [];
  let at = version;
  while (at < SAVE_VERSION) {
    const migration = MIGRATIONS[String(at)];
    if (migration === void 0)
      return { raw: null, from: version, to: SAVE_VERSION, steps, problem: "no migration from version " + at };
    raw = migration(raw);
    steps.push(at);
    at += 1;
    raw.version = at;
  }
  return { raw, from: version, to: SAVE_VERSION, steps, problem: "" };
}
var LEGACY_GARAGE_KEYS = [
  "kartBody",
  "kartPaint",
  "kartNumber",
  "rivalLevel",
  "raceMode",
  "mathSet",
  "sound",
  "reducedMotion",
  "scanlines"
];
function migrateLegacyGarageSettings(value) {
  if (!isPlainObject(value)) return { settings: null, problem: "not an object" };
  const settings = value.settings;
  if (!isPlainObject(settings)) return { settings: null, problem: "no settings object" };
  if (!Object.prototype.hasOwnProperty.call(settings, "kartBody"))
    return { settings: null, problem: "not the garage's own settings shape" };
  for (const key in settings) {
    if (!Object.prototype.hasOwnProperty.call(settings, key)) continue;
    if (LEGACY_GARAGE_KEYS.indexOf(key) === -1)
      return { settings: null, problem: "unknown legacy setting: " + key };
  }
  const records = value.records;
  if (records !== void 0 && (!isPlainObject(records) || Object.keys(records).length > 0))
    return { settings: null, problem: "the legacy shape never held a record, and this one does" };
  const facts = value.facts;
  const factsEmpty = facts === void 0 || Array.isArray(facts) && facts.length === 0 || isPlainObject(facts) && Object.keys(facts).length === 0;
  if (!factsEmpty)
    return { settings: null, problem: "the legacy shape never held a fact history, and this one does" };
  const level = RIVAL_LEVEL_ORDER[clampWhole(settings.rivalLevel, 0, RIVAL_LEVEL_ORDER.length - 1, 1)];
  return {
    settings: {
      sound: settings.sound !== false,
      reducedMotion: settings.reducedMotion === true,
      scanlines: settings.scanlines === true,
      kart: clampWhole(toNumber(settings.kartBody) + 1, 1, KART_BODIES, 1),
      paint: clampWhole(toNumber(settings.kartPaint) + 1, 1, PAINT_SWATCHES, 1),
      number: clampWhole(settings.kartNumber, KART_NUMBER_MIN, KART_NUMBER_MAX, 1),
      rivalLevel: level,
      streakThreshold: STREAK_THRESHOLD
    },
    problem: ""
  };
}
function toNumber(value) {
  return typeof value === "number" && isFinite(value) ? value : NaN;
}
function clampWhole(value, low, high, fallback) {
  const number = Math.round(toNumber(value));
  if (!isFinite(number)) return fallback;
  return number < low ? low : number > high ? high : number;
}
function resetSettings(file) {
  const next = cloneSave(file);
  next.settings = defaultSettings();
  return next;
}
function resetRecords(file) {
  const next = cloneSave(file);
  next.records = {};
  return next;
}
function resetFacts(file) {
  const next = cloneSave(file);
  next.facts = [];
  return next;
}
function serialiseSave(file) {
  const settings = file.settings;
  const ordered = {
    version: file.version,
    settings: {
      sound: settings.sound,
      reducedMotion: settings.reducedMotion,
      scanlines: settings.scanlines,
      kart: settings.kart,
      paint: settings.paint,
      number: settings.number,
      rivalLevel: settings.rivalLevel,
      streakThreshold: settings.streakThreshold
    },
    records: {},
    facts: file.facts.map((record) => ({
      fact: record.fact,
      attempts: record.attempts,
      correct: record.correct,
      lastThree: record.lastThree.slice()
    }))
  };
  for (const key of recordKeys(file.records)) {
    const record = file.records[key];
    ordered.records[key] = {
      preset: record.preset,
      timeMs: record.timeMs,
      correct: record.correct,
      attempted: record.attempted,
      timeline: {
        samples: record.timeline.samples.map((sample) => ({
          atMs: sample.atMs,
          progress: sample.progress
        }))
      }
    };
  }
  return JSON.stringify(ordered, null, 2) + "\n";
}
function parseSave(text) {
  let value;
  try {
    value = JSON.parse(text);
  } catch (error) {
    return {
      ok: false,
      file: null,
      issues: [{ path: "", problem: "not JSON: " + String(error) }],
      migratedFrom: 0
    };
  }
  const migrated = migrateSave(value);
  if (migrated.raw === null)
    return {
      ok: false,
      file: null,
      issues: [{ path: "version", problem: migrated.problem }],
      migratedFrom: migrated.from
    };
  const validated = validateSave(migrated.raw);
  return {
    ok: validated.ok,
    file: validated.file,
    issues: validated.issues,
    migratedFrom: migrated.from
  };
}
function factHistoryForRace(file) {
  return cloneFactHistory(file.facts);
}
function factHistoryDelta(seededWith, history) {
  const baseline = seededWith != null ? seededWith : [];
  const delta = [];
  for (const record of history) {
    const before = factRecordOf(baseline, record.fact);
    const attempts = record.attempts - (before === null ? 0 : before.attempts);
    const correct = record.correct - (before === null ? 0 : before.correct);
    if (attempts <= 0) continue;
    const window = record.lastThree;
    const kept = attempts >= window.length ? 0 : window.length - attempts;
    delta.push({
      fact: record.fact,
      attempts,
      correct: correct > 0 ? correct : 0,
      lastThree: window.slice(kept)
    });
  }
  return delta;
}
function baselineIsFile(file, seededWith) {
  const baseline = seededWith != null ? seededWith : [];
  if (baseline.length !== file.facts.length) return false;
  for (let index = 0; index < baseline.length; index++) {
    const left = baseline[index];
    const right = file.facts[index];
    if (left.fact !== right.fact) return false;
    if (left.attempts !== right.attempts) return false;
    if (left.correct !== right.correct) return false;
    if (left.lastThree.length !== right.lastThree.length) return false;
    for (let slot = 0; slot < left.lastThree.length; slot++)
      if (left.lastThree[slot] !== right.lastThree[slot]) return false;
  }
  return true;
}
function factHistoryAlreadyHolds(file, delta) {
  if (delta.length === 0) return false;
  for (const record of delta) {
    const saved = factRecordOf(file.facts, record.fact);
    if (saved === null) return false;
    if (saved.attempts < record.attempts) return false;
    if (saved.correct < record.correct) return false;
    const tail = saved.lastThree.slice(saved.lastThree.length - record.lastThree.length);
    if (tail.length !== record.lastThree.length) return false;
    for (let slot = 0; slot < tail.length; slot++)
      if (tail[slot] !== record.lastThree[slot]) return false;
  }
  return true;
}
function factHistoryMergeIssues(file, state, seededWith, history) {
  const human = state.racers.find((racer) => racer.id === state.humanId);
  if (human === void 0)
    return [{ path: "facts", problem: "the race has no human racer to account for" }];
  const delta = factHistoryDelta(seededWith, history);
  if (!baselineIsFile(file, seededWith) && factHistoryAlreadyHolds(file, delta))
    return [{
      path: "facts",
      problem: "this race is already in the file -- every fact it adds is there with the same outcomes -- and no baseline says it was seeded from this file"
    }];
  let added = 0;
  for (const record of delta) added += record.attempts;
  if (added !== human.attemptCount)
    return [{
      path: "facts",
      problem: "the declared baseline does not account for this race's answers"
    }];
  return [];
}
function factHistoryAccounts(file, state, seededWith, history) {
  return factHistoryMergeIssues(file, state, seededWith, history).length === 0;
}
function withFactHistory(file, history) {
  const next = cloneSave(file);
  next.facts = cloneFactHistory(history);
  return next;
}
function mergeFactHistory(base, incoming) {
  const merged = cloneFactHistory(base);
  for (const record of incoming) {
    let at = -1;
    for (let index = 0; index < merged.length; index++) {
      if (merged[index].fact === record.fact) {
        at = index;
        break;
      }
    }
    if (at === -1) {
      let insert = merged.length;
      for (let index = 0; index < merged.length; index++) {
        if (merged[index].fact > record.fact) {
          insert = index;
          break;
        }
      }
      merged.splice(insert, 0, {
        fact: record.fact,
        attempts: record.attempts,
        correct: record.correct,
        lastThree: record.lastThree.slice()
      });
      continue;
    }
    const existing = merged[at];
    existing.attempts += record.attempts;
    existing.correct += record.correct;
    const combined = existing.lastThree.concat(record.lastThree);
    existing.lastThree = combined.slice(
      combined.length > FACT_HISTORY_WINDOW ? combined.length - FACT_HISTORY_WINDOW : 0
    );
  }
  return merged;
}
function recordEntryIssues(key, entry) {
  if (!isRecordKey(key)) return [{ path: "records." + key, problem: "not a record key" }];
  const probe = emptySave();
  probe.records[key] = entry;
  return validateSave(probe).issues;
}
function factHistoryIssues(facts) {
  const probe = emptySave();
  probe.facts = facts;
  return validateSave(probe).issues;
}
function commitRace(file, state, history, candidate, seededWith) {
  const issues = [];
  const key = recordKeyOf(state);
  const mergeIssues = factHistoryMergeIssues(file, state, seededWith, history);
  for (const issue of mergeIssues) issues.push(issue);
  let next = cloneSave(file);
  let factsUpdated = false;
  if (mergeIssues.length === 0) {
    const merged = mergeFactHistory(file.facts, factHistoryDelta(seededWith, history));
    const factIssues = factHistoryIssues(merged);
    for (const issue of factIssues) issues.push(issue);
    if (factIssues.length === 0) {
      next = withFactHistory(file, merged);
      factsUpdated = true;
    }
  }
  const standing = Object.prototype.hasOwnProperty.call(next.records, key) ? next.records[key] : null;
  if (candidate === null) return { file: next, factsUpdated, recordUpdated: false, record: standing, issues };
  if (!isRecordEligible(state)) {
    issues.push({ path: "records." + key, problem: "the race is not one that sets records" });
    return { file: next, factsUpdated, recordUpdated: false, record: standing, issues };
  }
  const badEntry = recordEntryIssues(key, candidate);
  if (badEntry.length > 0) {
    for (const issue of badEntry) issues.push(issue);
    return { file: next, factsUpdated, recordUpdated: false, record: standing, issues };
  }
  if (!beatsRecord(standing, candidate))
    return { file: next, factsUpdated, recordUpdated: false, record: standing, issues };
  next.records[key] = cloneRecord(candidate);
  return { file: next, factsUpdated, recordUpdated: true, record: next.records[key], issues };
}

// src/engine/index.ts
var repositoryBootstrap = Object.freeze({
  pluginId: "io.github.dmcchesney.turbo-tables-solo",
  schemaVersion: 1
});
export {
  ATTACK_CARDS,
  BELLRINGER_STREAK_THRESHOLD,
  BOOST_CARDS,
  CALLOUT_MS,
  CARDS,
  CARD_SCHEDULE,
  CHARGE_GLOW_FROM,
  CHARGE_SEGMENTS,
  EVENT_ORDER,
  FACT_HISTORY_WINDOW,
  FORBIDDEN_KEY_WORDS,
  HALF_LAP,
  HAND_SIZE,
  KART_BODIES,
  KART_NUMBER_MAX,
  KART_NUMBER_MIN,
  MIGRATIONS,
  NEXT_FACT_MS,
  NICE_RUN_CHANCE,
  PAINT_SWATCHES,
  PODIUM_SIZE,
  POLICY_INTERVAL,
  PRESET_TABLES,
  QUESTIONS_NEEDED_FLOOR,
  QUESTIONS_PER_LAP,
  REVEAL_MS,
  RIVAL_FLOOR_MS,
  RIVAL_LEVELS,
  RIVAL_LEVEL_ORDER,
  RIVAL_ORDER,
  RIVAL_PACE_WINDOW,
  RIVAL_PROFILES,
  RUBBER_BAND_LIMIT,
  SAVE_VERSION,
  SETTLE_MS,
  SIGNAL_CATALOG,
  SPUTTER_MS,
  STREAK_THRESHOLD,
  TABLE_MAX,
  TABLE_MIN,
  TABLE_NAMES,
  accuracyPercent,
  aoeVictims,
  applyFloor,
  baselineIsFile,
  beatsRecord,
  bestRecord,
  cardByBellringerName,
  chargeReady,
  chargeSegments,
  childPaceMs,
  choosePlay,
  chooseTarget,
  cloneFactHistory,
  cloneFactRecord,
  cloneMind,
  cloneRacer,
  cloneRecord,
  cloneRivals,
  cloneRng,
  cloneSave,
  cloneSettings,
  cloneState,
  cloneTimeline,
  commitRace,
  compareByFactHistory,
  compareRacers,
  createRace,
  createRivals,
  createRng,
  currentTable,
  currentTableName,
  dateLikeKeys,
  dealHand,
  defaultSettings,
  drawThinkTime,
  drawThinkTimeMs,
  drawWrongAnswer,
  drawsCorrect,
  effectiveProgress,
  emptySave,
  emptyTimeline,
  extraQuestions,
  factAnswer,
  factHistoryAccounts,
  factHistoryAlreadyHolds,
  factHistoryDelta,
  factHistoryEntry,
  factHistoryForRace,
  factHistoryIssues,
  factHistoryMergeIssues,
  factHistoryOf,
  factLabel,
  factLeft,
  factRecordOf,
  factRight,
  forkRng,
  ghostLead,
  ghostProgressAt,
  ghostReachedAt,
  hashLabel,
  headlineForPlace,
  humanRacer,
  isAttackCard,
  isCard,
  isCleanMode,
  isEventOrdered,
  isRecordEligible,
  isRecordKey,
  isStalled,
  lapDeck,
  lastPlaceIds,
  mayAttack,
  mergeFactHistory,
  mergeSignals,
  migrateLegacyGarageSettings,
  migrateSave,
  mindOf,
  newFactRecord,
  nextFloat,
  nextInt,
  nextRivalDeadline,
  nextStreak,
  nextUint32,
  orderByFactHistory,
  ordinal,
  packFact,
  parseSave,
  placeOf,
  positionOrder,
  positionTriple,
  progressFraction,
  questionCountForPreset,
  raceLength,
  raceOrder,
  racerById,
  racerProgress,
  rankRacers,
  recentSuccesses,
  recordEntryIssues,
  recordFactOutcome,
  recordFromRace,
  recordKey,
  recordKeyOf,
  recordKeys,
  recordStep,
  replay,
  repositoryBootstrap,
  resetFacts,
  resetRecords,
  resetSettings,
  resultsBoard,
  rivalObserve,
  rivalStep,
  rivalTuning,
  rubberBandScale,
  serialiseSave,
  shouldDealHand,
  shuffle,
  standings,
  step,
  swapPositions,
  tableFacts,
  tableName,
  tablesForPreset,
  timelineFromEvents,
  updateRecord,
  validateSave,
  victimsOf,
  withFactHistory
};
