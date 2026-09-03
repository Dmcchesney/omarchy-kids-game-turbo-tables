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

  // Broadcast: two arcs spreading from a source. The previous grid was a
  // dashed box around an asterisk and read as nothing at all.
  readonly property var broadcast: [
    "............",
    "...######...",
    "..##....##..",
    ".##......##.",
    "##........##",
    "............",
    "....####....",
    "...##..##...",
    "............",
    ".....##.....",
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
  // Thumbs up: a tapered thumb, a fist ruled into fingers, and a cuff.
  //
  // Every separating rule keeps its outer columns inked. The previous grid's
  // second-to-last row was "..oooooooooo.." -- a rule with nothing filled on
  // either side of it -- so the bottom row was cut clean off the icon and
  // floated 4 px under the fist as a loose bar.
  readonly property var thumbUp: [
    "..###.........",
    "..###.........",
    ".####.........",
    ".####.........",
    ".####.........",
    ".############.",
    ".############.",
    ".#oooooooooo#.",
    ".############.",
    ".#oooooooooo#.",
    ".############.",
    ".############.",
    ".#oooooooooo#.",
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
