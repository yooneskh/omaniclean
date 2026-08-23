var MIN_BYTES = 16 * 1024 * 1024
var BAR_SIZE_BYTES = 1024 * 1024 * 1024
var USER_CLEAN_IDS = ["trash", "thumbnails", "aur-cache", "dev-caches"]

var CATALOG = {
  "pacman-cache": {
    title: "Package cache",
    detail: "Old versions beyond the last two, plus uninstalled packages",
    confirm: "Prune extra and uninstalled package files",
    icon: "󰏖",
    privilege: "pkexec",
    userOwned: false
  },
  "journal": {
    title: "Journal logs",
    detail: "Archived journals older than seven days",
    confirm: "Delete archived journal files older than 7 days",
    icon: "󰦪",
    privilege: "pkexec",
    userOwned: false
  },
  "trash": {
    title: "Trash",
    detail: "Empty the user trash folder",
    confirm: "Empty Trash",
    icon: "󰩺",
    privilege: "user",
    userOwned: true
  },
  "thumbnails": {
    title: "Thumbnails",
    detail: "Regenerable image preview cache",
    confirm: "Delete thumbnail cache",
    icon: "󰋩",
    privilege: "user",
    userOwned: true
  },
  "aur-cache": {
    title: "AUR build cache",
    detail: "yay and paru build leftovers",
    confirm: "Delete AUR build caches",
    icon: "󰣇",
    privilege: "user",
    userOwned: true
  },
  "dev-caches": {
    title: "Developer caches",
    detail: "pip, npm, cargo, Go, and bun caches",
    confirm: "Delete regenerable developer caches",
    icon: "󰘧",
    privilege: "user",
    userOwned: true
  },
  "docker": {
    title: "Docker leftovers",
    detail: "Stopped containers, dangling images, build cache",
    confirm: "Prune unused Docker data (not volumes)",
    icon: "󰡨",
    privilege: "user",
    userOwned: false
  },
  "coredumps": {
    title: "Crash dumps",
    detail: "Systemd coredumps that can be removed",
    confirm: "Remove system crash dumps",
    icon: "󰱯",
    privilege: "pkexec",
    userOwned: false
  }
}

function envOr(value, fallback) {
  var text = String(value || "")
  return text !== "" ? text : fallback
}

function dirsFrom(home, cacheDir, dataDir) {
  var homePath = String(home || "")
  return {
    home: homePath,
    cache: envOr(cacheDir, homePath + "/.cache"),
    data: envOr(dataDir, homePath + "/.local/share")
  }
}

function catalogEntry(id) {
  return CATALOG[String(id || "")] || null
}

function userPaths(id, dirs) {
  var d = dirs || dirsFrom("", "", "")
  var key = String(id || "")
  if (key === "trash") return [d.data + "/Trash/files", d.data + "/Trash/info"]
  if (key === "thumbnails") return [d.cache + "/thumbnails"]
  if (key === "aur-cache") return [d.cache + "/yay", d.cache + "/paru"]
  if (key === "dev-caches") {
    return [
      d.cache + "/pip",
      d.home + "/.npm",
      d.cache + "/cargo",
      d.cache + "/go-build",
      d.home + "/.bun",
      d.home + "/.cargo/registry",
      d.home + "/.cargo/git"
    ]
  }
  return []
}

function userCleanArgs(id, dirs) {
  var paths = userPaths(id, dirs)
  if (paths.length === 0) return null
  return ["rm", "-rf", "--"].concat(paths)
}

function userCleanAllArgs(dirs) {
  var paths = []
  for (var i = 0; i < USER_CLEAN_IDS.length; i++) {
    var extra = userPaths(USER_CLEAN_IDS[i], dirs)
    for (var j = 0; j < extra.length; j++) paths.push(extra[j])
  }
  if (paths.length === 0) return null
  return ["rm", "-rf", "--"].concat(paths)
}

function dockerCleanArgs() {
  return ["docker", "system", "prune", "-f"]
}

function cleanArgs(id, dirs) {
  var key = String(id || "")
  if (key === "docker") return dockerCleanArgs()
  return userCleanArgs(key, dirs)
}

function privilegedCommands(id) {
  var key = String(id || "")
  if (key === "pacman-cache") {
    return [
      ["pkexec", "paccache", "-rk2"],
      ["pkexec", "paccache", "-ruk0"]
    ]
  }
  if (key === "journal") {
    return [[
      "pkexec", "find", "/var/log/journal", "/run/log/journal",
      "-type", "f",
      "(", "-name", "*@*.journal", "-o", "-name", "*@*.journal~", ")",
      "-mtime", "+7", "-delete"
    ]]
  }
  if (key === "coredumps") {
    return [["pkexec", "find", "/var/lib/systemd/coredump", "-mindepth", "1", "-delete"]]
  }
  return []
}

function isKnownId(id) {
  return !!catalogEntry(id)
}

function parseScan(raw) {
  var text = String(raw || "").trim()
  if (text === "") {
    return { ok: false, scannedAt: 0, tasks: [], error: "Empty scan" }
  }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") {
      return { ok: false, scannedAt: 0, tasks: [], error: "Invalid scan" }
    }
    var rows = Array.isArray(parsed.tasks) ? parsed.tasks : []
    var tasks = []
    for (var i = 0; i < rows.length; i++) {
      var task = enrichTask(rows[i])
      if (task) tasks.push(task)
    }
    return {
      ok: true,
      scannedAt: Number(parsed.scannedAt || 0),
      tasks: tasks,
      error: ""
    }
  } catch (e) {
    return { ok: false, scannedAt: 0, tasks: [], error: "Failed to parse scan" }
  }
}

function enrichTask(row) {
  if (!row || typeof row !== "object") return null
  var id = String(row.id || "")
  var meta = catalogEntry(id)
  if (!meta) return null
  var bytes = Number(row.bytes)
  if (!isFinite(bytes)) bytes = -1
  var available = row.available !== false
  if (!available) return null
  if (bytes >= 0 && bytes < MIN_BYTES) return null
  return {
    id: id,
    title: meta.title,
    detail: meta.detail,
    confirm: meta.confirm,
    icon: meta.icon,
    privilege: meta.privilege,
    userOwned: meta.userOwned === true,
    bytes: bytes,
    available: true
  }
}

function visibleTasks(tasks) {
  var list = Array.isArray(tasks) ? tasks : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].available !== false) out.push(list[i])
  }
  return out
}

function findTask(tasks, id) {
  var key = String(id || "")
  var list = Array.isArray(tasks) ? tasks : []
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].id) === key) return list[i]
  }
  return null
}

function userOwnedTasks(tasks) {
  var list = visibleTasks(tasks)
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i].userOwned === true) out.push(list[i])
  }
  return out
}

function sumKnownBytes(tasks) {
  var list = Array.isArray(tasks) ? tasks : []
  var total = 0
  var any = false
  for (var i = 0; i < list.length; i++) {
    var bytes = Number(list[i] && list[i].bytes)
    if (isFinite(bytes) && bytes >= 0) {
      total += bytes
      any = true
    }
  }
  return { bytes: total, known: any }
}

function hasUnknownSize(tasks) {
  var list = Array.isArray(tasks) ? tasks : []
  for (var i = 0; i < list.length; i++) {
    var bytes = Number(list[i] && list[i].bytes)
    if (!isFinite(bytes) || bytes < 0) return true
  }
  return false
}

function formatBytes(bytes) {
  var value = Number(bytes)
  if (!isFinite(value) || value < 0) return "size unknown"
  if (value === 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000
    index++
  }
  var decimals = value >= 100 || index === 0 ? 0 : (value >= 10 ? 1 : 2)
  return value.toFixed(decimals).replace(/\.0+$/, "").replace(/(\.\d)0$/, "$1") + " " + units[index]
}

function formatCompactBytes(bytes) {
  var value = Number(bytes)
  if (!isFinite(value) || value < 0) return "?"
  if (value === 0) return "0B"
  var units = ["B", "K", "M", "G", "T"]
  var index = 0
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000
    index++
  }
  var decimals = value >= 10 || index === 0 ? 0 : 1
  return value.toFixed(decimals).replace(/\.0$/, "") + units[index]
}

function tooltipText(tasks) {
  var list = visibleTasks(tasks)
  if (list.length === 0) return "Nothing to clean"
  var summed = sumKnownBytes(list)
  if (summed.known && summed.bytes > 0) {
    var extra = hasUnknownSize(list) ? " plus more" : ""
    return formatBytes(summed.bytes) + " can be cleaned" + extra
  }
  return "Cleanup available"
}

function heroMeta(tasks, scannedAt, nowMs, scanning, lastFreedLabel) {
  if (lastFreedLabel) return String(lastFreedLabel)
  if (scanning) return "Scanning"
  var list = visibleTasks(tasks)
  var summed = sumKnownBytes(list)
  var parts = []
  if (list.length === 0) parts.push("Nothing worth cleaning right now")
  else if (summed.known && summed.bytes > 0) parts.push(formatBytes(summed.bytes) + " can be cleaned")
  else parts.push("Cleanup available")
  var when = relativeTime(scannedAt, nowMs)
  if (when !== "") parts.push(when)
  return parts.join(" · ")
}

function relativeTime(timestampSec, nowMs) {
  var ts = Number(timestampSec || 0)
  if (!isFinite(ts) || ts <= 0) return ""
  var now = Number(nowMs || Date.now())
  var delta = Math.max(0, Math.floor(now / 1000 - ts))
  if (delta < 10) return "Scanned just now"
  if (delta < 60) return "Scanned " + delta + "s ago"
  if (delta < 3600) return "Scanned " + Math.floor(delta / 60) + "m ago"
  if (delta < 86400) return "Scanned " + Math.floor(delta / 3600) + "h ago"
  return "Scanned " + Math.floor(delta / 86400) + "d ago"
}

function confirmMessage(task) {
  if (!task) return "Clean this item? This cannot be undone."
  var size = formatBytes(task.bytes)
  var sizeBit = size === "size unknown" ? "" : " (" + size + ")"
  var suffix = task.privilege === "pkexec"
    ? " A system prompt will ask for your password."
    : " This cannot be undone."
  return String(task.confirm || "Clean this item") + sizeBit + "?" + suffix
}

function confirmAllMessage(tasks) {
  var list = userOwnedTasks(tasks)
  var summed = sumKnownBytes(list)
  var sizeBit = summed.known && summed.bytes > 0 ? " (" + formatBytes(summed.bytes) + ")" : ""
  return "Clean all user-owned caches" + sizeBit + "? This cannot be undone."
}

function showBarSize(tasks) {
  var summed = sumKnownBytes(visibleTasks(tasks))
  return summed.known && summed.bytes >= BAR_SIZE_BYTES
}

function barLabel(tasks) {
  var summed = sumKnownBytes(visibleTasks(tasks))
  return "󰃢  " + formatCompactBytes(summed.bytes)
}

function bytesForIds(tasks, ids) {
  var keys = Array.isArray(ids) ? ids : []
  var total = 0
  for (var i = 0; i < keys.length; i++) {
    var task = findTask(tasks, keys[i])
    var bytes = Number(task && task.bytes)
    if (isFinite(bytes) && bytes > 0) total += bytes
  }
  return total
}

function freedLabel(bytes) {
  var value = Number(bytes)
  if (!isFinite(value) || value <= 0) return "Cleaned"
  return "Freed " + formatBytes(value)
}
