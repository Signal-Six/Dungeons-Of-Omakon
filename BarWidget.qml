import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar pill for Dungeons of Omakon. Shows a tiny sword glyph plus a compact
// HP/MP ticker; left click toggles the game window (Panel.qml).
//
// Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
// requires open/close/opened on the bar-widget root), plus the popout
// identity stand-ins the bar expects of widgets that host a popup.
BarWidget {
  id: root
  moduleName: "b.omakon"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // Bar pill shows just the sword glyph until we ship a real pixel icon;
  // the HP/MP ticker lived here in Phase 1 but overlapped neighbor widgets.
  // Live character state (Phase 4) surfaces in the game window instead.
  readonly property string ticker: "†"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Panel.qml sets manageIpc: false, so this widget owns the plugin's IPC
  // target (single monitor instance handles routing; toggle is global state).
  IpcHandler {
    target: "b.omakon"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.ticker
    slotSize: Style.bar.statusSlot
    tooltipText: "Dungeons of Omakon"

    onPressed: function(b) {
      root.togglePanel()
    }
  }
}
