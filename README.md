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
| `x`, `ctrl+k`, or Kill button | Kill owning process, then refresh |
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

## Dependencies

All standard on Omarchy. No sudo, no daemon, no extra packages.

| Dependency | Used for | Required |
|------------|----------|----------|
| `ss` (iproute2) | reading listening sockets | yes |
| `jq` | parsing port list to JSON | yes |
| `/proc` | process cwd lookup | yes |
| `xdg-open` | opening ports in browser | for Open action |

## Uninstall

```bash
omarchy plugin remove dev.ritik.portkiller
```

## License

MIT
