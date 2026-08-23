import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import Quickshell.Io
import "Dungeon.js" as Dungeon
import "Save.js" as Save
import "Combat.js" as Combat
import "Stats.js" as Stats

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

  // ---- Phase 4: run lifecycle ----------------------------------------------
  // mode: "loading" -> "menu" (no active run) | "game" (run live) | "archive"
  //       | "newgame" (name entry) | "dead" (death screen)
  property string mode: "loading"
  property var archive: []
  property string runName: ""
  property string runStarted: ""
  property int heroLevel: 1
  property var heroStats: ({ str: 4, dex: 4, con: 4, int: 4, wil: 4, unspent: 0 })
  property string lastLevelUpToast: ""
  property var heroEffects: []
  property int heroXp: 0
  property string pendingNewName: ""

  function open() {
    if (mode === "loading") bootLoad()
    root.controller.show()
  }
  function toggle() { opened ? close() : open() }
  // Panel base provides controller; override its open-close path via
  // function shadowing so close saves.
  function close() {
    if (mode === "game") saveRun()
    root.controller.hide()
  }

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

  property string popupMode: "none"    // "none" | "spells" | "inventory" | "stats" | "alloc"
  function togglePopup(mode) {
    popupMode = (popupMode === mode) ? "none" : mode
  }

  // ---- Stats + allocation ---------------------------------------------------
  function openStatsPopup() { popupMode = "stats" }
  function grantXp(xp, sourceLabel) {
    var out = Stats.addXp(heroStats, { level: heroLevel, xp: heroXp }, xp)
    heroXp = out.xp
    heroLevel = out.level
    heroStats = out.stats
    heroHpMax = Stats.hpMax(heroStats, heroLevel)
    heroMpMax = Stats.mpMax(heroStats, heroLevel)
    if (out.levelsGained > 0) {
      lastLevelUpToast = "LEVEL UP → " + out.level + " (+" + out.levelsGained + ")"
      popupMode = "alloc"
    }
  }
  function assignStat(stat) {
    heroStats = Stats.assignPoint(heroStats, stat)
    heroHpMax = Stats.hpMax(heroStats, heroLevel)
    heroMpMax = Stats.mpMax(heroStats, heroLevel)
  }
  // Combat hooks read the primary stats via combatState().

  // Build the state object Combat.attack() expects — this is the seam that
  // Phase 5's HUD buttons and Phase 6's status effects will feed through.
  function combatState() {
    return {
      str: heroStats.str || 0, dex: heroStats.dex || 0, int: heroStats.int || 0,
      wil: heroStats.wil || 0,
      rightHand: rightHand, leftHand: leftHand,
      worn: [], effects: heroEffects
    }
  }
  // Attack a monster { dv: int, ... }. Returns Combat.attack's result
  // without applying HP — the combat loop (Phase 5) owns that.
  function attackMonster(monster) { return Combat.attack(combatState(), monster) }

  // ---- Floor state (persisted via Save.js / keyring) -----------------------
  property bool automapOn: true
  property int floorNum: 1
  property int floorSeed: ((Math.random() * 0x7fffffff) | 0)
  property bool descending: false       // true while dissolve anim runs
  property var floor: Dungeon.generate(floorSeed)
  property var pos: ({ row: floor.start.row, col: floor.start.col, facing: 0 })

  function beginDescend() {
    if (floor.nodes[pos.row][pos.col].feature !== "down" || descending) return
    descending = true               // dissolve layer activates; step resets there
  }

  function completeDescend() {
    floorNum++
    floorSeed = (Math.random() * 0x7fffffff) | 0
    floor = Dungeon.generate(floorSeed)
    pos = ({ row: floor.start.row, col: floor.start.col, facing: 0 })
    explored = ({})
    markExplored(pos.row, pos.col)
    descending = false
    saveRun()
  }

  // ---- Keyring I/O -------------------------------------------------------------
  // secret-tool shells via bash; text goes through a temp file in
  // XDG_RUNTIME_DIR (secret-tool reads stdin to EOF).
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  property string ioTempPath: ""
  property string ioText: ""
  property string ioField: ""

  function newTempPath() {
    return runtimeDir + "/omakon-"
      + Date.now().toString(36) + "-"
      + Math.floor(Math.random() * 0x100000000).toString(36) + ".json"
  }

  Process {
    id: ioProc
    onExited: function(exitCode) { root.ioFinished(exitCode) }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ioStdout(String(text || ""))
    }
  }

  property string ioStdoutText: ""

  function ioFinished(exitCode) {
    if (ioField === "boot_run") {
      var run = Save.parseRun(ioStdoutText)
      if (run) { applyRun(run); mode = "game" }
      else mode = "menu"
      ioField = ""
    } else if (ioField === "archive_load") {
      archive = Save.parseArchive(ioStdoutText)
      ioField = ""
    }
    // saves have no completion handling needs
  }

  function ioStdout(t) { ioStdoutText = t }

  function bootLoad() {
    ioField = "boot_run"
    ioStdoutText = ""
    ioProc.command = ["bash", "-c", Save.loadCmd("run")]
    ioProc.running = true
  }

  function loadArchive() {
    ioField = "archive_load"
    ioStdoutText = ""
    ioProc.command = ["bash", "-c", Save.loadCmd("archive")]
    ioProc.running = true
  }

  function saveRun() {
    if (mode !== "game") return
    var state = currentState()
    var text = Save.serializeRun(state)
    ioText = text
    ioTempPath = newTempPath()
    ioField = "run_save"
    ioProc.command = ["bash", "-c",
      "printf '%s' " + JSON.stringify(text) + " > " + ioTempPath + " && "
      + Save.storeScript("run")]
    ioProc.running = true
  }

  function saveArchiveEntry(entry) {
    var a = Save.appendArchive(archive, entry)
    archive = a
    var text = JSON.stringify(a)
    ioTempPath = newTempPath()
    ioField = "archive_save"
    ioProc.command = ["bash", "-c",
      "printf '%s' " + JSON.stringify(text) + " > " + ioTempPath + " && "
      + Save.storeScript("archive")]
    ioProc.running = true
  }

  function currentState() {
    return {
      name: runName, started: runStarted,
      hp: heroHp, hpMax: heroHpMax, mp: heroMp, mpMax: heroMpMax,
      level: heroLevel, xp: heroXp,
      stats: heroStats,
      leftHand: leftHand, rightHand: rightHand,
      pack: pack, spells: spells, effects: heroEffects,
      floorNum: floorNum, seed: floorSeed,
      pos: pos, explored: explored
    }
  }

  function applyRun(run) {
    runName = run.name || "Hero"
    runStarted = run.started || ""
    heroHp = run.hp; heroHpMax = run.hpMax
    heroMp = run.mp; heroMpMax = run.mpMax
    heroLevel = run.level || 1; heroXp = run.xp || 0
    heroStats = run.stats || Stats.freshStats()
    heroEffects = run.effects || []
    leftHand = run.leftHand || null
    rightHand = run.rightHand || ({ icon: "†", name: "Rusty Sword" })
    pack = run.pack || (new Array(12)).fill(null)
    spells = run.spells || []
    floorNum = run.floorNum || 1
    floorSeed = run.seed
    floor = Dungeon.generate(floorSeed)
    pos = run.pos || ({ row: floor.start.row, col: floor.start.col, facing: 0 })
    explored = run.explored || ({})
    markExplored(pos.row, pos.col)
  }

  // ---- Run lifecycle transitions ----------------------------------------------
  function startNewGame() { mode = "newgame"; pendingNewName = "" }

  function confirmNewGame(name) {
    name = ("" + name).trim(); if (name === "") return
    runName = name
    runStarted = Qt.formatDate(new Date(), "yyyy-MM-dd")
    heroHp = 25; heroHpMax = 25; heroMp = 15; heroMpMax = 15
    heroLevel = 1; heroXp = 0
    heroStats = Stats.freshStats()
    leftHand = null
    rightHand = ({ icon: "†", name: "Rusty Sword" })
    pack = (new Array(12)).fill(null)
    spells = []
    floorNum = 1
    floorSeed = (Math.random() * 0x7fffffff) | 0
    floor = Dungeon.generate(floorSeed)
    pos = ({ row: floor.start.row, col: floor.start.col, facing: 0 })
    explored = ({})
    markExplored(pos.row, pos.col)
    mode = "game"
    saveRun()
  }

  function showArchive() { loadArchive(); mode = "archive" }

  function die() {
    // Permadeath: archive the run, clear the active run, bump to menu.
    saveArchiveEntry({
      name: runName, started: runStarted,
      floor: floorNum, level: heroLevel,
      score: Save.computeScore(currentState())
    })
    ioField = "run_clear"
    ioProc.command = ["bash", "-c", Save.clearScript("run")]
    ioProc.running = true
    mode = "dead"
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

  readonly property var view: floor ? Dungeon.vista(floor, pos) : []
  function wallAt(rel) { return Dungeon.hasWall(floor, pos.row, pos.col, (pos.facing + rel + 4) % 4) }
  // Wall on the FAR edge of the side cell at relative direction rel (0 =
  // forward edge of that side cell, etc.). Used to decide whether an open
  // side passage has a visible back wall to draw.
  function sideWallAt(rel) {
    var d = (pos.facing + rel + 4) % 4
    var sr = pos.row + Dungeon.DR[d], sc = pos.col + Dungeon.DC[d]
    return Dungeon.hasWall(floor, sr, sc, pos.facing)
  }

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
        else if (root.mode === "menu") root.close()
        else root.close()      // close always saves in game mode
      }

      Component.onCompleted: {
        if (root.mode === "loading") root.bootLoad()
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
        visible: root.mode === "game"
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

            // face geometry at depth d (0 = current cell, 1..4): half-size of
            // the projected square face, centered. Scale series uses roughly
            // harmonic falloff (1/(d+1)) so successive cells read at even
            // visual steps; with depth-4 the farthest perceptible segment is
            // four cells away — enough to see a three-cells-away side branch
            // or a four-cells-away end wall clearly.
            var base = Math.min(W2, H2)
            var half = [base, base * 0.62, base * 0.40, base * 0.26, base * 0.17]

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
            if (v.length !== 4) return

            // Bright close → dark far (classic flashlight falloff).
            var colEnd  = ["#6e6552", "#51493c", "#3c362c", "#2a2620"]
            var colSide = ["#8a7f66", "#605847", "#453f34", "#332e27"]

            // Perception rules:
            //   * cell(d).left/right: wall on that cell's side edge → slab
            //     spanning face(d-1) -> face(d).
            //   * An OPEN side at depth d shows its side-passage mouth. The
            //     recess panel (back wall of that passage) is only drawn
            //     when the view further in that direction would otherwise
            //     leave naked background — i.e. when the slice at depth d+1
            //     is not visible or is itself open-ended on that side.
            //     When the corridor continues, the opening reads naturally
            //     from the side slabs of the continuing cells.
            //   * cell(d).end: wall on that cell's far edge → face(d).
            //   * wallAt(0): forward edge of YOUR cell is blocked → whole
            //     viewport (nose against the wall).

            // Internal-corner patches, painted FIRST so the depth loop can
            // overdraw them. When your own cell's side is open (you're
            // standing at an L-junction with a passage beside you), the side
            // slab for depth 0 is never drawn and sky/floor leaks through;
            // patch it with a full-height panel at the passage's back wall.
            if (!root.wallAt(3) && root.sideWallAt(3)) { // left open, back wall exists
              var fL = faceRect(1)
              ctx.fillStyle = colEnd[0]
              ctx.fillRect(0, fL.y, fL.x, fL.h)
            }
            if (!root.wallAt(1) && root.sideWallAt(1)) { // right open, back wall exists
              var fR = faceRect(1)
              ctx.fillStyle = colEnd[0]
              ctx.fillRect(fR.x + fR.w, fR.y, W - (fR.x + fR.w), fR.h)
            }

            for (var d = 4; d >= 1; d--) {
              var slice = v[d - 1]
              if (!slice.visible) continue

              // (1) side-passage recess: draw the open side cell's own far
              // wall (its "end" edge). Bounds: the passage mouth at this
              // depth spans face(d)'s side edge -> face(d+1)'s side edge
              // (the recess goes ONE band deeper). Bounding the near side
              // at face(d-1) instead pushes the recess one tile too close
              // and it swallows the middle column — the timing bug from the
              // last screenshot.
              if (!slice.left && slice.sideL && slice.sideL.end && d + 1 <= 4) {
                var nearL = faceRect(d), farL = faceRect(d + 1)
                ctx.fillStyle = colEnd[Math.min(d, 3)]
                ctx.fillRect(farL.x, farL.y, nearL.x - farL.x, farL.h)
              }
              if (!slice.right && slice.sideR && slice.sideR.end && d + 1 <= 4) {
                var nearR = faceRect(d), farR = faceRect(d + 1)
                ctx.fillStyle = colEnd[Math.min(d, 3)]
                ctx.fillRect(farR.x + farR.w, farR.y,
                             (nearR.x + nearR.w) - (farR.x + farR.w), farR.h)
              }

              // (2) middle side slabs
              if (slice.left) fillQuad(wallQuad(d, -1), colSide[d - 1])
              if (slice.right) fillQuad(wallQuad(d, 1), colSide[d - 1])

              // (3) middle end face — always on top within this row
              if (slice.end) fillFace(d, colEnd[d - 1])
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
            id: dissolveTimer
            interval: 16
            repeat: true
            running: root.descending
            onTriggered: {
              dissolveLayer.step += 20
              if (dissolveLayer.step >= 560) root.completeDescend()
              // completeDescend sets descending = false; the running binding
              // then evaluates to false on its own (never assign `running`
              // imperatively — it clobbers the binding and the next
              // descent's dissolve never restarts, leaving root.descending
              // stuck true, which hid the DESCEND button the second time).
            }
          }
        }
      }

      // ---- Mode overlay screens (Phase 4) -----------------------------------
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: 28
        visible: root.mode === "menu" || root.mode === "newgame"
          || root.mode === "archive" || root.mode === "dead" || root.mode === "loading"
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: 2
        z: 20

        // MENU
        Column {
          visible: root.mode === "menu"
          anchors.centerIn: parent
          spacing: 22

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "DUNGEONS OF OMAKON"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 18
          }
          Repeater {
            model: [
              { label: "NEW GAME", act: "newgame" },
              { label: "ARCHIVE", act: "archive" }
            ]
            Rectangle {
              property var m: modelData
              width: 160; height: 34
              color: Color.menu.selectedBackground
              border.color: Color.menu.border
              border.width: 2
              anchors.horizontalCenter: parent.horizontalCenter
              Text {
                anchors.centerIn: parent
                text: m.label
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.bold: true
                font.pixelSize: 13
              }
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  if (m.act === "newgame") root.startNewGame()
                  else root.showArchive()
                }
              }
            }
          }
        }

        // NEWGAME name entry
        Column {
          visible: root.mode === "newgame"
          anchors.centerIn: parent
          spacing: 14

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "NAME YOUR ADVENTURER"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 15
          }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220; height: 36
            color: Color.menu.selectedBackground
            border.color: Color.menu.border
            border.width: 2
            TextInput {
              id: nameInput
              anchors.fill: parent
              anchors.margins: 6
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: 15
              maximumLength: 18
              focus: true
              Keys.onReturnPressed: root.confirmNewGame(text)
              Keys.onEnterPressed: root.confirmNewGame(text)
            }
          }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 140; height: 32
            color: Color.menu.selectedBackground
            border.color: Color.menu.border
            border.width: 2
            Text {
              anchors.centerIn: parent
              text: "BEGIN"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.bold: true; font.pixelSize: 12
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.confirmNewGame(nameInput.text)
            }
          }
        }

        // ARCHIVE
        Column {
          visible: root.mode === "archive"
          anchors.fill: parent
          anchors.margins: 16
          spacing: 6

          Text {
            text: "FALLEN HEROES"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true; font.pixelSize: 14
          }
          Rectangle { height: 1; width: parent.width; color: Color.menu.border }
          Repeater {
            model: root.archive
            Row {
              property var e: modelData
              spacing: 16
              Text { text: e.name; color: Color.menu.text
                     font.family: Style.font.menuFamily; font.pixelSize: 12; width: 120 }
              Text { text: e.started || ""; color: Qt.darker(Color.menu.text, 1.4)
                     font.family: Style.font.menuFamily; font.pixelSize: 11; width: 90 }
              Text { text: "FLOOR " + e.floor; color: "#b09030"
                     font.family: Style.font.menuFamily; font.pixelSize: 12; width: 70 }
              Text { text: "LVL " + e.level; color: Color.menu.text
                     font.family: Style.font.menuFamily; font.pixelSize: 12; width: 60 }
              Text { text: "SCORE " + e.score; color: Color.menu.text
                     font.family: Style.font.menuFamily; font.pixelSize: 12 }
            }
          }
          Text {
            visible: root.archive.length === 0
            text: "— no fallen heroes yet —"
            color: Qt.darker(Color.menu.text, 1.8)
            font.family: Style.font.menuFamily; font.pixelSize: 11
          }
          Rectangle {
            width: 120; height: 28
            color: Color.menu.selectedBackground
            border.color: Color.menu.border
            border.width: 2
            Text { anchors.centerIn: parent; text: "BACK"
                   color: Color.menu.text; font.family: Style.font.menuFamily
                   font.bold: true; font.pixelSize: 11 }
            MouseArea { anchors.fill: parent; onClicked: root.mode = "menu" }
          }
        }

        // DEAD
        Column {
          visible: root.mode === "dead"
          anchors.centerIn: parent
          spacing: 18

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "YOU HAVE FALLEN"
            color: "#a55555"
            font.family: Style.font.menuFamily
            font.bold: true; font.pixelSize: 20
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.runName + " of Floor " + root.floorNum
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: 13
          }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 170; height: 34
            color: Color.menu.selectedBackground
            border.color: Color.menu.border
            border.width: 2
            Text { anchors.centerIn: parent; text: "RETURN TO MENU"
                   color: Color.menu.text; font.family: Style.font.menuFamily
                   font.bold: true; font.pixelSize: 12 }
            MouseArea { anchors.fill: parent; onClicked: root.mode = "menu" }
          }
        }

        // LOADING
        Text {
          visible: root.mode === "loading"
          anchors.centerIn: parent
          text: "awakening the dungeon…"
          color: Qt.darker(Color.menu.text, 1.6)
          font.family: Style.font.menuFamily; font.pixelSize: 13
        }
      }

      Rectangle {
        id: hud
        visible: root.mode === "game"
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

          // STATS — opens the character-sheet popup (heart icon per request).
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: root.popupMode === "stats" ? Color.menu.selectedBackground : "transparent"
              border.color: Color.menu.border
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: "♥"
                color: root.popupMode === "stats" ? Color.menu.text : Qt.darker(Color.menu.text, 2.0)
                font.family: Style.font.menuFamily
                font.pixelSize: 18
              }
              MouseArea { anchors.fill: parent; onClicked: root.togglePopup("stats") }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "STATS"
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

        // ---- Stats popup (STATS button) — read-only view ------------------------
        Rectangle {
          visible: root.popupMode === "stats"
          anchors.bottom: parent.top
          anchors.right: parent.right
          anchors.bottomMargin: 4
          width: 260
          height: 250
          color: Color.menu.background
          border.color: Color.menu.border
          border.width: 2
          z: 10
          Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            Text { text: "CHARACTER SHEET"; font.bold: true; font.pixelSize: 12
              font.family: Style.font.menuFamily; color: Color.menu.text }
            Rectangle { width: parent.width; height: 1; color: Color.menu.border }

            Text { text: "LVL " + root.heroLevel + "  " + root.runName; font.pixelSize: 11
              font.family: Style.font.menuFamily; color: Color.menu.text }
            Text { text: "HP " + root.heroHp + "/" + root.heroHpMax
                   + "    MP " + root.heroMp + "/" + root.heroMpMax
              font.pixelSize: 11; font.family: Style.font.menuFamily; color: Color.menu.text }

            // EXP bar, e.g. EXP [|||||  ] 75/100
            Text { text: "EXP"; font.pixelSize: 10; font.family: Style.font.menuFamily;
              color: Qt.darker(Color.menu.text, 1.6) }
            Rectangle {
              width: parent.width; height: 12
              color: "transparent"; border.color: Color.menu.border; border.width: 1
              Rectangle {
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: (parent.width * Math.min(1, (root.heroXp % 100) / 100)) - 2
                color: "#b09030"
              }
              Text {
                anchors.centerIn: parent
                text: (root.heroXp % 100) + "/100"
                font.pixelSize: 9; font.family: Style.font.menuFamily
                color: Color.menu.text
              }
            }

            Repeater {
              model: [
                { k: "str", label: "STR" }, { k: "dex", label: "DEX" },
                { k: "con", label: "CON" }, { k: "int", label: "INT" },
                { k: "wil", label: "WIL" }
              ]
              Text {
                property var s: modelData
                text: s.label + "  " + ((root.heroStats && root.heroStats[s.k]) || 0)
                font.pixelSize: 12; font.family: Style.font.menuFamily; color: Color.menu.text
              }
            }
          }
        }

        // ---- ALLOC modal — level up: pick one stat to bump ----------------------
        Rectangle {
          visible: root.popupMode === "alloc"
          anchors.centerIn: parent
          width: 240
          height: 220
          color: Color.menu.background
          border.color: Color.menu.border
          border.width: 2
          z: 20
          Column {
            anchors.fill: parent; anchors.margins: 12; spacing: 6

            Text {
              text: "LEVEL UP — " + root.lastLevelUpToast
              font.bold: true; font.pixelSize: 12
              font.family: Style.font.menuFamily; color: "#b09030"
            }
            Text { text: "Confirm a +1 to one stat:"; font.pixelSize: 10
              font.family: Style.font.menuFamily; color: Qt.darker(Color.menu.text, 1.5) }

            Repeater {
              model: [
                { k: "str", label: "STR" }, { k: "dex", label: "DEX" },
                { k: "con", label: "CON" }, { k: "int", label: "INT" },
                { k: "wil", label: "WIL" }
              ]
              Rectangle {
                property var s: modelData
                width: parent.width; height: 24
                color: Color.menu.selectedBackground
                border.color: Color.menu.border; border.width: 1
                Row {
                  anchors.fill: parent; anchors.margins: 4; spacing: 8
                  Text { text: s.label + "  " + ((root.heroStats && root.heroStats[s.k]) || 0)
                    font.pixelSize: 11; font.family: Style.font.menuFamily; color: Color.menu.text }
                  Rectangle {
                    width: 22; height: 16
                    color: "#d0b040"
                    Text { anchors.centerIn: parent; text: "+"; color: "#1b1712"
                      font.bold: true; font.pixelSize: 11 }
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    root.assignStat(s.k)
                    if ((root.heroStats && root.heroStats.unspent || 0) <= 0) root.popupMode = "none"
                  }
                }
              }
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
