import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Dungeons of Omakon — game window.
// Phase 2: full GUI frame. Directional arrows over the viewport, hand-slot
// equip buttons flanking the HUD read-outs, spell + inventory popups, and a
// toggleable automap. Maze data below is a DEBUG STUB — Phase 3's Dungeon.js
// replaces it with real generation.
Panel {
  id: root
  moduleName: "b.omakon"
  ipcTarget: "b.omakon"
  manageIpc: false   // BarWidget.qml owns the IPC target for this plugin.

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function refresh() {}
  function openFromHotkey() { root.open() }

  // ---- Character (Phase 4 binds to the save file) -------------------------
  property int heroHp: 20
  property int heroHpMax: 20
  property int heroMp: 8
  property int heroMpMax: 8

  // ---- Equipment / inventory shells ---------------------------------------
  property var leftHand: null          // shield-type item card, or null
  property var rightHand: ({ icon: "†", name: "Rusty Sword" })
  property var pack: (new Array(12)).fill(null)
  property var spells: []              // discovered spells

  property string popupMode: "none"    // "none" | "spells" | "inventory"
  function togglePopup(mode) {
    popupMode = (popupMode === mode) ? "none" : mode
  }

  // ---- Automap --------------------------------------------------------------
  property bool automapOn: true
  // Debug stub: 6x7, 1 = open node. Phase 3 fills this from Dungeon.js and
  // masks it behind an explored Rooms mask.
  property var stubMaze: [
    [1,1,1,1,1,1,1],
    [1,0,0,0,1,0,1],
    [1,1,1,1,1,0,1],
    [1,0,0,0,1,0,1],
    [1,0,1,1,1,1,1],
    [1,1,1,0,0,0,0]
  ]
  property int heroCol: 0
  property int heroRow: 5
  property int facing: 0               // 0=N 1=E 2=S 3=W

  // Wall stubs for arrow greying: all open until Phase 3.
  readonly property bool wallAhead: false
  readonly property bool wallBehind: false

  function move(dir) {
    // Placeholder movement inside the stub bounds, for arrow feedback.
    var d = (facing + dir + 4) % 4
    var dc = [0, 1, 0, -1][d]
    var dr = [-1, 0, 1, 0][d]
    var nc = heroCol + dc, nr = heroRow + dr
    if (nr >= 0 && nr < 6 && nc >= 0 && nc < 7 && stubMaze[nr][nc] === 1) {
      heroCol = nc; heroRow = nr
    }
  }

  // ---- Window ---------------------------------------------------------------
  PanelWindow {
    id: win
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    implicitWidth: 640
    implicitHeight: 480

    WlrLayershell.namespace: "omarchy-omakon"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None

    property bool focusPrimed: false
    onVisibleChanged: {
      if (visible) {
        focusPrimed = false
        focusPrimeTimer.restart()
      }
    }

    Timer {
      id: focusPrimeTimer
      interval: 120
      onTriggered: win.focusPrimed = true
    }

    Rectangle {
      id: frame
      anchors.fill: parent
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 2
      focus: true

      Keys.onEscapePressed: {
        if (root.popupMode !== "none") root.popupMode = "none"
        else root.close()
      }

      // ---- Title strip ------------------------------------------------------
      Rectangle {
        id: titleBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 28
        color: "transparent"
        border.color: Color.menu.border
        border.width: 2

        Text {
          anchors.centerIn: parent
          text: "DUNGEONS OF OMAKON"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.bold: true
          font.pixelSize: 13
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: 8
          text: "✕"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: 12
          MouseArea {
            anchors.fill: parent
            onClicked: root.close()
          }
        }
      }

      // ---- Viewport ---------------------------------------------------------
      Rectangle {
        id: viewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleBar.bottom
        anchors.bottom: hud.top
        anchors.margins: 8
        color: "black"
        border.color: Color.menu.border
        border.width: 2
        clip: true

        Text {
          anchors.centerIn: parent
          text: "[ dungeon viewport ]"
          color: Qt.darker(Color.menu.text, 1.6)
          font.family: Style.font.menuFamily
          font.pixelSize: 14
        }

        // Directional arrows. Pixel-style glyphs; Phase 3 feeds wallAhead/
        // wallBehind from the real maze so blocked moves grey out.
        component Arrow: Text {
          property int dir: 0          // 0 forward, 1 right, 2 back, 3 left
          property bool blocked: false
          font.family: Style.font.menuFamily
          font.pixelSize: 22
          color: blocked ? Qt.darker(Color.menu.text, 2.2) : Color.menu.text
          MouseArea {
            anchors.fill: parent
            enabled: !blocked
            onClicked: root.move(parent.dir)
          }
        }

        Arrow { // forward
          dir: 0
          text: "▲"
          blocked: root.wallAhead
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: 8
        }
        Arrow { // left turn/strafe
          dir: 3
          text: "◀"
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 8
        }
        Arrow { // right
          dir: 1
          text: "▶"
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: 8
        }
        Arrow { // back
          dir: 2
          text: "▼"
          blocked: root.wallBehind
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 8
        }

        // ---- Automap (toggleable; top-right corner) -------------------------
        Rectangle {
          id: automap
          visible: root.automapOn
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 8
          width: mapGrid.width + 8
          height: mapGrid.height + 8
          color: Qt.rgba(0, 0, 0, 0.7)
          border.color: Color.menu.border
          border.width: 1

          Grid {
            id: mapGrid
            anchors.centerIn: parent
            rows: 6
            columns: 7
            spacing: 1

            Repeater {
              model: 42
              Rectangle {
                property int c: index % 7
                property int r: Math.floor(index / 7)
                width: 10
                height: 10
                color: (c === root.heroCol && r === root.heroRow)
                  ? "#e0c040"                                   // hero
                  : (root.stubMaze[r][c] === 1
                      ? Qt.darker(Color.menu.text, 1.8)         // open node
                      : "black")                                 // void
                border.color: Qt.darker(Color.menu.border, 1.5)
                border.width: 1
              }
            }
          }
        }

        // (Map toggle now lives in the HUD strip as a permanent button.)
      }

      // ---- HUD strip ---------------------------------------------------------
      Rectangle {
        id: hud
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        height: 64
        color: "transparent"
        border.color: Color.menu.border
        border.width: 2

        Row {
          anchors.centerIn: parent
          spacing: 14

          // Map toggle — permanently visible, leftmost in the HUD.
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: root.automapOn ? Color.menu.selectedBackground : "transparent"
              border.color: Color.menu.border
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: "▦"
                color: root.automapOn ? Color.menu.text : Qt.darker(Color.menu.text, 2.0)
                font.family: Style.font.menuFamily
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.automapOn = !root.automapOn
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "MAP"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }

          // Left hand — shield slot
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: Color.menu.selectedBackground
              border.color: Color.menu.border
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: root.leftHand ? root.leftHand.icon : "⌾"
                color: root.leftHand ? Color.menu.text : Qt.darker(Color.menu.text, 2.2)
                font.family: Style.font.menuFamily
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.togglePopup("inventory")
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "L"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }

          // HP / MP read-outs
          Column {
            spacing: 4
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "HP " + root.heroHp + "/" + root.heroHpMax
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.bold: true
              font.pixelSize: 15
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "MP " + root.heroMp + "/" + root.heroMpMax
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.bold: true
              font.pixelSize: 15
            }
          }

          // Right hand — weapon slot
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: Color.menu.selectedBackground
              border.color: Color.menu.border
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: root.rightHand ? root.rightHand.icon : "⚔"
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.togglePopup("inventory")
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "R"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }

          // Spell book button
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: root.popupMode === "spells" ? Color.menu.selectedBackground : "transparent"
              border.color: root.spells.length > 0 ? Color.menu.border : Qt.darker(Color.menu.border, 1.8)
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: "✦"
                color: root.spells.length > 0 ? Color.menu.text : Qt.darker(Color.menu.text, 2.0)
                font.family: Style.font.menuFamily
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.togglePopup("spells")
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "SPL"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }

          // Inventory button
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: root.popupMode === "inventory" ? Color.menu.selectedBackground : "transparent"
              border.color: Color.menu.border
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: "▤"
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.togglePopup("inventory")
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "INV"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }
        }

        // ---- Spells popup ------------------------------------------------------
        Rectangle {
          visible: root.popupMode === "spells"
          anchors.bottom: parent.top
          anchors.right: parent.right
          anchors.bottomMargin: 4
          width: 220
          height: 140
          color: Color.menu.background
          border.color: Color.menu.border
          border.width: 2
          z: 10

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 8
            text: "SPELLS"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 11
          }
          Text {
            anchors.centerIn: parent
            text: root.spells.length === 0 ? "— none discovered —" : ""
            color: Qt.darker(Color.menu.text, 1.8)
            font.family: Style.font.menuFamily
            font.pixelSize: 11
          }
          ListView {
            anchors.fill: parent
            anchors.topMargin: 30
            anchors.margins: 8
            model: root.spells
            delegate: Text {
              text: modelData.icon + " " + modelData.name
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: 11
            }
          }
        }

        // ---- Inventory popup (12 slots) ---------------------------------------
        Rectangle {
          visible: root.popupMode === "inventory"
          anchors.bottom: parent.top
          anchors.right: parent.right
          anchors.bottomMargin: 4
          width: 232
          height: 158
          color: Color.menu.background
          border.color: Color.menu.border
          border.width: 2
          z: 10

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 6
            text: "PACK"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 11
          }
          Grid {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 8
            rows: 3
            columns: 4
            spacing: 4
            Repeater {
              model: 12
              Rectangle {
                property var item: root.pack[index]
                width: 40
                height: 34
                color: Color.menu.selectedBackground
                border.color: Color.menu.border
                border.width: 1
                Text {
                  anchors.centerIn: parent
                  text: item ? item.icon : "·"
                  color: item ? Color.menu.text : Qt.darker(Color.menu.text, 2.4)
                  font.family: Style.font.menuFamily
                  font.pixelSize: 14
                }
              }
            }
          }
        }
      }
    }
  }
}
