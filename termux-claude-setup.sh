#!/data/data/com.termux/files/usr/bin/bash
# Termux -> Debian (proot) + herdr + Claude Code
# Run from plain Termux:  bash termux-claude-setup.sh [-y]
#
# Asks one question: whether Termux should open Debian automatically.
# Options (env vars):
#   AUTOSTART=1|0   answer that question up front (-y keeps the current setting)
#   AUTO_HERDR=1|0  start herdr automatically when entering Debian (default: current setting, else 0)
#   DEV_USER=name   non-root user inside Debian          (default: dev)
#   LAUNCHER=name   Termux command that enters Debian    (default: dev)
set -euo pipefail

DISTRO="debian"
DEV_USER="${DEV_USER:-dev}"
LAUNCHER="${LAUNCHER:-dev}"
ASSUME_YES=0
MARK="# managed-by: termux-claude-setup"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
for arg in "$@"; do
  case "$arg" in
    -y|--yes)  ASSUME_YES=1 ;;
    -h|--help) usage ;;
    *) die "Unknown option: $arg (try --help)" ;;
  esac
done

# ---------- 0. Sanity checks ----------
[ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ] && command -v pkg >/dev/null 2>&1   || die "Run this from Termux, not from inside Debian or another shell."
[ "$(id -u)" != "0" ] || die "Don't run this as root in Termux."
[[ "$DEV_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Invalid DEV_USER: '$DEV_USER'"
[[ "$LAUNCHER" =~ ^[A-Za-z0-9_.-]+$ ]]       || die "Invalid LAUNCHER: '$LAUNCHER'"

TBRC="$HOME/.bashrc"
PROPS="$HOME/.termux/termux.properties"
LAUNCH_PATH="$PREFIX/bin/$LAUNCHER"

# If the launcher name is taken by something we didn't create, don't clobber it.
# (Launchers from older versions of this script have no marker but do call proot-distro.)
if [ -e "$LAUNCH_PATH" ] && ! grep -qE "$MARK|proot-distro login $DISTRO" "$LAUNCH_PATH" 2>/dev/null; then
  die "'$LAUNCH_PATH' already exists and wasn't created by this script. Re-run with LAUNCHER=<other-name>."
fi

# ---------- 1. The one question: open Debian when Termux starts? ----------
# Defaults to the current setting, so re-running and pressing Enter changes nothing.
grep -q '# >>> debian-autostart >>>' "$TBRC" 2>/dev/null && def=y || def=n
case "${AUTOSTART:-}" in
  1|y|Y|yes) AUTOSTART=1 ;;
  0|n|N|no)  AUTOSTART=0 ;;
  *)
    if [ "$ASSUME_YES" = 1 ]; then
      [ "$def" = y ] && AUTOSTART=1 || AUTOSTART=0
    else
      [ -r /dev/tty ] || die "No terminal to ask on. Set AUTOSTART=1 or AUTOSTART=0, or pass -y."
      [ "$def" = y ] && hint="Y/n" || hint="y/N"
      while :; do
        read -r -p "Open Debian automatically every time Termux starts? [$hint] " ans </dev/tty || die "Aborted."
        case "${ans:-$def}" in
          y|Y|yes|YES) AUTOSTART=1; break ;;
          n|N|no|NO)   AUTOSTART=0; break ;;
        esac
      done
    fi
    ;;
esac

# herdr autostart isn't asked; keep whatever is set up now unless AUTO_HERDR is given.
if [ -z "${AUTO_HERDR:-}" ]; then
  proot-distro login "$DISTRO" -- grep -q CLAUDE_TERMUX_IN_HERDR "/home/$DEV_USER/.bashrc"     >/dev/null 2>&1 && AUTO_HERDR=1 || AUTO_HERDR=0
fi
case "$AUTO_HERDR" in 1|y|Y|yes) AUTO_HERDR=1 ;; *) AUTO_HERDR=0 ;; esac

# ---------- 2. Termux side ----------
log "Updating Termux packages"
# Keep existing config files instead of prompting (no 'yes |': it breaks under pipefail)
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
pkg update "${APT_OPTS[@]}"
pkg upgrade "${APT_OPTS[@]}"
pkg install "${APT_OPTS[@]}" proot-distro termux-tools

# Remove broken npm install if present (there is no Android binary)
if command -v npm >/dev/null 2>&1 && npm ls -g @anthropic-ai/claude-code >/dev/null 2>&1; then
  log "Removing Termux npm claude-code"
  npm uninstall -g @anthropic-ai/claude-code || true
fi

# ---------- 3. Debian rootfs ----------
if proot-distro login "$DISTRO" -- true >/dev/null 2>&1; then
  log "$DISTRO already installed, skipping"
else
  log "Installing $DISTRO rootfs"
  proot-distro install "$DISTRO"
fi

# ---------- 4. Inside Debian (as root) ----------
# Passed as an argument (bash -c), not on stdin, so nothing inside can swallow the script.
read -r -d '' INNER <<'EOF' || true
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  curl ca-certificates git ripgrep locales sudo less procps nano openssh-client

# Keep apt lean on a phone
cat > /etc/apt/apt.conf.d/99lean <<'APT'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Acquire::Languages "none";
APT
apt-get clean

# UTF-8 locale (TUIs render garbage without it)
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen >/dev/null
update-locale LANG=en_US.UTF-8 || true

# Non-root user (Claude Code behaves better, and some flags refuse root)
if ! id "$DEV_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$DEV_USER"
fi
echo "$DEV_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$DEV_USER"
chmod 440 "/etc/sudoers.d/$DEV_USER"

# Shell environment for the user (block is replaced on re-run)
BRC="/home/$DEV_USER/.bashrc"
touch "$BRC"
sed -i '/# >>> claude-termux >>>/,/# <<< claude-termux <<</d' "$BRC"
cat >> "$BRC" <<RC
# >>> claude-termux >>>
export PATH="\$HOME/.local/bin:\$PATH"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export TERM=xterm-256color COLORTERM=truecolor
export TMPDIR=/tmp
export XDG_RUNTIME_DIR="/tmp/runtime-\$(id -un)"
mkdir -p "\$XDG_RUNTIME_DIR" && chmod 700 "\$XDG_RUNTIME_DIR"
# Less background work on a phone (also disables auto-update: run 'claude update' now and then)
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
alias c='claude'
alias h='herdr'
RC
if [ "$AUTO_HERDR" = "1" ]; then
  cat >> "$BRC" <<'RC'
# Start herdr on login. Our own guard var: shells inside herdr panes inherit it, so herdr never nests.
# Disable for one session with:  NO_HERDR=1 dev
if [ -z "${CLAUDE_TERMUX_IN_HERDR:-}" ] && [ -z "${NO_HERDR:-}" ] && [ -t 1 ] && command -v herdr >/dev/null; then
  export CLAUDE_TERMUX_IN_HERDR=1
  herdr
fi
RC
fi
echo '# <<< claude-termux <<<' >> "$BRC"
chown "$DEV_USER:$DEV_USER" "$BRC"

# Install herdr then Claude Code, as the user
su - "$DEV_USER" -c '
  set -e
  mkdir -p ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"
  echo "--- installing herdr"
  curl -fsSL https://herdr.dev/install.sh | sh
  echo "--- installing claude"
  curl -fsSL https://claude.ai/install.sh | bash
  herdr --version || true
  claude --version || true
' </dev/null
EOF

log "Configuring Debian: packages, locale, user '$DEV_USER'"
proot-distro login "$DISTRO" -- env DEV_USER="$DEV_USER" AUTO_HERDR="$AUTO_HERDR" bash -c "$INNER"

# ---------- 5. Launcher ----------
log "Creating launcher: '$LAUNCHER'"
cat > "$LAUNCH_PATH" <<LAUNCH
#!/data/data/com.termux/files/usr/bin/bash
$MARK
# Hold a wake lock only while Debian is open, so Android doesn't throttle the CPU mid-task
termux-wake-lock 2>/dev/null || true
trap 'termux-wake-unlock 2>/dev/null || true' EXIT
BINDS=(--bind "\$HOME:/home/$DEV_USER/termux")
[ -r /storage/emulated/0 ] && BINDS+=(--bind "/storage/emulated/0:/home/$DEV_USER/sdcard")
# Pass NO_HERDR through so 'NO_HERDR=1 $LAUNCHER' skips herdr autostart once
proot-distro login $DISTRO --user $DEV_USER --shared-tmp "\${BINDS[@]}" \\
  \${NO_HERDR:+--env NO_HERDR=1} "\$@"
LAUNCH
chmod +x "$LAUNCH_PATH"

# ---------- 6. Autostart ----------
touch "$TBRC"
if grep -q '# >>> debian-autostart >>>' "$TBRC"; then
  cp "$TBRC" "$TBRC.bak.$(date +%s).$$"
  sed -i '/# >>> debian-autostart >>>/,/# <<< debian-autostart <<</d' "$TBRC"
fi
if [ "$AUTOSTART" = 1 ]; then
  log "Enabling Debian autostart (touch ~/.no-debian to disable)"
  cat >> "$TBRC" <<AS
# >>> debian-autostart >>>
if [ -t 1 ] && [ -z "\${DEBIAN_STARTED:-}" ] && [ ! -f "\$HOME/.no-debian" ]; then
  export DEBIAN_STARTED=1
  $LAUNCHER
  echo "Back in Termux. Type '$LAUNCHER' to re-enter Debian."
fi
# <<< debian-autostart <<<
AS
fi

# ---------- 7. Termux UI tweaks ----------
if ! grep -q '^extra-keys' "$PROPS" 2>/dev/null; then
  log "Adding extra keys (Esc/Tab/Ctrl/arrows) for Claude's TUI"
  mkdir -p "$HOME/.termux"
  touch "$PROPS"
  cp "$PROPS" "$PROPS.bak.$(date +%s).$$"
  cat >> "$PROPS" <<'P'
extra-keys = [['ESC','TAB','CTRL','ALT','/','-','UP','ENTER'],['|','~','HOME','LEFT','DOWN','RIGHT','END','PGDN']]
terminal-cursor-blink-rate = 0
P
  termux-reload-settings 2>/dev/null || true
fi

log "Done."
if [ "$AUTOSTART" = 1 ]; then
  echo "Restart Termux to enter Debian automatically, or run '$LAUNCHER' now."
else
  echo "Run '$LAUNCHER' to enter Debian."
fi
if [ "$AUTO_HERDR" = 1 ]; then
  echo "herdr starts on entry (skip once with: NO_HERDR=1 $LAUNCHER). Run 'claude' in a pane."
else
  echo "Then run 'herdr' and start 'claude' in a pane (or run 'claude' directly)."
fi
