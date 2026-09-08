/**
 * The eight cards.
 *
 * Effects, deltas, scopes and the dealing schedule are the bellringer runtime's,
 * transcribed from internal/bellringerruntime/powerups.go. Only the names and
 * the stall durations belong to the garage. Nothing here is invented: the deltas
 * come from `powerupDefinitions`, the schedule order from
 * `canonicalPowerupSchedule`, and the dealing loop from `awardPowerupInventory`.
 */

export type Card =
  | "nitro"
  | "oilSlick"
  | "wrench"
  | "pothole"
  | "rollCage"
  | "pileUp"
  | "turbo"
  | "towHook";

export type CardScope = "self" | "aoe" | "targeted";

export type CardTier = "common" | "uncommon" | "rare" | "legendary";

export interface CardDefinition {
  /** Who the card reaches. `aoe` is every other racer; `targeted` needs one. */
  scope: CardScope;
  /** Change to the target's `questionsNeededThisLap`. Zero means no delta. */
  questionDelta: number;
  tier: CardTier;
  /** The bellringer's name for the same effect, kept so parity is checkable. */
  bellringerName: string;
  /** Display name. */
  label: string;
  /**
   * How long an unblocked landing locks the victim's field, from the design's
   * "Stalled" rule: three seconds for a Wrench, two for a Pothole or a Pile-Up,
   * and none at all for Oil Slick, Tow Hook, self boosts or blocked hits.
   */
  stallMs: number;
}

/**
 * The fixed schedule. Go's `canonicalPowerupSchedule` is
 * FuelBoost, GravityWell, Lightning, BlackHole, Shield, Supernova, Turbo,
 * Wormhole; the design renames those to Nitro, Oil Slick, Wrench, Pothole,
 * Roll Cage, Pile-Up, Turbo, Tow Hook and keeps the order.
 */
export const CARD_SCHEDULE: readonly Card[] = [
  "nitro",
  "oilSlick",
  "wrench",
  "pothole",
  "rollCage",
  "pileUp",
  "turbo",
  "towHook",
];

export const CARDS: Readonly<Record<Card, CardDefinition>> = {
  nitro: {
    scope: "self",
    questionDelta: -4,
    tier: "common",
    bellringerName: "FuelBoost",
    label: "Nitro",
    stallMs: 0,
  },
  oilSlick: {
    scope: "aoe",
    questionDelta: 3,
    tier: "common",
    bellringerName: "GravityWell",
    label: "Oil Slick",
    stallMs: 0,
  },
  wrench: {
    scope: "targeted",
    questionDelta: 5,
    tier: "uncommon",
    bellringerName: "Lightning",
    label: "Wrench",
    stallMs: 3000,
  },
  pothole: {
    scope: "targeted",
    questionDelta: 8,
    tier: "rare",
    bellringerName: "BlackHole",
    label: "Pothole",
    stallMs: 2000,
  },
  rollCage: {
    scope: "self",
    questionDelta: 0,
    tier: "uncommon",
    bellringerName: "Shield",
    label: "Roll Cage",
    stallMs: 0,
  },
  pileUp: {
    scope: "targeted",
    questionDelta: 15,
    tier: "legendary",
    bellringerName: "Supernova",
    label: "Pile-Up",
    stallMs: 2000,
  },
  turbo: {
    scope: "self",
    questionDelta: -10,
    tier: "rare",
    bellringerName: "Turbo",
    label: "Turbo",
    stallMs: 0,
  },
  towHook: {
    scope: "targeted",
    questionDelta: 0,
    tier: "legendary",
    bellringerName: "Wormhole",
    label: "Tow Hook",
    stallMs: 0,
  },
};

export const HAND_SIZE = 3;

/** The floor on `questionsNeededThisLap`. Go: `max(1, need + delta)`. */
export const QUESTIONS_NEEDED_FLOOR = 1;

export function isCard(value: string): value is Card {
  return Object.prototype.hasOwnProperty.call(CARDS, value);
}

export function cardByBellringerName(name: string): Card | null {
  for (const card of CARD_SCHEDULE) {
    if (CARDS[card].bellringerName === name) return card;
  }
  return null;
}

/**
 * Deal one hand from the shared round-robin cursor.
 *
 * Transcribed from `awardPowerupInventory`: take the card under the cursor,
 * advance the cursor whether or not the card was kept, and stop at three cards
 * or when the schedule has been exhausted. The duplicate check is why a
 * single-card schedule yields a hand of one and still moves the cursor.
 *
 * "Exhausted" is counted in cards scanned, not in cards kept. Using the hand
 * size as the proxy for exhaustion -- `hand.length < schedule.length` -- is only
 * equivalent while the schedule holds no duplicates: `["nitro","nitro","wrench"]`
 * caps the hand at two while the condition keeps demanding a third, and the loop
 * spins forever. `RaceConfig.schedule` is public and unvalidated and the engine
 * runs on the QML main thread, so that spin is a silently frozen plugin. Every
 * schedule in this repository is duplicate-free, and on a duplicate-free
 * schedule scanning stops on exactly the same iteration as the old condition, so
 * this moves no vector.
 */
export function dealHand(
  schedule: readonly Card[],
  cursor: number,
): { hand: Card[]; cursor: number } {
  const hand: Card[] = [];
  let next = cursor;
  let scanned = 0;
  while (hand.length < HAND_SIZE && scanned < schedule.length) {
    const candidate = schedule[((next % schedule.length) + schedule.length) % schedule.length]!;
    next += 1;
    scanned += 1;
    if (hand.indexOf(candidate) === -1) hand.push(candidate);
  }
  return { hand, cursor: next };
}

/** The floor rule, on its own so a test can name it. */
export function applyFloor(questionsNeeded: number, delta: number): number {
  return Math.max(QUESTIONS_NEEDED_FLOOR, questionsNeeded + delta);
}
