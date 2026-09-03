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

  signal picked(int index)

  readonly property int count: Theme.paints.length
  readonly property int rows: Math.ceil(count / columns)
  readonly property real cellW: (width - gap * (columns - 1)) / columns
  readonly property real cellH: (height - gap * (rows - 1)) / rows

  activeFocusOnTab: true

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

  Repeater {
    model: grid.count

    Item {
      x: (index % grid.columns) * (grid.cellW + grid.gap)
      y: Math.floor(index / grid.columns) * (grid.cellH + grid.gap)
      width: grid.cellW
      height: grid.cellH

      Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusSmall
        color: Theme.paint(index)
        border.width: index === grid.selected ? 3 : 1
        border.color: index === grid.selected
                      ? "#ffffff"
                      : Qt.rgba(0, 0, 0, 0.55)
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
