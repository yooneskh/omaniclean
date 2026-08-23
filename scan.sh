#!/usr/bin/env bash
# Read-only size scan for OmaniClean. Never deletes anything.

set -u

MIN_BYTES=$((16 * 1024 * 1024))
HOME="${HOME:-}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

run_to() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 8 "$@"
  else
    "$@"
  fi
}

dir_bytes() {
  local path=$1
  if [[ ! -e $path ]]; then
    echo 0
    return
  fi
  run_to du -sb --apparent-size "$path" 2>/dev/null | awk '{ print $1; exit }'
}

sum_dirs() {
  local total=0
  local bytes
  local path
  for path in "$@"; do
    [[ -e $path ]] || continue
    bytes=$(dir_bytes "$path")
    [[ $bytes =~ ^[0-9]+$ ]] || bytes=0
    total=$((total + bytes))
  done
  echo "$total"
}

human_to_bytes() {
  python3 -c '
import re, sys
raw = sys.argv[1].strip().replace(",", "")
match = re.search(r"([0-9]*\.?[0-9]+)\s*([KMGTPE]i?B?)?", raw, re.I)
if not match:
    print(-1)
    raise SystemExit
number = float(match.group(1))
unit = (match.group(2) or "B").upper()
table = {
    "B": 1,
    "K": 1000, "KB": 1000, "KIB": 1024,
    "M": 1000 ** 2, "MB": 1000 ** 2, "MIB": 1024 ** 2,
    "G": 1000 ** 3, "GB": 1000 ** 3, "GIB": 1024 ** 3,
    "T": 1000 ** 4, "TB": 1000 ** 4, "TIB": 1024 ** 4,
    "P": 1000 ** 5, "PB": 1000 ** 5, "PIB": 1024 ** 5,
}
print(int(number * table.get(unit, 1)))
' "$1"
}

paccache_reclaim() {
  local out
  out=$(run_to paccache "$@" 2>&1 || true)
  python3 -c '
import re, sys
text = sys.argv[1]
if re.search(r"no candidate packages", text, re.I):
    print(0)
    raise SystemExit
match = re.search(r"disk space saved:\s*([0-9]*\.?[0-9]+)\s*([KMGTPE]i?B?)", text, re.I)
if not match:
    print(0)
    raise SystemExit
number = float(match.group(1))
unit = match.group(2).upper()
table = {
    "B": 1,
    "K": 1000, "KB": 1000, "KIB": 1024,
    "M": 1000 ** 2, "MB": 1000 ** 2, "MIB": 1024 ** 2,
    "G": 1000 ** 3, "GB": 1000 ** 3, "GIB": 1024 ** 3,
    "T": 1000 ** 4, "TB": 1000 ** 4, "TIB": 1024 ** 4,
}
print(int(number * table.get(unit, 1)))
' "$out"
}

TASKS_JSON="[]"

add_task() {
  local id=$1
  local bytes=$2
  local available=$3
  local privilege=$4
  TASKS_JSON=$(python3 -c '
import json, sys
tasks = json.loads(sys.argv[1])
tasks.append({
    "id": sys.argv[2],
    "bytes": int(sys.argv[3]),
    "available": sys.argv[4] == "true",
    "privilege": sys.argv[5],
})
print(json.dumps(tasks, separators=(",", ":")))
' "$TASKS_JSON" "$id" "$bytes" "$available" "$privilege")
}

maybe_add() {
  local id=$1
  local bytes=$2
  local privilege=$3
  local unknown_ok=${4:-false}

  if [[ $bytes == unknown ]]; then
    if [[ $unknown_ok == true ]]; then
      add_task "$id" -1 true "$privilege"
    fi
    return
  fi
  [[ $bytes =~ ^-?[0-9]+$ ]] || return
  if (( bytes < 0 )); then
    if [[ $unknown_ok == true ]]; then
      add_task "$id" -1 true "$privilege"
    fi
    return
  fi
  if (( bytes >= MIN_BYTES )); then
    add_task "$id" "$bytes" true "$privilege"
  fi
}

scan_pacman() {
  command -v paccache >/dev/null 2>&1 || return
  local extra unused bytes
  extra=$(paccache_reclaim -dk2)
  unused=$(paccache_reclaim -duk0)
  [[ $extra =~ ^[0-9]+$ ]] || extra=0
  [[ $unused =~ ^[0-9]+$ ]] || unused=0
  bytes=$((extra + unused))
  maybe_add pacman-cache "$bytes" pkexec
}

scan_journal() {
  local bytes=0
  local path sz
  # --vacuum-time=7d only removes archived files. Live system.journal /
  # user-*.journal stay allocated even when vacuum succeeds.
  while IFS= read -r path; do
    [[ -n $path ]] || continue
    sz=$(dir_bytes "$path")
    [[ $sz =~ ^[0-9]+$ ]] || continue
    bytes=$((bytes + sz))
  done < <(find /var/log/journal /run/log/journal -type f \
    \( -name '*@*.journal' -o -name '*@*.journal~' \) -mtime +7 2>/dev/null)
  maybe_add journal "$bytes" pkexec
}

scan_trash() {
  maybe_add trash "$(sum_dirs "$DATA/Trash")" user
}

scan_thumbnails() {
  maybe_add thumbnails "$(sum_dirs "$CACHE/thumbnails")" user
}

scan_aur() {
  maybe_add aur-cache "$(sum_dirs "$CACHE/yay" "$CACHE/paru")" user
}

scan_dev() {
  maybe_add dev-caches "$(sum_dirs \
    "$CACHE/pip" \
    "$HOME/.npm" \
    "$CACHE/cargo" \
    "$CACHE/go-build" \
    "$HOME/.bun" \
    "$HOME/.cargo/registry" \
    "$HOME/.cargo/git")" user
}

scan_docker() {
  command -v docker >/dev/null 2>&1 || return
  local formatted out bytes
  formatted=$(run_to docker system df --format '{{.Type}} {{.Reclaimable}}' 2>/dev/null || true)
  if [[ -n $formatted ]]; then
    out=$formatted
  else
    out=$(run_to docker system df 2>/dev/null || true)
  fi
  [[ -n $out ]] || return
  bytes=$(python3 -c '
import re, sys
total = 0
found = False
for line in sys.stdin:
    kind = line.split(None, 1)[0] if line.strip() else ""
    if kind not in ("Images", "Containers", "Build"):
        continue
    match = re.search(r"([0-9]*\.?[0-9]+)\s*([KMGTPE]i?B?)", line, re.I)
    if not match:
        continue
    number = float(match.group(1))
    unit = match.group(2).upper()
    table = {
        "B": 1,
        "K": 1000, "KB": 1000, "KIB": 1024,
        "M": 1000 ** 2, "MB": 1000 ** 2, "MIB": 1024 ** 2,
        "G": 1000 ** 3, "GB": 1000 ** 3, "GIB": 1024 ** 3,
        "T": 1000 ** 4, "TB": 1000 ** 4, "TIB": 1024 ** 4,
    }
    total += int(number * table.get(unit, 1))
    found = True
print(total if found else -1)
' <<< "$out")
  if [[ $bytes == -1 ]]; then
    return
  fi
  maybe_add docker "$bytes" user
}

scan_coredumps() {
  local dir=/var/lib/systemd/coredump
  local bytes
  if [[ ! -e $dir ]]; then
    return
  fi
  if [[ ! -r $dir ]]; then
    maybe_add coredumps unknown pkexec true
    return
  fi
  bytes=$(dir_bytes "$dir")
  if [[ $bytes =~ ^[0-9]+$ ]]; then
    maybe_add coredumps "$bytes" pkexec
  else
    maybe_add coredumps unknown pkexec true
  fi
}

scan_pacman
scan_journal
scan_trash
scan_thumbnails
scan_aur
scan_dev
scan_docker
scan_coredumps

python3 -c '
import json, sys, time
tasks = json.loads(sys.argv[1])
print(json.dumps({"scannedAt": int(time.time()), "tasks": tasks}, separators=(",", ":")))
' "$TASKS_JSON"
