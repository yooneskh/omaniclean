import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "yooneskh.omaniclean"
  ipcTarget: "yooneskh.omaniclean"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var cleaner: null
  property bool openedFromHotkey: false

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"

  readonly property var taskList: cleaner && cleaner.visibleTasks ? cleaner.visibleTasks : []
  readonly property int taskCount: taskList.length
  readonly property bool hasUserTasks: cleaner && cleaner.userTasks ? cleaner.userTasks.length > 0 : false
  readonly property bool scanning: cleaner ? cleaner.scanning === true : false
  readonly property bool cleaning: cleaner ? cleaner.cleaning === true : false
  readonly property string lastError: cleaner ? String(cleaner.lastError || "") : ""
  readonly property string lastFreedLabel: cleaner ? String(cleaner.lastFreedLabel || "") : ""

  property string focusSection: "refresh"
  property int taskIndex: 0
  property bool cursorActive: false
  property bool confirmOpen: false
  property string pendingCleanId: ""
  property bool pendingCleanAll: false
  property double nowMs: Date.now()

  readonly property var selectedTask: {
    if (taskList.length === 0) return null
    return taskList[Math.max(0, Math.min(taskIndex, taskList.length - 1))]
  }

  function bindService() {
    var shell = bar && bar.shell
    if (!shell || typeof shell.serviceFor !== "function") return
    var svc = shell.serviceFor(root.moduleName)
    if (svc) cleaner = svc
  }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    bindService()
    if (cleaner && cleaner.refresh) cleaner.refresh()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    bindService()
    if (cleaner && cleaner.refresh) cleaner.refresh()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (confirmOpen) cancelConfirm()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function clampCursor() {
    if (taskList.length === 0) {
      focusSection = "refresh"
      taskIndex = 0
      return
    }
    if (taskIndex >= taskList.length) taskIndex = taskList.length - 1
    if (taskIndex < 0) taskIndex = 0
    if (focusSection !== "refresh" && focusSection !== "tasks" && focusSection !== "all")
      focusSection = "tasks"
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (confirmOpen) {
      if (dx !== 0) confirmDialog.selectedIndex = confirmDialog.selectedIndex === 0 ? 1 : 0
      return
    }
    clampCursor()
    if (dy === 0) return
    if (focusSection === "refresh") {
      if (dy > 0) {
        if (taskList.length > 0) {
          focusSection = "tasks"
          taskIndex = 0
        } else if (root.hasUserTasks) {
          focusSection = "all"
        }
      }
    } else if (focusSection === "tasks") {
      if (dy < 0) {
        if (taskIndex > 0) taskIndex--
        else focusSection = "refresh"
      } else if (taskIndex < taskList.length - 1) {
        taskIndex++
      } else if (root.hasUserTasks) {
        focusSection = "all"
      }
    } else if (focusSection === "all") {
      if (dy < 0) {
        if (taskList.length > 0) {
          focusSection = "tasks"
          taskIndex = taskList.length - 1
        } else {
          focusSection = "refresh"
        }
      }
    }
    scrollCursorIntoView()
  }

  function activateCursor() {
    if (confirmOpen) {
      if (confirmDialog.selectedIndex === 0) cancelConfirm()
      else runConfirm()
      return
    }
    cursorActive = true
    if (focusSection === "refresh") {
      if (cleaner) cleaner.refresh()
      return
    }
    if (focusSection === "all") {
      requestCleanAll()
      return
    }
    requestClean(selectedTask)
  }

  function scrollCursorIntoView() {
    if (!panelFlick) return
    var item = null
    if (focusSection === "refresh") item = hero
    else if (focusSection === "all") item = allRow
    else if (taskRepeater && taskRepeater.itemAt) item = taskRepeater.itemAt(taskIndex)
    if (!item) return
    Qt.callLater(function() {
      if (!item || !panelFlick) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin)
        panelFlick.contentY = Math.min(Math.max(0, panelFlick.contentHeight - panelFlick.height), bottom - panelFlick.height + margin)
    })
  }

  function requestClean(task) {
    if (!task || root.cleaning) return
    pendingCleanId = String(task.id)
    pendingCleanAll = false
    confirmDialog.selectedIndex = 1
    confirmOpen = true
  }

  function requestCleanAll() {
    if (!root.hasUserTasks || root.cleaning) return
    pendingCleanId = ""
    pendingCleanAll = true
    confirmDialog.selectedIndex = 1
    confirmOpen = true
  }

  function cancelConfirm() {
    confirmOpen = false
    pendingCleanId = ""
    pendingCleanAll = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function runConfirm() {
    var all = pendingCleanAll
    var id = pendingCleanId
    cancelConfirm()
    if (!cleaner) return
    if (all) cleaner.cleanAllUser()
    else if (id !== "") cleaner.clean(id)
  }

  function handleTextKey(text) {
    if (confirmOpen) return
    var t = String(text || "")
    if (t === "r" || t === "R") {
      if (cleaner) cleaner.refresh()
    } else if (t === "a" || t === "A") {
      requestCleanAll()
    }
  }

  readonly property string confirmText: {
    if (pendingCleanAll) return Model.confirmAllMessage(taskList)
    return Model.confirmMessage(Model.findTask(taskList, pendingCleanId) || selectedTask)
  }

  readonly property string heroMetaText: Model.heroMeta(taskList, cleaner ? cleaner.scannedAt : 0, root.nowMs, root.scanning, root.lastFreedLabel)

  Timer {
    interval: 250
    running: root.cleaner === null
    repeat: true
    onTriggered: root.bindService()
  }

  Timer {
    interval: 15000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  onBarChanged: bindService()
  onTaskCountChanged: clampCursor()
  onOpenedChanged: if (opened) {
    cursorActive = false
    clampCursor()
    bindService()
    root.nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { if (root.cleaner) root.cleaner.refresh() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: false
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: {
        if (root.confirmOpen) root.cancelConfirm()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { root.handleTextKey(t) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "OmaniClean"
            meta: root.heroMetaText
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display
                Text {
                  anchors.centerIn: parent
                  text: "󰃢"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: root.scanning ? "Scanning…" : "Refresh"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.scanning && !root.cleaning
                hasCursor: root.cursorActive && !root.confirmOpen && root.focusSection === "refresh"
                onHovered: function(on) {
                  if (!on) return
                  root.cursorActive = true
                  root.focusSection = "refresh"
                }
                onClicked: if (root.cleaner) root.cleaner.refresh()
              }
            }
          }

          Text {
            visible: root.lastError !== ""
            width: parent.width
            text: root.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.taskCount === 0 && !root.scanning
            width: parent.width
            text: "Nothing worth cleaning right now."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.taskCount === 0 && root.scanning
            width: parent.width
            text: "Looking for reclaimable caches…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.taskCount > 0
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              id: taskRepeater
              model: root.taskList

              TaskRow {
                required property var modelData
                required property int index
                width: parent.width
                task: modelData
                rowIndex: index
              }
            }
          }

          CursorSurface {
            id: allRow
            visible: root.hasUserTasks
            width: parent.width
            implicitHeight: allBody.implicitHeight + Style.spacing.xl
            hasCursor: root.cursorActive && !root.confirmOpen && root.focusSection === "all"
            foreground: root.foreground
            fill: root.hoverFill

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: {
                root.cursorActive = true
                root.focusSection = "all"
              }
              onClicked: root.requestCleanAll()
            }

            RowLayout {
              id: allBody
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Text {
                text: "Clean all user-owned"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              PanelActionButton {
                iconText: "󰃢"
                tooltipText: "Trash, thumbnails, AUR, and developer caches"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.cleaning
                onClicked: root.requestCleanAll()
              }
            }
          }
        }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        opened: root.confirmOpen
        z: 10
        message: root.confirmText
        confirmText: "Clean"
        background: Color.popups.background
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.cancelConfirm()
        onConfirmed: root.runConfirm()
      }
    }
  }

  component TaskRow: CursorSurface {
    id: taskRow
    property var task: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && !root.confirmOpen && root.focusSection === "tasks" && root.taskIndex === rowIndex
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: rowBody.implicitHeight + Style.spacing.xl

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton
      onEntered: {
        root.cursorActive = true
        root.focusSection = "tasks"
        root.taskIndex = taskRow.rowIndex
      }
      onClicked: root.requestClean(taskRow.task)
    }

    RowLayout {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: taskRow.task ? taskRow.task.icon : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        Layout.alignment: Qt.AlignVCenter
      }

      Column {
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: taskRow.task ? taskRow.task.title : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: taskRow.task ? taskRow.task.detail : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        text: taskRow.task ? Model.formatBytes(taskRow.task.bytes) : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }

      PanelActionButton {
        iconText: "󰃢"
        tooltipText: taskRow.task && taskRow.task.privilege === "pkexec" ? "Clean (needs permission)" : "Clean"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !root.cleaning
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.requestClean(taskRow.task)
      }
    }
  }
}
