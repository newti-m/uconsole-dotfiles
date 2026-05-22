# uConsole Dotfiles

Dotfiles and configuration for a [ClockworkPi uConsole](https://www.clockworkpi.com/uconsole) running Raspberry Pi CM4 on Raspberry Pi OS (Bookworm, arm64) with Sway on Wayland.

## Hardware

- **Device**: ClockworkPi uConsole (CM4 core)
- **OS**: Raspberry Pi OS Bookworm (arm64)
- **Kernel**: `6.12.62-v8-16k+`
- **Display**: DSI-2, 720×1280 physical (portrait panel), rotated to 1280×720 landscape
- **Compositor**: Sway (Wayland)

## Setup

### Packages

Install the core Wayland/Sway stack:

```bash
sudo apt install \
  sway swaybg swayidle swaylock \
  waybar wofi \
  grim slurp wl-clipboard \
  brightnessctl \
  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
  pipewire pipewire-pulse wireplumber \
  lxterminal
```

### Display rotation

The uConsole's DSI panel is physically portrait (720×1280) but the device is used in landscape. The correct Sway transform is **`90`** (not `270` — that renders upside down).

`~/.config/sway/config`:
```
output DSI-2 mode 720x1280 transform 90
output DSI-1 mode 720x1280 transform 90
```

Both `DSI-1` and `DSI-2` are listed since the output name varies between boots.

### Sway config highlights

- **Modifier**: `Alt` (`Mod1`) — easier on the uConsole's small keyboard than Super
- **Terminal**: `x-terminal-emulator` (resolves to lxterminal)
- **Launcher**: `wofi --show drun --allow-images`
- **Theme**: Catppuccin Mocha
- **Font**: PibotoLt 11 (system default on RPi OS)
- **Gaps**: 8px inner, 4px outer, smart gaps/borders on
- **Idle**: swayidle — lock after 10 min, display off after 10m10s
- **Lock**: `swaylock -f -c 1e1e2e`

Key bindings:
| Binding | Action |
|---|---|
| `Alt+Return` | Terminal |
| `Alt+Space` | App launcher (wofi) |
| `Alt+q` | Kill window |
| `Alt+Shift+c` | Reload config |
| `Alt+f` | Toggle fullscreen |
| `Alt+Shift+f` | Toggle floating |
| `Alt+r` | Resize mode |
| `Alt+Tab` / `Alt+Shift+Tab` | Next/prev workspace |
| `Alt+1–5` | Switch workspace |
| `Alt+Shift+1–5` | Move to workspace |
| `Alt+minus` | Scratchpad toggle |
| `Alt+Shift+minus` | Send to scratchpad |
| `Alt+h/j/k/l` or arrows | Focus direction |
| `Alt+Shift+h/j/k/l` or arrows | Move window |
| `XF86AudioRaiseVolume/LowerVolume/Mute` | Volume (hardware keys) |
| `XF86MonBrightnessUp/Down` | Brightness (hardware keys) |
| `Alt+Print` | Screenshot (full) |
| `Alt+Shift+Print` | Screenshot (region select) |

Screenshots save to `~/Screenshots/YYYYMMDD_HHMMSS.png`.

### Waybar

Minimal bar: workspaces + mode + window title on the left; audio, battery, clock on the right.

- Battery warning at 30%, critical at 15%
- Clock format: `Wed 21 May  14:30`
- Audio: click to mute/unmute via `wpctl`

### XDG portal

Required for screen sharing and some apps under Sway:

```bash
exec dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway
exec /usr/libexec/xdg-desktop-portal
```

Both lines are in the Sway config autostart section.

## Config files in this repo

```
.config/sway/config                        — Sway compositor (display rotation, keybindings, theme)
.config/waybar/config                      — Waybar layout and modules
.config/waybar/style.css                   — Waybar Catppuccin Mocha theme
.config/lxterminal/lxterminal.conf         — Terminal emulator (font size 20 for uConsole display)
.config/kanshi/config                      — kanshi display profiles (not active; sway handles rotation)
.config/labwc/autostart                    — labwc autostart (RPi default desktop alternative)
.config/labwc/environment                  — labwc keyboard layout
.config/labwc/rc.xml                       — labwc window manager config
.config/labwc/themerc-override             — labwc theme overrides
.config/wf-panel-pi.ini                    — wf-panel-pi taskbar config
.config/wf-panel-pi/wf-panel-pi.ini        — wf-panel-pi per-output config
.config/xsettingsd/xsettingsd.conf         — GTK font and theme settings
.config/pcmanfm/LXDE-pi/pcmanfm.conf       — PCManFM file manager config
.config/pcmanfm/LXDE-pi/desktop-items*.conf — Desktop icon layouts
.config/libfm/libfm.conf                   — libfm file manager library config
.config/qt5ct/qt5ct.conf                   — Qt5 appearance config
.config/qt6ct/qt6ct.conf                   — Qt6 appearance config
.config/mimeapps.list                      — Default application associations
.config/user-dirs.dirs                     — XDG user directory paths
```

## Notes

- `kanshi` is installed but Sway's built-in `output` directives handle rotation directly — kanshi is not used.
- `wf-panel-pi` / `labwc` configs exist from the default RPi desktop install and are left untouched.
- The home directory is used as the git repo root; `.gitignore` excludes caches, browser data, and large app data directories.
