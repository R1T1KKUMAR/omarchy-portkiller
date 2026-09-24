# Portkiller

Local dev-server manager for the Omarchy bar.

- Bar shows a server glyph with a live localhost port-count badge.
- Click to open a panel listing every listening localhost TCP port with owning process, PID, and cwd.
- **Open** opens `http://localhost:<port>` in the browser. **Kill** terminates the owning process and refreshes.

![kind: bar-widget](https://img.shields.io/badge/kind-bar--widget-blue)

## Keys

| Key | Action |
|-----|--------|
| type in filter box | Filter by port / process / directory |
| `enter` / click row / Open | Open `http://localhost:<port>` |
| `x`, `ctrl+k`, or Kill button | Kill everything on the port (SIGTERM; press again to force SIGKILL) |
| `r` / `ctrl+r` | Refresh list |
| `j`/`k` or arrows | Move selection |
| `esc` | Clear filter, then close |

## Install

```bash
omarchy plugin add https://github.com/R1T1KKUMAR/omarchy-portkiller --enable
omarchy bar put dev.ritik.portkiller --section right
```

Or by hand:

```bash
cp -r . ~/.config/omarchy/plugins/dev.ritik.portkiller
omarchy-shell shell rescanPlugins
omarchy plugin enable dev.ritik.portkiller
```

## How it works

The widget runs `list-ports.sh` (an `ss -tlnp` wrapper emitting JSON) on open, every 5s while open, and every 20s for the bar badge. Only loopback/wildcard sockets are shown; one row per port.

Ports owned by other users show `?` for process/PID since `ss` cannot read them without root — Kill is disabled for those rows.

## How Kill works

Kill targets the **port**, not the listed PID, via `kill-port.sh`:

1. Resolves **all** current holders of the port at kill time (the list is a snapshot — HMR restarts make stored PIDs stale, and some stacks share one port across processes).
2. Signals the holders **plus one level of dev-supervisor parent** (`node`/`npm`/`tsx`/`vite`/`next`/…), so supervised servers (tsx, `npm run dev`, Next.js) die instead of respawning seconds later. Shells and terminals never match the supervisor pattern, so a foreground-started server costs exactly its own process — never your shell.
3. Re-lists and verifies. First press sends SIGTERM; if the port survives, the status line says so and the next press escalates to SIGKILL. A freed port that returns within seconds is reported as supervisor-respawned instead of silently re-listing.

Kill is enabled for every numeric port, including ones whose owner `ss` cannot read — permission failures surface in the status line instead of a dead button.

## Note: applying updates

Edits to a mounted bar widget's QML do not hot-reload — after `omarchy plugin update` (or hand-editing files), run:

```bash
omarchy restart shell
```

## Dependencies

All standard on Omarchy. No sudo, no daemon, no extra packages.

| Dependency | Used for | Required |
|------------|----------|----------|
| `ss` (iproute2) | reading listening sockets | yes |
| `jq` | parsing port list to JSON | yes |
| `/proc` | process cwd/name lookup | yes |
| `xdg-open` | opening ports in browser | for Open action |

## Uninstall

```bash
omarchy plugin remove dev.ritik.portkiller
```

## License

MIT
