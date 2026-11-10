# Background Display for Omarchy

Omarchy's default fill mode works well for most displays, but on ultrawide monitors it can crop away large parts of a wallpaper or cut the subject in awkward places. Background Display gives you a few simple alternatives while keeping the stock behavior one click away.

Everything lives in a bar icon and its panel; there are no menu entries and no separate app.

- **Presets, per display** — Fill (Omarchy's standard crop), Framed (the whole image over a blurred copy, in a theme-accent frame clear of the bar) or Extend (the whole image over the color of its edges). Pick one for the display you are on, or for all of them.
- **Real previews** — the panel draws your current background the way each preset and each display shows it.
- **Colors** — the frame follows the theme accent and the extend color is sampled from the image, or pick either from the screen.
- **Cycling** — move on to the next background every few hours, in Omarchy's order or shuffled, counted from the last time it changed. Right-click the icon for the next one now.

## The panel

![The Background panel open from the bar: the current background framed on the display, the three presets, the frame color, and cycling every 3 hours](demo/panel.png)

## Preview

**Framed** — instead of cropping the wallpaper on an ultrawide display:

![Fill (Default) cropping a wallpaper on an ultrawide display](demo/gruvbox_default.jpg)

the full composition is preserved over a blurred background:

![Framed mode preserving the full wallpaper on an ultrawide display](demo/gruvbox_framed.jpg)

**Extend Edges** — instead of cropping a centered design:

![Fill (Default) cropping a centered wallpaper on an ultrawide display](demo/lumon_default.jpg)

the sampled edge color fills the remaining space:

![Extend Edges preserving a centered wallpaper on an ultrawide display](demo/lumon_etend.jpg)

## Requirements

- Omarchy 4 / Quattro
- ImageMagick (`magick`) for automatic edge-color detection
- Perl for bounded, no-follow wallpaper reads
- `hyprpicker` for picking a color from the screen

These are included with a standard Omarchy installation. The plugin runs inside `omarchy-shell` with normal user permissions; it uses no network access or privilege escalation.

## Install

```sh
omarchy plugin add https://github.com/fchtngr/omarchy-background-display.git --yes
omarchy plugin enable io.github.fchtngr.background-display
```

Enabling puts the icon on the right of the bar and takes over from Omarchy's own background service, which is switched off while this one is on. Move the icon with `omarchy plugin enable io.github.fchtngr.background-display <section>`.

## Settings

The panel writes `~/.config/omarchy/background-display.json`, and the background follows the file, so hand-edits apply too:

```json
{
  "preset": "fill",
  "displays": { "DP-3": "framed" },
  "frameColor": "",
  "edgeColor": "",
  "cycleHours": 4,
  "shuffle": false
}
```

`preset` is every display's; `displays` holds those with their own. Empty colors follow the theme accent and the image's edge. `cycleHours` 0 turns cycling off.

## Remove

Disabling brings Omarchy's own background service back:

```sh
omarchy plugin disable io.github.fchtngr.background-display
omarchy plugin remove io.github.fchtngr.background-display
```

## Validate

```sh
omarchy plugin validate .
node --test tests/
./sample-edge-color --self-test
```

## License

[MIT](LICENSE). The renderer is derived from Omarchy's MIT-licensed background plugin.
