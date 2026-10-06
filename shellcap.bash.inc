if [ -z "$SHELLCAP_SESSION_ID" ]; then
  if command -v uuidgen >/dev/null 2>&1; then
    export SHELLCAP_SESSION_ID="$(uuidgen)"
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    export SHELLCAP_SESSION_ID="$(cat /proc/sys/kernel/random/uuid)"
  else
    export SHELLCAP_SESSION_ID="$(date +%s%N)-$$-$(hostname)"
  fi
fi

if [ -z "$SHELLCAP_TTY" ]; then
  if [ -t 0 ]; then
    export SHELLCAP_TTY="$(tty 2>/dev/null || echo '')"
  elif [ -n "$SSH_TTY" ]; then
    export SHELLCAP_TTY="$SSH_TTY"
  fi
fi

[ -z "$SHELLCAP_DB" ] && export SHELLCAP_DB="$HOME/.local/share/shellcap/shellcap.db"
SHELLCAP_LOGGER="${SHELLCAP_LOGGER:-$HOME/.local/lib/shellcap/shellcap_log.py}"
SHELLCAP_SKIP_ROOT="${SHELLCAP_SKIP_ROOT:-1}"

_scap_is_interactive() {
  [ "${SHELLCAP_FORCE:-0}" = "1" ] && return 0
  case $- in
    *i*) return 0 ;;
    *) return 1 ;;
  esac
}

_scap_should_log() {
  _scap_is_interactive || return 1
  [ "${SHELLCAP_SKIP_ROOT:-1}" = "1" ] && [ "$(id -u)" -eq 0 ] && return 1
  _scap_is_paused && return 1
  return 0
}


_scap_is_paused() {
  [ "${SHELLCAP_PAUSED:-0}" = "1" ] && return 0
  local state_dir="${SHELLCAP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/shellcap}"
  [ -f "$state_dir/paused/global" ] && return 0
  [ -n "${SHELLCAP_SESSION_ID:-}" ] && [ -f "$state_dir/paused/${SHELLCAP_SESSION_ID}" ] && return 0
  return 1
}

_scap_create_state_dir() {
  local state_dir="${SHELLCAP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/shellcap}"
  mkdir -p "$state_dir/paused" 2>/dev/null || true
}

_scap_is_internal() {
  local c="$1"
  [ -z "$c" ] && return 0
  case "$c" in
    _scap_*|PROMPT_COMMAND*|BASH_FUNC__scap_*|trap*) return 0 ;;
  esac
  return 1
}

if _scap_should_log; then
  _SCAP_CMD=""
  _SCAP_START=""
  _SCAP_LAST_LOGGED=""
  _SCAP_IN_TRAP=0
  trap '_scap_preexec "$BASH_COMMAND"' DEBUG
fi

_scap_preexec() {
  [ "${_SCAP_IN_TRAP:-0}" = "1" ] && return
  _SCAP_IN_TRAP=1
  local c="$1"
  if _scap_is_internal "$c"; then
    if [ -z "${_SCAP_CMD:-}" ]; then
      _SCAP_CMD=""
      _SCAP_START=""
    fi
    _SCAP_IN_TRAP=0
    return
  fi
  _SCAP_CMD="$c"
  _SCAP_START="$(date +%s%N 2>/dev/null || echo 0)"
  _SCAP_IN_TRAP=0
}

_scap_precmd() {
  local ec=$?
  [ "${_SCAP_IN_TRAP:-0}" = "1" ] && _SCAP_IN_TRAP=0
  if ! _scap_should_log; then
    return $ec
  fi
  local cmd="${_SCAP_CMD:-}"
  _scap_is_internal "$cmd" && cmd=""
  if [ -z "$cmd" ] || [ "$cmd" = "${_SCAP_LAST_LOGGED:-}" ]; then
    _SCAP_CMD=""
    _SCAP_START=""
    return $ec
  fi
  local dur=0
  if [ -n "${_SCAP_START:-}" ] && [ "${_SCAP_START:-}" != "0" ]; then
    local now
    now="$(date +%s%N 2>/dev/null || echo ${_SCAP_START:-0})"
    dur=$(( (now - _SCAP_START) / 1000000 ))
    [ "$dur" -lt 0 ] && dur=0
  fi
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
  local cmd_esc
  cmd_esc=$(python3 -c "import json; print(json.dumps(r'''$cmd'''))" 2>/dev/null || echo '""')
  printf '{"session_id":"%s","executed_at":"%s","cwd":"%s","command":%s,"exit_code":%d,"duration_ms":%d,"shell_pid":%d}\n' \
    "$SHELLCAP_SESSION_ID" \
    "$ts" \
    "$PWD" \
    "$cmd_esc" \
    "$ec" \
    "$dur" \
    "$$" | python3 "$SHELLCAP_LOGGER" >/dev/null 2>&1
  _SCAP_LAST_LOGGED="$cmd"
  _SCAP_CMD=""
  _SCAP_START=""
  return $ec
}

PROMPT_COMMAND="_scap_precmd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"


shellcap_pause() {
  _scap_create_state_dir
  local state_dir="${SHELLCAP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/shellcap}"
  if [ "$1" = "--global" ] || [ "$1" = "-g" ]; then
    touch "$state_dir/paused/global"
    echo "shellcap paused (global)"
    return 0
  fi
  if [ -n "${SHELLCAP_SESSION_ID:-}" ]; then
    touch "$state_dir/paused/${SHELLCAP_SESSION_ID}"
    echo "shellcap paused (this session)"
    return 0
  fi
  touch "$state_dir/paused/global"
  echo "shellcap paused (global)"
}

shellcap_unpause() {
  local state_dir="${SHELLCAP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/shellcap}"
  if [ "$1" = "--global" ] || [ "$1" = "-g" ]; then
    rm -f "$state_dir/paused/global" 2>/dev/null || true
    echo "shellcap unpaused (global)"
    return 0
  fi
  if [ "$1" = "--all" ] || [ "$1" = "-a" ]; then
    rm -rf "$state_dir/paused" 2>/dev/null || true
    mkdir -p "$state_dir/paused" 2>/dev/null || true
    echo "shellcap unpaused (all sessions)"
    return 0
  fi
  if [ -n "${SHELLCAP_SESSION_ID:-}" ]; then
    rm -f "$state_dir/paused/${SHELLCAP_SESSION_ID}" 2>/dev/null || true
  fi
  rm -f "$state_dir/paused/global" 2>/dev/null || true
  echo "shellcap unpaused"
}

shellcap_status() {
  local state_dir="${SHELLCAP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/shellcap}"
  if [ -f "$state_dir/paused/global" ]; then
    echo "shellcap: paused (global)"
    return 0
  fi
  if [ -n "${SHELLCAP_SESSION_ID:-}" ] && [ -f "$state_dir/paused/${SHELLCAP_SESSION_ID}" ]; then
    echo "shellcap: paused (this session)"
    return 0
  fi
  echo "shellcap: active"
}

