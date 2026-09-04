import QtQuick
import QtQuick.Window
import QtQuick.Controls

ApplicationWindow {
    id: window
    width: 640
    height: 480
    visible: true
    title: "Dungeons of Omakon"
    color: "#15131a"

    // The game scene. All game logic lives here; this file is only the
    // OS-window wrapper the standalone build adds around it.
    Loader {
        id: game
        anchors.fill: parent
        // Panel.qml was written as a plugin Panel (640x480 rectangle whose
        // root is `Item`). Loading it as a component gives us the Item
        // directly; the parent Item drives `storage` via context property.
        source: Qt.resolvedUrl("Panel.qml")
        focus: true
        onLoaded: {
            item.anchors.fill = game
        }
    }

    onClosing: function(close) {
        // Save-and-quit hook. Panel.qml's close() routes through Qt.quit(),
        // which we intercept below to make sure the last save lands before
        // the process ends.
        if (game.item && game.item.mode === "game") {
            try { game.item.saveRun() } catch (e) { console.log("onClosing save: " + e) }
        }
        close.accepted = true
    }

    Component.onCompleted: {
        // Focus the loaded scene so arrow-key movement works out of the box.
        game.forceActiveFocus()
    }
}
