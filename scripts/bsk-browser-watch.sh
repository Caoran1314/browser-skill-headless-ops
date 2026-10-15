#!/bin/sh
# Watchdog for the headless BrowserSkill chain.
#
# Every run it makes sure (a) the bsk daemon is reachable, (b) a Chromium with the
# extension is running, (c) the extension is actually connected. It restarts only what
# is missing and NEVER restarts a running daemon or touches ~/.bsk files.
#
# Output contract (cron / no_agent friendly): prints one line on a state *change*
# (restarted, broken, recovered) and nothing while healthy => no notification spam.
#
# Env: BSK (bsk path), BSK_EXT_DIR, BSK_PROFILE, BSK_START_SCRIPT, BSK_WAIT (default 12)
set -u

BSK=${BSK:-}
if [ -z "$BSK" ]; then
    BSK=$(command -v bsk 2>/dev/null || true)
fi
[ -n "$BSK" ] || BSK=$HOME/.local/bin/bsk

EXT=${BSK_EXT_DIR:-$HOME/bsk-ext}
PROFILE=${BSK_PROFILE:-$EXT/profile}
START=${BSK_START_SCRIPT:-$(dirname "$0")/start-headless-browser.sh}
WAIT=${BSK_WAIT:-12}
STATE_FILE=$EXT/watch.state
LOG=$EXT/watch.log

prev=$(cat "$STATE_FILE" 2>/dev/null || echo unknown)
mkdir -p "$EXT"

if [ ! -x "$BSK" ]; then
    state=cli-missing
else
    running=0
    if pgrep -f "user-data-dir=$PROFILE" >/dev/null 2>&1; then
        running=1
    else
        # The CLI auto-starts its daemon on any ordinary command; start it explicitly
        # only when nothing is listening (never restart a live one).
        if ! BSK_AUTO_START=0 "$BSK" status --json >/dev/null 2>&1; then
            BSK_AUTO_START=0 "$BSK" daemon start >>"$LOG" 2>&1 || true
        fi
        CHROME=${CHROME:-} setsid sh "$START" >>"$LOG" 2>&1 &
        sleep "$WAIT"
    fi

    browsers=$(BSK_AUTO_START=0 "$BSK" browsers --json 2>/dev/null | grep -c '"instance_id"' || true)
    if [ "${browsers:-0}" -lt 1 ]; then
        state=extension-missing
    elif [ "$running" -eq 1 ]; then
        state=ok
    else
        state=restarted
    fi
fi

case "$state" in
    ok)
        if [ "$prev" = ok ] || [ "$prev" = unknown ]; then
            :
        else
            echo "bsk watchdog: recovered — extension connected ($browsers browser(s) online, previous state: $prev)"
        fi
        ;;
    restarted)
        echo "bsk watchdog: browser was down and has been restarted ($browsers browser(s) online)."
        ;;
    extension-missing)
        if [ "$prev" != extension-missing ]; then
            echo "bsk watchdog: Chromium is running but the extension is not connected to the daemon. Log: $LOG — run \`$BSK doctor\`."
        fi
        ;;
    cli-missing)
        echo "bsk watchdog: bsk CLI not found at $BSK (set BSK=/path/to/bsk)."
        ;;
esac

echo "$state" >"$STATE_FILE"
exit 0
