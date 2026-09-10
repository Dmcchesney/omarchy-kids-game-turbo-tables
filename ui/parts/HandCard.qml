import QtQuick
import "../"
import "../../engine/engine.mjs" as Engine

// One of the three cards in the hand, as the picker draws it.
//
// Everything printed on the card is read out of the engine's own card table --
// the label, the scope, the number of questions, the tier -- so a card can
// never say something the rules do not do. The design's powerup table and
// `src/engine/cards.ts` are the same eight rows; retyping "skip 4 questions"
// here would be a second copy of a number that has to match, and the one that
// drifts is always the copy.
//
// PIECE F ROUND 7 -- THE KEYCAP IS GONE, BECAUSE THE KEY IS GONE.
//
// The band across the head of this card used to carry a keycap with `1`, `2`
// or `3` on it: the digit that chose the card. Design v4.1 takes the digits
// away from the hand entirely -- "digits never touch the hand; they are always
// the answer" -- so a `1` printed on a card would now be a promise about a
// key that does something else. What chooses a card is the highlight, moved
// by Left and Right and landed by a click, and what a highlighted card looks
// like is `selected`: the accent ring, the lifted face, the brighter band.
//
// The card is not a focus stop. The whole picker is one keyboard surface: the
// arrows move a highlight across three cards, and a Tab chain through them
// would be a second way to do the same thing that a child would have to
// discover. It IS a click target: design v4.1 names "the picker's cards" among
// the things that must be clickable, and this is the one moment of choice in
// the whole game. The card OWNS the target rather than the picker placing one
// over it, so the hover paint and the press are the same fact: `hovered` below
// is read off the very MouseArea that fires `tapped`.
//
// IT IS A CARD, AND IT WAS A ROW IN A LIST. Portrait, three across, each with
// the tier's own colour band along the top carrying the rarity pips, the
// card's NAME in the largest type the picker owns, what it does underneath it
// in the middle of the face, and the rarity spelled out along the bottom.
Item {
  id: card

  objectName: "handCard"

  // A key of the engine's CARDS table: "nitro", "oilSlick", and so on.
  property string cardId: ""
  // Which of the three this is, 1 to 3. Named to a screen reader and in the
  // click table; never printed as a key, because it is not one.
  property int index: 1
  property bool selected: false
  property int labelSize: 22
  property int detailSize: 15
  property real scaleUnit: 1.0
  // PIECE F. Design v4: "An unused hand breathes gently so the child remembers
  // it." 0..1, driven by ui/Picker.qml off the effect clock; it moves the
  // card's border and nothing else, so it is a breath rather than a blink and
  // nothing on the card ever changes what it says.
  property real breathe: 0

  // PIECE M. A click on the card. The picker wires it to `highlight(index)`,
  // which is the same function its Left and Right branches land on.
  signal tapped()
  // The presses that put the highlight on this card from where it is now, set
  // by the picker: none when it is already here, otherwise Right as many times
  // as this card is round the hand. The parity crossover presses exactly this.
  property var keyRoute: null
  readonly property bool hovered: cardHit.hovered

  function px(v) { return Math.round(v * card.scaleUnit) }

  readonly property var definition: (cardId.length > 0 && Engine.isCard(cardId))
                                    ? Engine.CARDS[cardId] : null
  readonly property string cardLabel: definition ? String(definition.label) : ""
  readonly property string tier: definition ? String(definition.tier) : "common"
  readonly property string scope: definition ? String(definition.scope) : "self"
  readonly property int questionDelta: definition ? Number(definition.questionDelta) : 0
  readonly property bool targeted: scope === "targeted"

  // The design's effect column, said in the game's words and built from the
  // engine's numbers. Every branch below is a row of that table:
  //   self,     delta < 0   Nitro and Turbo, "skip 4 / 10 questions this lap"
  //   self,     delta = 0   Roll Cage, "block the next attack"
  //   aoe                   Oil Slick, "add 3 questions to every other racer"
  //   targeted, delta > 0   Wrench, Pothole, Pile-Up
  //   targeted, delta = 0   Tow Hook, "swap positions with one racer"
  readonly property string effect: {
    if (!definition)
      return ""
    if (scope === "self")
      return questionDelta < 0 ? ("SKIP " + (-questionDelta) + " QUESTIONS")
                               : "BLOCK THE NEXT ATTACK"
    if (scope === "aoe")
      return "ADD " + questionDelta + " TO EVERY RIVAL"
    return questionDelta > 0 ? ("ADD " + questionDelta + " TO ONE RIVAL")
                             : "SWAP PLACES WITH ONE RIVAL"
  }

  // Tier is colour and shape and a word, never colour alone: one pip for a
  // common card up to four for a legendary, and the tier spelled out beside
  // them. The design's accessibility rule is that every state has shape or text
  // as well as colour, and a rarity that is only a hue fails it.
  readonly property int tierPips: tier === "legendary" ? 4
                                : tier === "rare" ? 3
                                : tier === "uncommon" ? 2 : 1
  readonly property color tierColor: tier === "legendary" ? "#e05fb0"
                                   : tier === "rare" ? Theme.amber
                                   : tier === "uncommon" ? Theme.teal
                                   : Theme.textLabel

  // A PORTRAIT CARD, IN THE PROPORTIONS OF A PLAYING CARD. Poker stock is 1.4
  // times as tall as it is wide and the eye knows the shape before it reads a
  // word of it, which is the whole reason for drawing one.
  //
  // ISSUE #3 -- THE RATIO IS A FLOOR, NOT A CEILING.
  //
  // It used to be the whole of the height, and at 1024 x 600 that put the
  // effect line through the rarity word: `ADD 8 TO ONE RIVAL` over RARE,
  // `BLOCK THE NEXT ATTACK` past the bottom edge, `ADD 15 TO ONE RIVAL` over
  // LEGENDARY. The cause is that the TYPE has floors and the BOX did not.
  // `ui/Picker.qml` sets `labelSize: fsFloor(22, 18)` and
  // `detailSize: fsFloor(14, 13)`, so below about a 0.82 scale the words stop
  // shrinking -- deliberately, because 9 px is under every legibility floor in
  // the design -- while `width * 1.4` kept shrinking underneath them. Two more
  // wrapped lines then had nowhere to go but through the rarity word.
  //
  // So the card is as tall as the taller of the two: the playing-card ratio,
  // or exactly what the band, the text block and the rarity word need with
  // their own margins. The band, the body and the rarity word each get a row
  // of their own and NEVER share one, at any size, not only at the three that
  // were checked. The consequence is honest and visible: at 1024 x 600 the
  // card is a little taller than poker stock, because the words a seven-year-
  // old has to read do not fit on poker stock at that scale. The dock is
  // anchored to the bottom right and `ui/Race.qml` stacks the charge bar off
  // `dockHeight`, so the panel grows upward into the sky and nothing below it
  // moves.
  readonly property int bandHeight: Math.round(card.labelSize * 1.6)
  // The gap over and under the text block, and the rarity word's own margin.
  readonly property int bodyGap: Math.max(3, card.px(6))
  readonly property int tierMargin: card.px(7)
  readonly property int contentHeight: 3 + card.bandHeight + card.bodyGap
                                       + Math.ceil(body.height) + card.bodyGap
                                       + Math.ceil(tierWord.height) + card.tierMargin
  implicitHeight: Math.max(Math.round(width * 1.4), card.contentHeight)

  // PIECE M: a Button, because it is one now. It was StaticText while the only
  // way to reach it was a key the picker's own handler read, and the enumeration
  // this piece is gated on reads Accessible.role to find controls the click
  // walk might have missed -- so a control that has become pressable has to say
  // so here too, or it is invisible to the very check that would catch it.
  Accessible.role: Accessible.Button
  Accessible.name: "Card " + card.index + ", " + card.cardLabel + ", " + card.effect
                   + ", " + card.tier + (card.selected ? ", highlighted" : "")
  // Pressing a highlighted card again does NOT use it. Using a card spends all
  // three and cannot be undone, so it belongs on a control of its own with the
  // cost printed on it -- the footer's `SPACE  USE IT` -- and not on the second
  // press of the control that merely highlighted it. See `ui/Picker.qml`.
  Accessible.description: card.selected
                          ? "Highlighted. Use it with the USE button below, or the space bar."
                          : "Press it, or the left and right arrows, to highlight it."
  Accessible.onPressAction: card.tapped()

  Rectangle {
    id: face
    anchors.fill: parent
    radius: Theme.cornerRadiusSmall
    // PIECE M ROUND 2. A CHOSEN CARD LIGHTS UNDER THE POINTER AS WELL.
    //
    // It did not: every branch of this colour and of the border below turned on
    // `selected` first, so the pointer on the one card the child had chosen
    // changed nothing on the screen. The ring outside stays off for the reason
    // it always has -- a chosen card already wears the accent and two accent
    // rings on one card is not a state -- so the answer is in the face instead,
    // which is a step of brightness and not a second ring.
    color: card.selected
           ? (card.hovered ? Qt.lighter(Theme.selectedFill, 1.22) : Theme.selectedFill)
           : (card.hovered
              ? Qt.rgba(Theme.panelSunken.r + Theme.hoverFill.r * 0.35,
                        Theme.panelSunken.g + Theme.hoverFill.g * 0.35,
                        Theme.panelSunken.b + Theme.hoverFill.b * 0.35, 0.96)
              : Qt.rgba(Theme.panelSunken.r, Theme.panelSunken.g,
                        Theme.panelSunken.b, 0.96))
    // The border is the rarity, at two pixels, so the three cards in a hand are
    // told apart at a glance and before any of them is read.
    //
    // PIECE M. Hover raises the rarity border to full rather than replacing it
    // with the accent: the border is how a child tells three cards apart from
    // across a room, and a pointer passing over one must not take that away.
    // The accent ring outside the card is what says "pressable".
    border.width: card.selected ? 3 : 2
    border.color: card.selected
                  ? Theme.focusRing
                  : Qt.rgba(card.tierColor.r, card.tierColor.g, card.tierColor.b,
                            card.hovered ? 1.0 : 0.50 + card.breathe * 0.45)
  }

  // ------------------------------------------------------------ the top band
  // The rarity's own colour across the head of the card, carrying the pips.
  // This is the part that makes three cards in a row read as three DIFFERENT
  // cards from across a room. It brightens with the highlight, so the card
  // Space would fire is told from the other two by the band as well as by the
  // ring.
  Rectangle {
    id: band
    x: face.border.width
    y: face.border.width
    width: parent.width - face.border.width * 2
    height: card.bandHeight
    radius: Theme.cornerRadiusSmall
    color: Qt.rgba(card.tierColor.r, card.tierColor.g, card.tierColor.b,
                   card.selected ? 0.42 : 0.26)

    // The band's own bottom corners are square: it is a head, not a pill.
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: parent.radius
      color: parent.color
    }

    // The highlight's own mark, in the band: the arrow the aim tiles use, so
    // "this is the one" is a shape and not only a colour. Design,
    // Accessibility: every state has shape or text as well as colour.
    Text {
      x: card.px(9)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: card.selected ? "▸" : ""
      color: Theme.textBright
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: Math.round(card.labelSize * 0.82)
    }

    Row {
      anchors.right: parent.right
      anchors.rightMargin: card.px(7)
      anchors.verticalCenter: parent.verticalCenter
      spacing: card.px(3)
      Repeater {
        model: 4
        Rectangle {
          width: Math.round(card.detailSize * 0.52)
          height: width
          radius: 1
          color: index < card.tierPips ? card.tierColor : "transparent"
          border.width: index < card.tierPips ? 0 : 1
          border.color: Qt.rgba(0, 0, 0, 0.45)
        }
      }
    }
  }

  // ------------------------------------------------------------- the face
  Column {
    id: body
    x: card.px(8)
    width: parent.width - card.px(16)
    // Centred in what is left of the face once the band and the rarity word
    // have taken theirs, so a one-line effect and a two-line one both sit in
    // the middle of the card rather than hanging off the top of it.
    readonly property real fieldTop: band.y + band.height
    // ISSUE #3: the rarity word's OWN measured height, not a ratio of the
    // detail size. The word is drawn at `max(12, detailSize * 0.86)` -- that
    // floor is why the two numbers part company at small scales -- so a
    // reserve computed from `detailSize` was reserving for a word of a
    // different size than the one on the card. This asks the word.
    readonly property real fieldBottom: card.height - card.tierMargin
                                        - Math.ceil(tierWord.height) - card.bodyGap
    y: Math.max(fieldTop + card.bodyGap,
                fieldTop + (fieldBottom - fieldTop - height) / 2)
    spacing: card.px(6)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: card.cardLabel
      color: Theme.cream
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: card.labelSize
      font.letterSpacing: 1
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: card.effect
      color: Theme.text
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      font.family: Theme.mono
      font.pixelSize: card.detailSize
      font.letterSpacing: 0.5
    }
  }

  // The rarity, spelled out, along the foot of the card.
  Text {
    id: tierWord
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: card.tierMargin
    textFormat: Text.PlainText
    text: card.tier.toUpperCase()
    color: card.tierColor
    font.family: Theme.mono
    font.bold: true
    // A floor, not a ratio alone. At 1366 x 768 the ratio put this word at
    // 9 px, which is under every legibility floor in the design and smaller
    // than anything else the game prints.
    font.pixelSize: Math.max(12, Math.round(card.detailSize * 0.86))
    font.letterSpacing: 1
  }

  // PIECE M. The accent ring outside the card, so the pointer's answer to "is
  // this pressable" is the same shape the keyboard's answer is everywhere else.
  // It is off while the card is chosen: a chosen card already carries the
  // accent on its own border, and two accent rings on one card is not a state.
  FocusRing {
    on: card.hovered && !card.selected
    hover: true
    radius: Theme.cornerRadiusSmall
    wash: false
    gap: 4
  }

  Clickable {
    id: cardHit
    objectName: "clickHandCard"
    // Null on purpose: the keys that reach a card are the arrows, not Tab. See
    // the note at the top of this file.
    stop: null
    label: "card " + card.index + " " + card.cardLabel
    // One meaning, in both columns. The click highlights, the arrows
    // highlight, and neither of them spends the hand.
    does: "highlight " + card.cardLabel
    key: "Left, Right"
    keyRoute: card.keyRoute
    onActed: card.tapped()
  }
}
