# CLAUDE.md

## What this repo is

`termux-claude-setup.sh` is a single bash script run on an Android phone, from plain Termux. It sets up Debian with `proot-distro`, creates a non-root user, and installs herdr and then Claude Code inside Debian. Claude Code has no `linux-arm64-android` build, so it has to run in Debian, which reports `linux-arm64`. herdr's installer also refuses when `uname -o` is `Android`.

## Layout of the script

1. Sanity checks: must run from Termux and not as root. Validates `DEV_USER` and `LAUNCHER`, and refuses to overwrite a launcher it didn't create.
2. Banner and plan, then the `Proceed?` prompt. Nothing may change before this point (read-only checks only).
3. Termux packages: `pkg update`/`upgrade`/`install`, and removal of the broken npm `claude-code`.
4. Debian setup: the `INNER` script, run as root with `proot-distro login debian -- bash -c "$INNER"`.
5. Termux side: the `$PREFIX/bin/$LAUNCHER` launcher, then the post-install `AUTOSTART` prompt and the autostart block in `~/.bashrc`, then extra keys in `~/.termux/termux.properties`.

## Conventions

- **Idempotent.** Every re-run must be safe. Blocks the script owns sit between markers (`# >>> name >>>` / `# <<< name <<<`) and are deleted and rewritten, never appended twice. The launcher carries `# managed-by: termux-claude-setup`.
- **Two prompts only:** `Proceed?` before any change, and Debian autostart after installing (it defaults to the current state, so re-runs don't flip it). Don't add prompts for other steps; other behavior is set with env vars (`AUTO_HERDR`, `DEV_USER`, `LAUNCHER`). Prompts go through `ask()`, which reads from `/dev/tty` and can be answered with an env var or `-y`.
- **Keep Claude's auto-updater on.** Don't set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` or `DISABLE_AUTOUPDATER`; use `DISABLE_TELEMETRY` and `DISABLE_ERROR_REPORTING` instead.
- **Banner** must fit a phone: the big art is 49 columns, and there's a small fallback when the terminal is narrower than 50.
- **Back up before editing the user's Termux files:** `*.bak.$(date +%s).$$`.
- **Don't put `yes |` in front of a command.** It fails under `set -o pipefail` (exit 141). Use `-y` with the dpkg `--force-confdef`/`--force-confold` options.
- **Keep the body inside the top-level `{ ... exit; }`.** Bash then reads the whole script before running it, so the `curl ... | bash` one-liner is safe. Code added after the closing `}` would break this.
- **Pass the inner script as an argument** (`bash -c`), not on stdin, and give child installers `</dev/null`, so nothing reads the script itself.
- **Watch heredoc quoting.** In the unquoted `<<RC` / `<<LAUNCH` heredocs, `$VAR` expands when the script writes the file and `\$VAR` expands when the generated file runs.
- **LF line endings only** (enforced by `.gitattributes`). With CRLF, bash fails on the phone.
- **Text style:** use hyphens, not em or en dashes, in docs, comments and messages.

## Testing

There's no Android device in CI. To check the script:

```bash
bash -n termux-claude-setup.sh
```

Then run the flow with stub commands. Make a temp dir with `usr/bin/{pkg,proot-distro,termux-reload-settings,termux-wake-lock}` as scripts that `exit 0`, and run:

```bash
env -i PATH="$T/usr/bin:/usr/bin:/bin" PREFIX=$T/usr HOME=$T/home AUTOSTART=1 bash termux-claude-setup.sh
```

To test the prompts, make a copy that reads answers from fd 3, then feed it answers:

```bash
sed -e 's#</dev/tty#<\&3#g' -e 's#\[ -r /dev/tty \]#true#' termux-claude-setup.sh > "$T/s.sh"
env -i PATH="$T/usr/bin:/usr/bin:/bin" PREFIX=$T/usr HOME=$T/home bash "$T/s.sh" 3< <(printf '\ny\n')
```

A plain answers file won't work, because each prompt reopens it and reads the first line again.

After a run, check the generated `$T/home/.bashrc`, `$T/usr/bin/dev` and `$T/home/.termux/termux.properties`. Anything inside Debian (apt, su, the installers) can only be checked on a real device.
