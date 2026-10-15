#!/bin/sh
# Launch a headless Chromium with the unpacked BrowserSkill extension loaded, so the
# bsk daemon (local mode, ws://127.0.0.1:52800) sees a browser and sessions can start.
#
# Usage: start-headless-browser.sh
# Env:
#   BSK_EXT_DIR   unpacked extension parent dir (default $HOME/bsk-ext; uses <dir>/ext)
#   BSK_PROFILE   Chromium user-data-dir     (default <BSK_EXT_DIR>/profile)
#   BSK_CDP_PORT  remote debugging port      (default 9222, loopback only)
#   BSK_WINDOW    initial window size        (default 1280,800)
#   CHROME        Chromium/Chrome binary     (default: first found in the globs below)
#
# Run it detached so it outlives your shell:  setsid sh start-headless-browser.sh >log 2>&1 &
set -eu

EXT=${BSK_EXT_DIR:-$HOME/bsk-ext}
EXTDIR=$EXT/ext
PROFILE=${BSK_PROFILE:-$EXT/profile}
PORT=${BSK_CDP_PORT:-9222}
WINDOW=${BSK_WINDOW:-1280,800}

[ -d "$EXTDIR" ] || { echo "no unpacked extension at $EXTDIR — run fetch-extension-crx.sh first" >&2; exit 1; }

if [ -z "${CHROME:-}" ]; then
    for c in "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux64/chrome \
             "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux/chrome \
             "$HOME"/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux*/chrome \
             "$(command -v chromium 2>/dev/null || true)" \
             "$(command -v chromium-browser 2>/dev/null || true)" \
             "$(command -v google-chrome 2>/dev/null || true)" \
             "$(command -v google-chrome-stable 2>/dev/null || true)"; do
        [ -n "$c" ] && [ -x "$c" ] && { CHROME=$c; break; }
    done
fi
[ -n "${CHROME:-}" ] || { echo "no Chromium binary found — set CHROME=/path/to/chrome" >&2; exit 1; }

# Idempotent: never start a second browser on the same profile (two would fight over it).
if pgrep -f "user-data-dir=$PROFILE" >/dev/null 2>&1; then
    echo "already running (profile $PROFILE)"
    exit 0
fi

"$CHROME" --version >&2
exec "$CHROME" \
    --headless=new \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --no-first-run \
    --no-default-browser-check \
    --window-size="$WINDOW" \
    --user-data-dir="$PROFILE" \
    --disable-extensions-except="$EXTDIR" \
    --load-extension="$EXTDIR" \
    --remote-debugging-port="$PORT" \
    about:blank
