import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import Quickshell.Io
import "Save.js" as Save

// Dungeons of Omakon — shell host (Omarchy bar plugin).
// The game scene is GameScene.qml (a host-agnostic Item: all game logic,
// tables, UI). This Panel is the shell host: bar/IPC contract, the
// PanelWindow overlay, and the keyring persistence pipeline (secret-tool via
// bash + temp file). The scene reaches the host through its `hostIo` property
// (bootRun/loadArchive/storeRun/storeArchive/clearRun/closeWindow), wired in
// the scene Loader's onLoaded.
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

  function open() {
    if (root.opened) return
    // First open boots the run (keyring lookup); the scene's bootLoad is a
    // guarded no-op until hostIo is wired, so re-trigger it here — same
    // lifecycle as pre-port (boot on open, not at shell startup).
    if (sceneLoader.item && sceneLoader.item.mode === "loading") sceneLoader.item.bootLoad()
    root.controller.show()
  }
  function toggle() { opened ? close() : open() }
  // close saves the live run before hiding — a throwing save must never block
  // the hide (2026-08-30 lesson).
  function close() { closeWindow() }

  // hostIo.closeWindow target: save if a run is live, then hide the window.
  function closeWindow() {
    if (sceneLoader.item && sceneLoader.item.mode === "game") {
      try { sceneLoader.item.saveRun() }
      catch (e) { console.log("omakon closeWindow save: " + e) }
    }
    root.controller.hide()
  }

  // ---- Keyring I/O -------------------------------------------------------------
  // secret-tool shells via bash; text goes through a temp file in
  // XDG_RUNTIME_DIR (secret-tool reads stdin to EOF).
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  property string ioTempPath: ""
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

  // Payloads are written straight to the temp file via FileView (blockWrites
  // = synchronous, atomic). No shell, no base64, no Qt string/byte encoding
  // — so there is nothing user-typed for the shell to interpolate. The bash
  // step only reads this fixed path. (Qt.stringToUtf8/base64Encode do not
  // exist in this QML runtime — a 2026-08-30 regression that made every
  // saveRun throw and froze the close path.)
  FileView {
    id: saveFile
    atomicWrites: true
    blockWrites: true
    printErrors: false
  }

  readonly property string dataDir:
    (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
    + "/omarchy/plugins/b.omakon"
  // Static data tables — read once from the plugin source dir.
  // blockLoading: the first .text() call blocks until the read completes,
  // so the scene Loader's onLoaded always sees full tables — no async race
  // between the FileView read and the scene component load. (Lives at the
  // Panel root, like the pre-port layout; the window section below just
  // hosts the scene.)
  FileView { id: monsterFile; path: root.dataDir + "/monsters.json"; blockLoading: true }
  FileView { id: equipFile;   path: root.dataDir + "/equipment.json"; blockLoading: true }
  FileView { id: spellFile;   path: root.dataDir + "/spells.json";   blockLoading: true }

  property string ioStdoutText: ""

  // Jobs wait in ioQueue; one runs at a time. die() fires an archive store
  // AND a run clear back-to-back — with the old fire-and-restart form the
  // second start() killed the first mid-write and the death entry was lost.
  // (Fixed 2026-08-30 alongside the missing-$1 root cause.)
  property var ioQueue: []

  function ioFinished(exitCode) {
    var field = ioField
    var text = ioStdoutText
    ioField = ""
    if (field === "boot_run") {
      var run = Save.parseRun(text)
      if (sceneLoader.item) {
        if (run) { sceneLoader.item.applyRun(run); sceneLoader.item.mode = "game" }
        else sceneLoader.item.mode = "menu"
      }
    } else if (field === "archive_load") {
      if (sceneLoader.item) sceneLoader.item.archive = Save.parseArchive(text)
    } else if (field === "run_save" || field === "archive_save" || field === "run_clear") {
      if (exitCode !== 0) console.log("omakon keyring " + field + " failed: exit " + exitCode)
    }
    // store/clear success paths need no handling
    ioPump()
  }

  function ioStdout(t) { ioStdoutText = t }

  function ioPump() {
    if (ioQueue.length === 0) return
    if (ioProc.running) return          // busy; onExited → ioFinished pumps
    ioStartGuarded(ioQueue.shift())
  }

  function ioStart(job) {
    if (job.kind === "boot_run") {
      ioField = "boot_run"
      ioStdoutText = ""
      ioProc.command = ["bash", "-c", Save.loadCmd("run")]
    } else if (job.kind === "archive_load") {
      ioField = "archive_load"
      ioStdoutText = ""
      ioProc.command = ["bash", "-c", Save.loadCmd("archive")]
    } else if (job.kind === "run_clear") {
      ioField = "run_clear"
      ioProc.command = ["bash", "-c", Save.clearScript("run")]
    } else if (job.kind === "store") {
      // FileView writes the payload to the temp file (synchronous — the
      // blockWrites flag makes setText block until flushed), then the
      // shell step just feeds that file to secret-tool. Nothing user-typed
      // reaches the shell: the path is generated by newTempPath() and the
      // text lives only in the file. The path rides as bash's positional
      // $1 — a bare `bash -c '<script>'` has none, which is why saves
      // silently failed since Phase 4 (fixed 2026-08-30).
      ioField = job.field + "_save"
      ioTempPath = job.tempPath
      saveFile.path = ioTempPath
      saveFile.setText(job.text)
      ioProc.command = ["bash", "-c", Save.storeScript(job.field),
        "omakon", ioTempPath]
    }
    ioProc.running = true
  }

  // Wrapper so a bad job can't jam the queue: if starting a job throws,
  // log it and pump the next one (onExited never fires for a job that
  // never started, so the queue would deadlock otherwise).
  function ioStartGuarded(job) {
    try { ioStart(job) }
    catch (e) { console.log("omakon io job failed (" + job.kind + "): " + e); ioPump() }
  }

  function bootLoad() { ioQueue.push({ kind: "boot_run" }); ioPump() }

  function loadArchive() { ioQueue.push({ kind: "archive_load" }); ioPump() }

  // hostIo entry points: the scene serializes (Save.js lives there) and hands
  // the finished text over; the host only moves bytes into the keyring.
  function storeRunText(text) {
    ioQueue.push({ kind: "store", field: "run",
                   text: text, tempPath: newTempPath() })
    ioPump()
  }

  function storeArchiveText(text) {
    ioQueue.push({ kind: "store", field: "archive",
                   text: text, tempPath: newTempPath() })
    ioPump()
  }

  function clearRun() { ioQueue.push({ kind: "run_clear" }); ioPump() }

  // ---- Window ---------------------------------------------------------------
  // The game UI (frame/viewport/HUD/popups) lives in GameScene.qml. This
  // window is only the layershell surface + keyboard-focus priming; the scene
  // fills it. The scene is built at panel creation (matching the old
  // lifecycle where the frame booted at shell startup); its Loader onLoaded
  // wires the persistence backend and loads the data tables.
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

    Loader {
      id: sceneLoader
      anchors.fill: parent
      source: "GameScene.qml"
      // Wire the persistence backend into the scene and load the data
      // tables (blockLoading FileViews — .text() is synchronous here).
      // Deliberately does NOT bootLoad: as pre-port, the run loads on the
      // first open() — the scene's frame onCompleted calls bootLoad(),
      // which no-ops while hostIo is null, and open() re-triggers it once
      // this has run.
      onLoaded: {
        item.hostIo = ({
          bootRun:      function() { root.bootLoad() },
          loadArchive:  function() { root.loadArchive() },
          storeRun:     function(t) { root.storeRunText(t) },
          storeArchive: function(t) { root.storeArchiveText(t) },
          clearRun:     function() { root.clearRun() },
          closeWindow:  function() { root.closeWindow() }
        })
        item.loadMonsters(monsterFile.text())
        item.loadEquipment(equipFile.text())
        item.loadSpells(spellFile.text())
      }
    }
  }
}
