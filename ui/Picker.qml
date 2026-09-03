import QtQuick
import "parts"
import "../engine/engine.mjs" as Engine

// The powerup hand, and the four keys that spend it.
//
// Design, Streaks and the powerup hand: "Keys: `1`, `2`, `3` choose a card; for
// a targeted card, left and right pick a rival, Enter confirms, Escape backs
// out. The picker is a small panel in the lower right, not a modal over the
// question, so the race stays visible."
//
// NOT A MODAL, AND THIS FILE IS WHERE THAT IS TRUE OR NOT. There is no scrim
// here, no full-bleed rectangle, no fill on the root item at all: the only
// pixels this screen paints are inside one panel anchored to the bottom-right
// corner. Everything the race screen draws -- the fact, the field, the track,
// the karts -- keeps drawing behind it. A hand arriving in the middle of a lap
// must not take the question off the screen, because the child is still
// answering it.
//
// ENTER CONFIRMS, FOR EVERY CARD. The design names Enter in the targeted case,
// where there is a rival to pick first. It is required here for the self and
// every-rival cards too, and that is a deliberate reading rather than an
// oversight: a hand costs the whole hand, `1` is next to the digits the child
// is typing at speed for the entire race, and a mistyped answer that fires a
// Turbo and throws away a Pile-Up is exactly the kind of loss the design's
// fairness section spends its length preventing. Choosing is one key; spending
// is two. Escape gets the hand back untouched either way.
//
// 1, 2 AND 3 ARE ALSO DIGITS. Plenty of answers begin with one of them, and the
// child is typing for the whole race, so this panel never swallows them: it
// takes 1, 2 and 3 as a choice and leaves the event unaccepted so the same key
// reaches the screen behind it as a digit as well. Enter is arbitrated the same
// way, through `entryLength`: with something already typed the answer wins and
// Enter is left alone, and only with the field empty does Enter spend the card.
// Nothing is ever spent by a keystroke that was meant as a digit.
FocusScope {
  id: picker

  readonly property Item focusTarget: picker

  // --------------------------------------------------------------- scaling
  readonly property real s: Math.max(0.42, Math.min(width / 1920, height / 1080))
  function px(v) { return Math.round(v * s) }
  function fs(v) { return Math.max(8, Math.round(v * s)) }

  // ------------------------------------------------------------- the hand
  //
  // The host hands the live hand down. Standing on its own -- in the harness,
  // or before a hand has ever been dealt -- it shows the hand the engine
  // actually deals first, off the shared round-robin cursor at zero. The
  // design fixes that hand: "The first hand of a race is always Nitro, Oil
  // Slick, Wrench."
  property var hand: Engine.dealHand(Engine.CARD_SCHEDULE, 0).hand

  // Who a targeted card can be aimed at, as { id, name, number }. The race
  // screen passes the racers who are still in the fight; a finished racer
  // "cannot attack and cannot be attacked", so it is the caller's list and not
  // a list this panel invents.
  property var rivals: [
    { "id": "bolt", "name": Theme.rivalNames[0], "number": Theme.rivalNumbers[0] },
    { "id": "piston", "name": Theme.rivalNames[1], "number": Theme.rivalNumbers[1] },
    { "id": "gasket", "name": Theme.rivalNames[2], "number": Theme.rivalNumbers[2] }
  ]

  property int seed: 42

  // How many digits the child has already typed into the answer, which the host
  // reads off the engine's `racer.entry`. It is the arbiter between Enter the
  // submit key and Enter the spend key, and it is the host's to tell us because
  // the entry belongs to the race, not to this panel.
  property int entryLength: 0

  // -1 is "no card chosen yet", which is the state a hand sits in for as long
  // as the child likes. The design: "You may hold a hand as long as you like."
  property int chosen: -1
  property int targetIndex: 0

  readonly property string chosenCard: (chosen >= 0 && chosen < hand.length)
                                       ? String(hand[chosen]) : ""
  readonly property bool targeting: chosenCard.length > 0
                                    && Engine.isCard(chosenCard)
                                    && Engine.CARDS[chosenCard].scope === "targeted"
                                    && picker.rivals.length > 0
  readonly property string targetId: (picker.targeting
                                      && targetIndex >= 0 && targetIndex < rivals.length)
                                     ? String(rivals[targetIndex].id) : ""
  readonly property string targetName: (picker.targeting
                                        && targetIndex >= 0 && targetIndex < rivals.length)
                                       ? String(rivals[targetIndex].name) : ""

  // index is the position in the hand, 0 to 2. targetId is "" for a card that
  // needs no rival.
  signal cardUsed(int index, string targetId)
  // Escape with nothing chosen: the child wants the panel to stop asking.
  signal dismissed()

  visible: hand.length > 0

  Accessible.role: Accessible.Pane
  Accessible.name: "Power-up hand"
  Accessible.description: "Press one, two or three to choose a card."
                          + (picker.targeting
                             ? " Left and right pick a rival, Enter uses it on " + picker.targetName + "."
                             : " Enter uses it.")
                          + " Escape puts the card back. Using a card costs the whole hand."

  function choose(index) {
    if (index < 0 || index >= picker.hand.length)
      return
    picker.chosen = index
    picker.targetIndex = 0
  }

  function stepTarget(delta) {
    if (!picker.targeting)
      return
    var count = picker.rivals.length
    picker.targetIndex = ((picker.targetIndex + delta) % count + count) % count
  }

  function confirm() {
    if (picker.chosen < 0)
      return
    var index = picker.chosen
    var target = picker.targeting ? picker.targetId : ""
    picker.chosen = -1
    picker.targetIndex = 0
    picker.cardUsed(index, target)
  }

  function back() {
    if (picker.chosen >= 0) {
      // The hand is untouched. Backing out of a choice is free and always was.
      picker.chosen = -1
      picker.targetIndex = 0
      return
    }
    picker.dismissed()
  }

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_1 || event.key === Qt.Key_2 || event.key === Qt.Key_3) {
      picker.choose(event.key - Qt.Key_1)
      // Deliberately NOT accepted: the same press is also the digit 1, 2 or 3,
      // and the screen behind has to see it.
      return
    }
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
      if (picker.targeting) {
        picker.stepTarget(event.key === Qt.Key_Left ? -1 : 1)
        event.accepted = true
      }
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      // A half-typed answer owns Enter. Only an empty field lets Enter spend a
      // card, which is what stops a submit from costing a hand.
      if (picker.entryLength === 0 && picker.chosen >= 0) {
        picker.confirm()
        event.accepted = true
      }
      return
    }
    if (event.key === Qt.Key_Escape) {
      picker.back()
      event.accepted = true
      return
    }
    // Every other key is left unaccepted on purpose. The race screen behind
    // this panel is where the digits of an answer belong, and a picker that
    // swallowed them would stall the child mid-fact.
  }

  // ------------------------------------------------------------- the panel
  Item {
    id: dock
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: picker.px(28)
    anchors.bottomMargin: picker.px(28)
    width: picker.px(500)
    height: body.height + picker.px(30)

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.94)
      border.width: 2
      border.color: picker.chosen >= 0 ? Theme.focusRing : Theme.amberDeep
    }

    Column {
      id: body
      x: picker.px(15)
      y: picker.px(15)
      width: parent.width - picker.px(30)
      spacing: picker.px(9)

      Row {
        width: parent.width
        spacing: picker.px(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "POWER-UP HAND"
          color: Theme.amber
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: picker.fs(18)
          font.letterSpacing: picker.px(3)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "USING ONE SPENDS ALL THREE"
          color: Theme.textLabel
          font.family: Theme.mono
          font.pixelSize: picker.fs(13)
          font.letterSpacing: picker.px(1)
        }
      }

      Repeater {
        model: picker.hand

        HandCard {
          width: body.width
          cardId: String(modelData)
          index: model.index + 1
          selected: picker.chosen === model.index
          scaleUnit: picker.s
          labelSize: picker.fs(22)
          detailSize: picker.fs(14)
        }
      }

      // ------------------------------------------------------- the target
      //
      // Only a targeted card asks this question, and it asks it in place rather
      // than in a second panel: the cards stay on screen, so a child who picked
      // the wrong one can see it and press Escape.
      Item {
        width: parent.width
        height: picker.targeting ? targetColumn.height + picker.px(10) : 0
        clip: true
        visible: picker.targeting

        Column {
          id: targetColumn
          y: picker.px(10)
          width: parent.width
          spacing: picker.px(6)

          Text {
            textFormat: Text.PlainText
            text: "AIM AT"
            color: Theme.teal
            font.family: Theme.mono
            font.bold: true
            font.pixelSize: picker.fs(14)
            font.letterSpacing: picker.px(2)
          }

          Row {
            spacing: picker.px(8)

            Repeater {
              model: picker.rivals

              Rectangle {
                readonly property bool aimed: picker.targetIndex === model.index
                width: Math.floor((targetColumn.width - picker.px(8) * Math.max(0, picker.rivals.length - 1))
                                  / Math.max(1, picker.rivals.length))
                height: picker.px(46)
                radius: Theme.cornerRadiusSmall
                color: aimed ? Theme.selectedFill
                             : Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.06)
                border.width: aimed ? 2 : 1
                border.color: aimed ? Theme.focusRing : Theme.line

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  // The arrow is the state, not the colour: the design's
                  // accessibility rule again.
                  text: (parent.aimed ? "▸ " : "") + String(modelData.name)
                  color: parent.aimed ? Theme.textBright : Theme.textLabel
                  font.family: Theme.mono
                  font.bold: true
                  font.pixelSize: picker.fs(16)
                  font.letterSpacing: picker.px(1)
                }
              }
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Theme.line
      }

      // The keys, always visible, always the same four. A child who has never
      // held a hand before finds out what to press by looking at the panel.
      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        text: picker.chosen < 0
              ? "1 2 3  CHOOSE      ESC  HIDE"
              : (picker.entryLength > 0
                 ? "FINISH THE ANSWER FIRST      ESC  BACK"
                 : (picker.targeting
                    ? "◀ ▶  RIVAL      ⏎  USE      ESC  BACK"
                    : "⏎  USE IT      ESC  BACK"))
        color: Theme.text
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: picker.fs(14)
        font.letterSpacing: picker.px(1)
        lineHeight: 1.25
      }
    }
  }
}
