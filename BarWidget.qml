import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "yooneskh.omaniclean"

  property var cleaner: null

  function bindService() {
    var shell = bar && bar.shell
    if (!shell || typeof shell.serviceFor !== "function") return
    var svc = shell.serviceFor(root.moduleName)
    if (svc) cleaner = svc
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("cleaner" in target) target.cleaner = root.cleaner
  }

  function toggle() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function togglePanel() {
    root.toggle()
  }

  function handlePress(mouseButton) {
    if (mouseButton === Qt.MiddleButton) {
      if (root.cleaner && root.cleaner.refresh) root.cleaner.refresh()
      return
    }
    if (mouseButton === Qt.LeftButton) root.togglePanel()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property bool iconDimmed: cleaner ? cleaner.dimmed === true : true
  readonly property bool showBarSize: cleaner ? cleaner.showBarSize === true : false
  readonly property string statusTip: cleaner ? String(cleaner.tooltipText || "OmaniClean") : "OmaniClean"
  readonly property string sizeLabel: cleaner ? String(cleaner.barLabel || "󰃢") : "󰃢"

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
    else if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: {
    bindService()
    injectPanel()
  }
  onSettingsChanged: injectPanel()
  onCleanerChanged: injectPanel()

  Timer {
    interval: 250
    running: root.cleaner === null
    repeat: true
    onTriggered: root.bindService()
  }

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

  Item {
    id: button
    implicitWidth: root.showBarSize ? statsButton.implicitWidth : iconButton.implicitWidth
    implicitHeight: root.showBarSize ? statsButton.implicitHeight : iconButton.implicitHeight
    width: implicitWidth
    height: implicitHeight

    BarIconButton {
      id: iconButton
      visible: !root.showBarSize
      interactive: visible
      anchors.fill: parent
      bar: root.bar
      text: "󰃢"
      dimmed: root.iconDimmed
      tooltipText: root.statusTip
      onPressed: function(mouseButton) { root.handlePress(mouseButton) }
    }

    WidgetButton {
      id: statsButton
      visible: root.showBarSize
      interactive: visible
      anchors.fill: parent
      bar: root.bar
      text: root.sizeLabel
      dimmed: root.iconDimmed
      tooltipText: root.statusTip
      onPressed: function(mouseButton) { root.handlePress(mouseButton) }
    }
  }
}
