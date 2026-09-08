import QtQuick
import "../"

// The eight paints, two rows of four. One focus stop: the arrows move the
// choice and the choice applies at once, so a child sees the kart change
// colour as they move rather than having to commit blind.
//
// The selected swatch carries a thick ring and a tick block as well as its
// position, because the design requires every state to have shape or text and
// not colour alone -- and this control is nothing but colour.
Item {
  id: grid

  property int selected: 0
  property int columns: 4
  property real gap: 8
  // ROUND 12 OF PIECE 3 -- THE EIGHT ARE ONE OBJECT, AND SEVEN OF THEM ARE
  // QUIET UNTIL THEY ARE POINTED AT.
  //
  // Squint-tested at 16:1, this grid was the FIRST thing the eye reached on the
  // garage -- ahead of the sun, the work light, the go button and, fifth, the
  // car the screen exists to show. The measurement is unarguable: the swatches
  // carry saturation 0.58 to 0.76 at value 0.79 to 0.95 across the WHOLE hue
  // circle -- green at h=0.29, blue at h=0.60, purple at h=0.76 -- while every
  // other pixel in that room lives between h=0.88 and h=0.13. A rainbow is the
  // only foreign-hue object in a strictly warm scene, so it wins, and it is a
  // control in the opposite corner from the subject.
  //
  // Two changes, and neither takes a colour away from the child. `plate` puts
  // the eight on one sunken face with a border, so they read as one palette
  // rather than eight competing colour fields. `rest` darkens the ones that are
  // not chosen, keeping their hue exactly -- a dark green is still green, and a
  // child picking green can see it is green -- while the chosen paint keeps full
  // chroma and its white ring. The pointer restores a swatch to its true colour
  // on hover, so the grid answers the pointer with the one thing it is about.
  property color plate: "transparent"
  property color plateBorder: "transparent"
  property real inset: 0
  property real rest: 1.0

  signal picked(int index)

  readonly property int count: Theme.paints.length
  readonly property int rows: Math.ceil(count / columns)
  readonly property real cellW: (width - inset * 2 - gap * (columns - 1)) / columns
  readonly property real cellH: (height - inset * 2 - gap * (rows - 1)) / rows

  function faceOf(index) {
    var c = Theme.paint(index)
    return (index === grid.selected || grid.rest >= 0.999) ? c : Qt.darker(c, 1 / grid.rest)
  }

  // ROUND-8: NOT in Qt's implicit tab chain, and that is what makes the
  // screen's own Tab handler reachable. Qt Quick delivers a key to the focused
  // item first; when that item has `activeFocusOnTab` set and ignores Tab, the
  // delivery agent runs focus-chain navigation and CONSUMES the event there,
  // so a screen's Keys.onPressed never sees Tab at all. Two rounds of Tab code
  // in Garage.qml were dead for exactly that reason, and two mutations of it
  // left twenty tests green. Focus on these controls is moved by the screen
  // that owns them, through its published `stops` list. `Accessible.focusable`
  // is unchanged, so a screen reader still sees a focusable control.
  activeFocusOnTab: false

  Accessible.role: Accessible.ComboBox
  Accessible.name: "Kart colour, " + Theme.paintName(selected)
  Accessible.description: "Eight paints. The arrows move through them and the kart changes as you go."
  Accessible.focusable: true

  function move(delta) {
    var next = (selected + delta + count) % count
    grid.picked(next)
  }

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Left) {
      move(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right) {
      move(1)
      event.accepted = true
    }
  }

  // The palette's own face. Drawn only when a caller asks for one, so every
  // other screen that uses this grid is unchanged to the pixel.
  Rectangle {
    visible: grid.plate.a > 0 || grid.plateBorder.a > 0
    anchors.fill: parent
    radius: Theme.cornerRadiusSmall + 2
    color: grid.plate
    border.width: grid.plateBorder.a > 0 ? 1 : 0
    border.color: grid.plateBorder
  }

  Repeater {
    model: grid.count

    Item {
      id: cell
      x: grid.inset + (index % grid.columns) * (grid.cellW + grid.gap)
      y: grid.inset + Math.floor(index / grid.columns) * (grid.cellH + grid.gap)
      width: grid.cellW
      height: grid.cellH

      // PIECE M. A swatch is the one control in this game that is nothing but
      // colour, so its hover state may not be a colour: it is a white rim, one
      // step lighter than nothing and two steps below the chosen swatch's own
      // 3 px white ring, plus the accent ring outside the cell. The same rule
      // the tick below is drawn for -- "every state has shape or text as well
      // as colour" -- applies to the pointer as much as to the choice.
      readonly property bool hovered: swatchHit.hovered

      Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusSmall
        color: cell.hovered ? Theme.paint(index) : grid.faceOf(index)
        border.width: index === grid.selected ? 3 : (cell.hovered ? 2 : 1)
        border.color: index === grid.selected
                      ? "#ffffff"
                      : (cell.hovered ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(0, 0, 0, 0.55))
      }

      // PIECE M ROUND 2. THE CHOSEN SWATCH LIGHTS TOO.
      //
      // This read `cell.hovered && index !== grid.selected`, so the one swatch
      // the child has already chosen was the one swatch that gave the pointer
      // no answer at all -- and a pixel sweep of every control on the garage
      // found it, which no boolean test could. The reason round one had for
      // suppressing it belongs to the CARD, where the chosen state and the
      // hover ring are both the accent and two accent rings on one card is not
      // a state. Here they are different colours: the chosen swatch's ring is
      // white and on the border, the pointer's is the accent and outside it.
      Rectangle {
        visible: cell.hovered
        anchors.fill: parent
        anchors.margins: -3
        radius: Theme.cornerRadiusSmall + 2
        color: "transparent"
        border.width: 2
        border.color: Theme.hoverRing
      }

      // The click is the arrow key's own `picked`, not a second way to choose:
      // `move(delta)` emits exactly this signal, so the kart changes colour on
      // a click for the same reason and by the same route it changes on Right.
      Clickable {
        id: swatchHit
        objectName: "clickPaint"
        stop: grid
        label: "paint " + Theme.paintName(index)
        does: "paint the kart " + Theme.paintName(index)
        key: "Left, Right"
        // ROUND 4. The keys STEP through the eight paints and the click LANDS on
        // one, so "the key that does the same thing" is Right pressed as many
        // times as this swatch is round the ring from the one that is on. That
        // is what `test_29` presses before it demands the same screen, and it is
        // why this control can be crossed over at all rather than declared a
        // gap: eight presses of Right from the chosen paint reach this swatch
        // exactly, and Escape reaches it never.
        keyRoute: {
          var steps = ((index - grid.selected) % grid.count + grid.count) % grid.count
          var route = []
          for (var i = 0; i < steps; i++)
            route.push("right")
          return route
        }
        onActed: grid.picked(index)
      }

      // The tick: a shape, so the chosen paint is not signalled by colour
      // alone. It sits in the corner rather than the middle. Round two put a
      // solid 16 x 16 white square dead centre of a 59 x 53 swatch -- 14 % of
      // the swatch, no shape language, and it obscured the one thing the
      // control exists to show, so the chosen red read as white-on-red.
      PixelIcon {
        visible: index === grid.selected
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Math.round(grid.cellH * 0.13)
        width: Math.round(grid.cellW * 0.34)
        height: Math.round(width * 0.8)
        art: Glyphs.check
        color: Theme.ink(Theme.paint(index))
      }

      // Where the arrows are, as distinct from what is chosen. The group ring
      // below says "you are in the swatches"; this says "and you are on this
      // one". Round two had only the white selection ring, so a child could
      // not tell where they were from what they had picked.
      Rectangle {
        visible: grid.activeFocus && index === grid.selected
        anchors.fill: parent
        anchors.margins: -4
        radius: Theme.cornerRadiusSmall + 3
        color: "transparent"
        border.width: 2
        border.color: Theme.focusRing
      }
    }
  }

  FocusRing {
    on: grid.activeFocus
    gap: 5
    wash: false
    radius: Theme.cornerRadiusSmall + 2
  }
}
