import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: "yooneskh.omaniclean"
  readonly property string home: Quickshell.env("HOME")
  readonly property string cacheDir: {
    var value = Quickshell.env("XDG_CACHE_HOME")
    return value && String(value) !== "" ? String(value) : root.home + "/.cache"
  }
  readonly property string dataDir: {
    var value = Quickshell.env("XDG_DATA_HOME")
    return value && String(value) !== "" ? String(value) : root.home + "/.local/share"
  }
  readonly property var dirs: Model.dirsFrom(root.home, root.cacheDir, root.dataDir)

  property var tasks: []
  property double scannedAt: 0
  property bool scanning: false
  property bool cleaning: false
  property bool wantRescan: false
  property string lastError: ""
  property string lastFreedLabel: ""
  property var pendingFreedIds: []
  property double pendingFreedBytes: 0
  property var privQueue: []

  readonly property var visibleTasks: Model.visibleTasks(tasks)
  readonly property var userTasks: Model.userOwnedTasks(tasks)
  readonly property bool dimmed: visibleTasks.length === 0
  readonly property bool showBarSize: Model.showBarSize(tasks)
  readonly property string barLabel: Model.barLabel(tasks)
  readonly property string tooltipText: Model.tooltipText(tasks)
  readonly property bool busy: scanning || cleaning || scanProc.running || cleanProc.running
  readonly property string scanPath: resolvedPath("scan.sh")

  function resolvedPath(name) {
    var url = String(Qt.resolvedUrl(name))
    if (url.indexOf("file://") === 0) {
      var path = url.substring(7)
      if (path.indexOf("localhost/") === 0) path = path.substring(9)
      try { return decodeURIComponent(path) } catch (e) { return path }
    }
    return url
  }

  function refresh() {
    if (cleanProc.running || root.cleaning) {
      root.wantRescan = true
      return
    }
    if (scanProc.running) return
    root.scanning = true
    root.lastError = ""
    scanProc.command = ["bash", root.scanPath]
    scanProc.running = true
  }

  function applyScan(exitCode, stdout) {
    root.scanning = false
    var parsed = Model.parseScan(stdout)
    if (exitCode !== 0 && !parsed.ok) {
      root.lastError = parsed.error || "Scan failed"
      return
    }
    if (!parsed.ok) {
      root.lastError = parsed.error || "Scan failed"
      return
    }

    if (root.pendingFreedIds.length > 0) {
      var after = Model.bytesForIds(parsed.tasks, root.pendingFreedIds)
      root.lastFreedLabel = Model.freedLabel(root.pendingFreedBytes - after)
      root.pendingFreedIds = []
      root.pendingFreedBytes = 0
      freedClear.restart()
    }

    root.tasks = parsed.tasks
    root.scannedAt = parsed.scannedAt
    root.lastError = ""
  }

  function rememberFreed(ids) {
    var keys = Array.isArray(ids) ? ids : [ids]
    root.pendingFreedIds = keys
    root.pendingFreedBytes = Model.bytesForIds(root.tasks, keys)
  }

  function clean(id) {
    var key = String(id || "")
    if (key === "" || !Model.isKnownId(key) || root.cleaning) return
    var task = Model.findTask(root.tasks, key)
    if (task && task.privilege === "pkexec") {
      launchPrivileged(key)
      return
    }
    var args = Model.cleanArgs(key, root.dirs)
    if (!args) {
      root.lastError = "Unknown cleanup"
      return
    }
    startUserClean(args, [key])
  }

  function cleanAllUser() {
    if (root.cleaning) return
    var list = root.userTasks
    if (list.length === 0) return
    var ids = []
    for (var i = 0; i < list.length; i++) ids.push(list[i].id)
    var args = Model.userCleanAllArgs(root.dirs)
    if (!args) return
    startUserClean(args, ids)
  }

  function startUserClean(args, ids) {
    root.cleaning = true
    root.lastError = ""
    root.lastFreedLabel = ""
    rememberFreed(ids)
    cleanProc.command = args
    cleanProc.running = true
  }

  function launchPrivileged(id) {
    var cmds = Model.privilegedCommands(id)
    if (!cmds || cmds.length === 0) {
      root.lastError = "Unknown cleanup"
      return
    }
    root.lastError = ""
    root.lastFreedLabel = ""
    rememberFreed([id])
    root.privQueue = cmds
    root.cleaning = true
    runNextPrivileged()
  }

  function runNextPrivileged() {
    if (root.privQueue.length === 0) {
      root.cleaning = false
      root.refresh()
      return
    }
    var next = root.privQueue[0]
    var rest = []
    for (var i = 1; i < root.privQueue.length; i++) rest.push(root.privQueue[i])
    root.privQueue = rest
    cleanProc.command = next
    cleanProc.running = true
  }

  Process {
    id: scanProc
    stdout: StdioCollector {
      id: scanOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: scanErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.applyScan(exitCode, scanOut.text)
    }
  }

  Process {
    id: cleanProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: cleanErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && root.privQueue.length > 0) {
        root.runNextPrivileged()
        return
      }

      root.cleaning = false
      if (exitCode !== 0) {
        root.privQueue = []
        var err = String(cleanErr.text || "").trim()
        root.lastError = err !== "" ? err : "Clean canceled or failed"
        root.pendingFreedIds = []
        root.pendingFreedBytes = 0
      }
      root.refresh()
      if (root.wantRescan) {
        root.wantRescan = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Timer {
    id: startupScan
    interval: 800
    running: true
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: freedClear
    interval: 6000
    repeat: false
    onTriggered: root.lastFreedLabel = ""
  }
}
