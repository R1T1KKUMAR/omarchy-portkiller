#!/bin/bash
#
# kill-port.sh <port> [TERM|KILL]
#
# Free a localhost TCP port: signal ALL current holders plus any
# dev-supervisor parent (tsx, npm, vite, next, nodemon, ...), so
# supervised servers die instead of respawning seconds later.
#
# Only one level is climbed, and only when the parent looks like a
# supervisor: shells and terminals (bash, zsh, fish, alacritty, ...)
# never match, so a foreground-started server costs exactly its own
# process — never the user's shell.
#
# Exit  0 if the port is free afterwards, 1 if something still listens.

set -u

port="${1:-}"
sig="${2:-TERM}"
[[ $port =~ ^[0-9]+$ ]] || exit 2
[[ $sig == TERM || $sig == KILL ]] || sig=TERM

SUPERVISOR_COMM='^(node|npm|bun|deno|tsx|ts-node|nodemon|vite|next-server|next|pm2|uvicorn|gunicorn|flask|rails|ruby|php|java|gradle|mvn|cargo|go)(-|$)'
SUPERVISOR_ARGS='(tsx|vite|next-server|nodemon|pm2|nodemon|/\.bin/(tsx|vite|next|nodemon|pm2))'

holders=$(ss -Htnlp 2>/dev/null | grep -E "[:.]${port}[[:space:]]" | grep -o 'pid=[0-9]\+' | cut -d= -f2 | sort -un)
[[ -z $holders ]] && exit 0

# shellcheck disable=SC2086
kill "-$sig" $holders 2>/dev/null

for pid in $holders; do
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  [[ $ppid =~ ^[0-9]+$ ]] || continue
  (( ppid <= 1 || ppid == $$ )) && continue
  pcomm=$(ps -o comm= -p "$ppid" 2>/dev/null | tr -d ' ')
  pargs=$(ps -o args= -p "$ppid" 2>/dev/null)
  if [[ $pcomm =~ $SUPERVISOR_COMM ]] || [[ $pargs =~ $SUPERVISOR_ARGS ]]; then
    kill "-$sig" "$ppid" 2>/dev/null
  fi
done

sleep 0.3
if ss -Htnl 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"; then
  exit 1
else
  exit 0
fi
