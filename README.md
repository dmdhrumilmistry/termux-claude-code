# termux-claude-code

Run [Claude Code](https://claude.com/claude-code) and [herdr](https://herdr.dev) on Android via Termux.

Claude Code has no Android build (`linux-arm64-android` isn't published), so the npm install fails in plain Termux. This script sets up a Debian userland with `proot-distro`. Debian reports `linux-arm64`, which is supported.

## Install

From plain Termux (not inside Debian):

```bash
curl -fsSLO https://raw.githubusercontent.com/dmdhrumilmistry/termux-claude-code/main/termux-claude-setup.sh
bash termux-claude-setup.sh
```

The script asks one question: whether Termux should open Debian automatically every time it starts. Everything else runs without asking. On a re-run the question defaults to your current setting, so pressing Enter changes nothing.

To answer up front, or to set up herdr autostart (which isn't asked):

```bash
AUTOSTART=1 bash termux-claude-setup.sh     # open Debian when Termux starts
AUTOSTART=0 bash termux-claude-setup.sh     # don't (removes it if enabled)
AUTO_HERDR=1 bash termux-claude-setup.sh    # also start herdr when entering Debian
bash termux-claude-setup.sh -y              # keep the current setting, no prompt
```

`AUTO_HERDR` keeps its current setting unless you set it, and is off on a first run.

Other settings: `DEV_USER` (Debian user, default `dev`) and `LAUNCHER` (the Termux command that enters Debian, default `dev`). If a `dev` command already exists and this script didn't create it, the script stops instead of overwriting it.

Files it edits in Termux (`~/.bashrc`, `~/.termux/termux.properties`) are backed up to `*.bak.<timestamp>.<pid>` first.

Ways out of the autostarts:

- `touch ~/.no-debian` turns off Debian autostart; `exit` in Debian drops you back to Termux.
- `NO_HERDR=1 dev` enters Debian without starting herdr.
- Re-run with `AUTOSTART=0` or `AUTO_HERDR=0` to remove them.

## What it sets up

- Debian (proot), plus a non-root user with passwordless sudo. Claude Code misbehaves as root.
- herdr, then Claude Code, both installed into `~/.local/bin` inside Debian.
- UTF-8 locale, `TERM=xterm-256color` and truecolor, so TUIs render correctly.
- Upgrades Termux packages, and removes the broken npm `claude-code` if it's installed.
- A `dev` launcher. It holds a wake lock while Debian is open, shares `/tmp`, and binds your Termux home to `~/termux` and phone storage to `~/sdcard` (run `termux-setup-storage` first for storage).
- Optional autostart into Debian, and optional herdr autostart once inside.
- Termux extra keys: Esc, Tab, Ctrl, Alt and arrows. Skipped if you already have your own `extra-keys`.
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`. This also turns off auto-updates, so run `claude update` now and then.

## Android 12+: phantom process killer

Android kills long-running child processes with signal 9, which takes down herdr and Claude. Disable it once over adb:

```bash
adb shell "settings put global settings_enable_monitor_phantom_procs false"                  # Android 14+
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"  # Android 12-13
```

Also set Termux's battery usage to **Unrestricted**.

## Logging in

`claude` prints an OAuth URL. Open it in your phone's browser, then paste the code back into the terminal.
