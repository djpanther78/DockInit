#!/bin/bash

set -Eeuo pipefail

CMD_LINES=${CMD_LINES:-10}
LOG_LEVEL=${LOG_LEVEL:-info}

_log_level() {
  case "$1" in
    debug) echo 0 ;;
    info) echo 1 ;;
    warn) echo 2 ;;
    error) echo 3 ;;
    success) echo 1 ;;
  esac
}

_log() {
  local level="$1"
  shift
  local msg="$*"

  local current=$(_log_level "$LOG_LEVEL")
  local target=$(_log_level "$level")

  [ "$target" -lt "$current" ] && return

  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")

  case "$level" in
    debug)   printf "\033[90m[%s] [DEBUG]   %s\033[0m\n" "$ts" "$msg" ;;
    info)    printf "\033[36m[%s] [INFO]    %s\033[0m\n" "$ts" "$msg" ;;
    warn)    printf "\033[33m[%s] [WARN]    %s\033[0m\n" "$ts" "$msg" ;;
    error)   printf "\033[31m[%s] [ERROR]   %s\033[0m\n" "$ts" "$msg" ;;
    success) printf "\033[32m[%s] [SUCCESS] %s\033[0m\n" "$ts" "$msg" ;;
  esac
}

debug()   { _log debug   "$@"; }
info()    { _log info    "$@"; }
warn()    { _log warn    "$@"; }
error()   { _log error   "$@"; exit 1; }
success() { _log success "$@"; }

run() {
  local start_msg="$1"
  local success_msg="$2"
  shift 2

  info "$start_msg"

  if [ ! -t 1 ]; then
    set +e
    "$@"
    local rc=$?
    set -e
    [ "$rc" -eq 0 ] && success "$success_msg" || error "$start_msg failed (exit $rc)"
    return
  fi

  local tmp
  tmp=$(mktemp)

  set +e
  if command -v stdbuf >/dev/null 2>&1; then
    (stdbuf -oL -eL "$@" >"$tmp" 2>&1) &
  else
    ("$@" >"$tmp" 2>&1) &
  fi
  local pid=$!
  set -e

  local printed=0
  local -a buf=()

  tput sc
  for _ in $(seq 1 "$CMD_LINES"); do
    printf "\n"
  done
  tput rc

  redraw() {
    tput rc
    local i=0
    while [ "$i" -lt "$CMD_LINES" ]; do
      tput el
      if [ "$i" -lt "${#buf[@]}" ]; then
        printf "%s" "${buf[$i]}"
      fi
      if [ "$i" -lt $((CMD_LINES - 1)) ]; then
        printf "\n"
      fi
      i=$((i + 1))
    done
    tput rc
  }

  consume() {
    local new
    new=$(wc -l <"$tmp" | tr -d ' ')
    [ "$new" -le "$printed" ] && return 0

    while IFS= read -r line; do
      line=${line//$'\r'/}
      buf+=("$line")
      if [ "${#buf[@]}" -gt "$CMD_LINES" ]; then
        buf=("${buf[@]:1}")
      fi
    done < <(tail -n +"$((printed + 1))" "$tmp")

    printed=$new
    redraw
  }

  while kill -0 "$pid" 2>/dev/null; do
    [ -s "$tmp" ] && consume
    sleep 0.08
  done

  wait "$pid"
  local rc=$?

  [ -s "$tmp" ] && consume
  rm -f "$tmp"

  tput rc
  for _ in $(seq 1 "$CMD_LINES"); do
    tput el
    tput cud1
  done
  tput rc
  tput ed

  if [ "$rc" -eq 0 ]; then
    success "$success_msg"
  else
    error "$start_msg failed (exit $rc)"
  fi
}

check_root() {
  info "Checking Permissions"
  if [ "$(id -u)" -ne 0 ]; then
    error "Script must be run as root (use sudo ./install.sh)"
  fi
  success "Running as root"
}

cat <<'EOF'
  _____             _    _____       _ _               _____      _               
 |  __ \           | |  |_   _|     (_) |             / ____|    | |              
 | |  | | ___   ___| | __ | |  _ __  _| |_   ______  | (___   ___| |_ _   _ _ __  
 | |  | |/ _ \ / __| |/ / | | | '_ \| | __| |______|  \___ \ / _ \ __| | | | '_ \ 
 | |__| | (_) | (__|   < _| |_| | | | | |_            ____) |  __/ |_| |_| | |_) |
 |_____/ \___/ \___|_|\_\_____|_| |_|_|\__|          |_____/ \___|\__|\__,_| .__/ 
                                                                           | |    
                                                                           |_|    
EOF

check_root

run "Updating APT Packages" "APT packages updated successfully" \
  env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
  apt-get update \
  -o Acquire::AllowReleaseInfoChange=true \
  -o Acquire::AllowReleaseInfoChange::Origin=true

run "Upgrading APT Packages" "APT packages upgraded successfully" \
  env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
  apt-get upgrade -y

run "Installing JQ" "JQ installed successfully" \
  env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
  apt-get install -y jq

success "All packages installed"
