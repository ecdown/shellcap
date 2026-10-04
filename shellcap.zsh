# shellcap zsh integration (basic - uses preexec/precmd)
if [ -f "$HOME/.config/shellcap/shellcap.env" ]; then
  source "$HOME/.config/shellcap/shellcap.env"
fi

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

_scap_zsh_should_log() {
  [[ -o interactive ]] || return 1
  [ "${SHELLCAP_FORCE:-0}" = "1" ] && return 0
  if [ "${SHELLCAP_SKIP_ROOT:-1}" = "1" ] && [ "$(id -u)" -eq 0 ]; then
    return 1
  fi
  return 0
}

_scap_zsh_preexec() {
  _SCAP_ZSH_CMD="$1"
  _SCAP_ZSH_START=$EPOCHREALTIME
}

_scap_zsh_precmd() {
  local ec=$?
  _scap_zsh_should_log || return $ec
  local cmd="${_SCAP_ZSH_CMD:-}"
  [ -z "$cmd" ] && return $ec
  local dur=0
  if [ -n "${_SCAP_ZSH_START:-}" ]; then
    local now=$EPOCHREALTIME
    dur=$(( (now - _SCAP_ZSH_START) * 1000 ))
    dur=${dur%.*}
    [ "$dur" -lt 0 ] 2>/dev/null && dur=0
  fi
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
  python3 -c "
import os,json,sys,subprocess
d={'session_id':os.environ.get('SHELLCAP_SESSION_ID'),'executed_at':'$ts','cwd':os.environ.get('PWD'),'command':r'''$cmd''','exit_code':int('$ec'),'duration_ms':int('$dur'),'shell_pid':int(os.getpid())}
p=os.environ.get('SHELLCAP_LOGGER') or os.path.expanduser('~/.local/lib/shellcap/shellcap_log.py')
try:
  if os.path.exists(p):
    subprocess.run([sys.executable,p], input=json.dumps(d).encode(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except Exception:
  pass
" >/dev/null 2>&1
  _SCAP_ZSH_CMD=""
  return $ec
}

if _scap_zsh_should_log; then
  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _scap_zsh_preexec
  add-zsh-hook precmd _scap_zsh_precmd
fi
