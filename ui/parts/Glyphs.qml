pragma Singleton
import QtQuick

// The garage's icon set, drawn as pixel grids and painted by PixelIcon.
// "." is empty; every other character is a colour slot the caller supplies.
// Most grids use a single "#". The flag uses "A" and "B" for the two squares
// of the check.
//
// Placeholder art. Hand-drawn at icon scale so the screens can be judged on
// composition now; real art replaces the grids without touching a caller.
QtObject {
  // ------------------------------------------------------- policy rail
  readonly property var lock: [
    "............",
    "....####....",
    "...#....#...",
    "...#....#...",
    "...#....#...",
    ".##########.",
    ".##########.",
    ".####..####.",
    ".###....###.",
    ".####..####.",
    ".##########.",
    "............"]

  readonly property var broadcast: [
    "............",
    ".#........#.",
    "#..#....#..#",
    "#.#......#.#",
    "#.#..##..#.#",
    "#.#.####.#.#",
    "#.#..##..#.#",
    "#.#......#.#",
    "#..#....#..#",
    ".#........#.",
    ".....##.....",
    "............"]

  readonly property var monitor: [
    "............",
    ".##########.",
    ".#........#.",
    ".#..####..#.",
    ".#..####..#.",
    ".#........#.",
    ".##########.",
    "....####....",
    "....####....",
    "..########..",
    "..########..",
    "............"]

  // ------------------------------------------------------- settings rows
  // The checkered flag. Every square touches its neighbours: the previous
  // grid left gaps as wide as the squares and read as confetti rather than
  // as a flag. "A" is the solid square and "B" is the hole the caller leaves
  // open, which is what makes the check read at any size.
  readonly property var flag: [
    "##............",
    "##AABBAABBAA..",
    "##AABBAABBAA..",
    "##BBAABBAABB..",
    "##BBAABBAABB..",
    "##AABBAABBAA..",
    "##AABBAABBAA..",
    "##BBAABBAA....",
    "##BBAA........",
    "##............",
    "##............",
    "##............",
    "###...........",
    "####.........."]

  readonly property var clock: [
    "....####....",
    "..##....##..",
    ".#...#....#.",
    "#....#.....#",
    "#....#.....#",
    "#....#####.#",
    "#..........#",
    "#..........#",
    ".#........#.",
    "..##....##..",
    "....####....",
    "............"]

  // A calculator, not a multiplication sign. A bare x in front of a settings
  // row reads as close or delete, which is the last thing it should say to a
  // child about their math set.
  readonly property var times: [
    ".##########.",
    ".#........#.",
    ".#.######.#.",
    ".#.######.#.",
    ".#........#.",
    ".#.##.##.##.",
    ".#.##.##.##.",
    ".#........#.",
    ".#.##.##.##.",
    ".#.##.##.##.",
    ".##########.",
    "............"]

  // A steering wheel with a hub and three spokes, for the rivals row.
  readonly property var wheel: [
    "...######...",
    ".##......##.",
    ".#........#.",
    "#..######..#",
    "#.##....##.#",
    "#.#..##..#.#",
    "#.#.####.#.#",
    "#..#.##.#..#",
    ".#..####..#.",
    ".##..##..##.",
    "...######...",
    "............"]

  readonly property var trophy: [
    "............",
    ".##########.",
    "###......###",
    ".#.######.#.",
    ".#.######.#.",
    ".##.####.##.",
    "...######...",
    "....####....",
    "....####....",
    "..########..",
    ".##########.",
    "............"]

  // ------------------------------------------------------- signal catalog
  // Thumbs up: a raised thumb with a gap down its middle, a fist ruled into
  // three fingers, and a cuff at the wrist. The old grid was one blob with a
  // nub on it and read as a mitten.
  readonly property var thumbUp: [
    "..####........",
    ".######.......",
    ".######.......",
    ".######.......",
    ".######.......",
    ".############.",
    ".############.",
    ".#oooooooooo#.",
    ".############.",
    ".#oooooooooo#.",
    ".############.",
    "..##########..",
    "..oooooooooo..",
    "..##########.."]

  // Rematch: two curved arrows closing a loop, each ending in a solid
  // triangular head -- one pointing down on the right, one pointing up on the
  // left. The old grid was a broken ring of dots with no head at either end
  // and read as a loading spinner.
  readonly property var rematch: [
    ".....####.....",
    "...##....##...",
    "..#........#..",
    ".#..........#.",
    ".#.......#####",
    "..........###.",
    "...........#..",
    "..#...........",
    ".###..........",
    "#####.........",
    "..#...........",
    "..#........#..",
    "...##....##...",
    ".....####....."]

  // An open hand: four fingers, splayed so the outer one starts a row lower,
  // and a thumb out to the left. The old grid had four prongs and no thumb
  // and read as a fork.
  readonly property var hand: [
    "...##.##.##...",
    "...##.##.##.##",
    "...##.##.##.##",
    "...##.##.##.##",
    "#..##.##.##.##",
    "##.###########",
    "##############",
    ".#############",
    "..###########.",
    "..###########.",
    "...#########..",
    "...#########..",
    "....#######...",
    "....#######..."]

  // ------------------------------------------------------- controls
  readonly property var chevron: [
    "...##.......",
    "...###......",
    "...####.....",
    "....####....",
    ".....####...",
    "......####..",
    "......####..",
    ".....####...",
    "....####....",
    "...####.....",
    "...###......",
    "...##......."]

  readonly property var exit: [
    ".#######....",
    ".#.....#....",
    ".#.....#..#.",
    ".#.....#.##.",
    ".#.....####.",
    ".#....######",
    ".#.....####.",
    ".#.....#.##.",
    ".#.....#..#.",
    ".#.....#....",
    ".#######....",
    "............"]

  // A key cap, for the keyboard legend on the policy rail.
  readonly property var keycap: [
    "............",
    ".##########.",
    ".#........#.",
    ".#........#.",
    ".#........#.",
    ".#........#.",
    ".##########.",
    ".##########.",
    "............",
    "............",
    "............",
    "............"]
}
