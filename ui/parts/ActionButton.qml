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

  signal activated()

  readonly property color toneColor: tone === "go" ? Theme.lime
                                                   : tone === "quit" ? Theme.urgent
                                                                     : Theme.textDisabled
  readonly property bool primary: variant === "primary"
  readonly property bool sign: variant === "sign"
  // Dark ink on a filled block; the theme's own rule for what stays legible
  // on a saturated fill.
  readonly property color inkColor: Theme.ink(button.toneColor)

  activeFocusOnTab: button.focusable

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
           ? Qt.rgba(Theme.panelSunken.r, Theme.panelSunken.g, Theme.panelSunken.b, 0.85)
           : button.primary
             ? (button.activeFocus ? Qt.lighter(button.toneColor, 1.16) : button.toneColor)
             : Qt.rgba(button.toneColor.r * 0.20, button.toneColor.g * 0.20,
                       button.toneColor.b * 0.20, 0.75)
    border.width: button.sign ? 0 : (button.primary ? (button.activeFocus ? 4 : 2) : 1)
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
  Row {
    anchors.centerIn: parent
    visible: !button.oneLine
    spacing: Math.round(button.iconSize * 0.5)

    // The icon aligns to the middle of the heading, not to the middle of the
    // two-line block. Centred on the block it landed in the gap between the
    // heading and its sub-line -- 16 px low on RACE A FRIEND -- so it belonged
    // to neither line.
    Item {
      visible: button.art.length > 0
      anchors.verticalCenter: parent.verticalCenter
      width: button.iconSize
      height: stack.height

      PixelIcon {
        width: button.iconSize
        height: button.iconSize
        y: Math.round(headline.y + headline.height / 2 - height / 2)
        art: button.art
        color: button.primary ? button.inkColor : button.toneColor
        inks: ({ "A": button.primary ? button.inkColor : button.toneColor,
                 "B": "transparent" })
      }
    }

    // ROUND-4: the two lines are centred on each other. Left-aligned, a
    // 9-character heading over a 40-character sub-line left a block of dead
    // fill to the right of the heading -- measured at (1660-1885, 780-830) on
    // round three's READY UP, which is 225 x 50 px of nothing inside the
    // loudest object on the screen.
    Column {
      id: stack
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.round(button.sublabelSize * 0.28)
      // Explicit, from the two implicit widths: a child bound to its parent's
      // width while the parent sizes to its children is a binding loop.
      width: Math.max(headline.implicitWidth, subline.implicitWidth)

      Text {
        id: headline
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: button.label
        color: button.primary ? button.inkColor : button.toneColor
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: button.labelSize
        font.letterSpacing: Math.max(1, button.labelSize * 0.06)
      }
      Text {
        id: subline
        visible: button.sublabel.length > 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: button.sublabel
        color: button.primary
               ? Qt.rgba(button.inkColor.r, button.inkColor.g, button.inkColor.b, 0.82)
               : Theme.textLabel
        font.family: Theme.mono
        font.bold: button.primary
        font.pixelSize: button.sublabelSize
        font.letterSpacing: 0.5
      }
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
      color: Theme.textLabel
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
