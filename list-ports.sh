#!/bin/bash
#
# Emit all listening localhost TCP ports as a JSON array of
# {port, process, pid, cwd} objects, sorted by port, one entry per port.

set -o pipefail

{
  ss -Htlnp 2>/dev/null | while read -r _ _ _ local _ users _; do
    addr="${local%:*}"
    port="${local##*:}"
    case "$addr" in
      127.* | 0.0.0.0 | '*' | '[::]' | '[::1]') ;;
      *) continue ;;
    esac

    pid="" name=""
    if [[ $users =~ \(\"([^\"]+)\",pid=([0-9]+) ]]; then
      name="${BASH_REMATCH[1]}"
      pid="${BASH_REMATCH[2]}"
    fi

    cwd="-"
    if [[ -n $pid ]]; then
      cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "-")
    else
      name="?" pid="?"
    fi

    printf '%s\t%s\t%s\t%s\n' "$port" "$name" "$pid" "$cwd"
  done | sort -un -t$'\t' -k1,1
} | jq -R -s '[split("\n")[] | select(length > 0) | split("\t") |
  {port: .[0], process: .[1], pid: .[2], cwd: .[3]}]'
