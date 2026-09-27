# Workspace Peek

A [Noctalia](https://noctalia.dev) 5 plugin for Hyprland. It replaces the bar's
workspaces widget with one that previews a workspace when you hover its name:
a thumbnail of the screen and a list of the apps open on it.

- Hover a workspace name to see its thumbnail, how old the thumbnail is, and
  its open apps (up to four, then "+N more").
- Click a name to switch to that workspace; scroll over the widget to step
  through workspaces on that monitor.
- A workspace you haven't visited yet shows "Visit workspace to get a
  snapshot".

## How the thumbnails work

Hyprland only draws the workspaces that are on screen, so a workspace you
aren't looking at can't be captured. The plugin keeps the last picture of each
workspace instead: a small helper (`scripts/peek.py`) follows Hyprland's event
socket and uses `grim` to snapshot each monitor's visible workspace

- shortly after you switch to it,
- when a window on it opens, closes or moves, and
- every 30 seconds otherwise (configurable).

So a thumbnail can be out of date if something changed on a workspace while
you weren't looking at it; the age shown next to the name says how old it is.
The app list is always live, read from Hyprland each time it changes.

Captures pause while the preview is open, so the preview never shows up in its
own thumbnail. Snapshots are small PNGs kept in the plugin's data directory
(`~/.local/state/noctalia/plugins/data/jpmoo/workspace-peek/snaps`), one per
workspace, and are deleted when the workspace goes away.

## Requirements

- Noctalia 5 (plugin API 32 or later)
- Hyprland (`hyprctl` on `PATH`)
- `grim`
- `python3` (standard library only)

## Install

Clone the repository and link it into Noctalia's local plugin directory:

```bash
git clone https://github.com/jpmoo/noctpreview.git ~/src/noctpreview
mkdir -p ~/.local/share/noctalia/plugins
ln -s ~/src/noctpreview ~/.local/share/noctalia/plugins/workspace-peek
noctalia msg plugins enable jpmoo/workspace-peek
```

Then put the widget on your bar in place of the built-in `workspaces` widget.
In `settings.toml`, give it a name and use that name in the bar's layout:

```toml
[bar.default]
start = [ "control-center", "workspace_peek" ]

[widget.workspace_peek]
type = "jpmoo/workspace-peek:workspaces"
```

and run `noctalia msg config-reload`.

## Settings

Under **Settings → Plugins → Workspace Peek**:

| Setting | Default | |
|---|---|---|
| Hover delay | 250 ms | How long the pointer rests on a name before the preview opens |
| Refresh interval | 30 s | How often the visible workspace is re-captured when nothing changes |

## Known limits

- **Position.** A plugin can't anchor a panel to the pointer, so the preview
  opens at the top left of the screen, under the bar. It suits a top bar with
  the workspaces near the left.
- **Height.** Noctalia fixes a plugin panel's size in the manifest, so the
  plugin declares one panel per list length (1–5 rows) and opens the one that
  fits. The heights assume a 16:10 screen; other shapes get thin bars around
  the thumbnail rather than a crop.
- **JPEG.** Some distributions (Ubuntu's included) build `grim` without JPEG
  support, so snapshots are PNG.

## Layout

| File | |
|---|---|
| `plugin.toml` | manifest: the service, the bar widget, the five preview panels, settings |
| `service.luau` | runs the helper, publishes its state, opens and closes the preview |
| `widget.luau` | the bar widget |
| `preview.luau` | the preview panel |
| `lib/layout.luau` | sizes shared by the service and the panel |
| `scripts/peek.py` | Hyprland events, snapshots |
| `translations/en.json` | strings |

## License

MIT — see [LICENSE](LICENSE).
