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
Item {
  id: card

  // A key of the engine's CARDS table: "nitro", "oilSlick", and so on.
  property string cardId: ""
  // What the child presses. 1, 2 or 3.
  property int index: 1
  property bool selected: false
  property int labelSize: 22
  property int detailSize: 15
  property real scaleUnit: 1.0

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

  implicitHeight: Math.round(labelSize * 2.9)

  Accessible.role: Accessible.StaticText
  Accessible.name: "Card " + card.index + ", " + card.cardLabel + ", " + card.effect
                   + ", " + card.tier + (card.selected ? ", chosen" : "")

  Rectangle {
    id: face
    anchors.fill: parent
    radius: Theme.cornerRadiusSmall
    color: card.selected ? Theme.selectedFill
                         : Qt.rgba(Theme.panelSunken.r, Theme.panelSunken.g, Theme.panelSunken.b, 0.92)
    border.width: 1
    border.color: card.selected ? Theme.focusRing : Theme.line
  }

  // The keycap. It is the whole interface of this card, so it is drawn as a
  // key and not as an ornament.
  Rectangle {
    id: keycap
    x: card.px(10)
    anchors.verticalCenter: parent.verticalCenter
    width: Math.round(card.labelSize * 1.5)
    height: width
    radius: Theme.cornerRadiusSmall
    color: card.selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.30)
                         : Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.08)
    border.width: 1
    border.color: card.selected ? Theme.focusRing : Theme.lineStrong

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: String(card.index)
      color: card.selected ? Theme.textBright : Theme.text
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: Math.round(card.labelSize * 0.9)
    }
  }

  Column {
    id: body
    anchors.verticalCenter: parent.verticalCenter
    x: keycap.x + keycap.width + card.px(12)
    width: pips.x - x - card.px(10)
    spacing: card.px(3)

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: card.cardLabel
      color: Theme.cream
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: card.labelSize
      font.letterSpacing: 1
      elide: Text.ElideRight
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: card.effect
      color: Theme.textLabel
      font.family: Theme.mono
      font.pixelSize: card.detailSize
      font.letterSpacing: 0.8
      elide: Text.ElideRight
    }
  }

  Column {
    id: pips
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: card.px(12)
    spacing: card.px(4)

    Row {
      anchors.right: parent.right
      spacing: card.px(3)
      Repeater {
        model: 4
        Rectangle {
          width: Math.round(card.detailSize * 0.55)
          height: width
          radius: 1
          color: index < card.tierPips ? card.tierColor : "transparent"
          border.width: index < card.tierPips ? 0 : 1
          border.color: Theme.textFaint
        }
      }
    }
    Text {
      anchors.right: parent.right
      textFormat: Text.PlainText
      text: card.tier.toUpperCase()
      color: card.tierColor
      font.family: Theme.mono
      // A floor, not a ratio alone. At 1366 x 768 the ratio put this word at
      // 9 px, which is under every legibility floor in the design and smaller
      // than anything else the game prints.
      font.pixelSize: Math.max(12, Math.round(card.detailSize * 0.86))
      font.letterSpacing: 1
    }
  }
}
