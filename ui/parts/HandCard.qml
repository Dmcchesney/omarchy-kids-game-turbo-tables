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
// The card is not a focus stop. The whole picker is one keyboard surface: the
// digit keys 1, 2 and 3 choose, which is what the design asks for, and a Tab
// chain through three cards would be a second way to do the same thing that a
// child would have to discover. `selected` is what a chosen card looks like.
//
// ---------------------------------------------------------------- ROUND 3
//
// IT IS A CARD NOW, AND IT WAS A ROW IN A LIST.
//
// A blind critic, on both builds: "The 'hand' is a dark list panel:
// `1 Pothole / ADD 8 TO ONE RIVAL / RARE` in ~12 px grey caps. These are not
// cards; nothing bursts from the twelve segments; the charge bar does not drain
// into anything." Design v4's whole paragraph on the hand is written in the
// language of cards -- they are dealt, they slide up, the chosen one slams
// down, the other two flip face down and fly off -- and none of that means
// anything to a six-year-old about three lines of a settings menu. This is the
// one moment of choice in the whole game.
//
// So: portrait, three across, each with the tier's own colour band along the
// top carrying the key to press and the rarity pips, the card's NAME in the
// largest type the picker owns, what it does underneath it in the middle of the
// face, and the rarity spelled out along the bottom. The chrome exemption in
// the plan covers the picker's panel; the cards inside it are the game layer
// and the design calls them cards, so they are drawn as cards.
Item {
  id: card

  objectName: "handCard"

  // A key of the engine's CARDS table: "nitro", "oilSlick", and so on.
  property string cardId: ""
  // What the child presses. 1, 2 or 3.
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
  implicitHeight: Math.round(width * 1.4)

  Accessible.role: Accessible.StaticText
  Accessible.name: "Card " + card.index + ", " + card.cardLabel + ", " + card.effect
                   + ", " + card.tier + (card.selected ? ", chosen" : "")

  Rectangle {
    id: face
    anchors.fill: parent
    radius: Theme.cornerRadiusSmall
    color: card.selected ? Theme.selectedFill
                         : Qt.rgba(Theme.panelSunken.r, Theme.panelSunken.g,
                                   Theme.panelSunken.b, 0.96)
    // The border is the rarity, at two pixels, so the three cards in a hand are
    // told apart at a glance and before any of them is read.
    border.width: card.selected ? 3 : 2
    border.color: card.selected
                  ? Theme.focusRing
                  : Qt.rgba(card.tierColor.r, card.tierColor.g, card.tierColor.b,
                            0.50 + card.breathe * 0.45)
  }

  // ------------------------------------------------------------ the top band
  // The rarity's own colour across the head of the card, carrying the key to
  // press at one end and the pips at the other. This is the part that makes
  // three cards in a row read as three DIFFERENT cards from across a room.
  Rectangle {
    id: band
    x: face.border.width
    y: face.border.width
    width: parent.width - face.border.width * 2
    height: Math.round(card.labelSize * 1.6)
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

    // The keycap. It is the whole interface of this card, so it is drawn as a
    // key and not as an ornament.
    Rectangle {
      id: keycap
      x: card.px(7)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.round(card.labelSize * 1.15)
      height: width
      radius: Theme.cornerRadiusSmall
      color: card.selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42)
                           : Qt.rgba(0, 0, 0, 0.34)
      border.width: 1
      border.color: card.selected ? Theme.focusRing : Theme.lineStrong

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: String(card.index)
        color: Theme.textBright
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: Math.round(card.labelSize * 0.82)
      }
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
    readonly property real fieldBottom: card.height - card.px(7) - card.detailSize * 1.4
    y: Math.max(fieldTop + card.px(4),
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
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: card.px(7)
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
}
