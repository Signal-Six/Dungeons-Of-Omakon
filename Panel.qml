import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Dungeons of Omakon — game window. Phase 1: themed frame with a placeholder
// viewport; the dungeon itself arrives in Phase 3. Self-contained overlay
// (exclusive-focus poke at map time, then OnDemand) so the game, not launchers
// or other plugins, owns the screen estate while playing.
Panel {
  id: root
  moduleName: "b.omakon"
  ipcTarget: "b.omakon"
  manageIpc: false   // BarWidget.qml owns the IPC target for this plugin.

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Placeholder character sheet values (Phase 4 will bind these to the save).
  property int heroHp: 20
  property int heroHpMax: 20
  property int heroMp: 8
  property int heroMpMax: 8

  function refresh() {}

  function openFromHotkey() { root.open() }

  Keys.onEscapePressed: root.close()

  PanelWindow {
    id: win
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    implicitWidth: 640
    implicitHeight: 480

    WlrLayershell.namespace: "omarchy-omakon"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive prime at map time so Esc/clicks land in the game, then settle
    // to OnDemand so the rest of the desktop isn't pointer-starved. Same
    // pattern KeyboardPanel uses; without the prime, QML Keys handlers never
    // see input.
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

      Keys.onEscapePressed: root.close()

      // Title strip
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

      // Viewport placeholder — Phase 2/3 replaces this with the pseudo-3D
      // first-person view and directional arrows.
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

        Text {
          anchors.centerIn: parent
          text: "[ dungeon viewport ]"
          color: Qt.darker(Color.menu.text, 1.6)
          font.family: Style.font.menuFamily
          font.pixelSize: 14
        }
      }

      // HUD strip: HP / MP digital read-outs, monospace.
      Rectangle {
        id: hud
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        height: 44
        color: "transparent"
        border.color: Color.menu.border
        border.width: 2

        Row {
          anchors.centerIn: parent
          spacing: 32

          Text {
            text: "HP " + root.heroHp + "/" + root.heroHpMax
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 16
          }

          Text {
            text: "MP " + root.heroMp + "/" + root.heroMpMax
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 16
          }
        }
      }
    }
  }
}
