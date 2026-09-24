#!/bin/bash
#
# Emit all listening localhost TCP ports as a JSON array of
# {port, process, pid, cwd} objects, sorted by port, one entry per port.
#
# PID extraction is independent of the process-name match: ss truncates
# long names (e.g. next-server (v15...) loses its closing quote), which
# used to hide real, killable PIDs behind "?".

set -o pipefail

# Resolve a display name: prefer ss's (possibly truncated) name, cleaned
# up, else the kernel comm for the pid, else "?".
proc_name() {
  local pid="$1" fallback="$2" comm=""
  if [[ -n $fallback ]]; then
    # Strip ss truncation debris: ("next-server (v1" -> "next-server").
    fallback="${fallback%% \(*}"
    [[ -n $fallback ]] && { printf '%s' "$fallback"; return; }
  fi
  comm=$(cat "/proc/$pid/comm" 2>/dev/null) || comm=""
  [[ -n $comm ]] && { printf '%s' "$comm"; return; }
  printf '?'
}

{
  # NOTE: `users` must be the LAST read variable so it captures the whole
  # remainder of the line — process names can contain spaces (e.g. ss
  # truncates "next-server (v15..."), which would otherwise split the
  # pid=... part into a discarded field.
  ss -Htlnp 2>/dev/null | while read -r _ _ _ local _ users; do
    addr="${local%:*}"
    port="${local##*:}"
    case "$addr" in
      127.* | 0.0.0.0 | '*' | '[::]' | '[::1]') ;;
      *) continue ;;
    esac

    pid="" name=""
    if [[ $users =~ pid=([0-9]+) ]]; then
      pid="${BASH_REMATCH[1]}"
    fi
    if [[ $users =~ \(\"([^\"]*)\" ]]; then
      name="${BASH_REMATCH[1]}"
    fi

    cwd="-"
    if [[ -n $pid ]]; then
      name=$(proc_name "$pid" "$name")
      cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "-")
    else
      name="?" pid="?"
    fi

    printf '%s\t%s\t%s\t%s\n' "$port" "$name" "$pid" "$cwd"
  done | sort -un -t$'\t' -k1,1
} | jq -R -s '[split("\n")[] | select(length > 0) | split("\t") |
  {port: .[0], process: .[1], pid: .[2], cwd: .[3]}]'
