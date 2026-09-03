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
  // A padlock: solid shackle, solid body, and a keyhole that is a straight
  // vertical slot. The previous grid widened the slot in its middle row, so
  // the hole came out cross-shaped and the icon read as a first-aid kit.
  readonly property var lock: [
    "............",
    "....####....",
    "...##..##...",
    "...##..##...",
    "...##..##...",
    ".##########.",
    ".##########.",
    ".####..####.",
    ".####..####.",
    ".####..####.",
    ".##########.",
    ".##########."]

  // PRESET SIGNALS. ROUND-4: this was a broadcast arc -- a Wi-Fi glyph -- on
  // a screen whose next chip says THIS COMPUTER ONLY and whose title bar says
  // OFFLINE. A critic named it exactly: "a radio glyph is the wrong metaphor
  // for 'the signal vocabulary is a fixed list'; it says networked."
  // What the row actually means is "a short fixed list of things you can
  // say", so it is a speech bubble with three dots in it: a message, and a
  // preset one. Nothing about it implies a second machine.
  readonly property var preset: [
    "############",
    "#..........#",
    "#..........#",
    "#.##.##.##.#",
    "#.##.##.##.#",
    "#..........#",
    "#..........#",
    "############",
    "..####......",
    "..###.......",
    "..##........",
    "..#........."]

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
  // NICE RUN. ROUND-4 REDRAW. The round-three grid was judged not to read
  // cold at the 74 px the tile displays -- "a book, a washboard, or a stack"
  // -- and the diagnosis was in the drawing: a three-row thumb on an
  // eight-row fist is a nub, and three full-width horizontal rules across a
  // plain rounded rectangle is a washboard whatever else is on it.
  //
  // So: the thumb is six rows against the fist's eight and five cells wide
  // against its thirteen, so it reads as a thumb by proportion and not only
  // by position; there are two knuckle rules instead of three and each stops
  // two cells short of the right edge, so they read as finger separations on
  // a fist rather than as ruling on a page; and the cuff is a separate band
  // below a wrist gap, which is the last thing B's has that this lacked.
  //
  // Every separating rule keeps its outer columns inked, so no part of the
  // glyph can be cut loose from the rest of it.
  readonly property var thumbUp: [
    "..###.........",
    ".####.........",
    ".####.........",
    ".####.........",
    ".####.........",
    ".####.........",
    ".#####........",
    ".########.....",
    ".###########..",
    ".############.",
    ".#####oooooo#.",
    ".############.",
    ".#####oooooo#.",
    ".############.",
    ".############.",
    ".#oooooooooo#.",
    ".############.",
    "..##########.."]

  // Rematch: a circular arrow -- a thick C-shaped arc with one solid
  // triangular head at its open end, pointing the way the arc travels.
  //
  // Round one had no arrowheads. Round two had heads that were described in
  // the source as solid triangles and rasterised as five-cell plus shapes,
  // because the ring was two cells thick, the heads sat on top of the ring
  // instead of at its end, and both were fighting for the same cells. This
  // grid was rasterised from real geometry -- annulus plus triangle -- and
  // then checked by rendering it at the 74 px the tile actually displays,
  // where the cell lands on 4 px: the head is 7 cells across against a
  // 3-cell stroke, so it survives as a triangle at that size. One head reads
  // better than two here; two of them at this scale collide with the ring
  // and each other and the whole glyph goes back to being a blob.
  readonly property var rematch: [
    "................",
    "......###.......",
    "....#######.....",
    "...#########....",
    "..####...##.....",
    "..###........###",
    ".###.....######.",
    ".###......#####.",
    ".###.......###..",
    "..###.......##..",
    "..####...###....",
    "...#########....",
    "....#######.....",
    "......###......."]

  // GOOD GAME. ROUND-4: tilted. Straight on and vertical, an open hand reads
  // as "stop" at least as readily as "wave", which is the last thing this
  // signal should say to a child; the mock's is tilted and that is what
  // separates the two readings. Four fingers, splayed and leaning, with the
  // thumb out to the left.
  readonly property var hand: [
    "......##.##.....",
    ".....##.##.##...",
    ".....##.##.##.##",
    "....##.##.##.##.",
    "....##.##.##.##.",
    "..#.##.##.##.##.",
    "..##############",
    "..##############",
    "...#############",
    "...############.",
    "....###########.",
    "....##########..",
    ".....#########..",
    ".....########..."]

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

  // A tick, for the chosen paint swatch. Ten columns by eight rows so the
  // diagonal has whole cells to land on at swatch size.
  readonly property var check: [
    "........##",
    ".......##.",
    "......##..",
    "#....##...",
    "##..##....",
    ".####.....",
    "..##......",
    ".........."]

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
