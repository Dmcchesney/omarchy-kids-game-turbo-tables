import QtQuick
import "../"

// One of the four seats on the grid: the child, then Bolt, Piston and Gasket.
//
// What is here is what the design lists for a solo roster -- kart preview,
// colour, number, a ready lamp, and a level badge for the rivals. What is not
// here is everything the multiplayer lobby needs and solo does not: no invite
// state, no approved-friend key, no device-verified mark, and above all no
// name. The child's seat is labelled YOU, which is the only label a game with
// no name field can honestly give it.
Item {
  id: slot

  property int number: 7
  property string name: "YOU"
  property int paintIndex: 0
  property int bodyIndex: 0
  // -1 for the child; 0, 1, 2 for Rookie, Pro, Champion.
  property int level: -1
  property bool ready: false
  property string statusText: ""
  property real scaleUnit: 1.0
  // The row's own fill and the ready lamp's sunken face. Defaults are what
  // they have always been; the garage sets them to the v3 dusk surfaces.
  property color surface: Theme.panelRaised
  property color sunkenSurface: Theme.panelSunken
  // Is this racer in the race that is set up? A Practice or Time trial run
  // has no rivals in it, and the three rival rows say so.
  //
  // ROUND-7. This used to be an `opacity: 0.45` that the garage put on the
  // WHOLE slot, and paint fidelity is on this screen's rubric: dimming the
  // row dims the car, so the one thing the roster exists to show -- what
  // colour that racer's kart is -- was being composited away to say something
  // about the race mode.
  //
  // There is no dim at all now. A first pass moved it off the kart and onto
  // the row's chrome, and the round's own contrast table caught THAT: the
  // dimmed SITTING OUT label measured 3.16:1, under the design's 4.5:1 floor,
  // because 0.80 alpha through 0.72 opacity is 0.58. So the state is carried
  // where the design says a state is carried -- by shape and text. The lamp
  // is unlit and reads SITTING OUT, which is what a ready lamp is for.
  property bool inRace: true
  // Whether the ready lamp is lit: a rival that is not in this race is not
  // ready for it. The word beside the lamp says so as well, because the
  // design requires every state to carry shape or text and not colour alone
  // -- and a dimmed row does not carry either.
  readonly property bool lit: ready && inRace

  readonly property color paintColor: Theme.paint(paintIndex)
  // The paint, lifted for type: a racer's own name is drawn in their own
  // colour, and no choice of paint may make it the least readable thing in
  // their row. ROUND-8: 1.45, not 1.25. The row is a brighter card this round
  // (`duskSurfaceRaised` went from #3c1228 to #632043), and at 1.25 the worst
  // of the eight -- purple, as #bd72ff -- measured 3.86:1 on it. Qt's
  // lighter() spends the overflow past value 255 on saturation, so a bigger
  // factor is a paler, brighter tint of the SAME hue: at 1.45 the worst of
  // the eight is red at 5.35:1. The kart preview and the badge border still
  // carry the paint itself, unlifted.
  readonly property color inkColor: Qt.lighter(paintColor, 1.45)
  readonly property bool isChild: level < 0

  function u(v) { return Math.round(v * scaleUnit) }

  // A row is read out as one thing: who, what colour, what number, and what
  // the lamp says. It is a display, not a control, so it is not focusable and
  // takes no Tab stop.
  activeFocusOnTab: false
  Accessible.role: Accessible.StaticText
  Accessible.name: slot.name + ", number " + slot.number + ", "
                   + Theme.paintName(slot.paintIndex).toLowerCase() + " "
                   + Theme.bodyName(slot.bodyIndex).toLowerCase() + ", "
                   + (slot.isChild ? "in the stall"
                                   : (slot.inRace ? "ready" : "sitting this race out"))

  implicitHeight: u(100)

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: slot.isChild
           ? Qt.rgba(Theme.accent.r * 0.16 + slot.surface.r * 0.5,
                     Theme.accent.g * 0.16 + slot.surface.g * 0.5,
                     Theme.accent.b * 0.2 + slot.surface.b * 0.5, 0.82)
           : slot.surface
    border.width: 1
    border.color: slot.isChild
                  ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                  : Theme.line
  }

  // The sun through the bay door reaches the roster column too: a warm
  // hairline along the top edge of every row, so the chrome is lit from the
  // same direction as the room and the cards stop reading as flat slabs.
  Rectangle {
    x: Theme.cornerRadius
    width: parent.width - Theme.cornerRadius * 2
    y: 1
    height: 1
    color: Theme.duskEdgeWarm
  }

  // ROUND-8. The bay is to the LEFT of this column, so the row's left edge is
  // the one facing the opening: a warm rim on it and a wash falling off across
  // the first third of the row, the same treatment every crate on the bay's
  // shelf already gets. A slab with a hairline along the top was a card that
  // had been tinted; this is a card that is lit.
  Rectangle {
    x: 0
    y: Theme.cornerRadius
    width: 2
    height: parent.height - Theme.cornerRadius * 2
    color: Theme.duskLitEdge
  }
  Rectangle {
    x: 2
    y: 1
    width: Math.round(parent.width * 0.34)
    height: parent.height - 2
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Qt.rgba(Theme.duskRim.r, Theme.duskRim.g, Theme.duskRim.b, 0.07) }
      GradientStop { position: 1.0; color: Qt.rgba(Theme.duskRim.r, Theme.duskRim.g, Theme.duskRim.b, 0.0) }
    }
  }

  // ---------------------------------------------------------- number badge
  Rectangle {
    id: badge
    x: slot.u(14)
    y: slot.u(12)
    width: slot.u(46)
    height: slot.u(38)
    radius: Theme.cornerRadiusSmall
    color: Qt.rgba(slot.paintColor.r * 0.22, slot.paintColor.g * 0.22, slot.paintColor.b * 0.22, 0.8)
    border.width: Math.max(1, slot.u(2))
    border.color: slot.paintColor

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: String(slot.number)
      color: slot.inkColor
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: slot.u(23)
    }
  }

  Text {
    id: racerName
    textFormat: Text.PlainText
    x: badge.x + badge.width + slot.u(14)
    y: badge.y + slot.u(2)
    text: slot.name
    color: slot.inkColor
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: slot.u(27)
    font.letterSpacing: slot.u(2)
  }

  // ------------------------------------------------------ level / identity
  // Three bars, filled to the rival's level. Shape carries the meaning; the
  // word beside it repeats it for anyone the shape does not reach.
  Row {
    id: levelMeter
    x: badge.x
    y: badge.y + badge.height + slot.u(10)
    spacing: slot.u(3)
    visible: !slot.isChild

    Repeater {
      model: 3
      Rectangle {
        width: slot.u(5)
        height: slot.u(6) + index * slot.u(4)
        anchors.bottom: parent.bottom
        radius: 1
        color: index <= slot.level ? Theme.amber : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.18)
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    x: slot.isChild ? badge.x : levelMeter.x + levelMeter.width + slot.u(9)
    y: badge.y + badge.height + slot.u(11)
    text: slot.isChild ? slot.statusText : Theme.levelNames[Math.max(0, Math.min(2, slot.level))]
    // ROUND-8: full strength, not the shared 0.80-alpha role. The v3
    // surfaces are brighter this round and 0.80 measures 3.75:1 on them.
    color: slot.isChild ? Theme.text : Theme.amber
    font.family: Theme.mono
    font.bold: !slot.isChild
    font.pixelSize: slot.u(15)
    font.letterSpacing: slot.u(1)
  }

  // ----------------------------------------------------------- kart preview
  // PIECE C: the same sheet cell the turntable shows, at the 0.5 row, so the
  // car in the child's row is the car on the dais and not a second drawing
  // of it. One pixel per sheet pixel at the design's base size; two once
  // the row is tall enough to hold them. The number is left to CarSprite's
  // own legibility floor: at this size the roundel is a few pixels and the
  // row's own badge already carries the number legibly.
  CarSprite {
    id: preview
    objectName: "carPreview"
    // The cell centred in the row; the anchor is the contact point, so the
    // cell's own centre is half a cell up and along from it.
    x: lamp.x - slot.u(10) - drawnWidth + anchorDx
    y: Math.round(slot.height / 2 - drawnHeight / 2 + anchorDy)
    body: slot.bodyIndex
    paint: slot.paintIndex
    number: slot.number
    camera: "stall"
    // The quarter view, not the rear: this is the screen where a child picks
    // a car, and from behind the coupe and the saloon were 12.4 % apart as
    // cut-outs. From column 6 the greenhouse, the pillars and the door panel
    // are all visible, which is what tells two cars apart at 96 px.
    yaw: 6
    sheetScale: 0.5
    // ROUND-7: 1.30, not 1.50. At 2560x1440 the screen's scale factor is
    // 1.333, so the old threshold left the roster car at one sheet pixel per
    // screen pixel on the biggest display the game runs on -- a 96 x 64 cell
    // in a 133 px row. Two pixels per sheet pixel is 192 x 128, which still
    // fits the row, and paint fidelity in the roster is on this screen's bar.
    pixelScale: slot.scaleUnit >= 1.30 ? 2 : 1
  }

  // ------------------------------------------------------------- ready lamp
  Rectangle {
    id: lamp
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: slot.u(14)
    // ROUND-8: 122, not 102. `SITTING OUT` is eleven characters at pixelSize
    // u(15) with u(1) of letter spacing -- 110 units -- so it was 8 units
    // WIDER than the pill it is centred in and overflowed 4 units onto the
    // row card at each end. That never showed as a defect while the card was
    // near-black: round seven measured that word at 5.70:1 against #4d2b44.
    // Raising the surfaces this round took the same overhang to 4.22:1 on
    // #6e375a -- the only string on any of the six frames that the value
    // range cost, and it was a latent layout bug rather than a colour choice.
    // 122 is the longest label plus six units of clearance at each end.
    width: slot.u(122)
    height: slot.u(74)
    radius: Theme.cornerRadiusSmall
    color: slot.sunkenSurface
    border.width: 1
    border.color: Theme.line

    Text {
      id: lampLabel
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      y: slot.u(11)
      text: slot.isChild ? "IN STALL" : (slot.inRace ? "READY" : "SITTING OUT")
      // Full strength, not `textLabel`. This word IS the row's state, and at
      // 0.80 alpha over the lamp's lit-side bevel it measured 4.23:1 on the
      // shipped Practice frame -- under the design's floor.
      // ROUND-8: amber, not lime. The lamp is the design's own amber, which
      // its Visual style already gives to lap lamps.
      color: slot.lit ? Theme.amberGlow : Theme.text
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: slot.u(15)
      font.letterSpacing: slot.u(1)
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      y: lampLabel.y + lampLabel.height + slot.u(8)
      width: slot.u(26)
      height: width
      radius: width / 2
      color: slot.lit ? Theme.amber : "#1c0a18"
      border.width: Math.max(1, slot.u(2))
      border.color: slot.lit
                    ? Qt.lighter(Theme.amber, 1.3)
                    : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.3)

      Rectangle {
        visible: slot.lit
        anchors.centerIn: parent
        width: parent.width * 0.42
        height: width
        radius: width / 2
        color: "#fff2d6"
      }
    }
  }
}
