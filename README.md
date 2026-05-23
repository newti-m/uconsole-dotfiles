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

## Volume keys

The uConsole hardware has a dedicated speaker button (reported as `KEY_VOLUMEDOWN`) on the CM4 module and up/down arrow keys on the keyboard — but no native volume-up key. A Python daemon intercepts both devices via `evdev` and implements a chord:

| Input | Action |
|---|---|
| Speaker + Up arrow | Volume +5% |
| Speaker + Down arrow | Volume −5% |
| Up / Down (alone) | Pass through normally |

The daemon grabs the keyboard exclusively while running, re-injecting all non-chord keys through a `uinput` virtual device so nothing reaches the focused app. Volume is applied via `wpctl set-volume @DEFAULT_AUDIO_SINK@`.

**Install:**

```bash
pip install evdev
cp .local/bin/uconsole-volume ~/.local/bin/
cp .config/systemd/user/uconsole-volume.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now uconsole-volume
```

The service retries device discovery for up to 10 seconds at startup, tolerating slow boot-time USB enumeration. It also requires the `uinput` group:

```bash
sudo usermod -aG uinput $USER   # then log out/in
```

**Files:**
```
.local/bin/uconsole-volume                   — daemon (Python, evdev + uinput)
.config/systemd/user/uconsole-volume.service — systemd user service
```

## fzf system manager

`fzf-system-manager.sh` is a terminal UI for common system tasks, navigable entirely with the arrow keys and Enter — designed for the uConsole's small keyboard and screen.

**Run:**
```bash
bash ~/fzf-system-manager.sh
```

**Categories:**

| Menu entry | What it does |
|---|---|
| user services | Browse/start/stop/restart user systemd services |
| system services | Same, for system services (sudo) |
| processes | List running processes, send signals |
| docker | List containers, start/stop/logs/exec shell |
| wireguard | Toggle homelab VPN tunnel |
| wifi | Scan, connect (saved or new), disconnect |
| bluetooth | Scan, pair, connect, disconnect, remove |
| spotify | Play/pause, next/prev/stop via playerctl (ncspot) |
| network status | Live view of WiFi, local IPs, public IP, WireGuard |

Navigation: arrow keys to move, Enter to select, Left/Esc to go back. Logs to `/tmp/fzf-system-manager.log`.

Requires: `fzf`, `nmcli` (wifi), `docker` (containers), `wg`/`wg-quick` (wireguard), `playerctl` (spotify).

**File:** `fzf-system-manager.sh`

## Plymouth boot theme

`cyberdeck-plymouth/` contains a Neuromancer-aesthetic Plymouth theme — dark background with a centered splash graphic.

**Install:**
```bash
sudo cp cyberdeck-plymouth/cyberdeck.plymouth /usr/share/plymouth/themes/cyberdeck/
sudo cp cyberdeck-plymouth/cyberdeck.script   /usr/share/plymouth/themes/cyberdeck/
sudo cp splash_plymouth_bg.png               /usr/share/plymouth/themes/cyberdeck/
sudo plymouth-set-default-theme -R cyberdeck
```

**Files:**
```
cyberdeck-plymouth/cyberdeck.plymouth  — theme metadata
cyberdeck-plymouth/cyberdeck.script    — Plymouth script (layout, animation)
splash_plymouth_bg.png                 — background image
make_splash.py                         — script used to generate the splash graphic
```

## Config files in this repo

```
.local/bin/uconsole-volume                        — volume key chord daemon
.config/systemd/user/uconsole-volume.service      — systemd user service for above
fzf-system-manager.sh                             — fzf-based system manager TUI
cyberdeck-plymouth/cyberdeck.plymouth             — Plymouth theme metadata
cyberdeck-plymouth/cyberdeck.script               — Plymouth theme script
splash_plymouth_bg.png                            — Plymouth background image
make_splash.py                                    — splash image generator
boot/firmware/config.txt                          — Pi firmware config (display, overlays)
.config/sway/config                               — Sway compositor (display rotation, keybindings, theme)
.config/waybar/config                             — Waybar layout and modules
.config/waybar/style.css                          — Waybar Catppuccin Mocha theme
.config/lxterminal/lxterminal.conf                — Terminal emulator (font size 20 for uConsole display)
.config/kanshi/config                             — kanshi display profiles (not active; sway handles rotation)
.config/labwc/autostart                           — labwc autostart (RPi default desktop alternative)
.config/labwc/environment                         — labwc keyboard layout
.config/labwc/rc.xml                              — labwc window manager config
.config/labwc/themerc-override                    — labwc theme overrides
.config/wf-panel-pi.ini                           — wf-panel-pi taskbar config
.config/wf-panel-pi/wf-panel-pi.ini               — wf-panel-pi per-output config
.config/xsettingsd/xsettingsd.conf                — GTK font and theme settings
.config/pcmanfm/LXDE-pi/pcmanfm.conf              — PCManFM file manager config
.config/pcmanfm/LXDE-pi/desktop-items*.conf       — Desktop icon layouts
.config/libfm/libfm.conf                          — libfm file manager library config
.config/qt5ct/qt5ct.conf                          — Qt5 appearance config
.config/qt6ct/qt6ct.conf                          — Qt6 appearance config
.config/mimeapps.list                             — Default application associations
.config/user-dirs.dirs                            — XDG user directory paths
```

## Notes

- `kanshi` is installed but Sway's built-in `output` directives handle rotation directly — kanshi is not used.
- `wf-panel-pi` / `labwc` configs exist from the default RPi desktop install and are left untouched.
- The home directory is used as the git repo root; `.gitignore` excludes caches, browser data, and large app data directories.
