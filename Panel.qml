import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Dungeon.js" as Dungeon

// Dungeons of Omakon — game window.
// Phase 3: real procedurally generated floors (Dungeon.js) rendered as a
// pseudo-3D first-person view 2 nodes deep, with arrow-driven turn/move,
// stairs overlays, and an explored-masked automap.
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

  // ---- Floor state (Phase 4 persists this) -----------------------------------
  property bool automapOn: true
  property int floorNum: 1
  property var floor: Dungeon.generate((Math.random() * 0x7fffffff) | 0)
  property var pos: ({ row: floor.start.row, col: floor.start.col, facing: 0 })

  // Explored mask for the automap, keyed "r,c".
  property var explored: ({})
  Component.onCompleted: markExplored(pos.row, pos.col)

  function markExplored(r, c) {
    var key = r + "," + c
    if (explored[key]) return
    var next = {}
    for (var k in explored) next[k] = true
    next[key] = true
    explored = next    // new object identity so the automap re-evaluates
  }

  readonly property var view: floor ? Dungeon.vista(floor, pos) : []
  function wallAt(rel) { return Dungeon.hasWall(floor, pos.row, pos.col, (pos.facing + rel + 4) % 4) }

  function move(dir) {
    var np = Dungeon.move(floor, pos, dir)
    if (np.row !== pos.row || np.col !== pos.col) {
      pos = np
      markExplored(np.row, np.col)
    }
  }
  function turn(rel) { pos = Dungeon.turn(pos, rel) }

  function descend() {
    if (floor.nodes[pos.row][pos.col].feature !== "down") return
    floorNum++
    floor = Dungeon.generate((Math.random() * 0x7fffffff) | 0)
    pos = ({ row: floor.start.row, col: floor.start.col, facing: 0 })
    explored = ({})
    markExplored(pos.row, pos.col)
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

      // ---- Viewport: pseudo-3D first-person render --------------------------
      Rectangle {
        id: viewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleBar.bottom
        anchors.bottom: hud.top
        anchors.margins: 8
        color: "#05060a"           // deep-space overdraw guard
        border.color: Color.menu.border
        border.width: 2
        clip: true

        readonly property color wallNear: "#8a7f66"
        readonly property color wallFar:  "#565045"
        readonly property color endNear:  "#6e6552"
        readonly property color endFar:   "#3c3830"
        readonly property color voidCol:  "#0a0b10"

        // Sky (ceiling) and floor slabs.
        Rectangle { anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; height: parent.height / 2
                    color: "#11131c" }
        Rectangle { anchors.left: parent.left; anchors.right: parent.right
                    anchors.bottom: parent.bottom; height: parent.height / 2
                    color: "#1b1712" }

        // Depth-2 slices drawn first (behind depth-1). Rects are clipped by
        // the depth-1 trapezoid footprint so the corridor reads correctly.
        Item {
          anchors.fill: parent
          visible: root.view.length === 2 && root.view[1].visible

          // End wall at depth 2
          Rectangle {
            visible: root.view[1].end
            anchors.centerIn: parent
            width: parent.width * 0.30
            height: parent.height * 0.30
            color: viewport.endFar
          }
          // Side walls of the depth-2 corridor cell
          Rectangle {
            visible: root.view[1].left
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.20
            height: parent.height * 0.55
            color: viewport.wallFar
          }
          Rectangle {
            visible: root.view[1].right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.20
            height: parent.height * 0.55
            color: viewport.wallFar
          }
        }

        // Depth-1 slices.
        Item {
          anchors.fill: parent
          visible: root.view.length === 2 && root.view[0].visible

          Rectangle {
            visible: root.view[0].end
            anchors.centerIn: parent
            width: parent.width * 0.62
            height: parent.height * 0.62
            color: viewport.endNear
          }
          Rectangle {
            visible: root.view[0].left
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.26
            height: parent.height
            color: viewport.wallNear
          }
          Rectangle {
            visible: root.view[0].right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.26
            height: parent.height
            color: viewport.wallNear
          }
        }

        // Feature glyph centered in the view: stairs up/down or item hints.
        Text {
          anchors.centerIn: parent
          visible: root.floor.nodes[root.pos.row][root.pos.col].feature !== "none"
            || (root.view.length === 2 && root.view[0].feature !== "none")
          text: {
            var here = root.floor.nodes[root.pos.row][root.pos.col].feature
            var ahead = root.view.length === 2 ? root.view[0].feature : "none"
            var feat = (here !== "none") ? here : ahead
            if (feat === "down") return "⬇"
            if (feat === "up") return "⬆"
            return "·"
          }
          color: text === "⬇" ? "#d0b040" : Color.menu.text
          font.family: Style.font.menuFamily
          font.bold: true
          font.pixelSize: 40
        }

        // Floor number tag, top-left of the viewport.
        Text {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: 6
          text: "FLOOR " + root.floorNum
          color: Qt.darker(Color.menu.text, 1.6)
          font.family: Style.font.menuFamily
          font.pixelSize: 10
        }

        // Directional arrows: ◀ ▶ turn, ▲ ▼ step forward/back, greyed by
        // real wall state from Dungeon.hasWall.
        component Arrow: Text {
          property int dir: 0          // 0 fwd, 1 right, 2 back, 3 left
          property bool turnOnly: false
          property bool blocked: false
          font.family: Style.font.menuFamily
          font.pixelSize: 22
          color: blocked ? Qt.darker(Color.menu.text, 2.2) : Color.menu.text
          MouseArea {
            anchors.fill: parent
            enabled: !blocked
            onClicked: {
              if (parent.dir === 3) root.turn(-1)
              else if (parent.dir === 1) root.turn(1)
              else if (parent.dir === 0) root.move(0)
              else root.move(2)
            }
          }
        }

        Arrow { dir: 0; text: "▲"
          blocked: root.wallAt(0)
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top; anchors.topMargin: 8 }
        Arrow { dir: 3; text: "◀"
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left; anchors.leftMargin: 8 }
        Arrow { dir: 1; text: "▶"
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right; anchors.rightMargin: 8 }
        Arrow { dir: 2; text: "▼"
          blocked: root.wallAt(2)
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom; anchors.bottomMargin: 8 }

        // Descend button — appears when standing on the downstairs.
        Rectangle {
          visible: root.floor.nodes[root.pos.row][root.pos.col].feature === "down"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 40
          width: 120
          height: 30
          color: "#d0b040"
          border.color: Color.menu.border
          border.width: 2
          Text {
            anchors.centerIn: parent
            text: "DESCEND"
            color: "#1b1712"
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 13
          }
          MouseArea { anchors.fill: parent; onClicked: root.descend() }
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
                property bool seen: root.explored[r + "," + c] === true
                property string feat: root.floor.nodes[r][c].feature
                width: 12
                height: 12
                color: !seen ? "black"
                  : (c === root.pos.col && r === root.pos.row) ? "#e0c040"
                  : feat === "down" ? "#b09030"
                  : "#5b5548"
                border.color: Qt.darker(Color.menu.border, 1.5)
                border.width: 1
              }
            }
          }
        }
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
