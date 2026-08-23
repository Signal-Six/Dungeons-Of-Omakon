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
  property bool descending: false       // true while dissolve anim runs
  property var floor: Dungeon.generate((Math.random() * 0x7fffffff) | 0)
  property var pos: ({ row: floor.start.row, col: floor.start.col, facing: 0 })

  function beginDescend() {
    if (floor.nodes[pos.row][pos.col].feature !== "down" || descending) return
    descending = true               // dissolve layer activates; step resets there
  }

  function completeDescend() {
    floorNum++
    floor = Dungeon.generate((Math.random() * 0x7fffffff) | 0)
    pos = ({ row: floor.start.row, col: floor.start.col, facing: 0 })
    explored = ({})
    markExplored(pos.row, pos.col)
    descending = false
  }

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

  property var view: pos ? Dungeon.vista(floor, pos) : []
  function wallAt(rel) { return Dungeon.hasWall(floor, pos.row, pos.col, (pos.facing + rel + 4) % 4) }

  function move(dir) {
    var np = Dungeon.move(floor, pos, dir)
    if (np.row !== pos.row || np.col !== pos.col) {
      pos = np
      markExplored(np.row, np.col)
    }
    debugVista()
  }
  function turn(rel) { pos = Dungeon.turn(pos, rel); debugVista() }

  // Dev trace: dumps the current cell, facing, and vista flags so on-screen
  // renders can be cross-checked against the maze data (journalctl).
  function debugVista() {
    var v = Dungeon.vista(floor, pos)
    console.log("omakon pos=" + pos.row + "," + pos.col + " face=" + pos.facing
      + " wallAt0=" + wallAt(0) + " vista=" + JSON.stringify(v))
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

        // Pseudo-3D cell-forward renderer. The view is composed of trapezoid
        // wall Ungl panels whose footprints match the perspective of a
        // 2-node-deep corridor; panels only render where the maze data says
        // there is a wall, so what you see IS the floor plan.
        //
        // Geometry: forward cell face = full viewport. Depth-1 end wall is a
        // centered rect 0.62w x 0.62h covering 0.19->0.81 on both axes. The
        // depth-1 side corridors (when that cell's left/right is OPEN) show
        // through the strips left/right of the end rect; when closed, side
        // wall trapezoids fill frame->end edges. Same construction repeats
        // between the end rect (0.62) and depth-2 rect (0.30).
        Canvas {
          id: scene3d
          anchors.fill: parent

          onPaint: {
            var ctx = getContext("2d")
            var W = width, H = height
            // Canvas persists between paints — clear fully first or old wall
            // slices linger and smear over the new frame.
            ctx.clearRect(0, 0, W, H)
            var W2 = W / 2, H2 = H / 2

            // face geometry at depth d (0 = current cell, 1..3): half-size of
            // the projected square face, centered. Depth 0 is the FULL
            // viewport (not a centered square) so side-wall quads anchor to
            // the real screen edges — otherwise uncovered sky/floor gutters
            // at the left/right edges read as open corridors you can walk
            // into (the "false walls" report).
            var base = Math.min(W2, H2)
            var half = [base * 1.0, base * 0.62, base * 0.38, base * 0.22]

            function faceRect(d) {
              if (d === 0) return { x: 0, y: 0, w: W, h: H }
              return { x: W2 - half[d], y: H2 - half[d], w: half[d] * 2, h: half[d] * 2 }
            }

            function wallQuad(d, side) { // side: -1 left, +1 right; d = cell depth
              var outer = faceRect(d - 1), inner = faceRect(d)
              if (side < 0)
                return [ [outer.x, outer.y], [inner.x, inner.y],
                         [inner.x, inner.y + inner.h], [outer.x, outer.y + outer.h] ]
              return [ [outer.x + outer.w, outer.y], [inner.x + inner.w, inner.y],
                       [inner.x + inner.w, inner.y + inner.h], [outer.x + outer.w, outer.y + outer.h] ]
            }

            function fillQuad(pts, color) {
              ctx.beginPath()
              ctx.moveTo(pts[0][0], pts[0][1])
              for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1])
              ctx.closePath()
              ctx.fillStyle = color
              ctx.fill()
            }
            function fillFace(d, color) {
              var r = faceRect(d)
              ctx.fillStyle = color
              ctx.fillRect(r.x, r.y, r.w, r.h)
            }

            var v = root.view
            if (v.length !== 3) return

            var colEnd = ["#6e6552", "#46413a", "#2c2822"]   // brightness falls off
            var colSide = ["#8a7f66", "#565045", "#38342c"]

            // Far-to-near: depth-3, then 2, then 1.
            //
            // Geometry: cell(d)'s side walls span face(d-1) -> face(d)
            // (correct corridor slabs). The end wall ON cell(d) is the wall
            // at that cell's far side — drawn at face(d) (d cells away).
            // SEPARATELY: if the forward edge of the cell you're standing in
            // is closed (wallAt(0)), you're nose-against-wall — paint the
            // full viewport as the wall face. These are distinct states;
            // conflating them caused both the "false walls" and the
            // "whole-screen tan" artefacts.
            for (var d = 3; d >= 1; d--) {
              var slice = v[d - 1]
              if (!slice.visible) continue
              if (slice.left) fillQuad(wallQuad(d, -1), colSide[d - 1])
              if (slice.right) fillQuad(wallQuad(d, 1), colSide[d - 1])
              if (slice.end) fillFace(d, colEnd[d - 1])

              // Side opening: when a side edge of cell(d) is open, the slab
              // is skipped, which otherwise leaves naked sky/floor — a "gap"
              // that looks like exposed void instead of a passage. Fill the
              // recess with the side-passage's back wall: a solid panel one
              // face deeper (d+1), covering the region beyond face(d)'s side
              // edge within face(d+1)'s vertical extent.
              if (!slice.left && d + 1 <= 3) {
                var inner = faceRect(d + 1)
                var outer = faceRect(d)
                ctx.fillStyle = colEnd[Math.min(d, 2)]
                ctx.fillRect(inner.x, inner.y, outer.x - inner.x, inner.h)
              }
              if (!slice.right && d + 1 <= 3) {
                var inR = faceRect(d + 1)
                var outR = faceRect(d)
                ctx.fillStyle = colEnd[Math.min(d, 2)]
                ctx.fillRect(inR.x + inR.w, inR.y,
                             (outR.x + outR.w) - (inR.x + inR.w), inR.h)
              }
            }
            if (root.wallAt(0)) fillFace(0, colEnd[0])
          }

          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          // root.pos gets a new object identity on every move/turn (unlike
          // `view`, a readonly computed var whose binding never notifies),
          // so this reliably repaints the scene each step.
          property var repaintKey: root.pos
          onRepaintKeyChanged: requestPaint()
          Component.onCompleted: requestPaint()
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

        // Stairs-down glyph when standing on (or directly facing) the
        // downstairs node. No ascent glyph: there is no going back up.
        Text {
          anchors.centerIn: parent
          visible: {
            if (root.floor.nodes[root.pos.row][root.pos.col].feature === "down") return true
            return root.view.length === 2 && root.view[0].feature === "down" && !root.view[0].end
          }
          text: "⬇"
          color: "#d0b040"
          font.family: Style.font.menuFamily
          font.bold: true
          font.pixelSize: 40
        }

        // Directional arrows: ◀ ▶ turn, ▲ ▼ step forward/back, greyed by
        // real wall state from Dungeon.hasWall.
        component Arrow: Text {
          property int dir: 0          // 0 fwd, 1 right, 2 back, 3 left
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
          id: descendBtn
          visible: root.floor.nodes[root.pos.row][root.pos.col].feature === "down"
            && !root.descending
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
          MouseArea { anchors.fill: parent; onClicked: root.beginDescend() }
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
              Item {
                property int c: index % 7
                property int r: Math.floor(index / 7)
                property bool seen: root.explored[r + "," + c] === true
                property bool hero: c === root.pos.col && r === root.pos.row
                property string feat: root.floor.nodes[r][c].feature
                width: 12
                height: 12

                Rectangle {
                  anchors.fill: parent  // the node's floor tile
                  color: !seen ? "black"
                    : hero ? "#e0c040"
                    : feat === "down" ? "#b09030"
                    : "#5b5548"
                  border.color: Qt.darker(Color.menu.border, 1.5)
                  border.width: 1
                }
                // Per-edge wall lines, overlaid on the tile so the automap
                // doubles as a debugging truth table for the 3D render.
                Rectangle { // N
                  visible: seen && root.floor.nodes[r][c].n
                  anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                  height: 2; color: "#f0e0c0"
                }
                Rectangle { // E
                  visible: seen && root.floor.nodes[r][c].e
                  anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom
                  width: 2; color: "#f0e0c0"
                }
                Rectangle { // S
                  visible: seen && root.floor.nodes[r][c].s
                  anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                  height: 2; color: "#f0e0c0"
                }
                Rectangle { // W
                  visible: seen && root.floor.nodes[r][c].w
                  anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom
                  width: 2; color: "#f0e0c0"
                }
                // Facing arrow over the hero tile.
                Text {
                  anchors.centerIn: parent
                  visible: hero
                  text: ["▲", "▶", "▼", "◀"][root.pos.facing]
                  color: "#1b1712"
                  font.family: Style.font.menuFamily
                  font.bold: true
                  font.pixelSize: 9
                }
              }
            }
          }
        }
        // ---- Pixel-dissolve transition into the next floor -------------------
        // Active while root.descending: a 26x20 grid of black pixels whose
        // opacity animates 0 -> 1 in pseudo-random order over ~500ms, the
        // floor state swaps at full dissolve, then the pixels fade back out.
        Item {
          id: dissolveLayer
          anchors.fill: parent
          visible: root.descending
          onVisibleChanged: if (visible) step = 0

          property int step: 0
          readonly property int cells: 26 * 20

          Repeater {
            model: dissolveLayer.visible ? dissolveLayer.cells : 0
            Rectangle {
              property int cx: index % 26
              property int cy: Math.floor(index / 26)
              // Stable pseudo-random order key per cell.
              property real ord: ((index * 137 + Math.floor(index / 7) * 61) % 521) / 521.0
              x: cx * (dissolveLayer.width / 26)
              y: cy * (dissolveLayer.height / 20)
              width: Math.ceil(dissolveLayer.width / 26) + 1
              height: Math.ceil(dissolveLayer.height / 20) + 1
              color: "#05060a"
              opacity: (dissolveLayer.step - ord * 520) > 0 ? 1 : 0
            }
          }

          Timer {
            interval: 16
            repeat: true
            running: root.descending
            onTriggered: {
              dissolveLayer.step += 20
              if (dissolveLayer.step >= 560) {
                running = false
                root.completeDescend()
                fadeOut.start()
              }
            }
          }
          // Brief fade-out after the swap: drop the layer via a frame delay.
          Timer {
            id: fadeOut
            interval: 32
            onTriggered: { /* root.descending cleared in completeDescend */ }
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
