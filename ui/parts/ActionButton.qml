import QtQuick
import "../"

// The three large controls at the bottom right: READY UP, LEAVE, and the
// RACE A FRIEND sign that stands where the mock's friend badges were.
//
// No mouse handler anywhere in it -- Enter and Space are the whole interface,
// which is also what makes the screen-reader name the only label a control
// needs.
//
// Three weights, because the round-one screen gave READY UP and LEAVE the
// same treatment and left a child scanning two equal buttons, one of which
// quits:
//
//   "primary"    a filled block in the go colour with dark ink on it, the
//                loudest object on the screen. Focus makes the fill brighter
//                and the border heavier -- never paler, which is what the
//                previous focus state did to the one control that matters.
//   "secondary"  one line, roughly half the height, outline only.
//   "sign"       not a control at all: no fill, a dashed rule instead of a
//                border, and `focusable` false so it is not in the Tab chain.
//                A child must never land on something that cannot act.
Item {
  id: button

  property string label: ""
  property string sublabel: ""
  property var art: []
  // "go" for the start control, "quit" for leave, "off" for the sign.
  property string tone: "go"
  property string variant: "secondary"
  property bool focusable: true
  property int labelSize: 34
  property int sublabelSize: 15
  property int iconSize: 40
  // The "sign" variant's fill. Defaults to what it has always been; the
  // garage sets it to the v3 dusk surface so the sign belongs to its column.
  property color surface: Theme.panelSunken
  // The "go" fill. Defaults to Theme.lime, which is what Results and Settings
  // still get; the garage passes the design's amber, because a lime slab is
  // the largest single block of a colour the bar does not contain.
  property color goTone: Theme.lime
  // ROUND-9. The "go" fill and the "go" ink, split off from `goTone` so a
  // filled primary control can be a DARK block with a bright rim instead of a
  // bright block. Both default to what they have always been -- the tone
  // itself, and the theme's own rule for what stays legible on a saturated
  // fill -- so Results, Settings and every other caller renders identically.
  property color goFill: button.goTone
  property color goInk: Theme.ink(button.fillColor)
  // Supporting text on this control. Defaults to the shared 0.80-alpha role;
  // the garage passes a full-strength one, because 0.80 does not clear 4.5:1
  // on the v3 surfaces this round raises.
  property color mutedColor: Theme.textLabel
  // The "off" tone, for the sign variant. Same reason as `mutedColor`.
  property color offTone: Theme.textDisabled

  signal activated()

  readonly property color toneColor: tone === "go" ? button.goTone
                                                   : tone === "quit" ? Theme.urgent
                                                                     : button.offTone
  readonly property bool primary: variant === "primary"
  readonly property bool sign: variant === "sign"
  // What the filled block is painted in, and what is legible on it. For every
  // tone but "go" these are the tone and the theme's ink rule, exactly as
  // before; "go" may separate them.
  readonly property color fillColor: tone === "go" ? button.goFill : button.toneColor
  readonly property color inkColor: tone === "go" ? button.goInk
                                                  : Theme.ink(button.toneColor)
  // The glyph. On a filled block whose fill is its own tone it takes the ink,
  // as it always did; where the fill has been dropped away from the tone, the
  // glyph keeps the TONE, so the accent colour is still on the control and is
  // on a few hundred pixels of it rather than a hundred thousand.
  readonly property color artColor: button.primary
                                    ? (Qt.colorEqual(button.fillColor, button.toneColor)
                                       ? button.inkColor : button.toneColor)
                                    : button.toneColor

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

  Accessible.role: button.sign ? Accessible.StaticText : Accessible.Button
  Accessible.name: label
  Accessible.description: sublabel
  Accessible.focusable: button.focusable
  Accessible.onPressAction: if (button.focusable) button.activated()

  Keys.onPressed: function (event) {
    if (!button.focusable)
      return
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      button.activated()
      event.accepted = true
    }
  }

  Rectangle {
    id: face
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: button.sign
           ? Qt.rgba(button.surface.r, button.surface.g, button.surface.b, 0.85)
           : button.primary
             ? (button.activeFocus ? Qt.lighter(button.fillColor, 1.22) : button.fillColor)
             : Qt.rgba(button.toneColor.r * 0.20, button.toneColor.g * 0.20,
                       button.toneColor.b * 0.20, 0.75)
    border.width: button.sign ? 0 : (button.primary ? (button.activeFocus ? 4 : 3) : 1)
    border.color: button.primary
                  ? (button.activeFocus ? Theme.focusRing
                                        : Qt.lighter(button.toneColor, 1.25))
                  : Qt.rgba(button.toneColor.r, button.toneColor.g, button.toneColor.b, 0.55)
  }

  // ROUND-4: the sign is a tile.
  //
  // Round three gave it no fill and one dashed rule along its bottom edge,
  // and a critic recorded the result as a defect in its own right: "RACE A
  // FRIEND is not a tile -- grey text at (1385-1790, 660-715) with no card or
  // border, on the roster's own background." The mock puts a block there and
  // so does this now: a sunken fill and a dashed border on all four sides.
  // Dashed, not solid, because the one thing the fill must not do is make it
  // look like the two controls under it -- it is still out of the Tab chain
  // and still cannot act.
  Canvas {
    visible: button.sign
    anchors.fill: parent
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)
      ctx.strokeStyle = Theme.lineStrong
      ctx.lineWidth = 1
      var r = Theme.cornerRadius
      var dash = 7, gap = 6
      function run(x0, y0, x1, y1) {
        var dx = x1 - x0, dy = y1 - y0
        var len = Math.sqrt(dx * dx + dy * dy)
        if (len <= 0)
          return
        for (var t = 0; t + dash < len; t += dash + gap) {
          ctx.beginPath()
          ctx.moveTo(x0 + dx * t / len, y0 + dy * t / len)
          ctx.lineTo(x0 + dx * (t + dash) / len, y0 + dy * (t + dash) / len)
          ctx.stroke()
        }
      }
      run(r, 0.5, width - r, 0.5)
      run(r, height - 0.5, width - r, height - 0.5)
      run(0.5, r, 0.5, height - r)
      run(width - 0.5, r, width - 0.5, height - r)
    }
  }

  // Primary and sign stack their two lines; secondary is one row.
  //
  // ROUND-9: THE GLYPH IS IN THE HEADING'S OWN ROW.
  //
  // It used to sit beside the two-line BLOCK, and the block is as wide as its
  // widest line -- the 40-character sub-line. With a 9-character heading
  // centred in it, that left about 120 px of empty fill between the flag and
  // the word READY at 1920, inside the loudest control on the screen. The
  // glyph and the heading are now one centred row and the sub-line is centred
  // under both, so the gap is the row's own spacing at every size and string.
  Column {
    id: stack
    anchors.centerIn: parent
    visible: !button.oneLine
    spacing: Math.round(button.sublabelSize * 0.28)

    Row {
      id: headRow
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Math.round(button.iconSize * 0.5)

      Item {
        visible: button.art.length > 0
        width: button.iconSize
        height: headline.height

        PixelIcon {
          width: button.iconSize
          height: button.iconSize
          y: Math.round((parent.height - height) / 2)
          art: button.art
          color: button.artColor
          inks: ({ "A": button.artColor, "B": "transparent" })
        }
      }

      Text {
        id: headline
        textFormat: Text.PlainText
        text: button.label
        color: button.primary ? button.inkColor : button.toneColor
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: button.labelSize
        font.letterSpacing: Math.max(1, button.labelSize * 0.06)
      }
    }

    Text {
      id: subline
      anchors.horizontalCenter: parent.horizontalCenter
      visible: button.sublabel.length > 0
      textFormat: Text.PlainText
      text: button.sublabel
      color: button.primary
             ? Qt.rgba(button.inkColor.r, button.inkColor.g, button.inkColor.b, 0.88)
             : button.mutedColor
      font.family: Theme.mono
      font.bold: button.primary
      font.pixelSize: button.sublabelSize
      font.letterSpacing: 0.5
    }
  }

  readonly property bool oneLine: variant === "secondary"

  Item {
    visible: button.oneLine
    anchors.fill: parent
    anchors.leftMargin: Math.round(button.iconSize * 0.6)
    anchors.rightMargin: Math.round(button.iconSize * 0.6)

    PixelIcon {
      id: rowIcon
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      width: button.iconSize
      height: button.iconSize
      art: button.art
      color: button.toneColor
      inks: ({ "A": button.toneColor, "B": "transparent" })
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: rowIcon.right
      anchors.leftMargin: Math.round(button.iconSize * 0.5)
      textFormat: Text.PlainText
      text: button.label
      color: button.toneColor
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: button.labelSize
      font.letterSpacing: Math.max(1, button.labelSize * 0.06)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      textFormat: Text.PlainText
      text: button.sublabel
      color: button.mutedColor
      font.family: Theme.mono
      font.pixelSize: button.sublabelSize
      font.letterSpacing: 0.5
    }
  }

  FocusRing {
    on: button.activeFocus
    radius: Theme.cornerRadius
    // The primary control never takes the accent wash: a translucent film
    // over a filled block is exactly the "focus dims it" fault this replaces.
    wash: !button.primary
    thickness: button.primary ? 3 : 2
    gap: button.primary ? 5 : 3
  }
}
