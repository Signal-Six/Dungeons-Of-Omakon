import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "Save.js" as Save

// Standalone desktop host. The game scene (GameScene.qml, staged next to this
// file into the qrc at build time) is host-agnostic: this window supplies the
// OS chrome and hands the scene a `hostIo` persistence backend backed by the
// FileStorage C++ context property (see main.cpp).
ApplicationWindow {
    id: window
    width: 640
    height: 480
    visible: true
    title: "Dungeons of Omakon"
    color: "#15131a"

    // The game scene. Fills the window; onLoaded wires the persistence
    // backend, loads the bundled data tables, and boots the run.
    Loader {
        id: game
        anchors.fill: parent
        source: "GameScene.qml"
        onLoaded: {
            item.hostIo = ({
                bootRun:      function() {
                    var run = Save.parseRun(storage.readRun())
                    if (run) { item.applyRun(run); item.mode = "game" }
                    else item.mode = "menu"
                },
                loadArchive:  function() {
                    item.archive = Save.parseArchive(storage.readArchive())
                },
                storeRun:     function(t) {
                    if (!storage.writeRun(t)) console.log("omakon run save failed")
                },
                storeArchive: function(t) {
                    if (!storage.writeArchive(t)) console.log("omakon archive save failed")
                },
                clearRun:     function() { storage.clearRun() },
                closeWindow:  function() { Qt.quit() }
            })
            item.loadMonsters(storage.readResource("qrc:/qt/qml/Omakon/data/monsters.json"))
            item.loadEquipment(storage.readResource("qrc:/qt/qml/Omakon/data/equipment.json"))
            item.loadSpells(storage.readResource("qrc:/qt/qml/Omakon/data/spells.json"))
            item.bootLoad()
        }
    }

    // Save-and-quit: the scene's close paths route through
    // hostIo.closeWindow() -> Qt.quit(); intercept the window close so the
    // last save lands before the process ends.
    onClosing: function(close) {
        if (game.item && game.item.mode === "game") {
            try { game.item.saveRun() } catch (e) { console.log("onClosing save: " + e) }
        }
        close.accepted = true
    }

    Component.onCompleted: {
        // Focus the loaded scene so arrow-key movement works out of the box.
        if (game.item) game.forceActiveFocus()
    }
}
