/**
 * Streaks and when a hand is dealt.
 *
 * The counter is the bellringer's `CorrectAnswerStreak`; only the threshold
 * changes. Design, Decisions settled 2026-09-02: "Streak threshold - 12. One
 * clean lap charges a power-up. The bellringer's 15 stays in the test vectors as
 * a parity case."
 */

/** The design's threshold: one clean lap. */
export const STREAK_THRESHOLD = 12;

/** The bellringer's `powerupStreakThreshold`, kept for the parity vector. */
export const BELLRINGER_STREAK_THRESHOLD = 15;

/** The charge bar: twelve segments, glowing from nine. */
export const CHARGE_SEGMENTS = 12;
export const CHARGE_GLOW_FROM = 9;

/**
 * How an answer touches the streak.
 *
 * - a genuine correct answer adds one,
 * - a wrong answer resets it to zero,
 * - a pit-crew answer and a revealed answer leave it exactly as it was, which is
 *   the bellringer's `attemptType == "forced"` branch: it skips the increment
 *   and never reaches the reset.
 */
export type StreakEffect = "build" | "reset" | "hold";

export function nextStreak(streak: number, effect: StreakEffect): number {
  if (effect === "reset") return 0;
  if (effect === "build") return streak + 1;
  return streak;
}

/**
 * Deal when the streak has reached the threshold and no hand is held.
 *
 * The bellringer checks this after every answer that was not wrong, including a
 * forced one, and does nothing while an inventory is held. That is the quirk the
 * design keeps: "If a hand is already held, the streak keeps climbing and the
 * next correct answer after the hand is spent deals a new one."
 */
export function shouldDealHand(streak: number, threshold: number, handSize: number): boolean {
  return streak >= threshold && handSize === 0;
}

/** Segments lit on the charge bar, clamped to the bar's length. */
export function chargeSegments(streak: number, threshold: number): number {
  const ratio = threshold <= 0 ? 1 : streak / threshold;
  return Math.min(CHARGE_SEGMENTS, Math.floor(ratio * CHARGE_SEGMENTS));
}

export function chargeReady(streak: number, threshold: number): boolean {
  return streak >= threshold;
}
