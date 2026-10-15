---
name: browser-skill-headless-ops
description: "Run BrowserSkill's bsk CLI against headless Chromium."
version: 0.1.0
author: Caoran1314, Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [browser-automation, browserskill, headless, chromium, ops]
    related_skills: [github-repo-management]
---

# BrowserSkill Headless Ops Skill

Get [Tencent BrowserSkill](https://github.com/Tencent/BrowserSkill) (`bsk`) working on a
**headless Linux server** by loading the store extension into a headless Chromium, then
driving it with the `bsk` CLI from an agent. Covers CLI + harness-skill install, CRX
unpacking, browser launch, a self-healing watchdog, and end-to-end verification.

**Scope limit, read first:** a headless Chromium has a *fresh profile with no logins*.
This skill proves the chain works and gives an agent an anonymous browser — it does
**not** give access to a user's authenticated sessions. For real logins use BrowserSkill's
remote/server mode with the extension installed in the user's own browser. Never extract
credentials, cookies, or tokens.

## When to Use

- A headless server/NAS/container must run `bsk`, and `bsk doctor` fails with
  `extension connected` / `no_browser_connected`.
- You need a persistent, agent-controllable browser on a machine with no display.
- You are installing BrowserSkill for a non-listed agent harness (Hermes, Cursor,
  Codex, …) and want the skill + verification before touching the user's own browser.
- Don't use for: the user's logged-in browser (use the extension in their browser or
  server mode), or for credentials/PII extraction.

## Prerequisites

- Linux x64/arm64 with `curl`, `python3`, `git`; `~/.local/bin` writable.
- Outbound access to `github.com`, `clients2.google.com`, and the sites you will visit.
  Behind a proxy, export `https_proxy`/`http_proxy` for install and CRX download; a
  Chromium launched without proxy flags will not use it.
- A Chromium/Chrome binary ≥ 116 (extensions need `--headless=new`; old headless
  never loads them). Playwright's cache works:
  `~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome`.

## How to Run

```sh
# 1. CLI (SHA-256 verified by the official installer)
curl -fsSL https://raw.githubusercontent.com/Tencent/BrowserSkill/main/install.sh | sh
BSK="$HOME/.local/bin/bsk"; "$BSK" --version

# 2. Harness skill — DSH: plugin (bundled skill). Others: bsk install-skill
"$BSK" install-skill --list --json          # find your harness id + skills_dir
"$BSK" install-skill --harness hermes --json

# 3. Extension CRX -> unpacked dir, then headless browser with it loaded
sh scripts/fetch-extension-crx.sh "$HOME/bsk-ext"
setsid sh scripts/start-headless-browser.sh &     # or run under your supervisor
sleep 12

# 4. Watchdog: silent while healthy, restarts the browser if it dies
sh scripts/bsk-browser-watch.sh
```

Frame these as `terminal(command="…", timeout=…)` calls; for a Hermes cron watchdog,
`cronjob(action='create', no_agent=True, script='bsk-browser-watch.sh',
schedule='*/10 * * * *')` — empty stdout stays silent, non-empty output notifies.

## Quick Reference

| Task | Command |
| --- | --- |
| Health, 8 rows | `bsk doctor` |
| Connected browsers | `bsk browsers --json` |
| Daemon state | `BSK_AUTO_START=0 bsk status --json` |
| Start session | `bsk session start --json` → `session_id` |
| Navigate / read | `bsk navigate <url> --session <id>`; `bsk observe --session <id>` |
| Interact by ref | `bsk fill @e3 --value "…" --session <id>`; `bsk click @e3 --session <id>` |
| Screenshot | `bsk screenshot --session <id> --full-page --out out.png` |
| Stop (always) | `bsk session stop <id>` |

## Procedure

1. **Install the CLI and verify by absolute path.** Completion: `bsk --version` prints a
   version from the installed binary, not a PATH lookup (a running agent may keep an
   old PATH; some hosts spawn non-login shells that never read `~/.bashrc`).
2. **Pick the right distribution form.** DSH = plugin (ships its own skill; skip
   `bsk install-skill`). Other harnesses = `bsk install-skill --harness <id> --json`.
   Unlisted harnesses: copy the repo's `crates/bsk-cli/skill/` to the harness skills
   dir as `browser-skill/`, `references/` included. Completion: the skill's
   `SKILL.md` exists in the harness skills dir and `bsk doctor` no longer prints
   `N/A  agent skill matches bundled CLI`.
3. **Dump the store extension to an unpacked dir.** `scripts/fetch-extension-crx.sh`
   downloads the CRX3 and strips the `Cr24` header to find the ZIP payload.
   Completion: it prints `extension BrowserSkill <version> mv 3`.
4. **Launch headless Chromium with the extension.** `--headless=new --no-sandbox
   --disable-gpu --disable-dev-shm-usage --disable-extensions-except=<ext>
   --load-extension=<ext> --user-data-dir=<profile>`. Detach it (`setsid`) so it
   outlives your shell. Completion: `bsk browsers --json` lists an `instance_id` with
   `extension_version` equal to the CLI version and `version_skew: false`.
5. **Start the daemon and check identity.** Any ordinary `bsk` command auto-starts it in
   local mode; `BSK_AUTO_START=0 bsk status --json` must show `daemon_version`,
   `protocol_version`, and a `pid`. Completion: `bsk doctor` shows 8 rows, all `ok`.
6. **Run the end-to-end task.** `session start` → `navigate` → `observe` → interact →
   `screenshot` → `click` a link (real navigation) → `session stop`. Completion:
   `observe` returns `RootWebArea` **plus `@eN` refs**, a Chinese/UTF-8 value survives
   `fill` + re-`observe` round-trip, and `status --json` ends with `sessions: []`.
7. **Add the watchdog.** `scripts/bsk-browser-watch.sh` restarts the browser only when
   the process is gone, starts the daemon only when nothing is listening, and prints
   nothing while healthy. Completion: silent `exit 0` when healthy; kill the browser
   and the next run prints one line and `bsk browsers` shows 1 again.

## Pitfalls

- **Editing the installed skill pauses its updates.** Touching
  `<skills_dir>/browser-skill/SKILL.md` makes `bsk doctor` report
  `WARN agent skill matches bundled CLI … automatic updates paused … local changes
  detected`. Keep local notes outside the managed skill (agent memory), or own the
  source: `bsk install-skill --harness <id> --source <your-dir> --force`.
- **Extension version skew is silent until you look.** `bsk browsers --json`
  `extension_version` vs `bsk --version`; store review lags releases. Upgrade CLI +
  extension first, then plugins.
- **`--headless=new` is required**; extensions (MV3 service worker) never register in
  legacy headless, so the daemon sees zero browsers. Containers also need `--no-sandbox`.
- **Playwright binary paths move:** newer revisions use `chrome-linux64/chrome`, older
  `chrome-linux/chrome`. Glob both before failing.
- **`pkill -f "user-data-dir=<path>"` kills your own shell** — the pattern appears in
  the command line running it. Use `pgrep -f 'user-data-di[r]=…'` (character class
  breaks self-match) or kill by PID.
- **The extension is only online while the browser runs.** Closing the browser gives
  `browser disconnected`; reopening reconnects automatically (the extension is the
  client, dialing `ws://127.0.0.1:52800` in local mode).
- **Never delete `~/.bsk/daemon.lock`** (a held file-handle lock, released on exit) and
  never restart a shared daemon to "recover" — `lock is already held by another
  process` means a daemon is correctly running.
- **`doctor` alone proves nothing** about the skill being installed or the browser
  being usable: an uninstalled skill shows `N/A`, and `extension connected` is the row
  that actually gates sessions. Always finish with step 6.
- **A headless browser has no user logins** and cannot be made to have them; do not
  route an authenticated task through it.

## Verification

```sh
BSK="$HOME/.local/bin/bsk"
BSK_AUTO_START=0 "$BSK" doctor | grep -c '^ok'        # 8
BSK_AUTO_START=0 "$BSK" browsers --json | grep -c instance_id   # >= 1
SID=$("$BSK" session start --json | sed 's/.*"session_id": *"\([^"]*\)".*/\1/')
"$BSK" navigate https://example.com --session "$SID"
"$BSK" observe --session "$SID" | grep -E 'RootWebArea|@e[0-9]'
"$BSK" session stop "$SID"; BSK_AUTO_START=0 "$BSK" status --json | grep -c '"sessions": \[\]'
```

All four checks pass on the tested matrix (bsk 0.3.3, protocol 1.3, Chromium 156 via
Playwright, extension 0.3.3, Linux x64).
