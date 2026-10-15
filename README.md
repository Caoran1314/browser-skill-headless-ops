# BrowserSkill headless ops

Get **[Tencent BrowserSkill](https://github.com/Tencent/BrowserSkill)** (`bsk`) working on a
**headless Linux box** (NAS / VPS / container) — no display, no desktop browser.

BrowserSkill normally needs a browser with its extension installed, and the extension is
*only* installable by a human clicking a store page. On a headless server you can still
close the loop: download the store CRX, unpack it, and load it into a **headless Chromium**
with `--load-extension`. The extension then dials the local daemon
(`ws://127.0.0.1:52800`) exactly as it would in a desktop browser, and an agent can drive
it through the `bsk` CLI.

> ⚠️ **This browser has a fresh profile and no logins.** It proves the chain works and gives
> an agent an anonymous browser. For tasks that need the user's own sessions, use
> BrowserSkill's remote/server mode with the extension in *their* browser. Never extract
> credentials, cookies, or tokens.

## What's here

| Path | Purpose |
| --- | --- |
| `SKILL.md` | Agent-facing skill (Hermes skill format): procedure, pitfalls, verification. |
| `scripts/fetch-extension-crx.sh` | Store CRX → unpacked extension dir (parses CRX2/CRX3 headers). |
| `scripts/start-headless-browser.sh` | Headless Chromium + `--load-extension`, idempotent, binary auto-detect. |
| `scripts/bsk-browser-watch.sh` | Watchdog: restarts the browser if it died, silent while healthy. |

## Quickstart

```sh
# 1. CLI (official installer, SHA-256 verified)
curl -fsSL https://raw.githubusercontent.com/Tencent/BrowserSkill/main/install.sh | sh
BSK="$HOME/.local/bin/bsk"; "$BSK" --version

# 2. Skill for your agent harness (DSH users: install the plugin instead)
"$BSK" install-skill --list --json
"$BSK" install-skill --harness hermes --json     # or cursor / claude-code / codex / …

# 3. Browser side
sh scripts/fetch-extension-crx.sh "$HOME/bsk-ext"
setsid sh scripts/start-headless-browser.sh >"$HOME/bsk-ext/watch.log" 2>&1 &
sleep 12

# 4. Verify
BSK_AUTO_START=0 "$BSK" doctor                     # expect 8x ok
BSK_AUTO_START=0 "$BSK" browsers --json            # expect one instance_id, no version_skew
SID=$("$BSK" session start --json | sed 's/.*"session_id": *"\([^"]*\)".*/\1/')
"$BSK" navigate https://example.com --session "$SID"
"$BSK" observe --session "$SID" | head             # must show RootWebArea AND @e1, @e2, …
"$BSK" session stop "$SID"

# 5. Keep it up (silent when healthy — cron-friendly)
sh scripts/bsk-browser-watch.sh
```

Verified chain: `bsk 0.3.3` / protocol 1.3 · Chromium 156 (Playwright build) · extension
0.3.3 · Linux x64. End-to-end: `start → navigate → observe(@eN) → fill UTF-8 → click →
select → screenshot → real link navigation → stop`, ending with `sessions: []`.

## Watchdog / cron

`bsk-browser-watch.sh` prints one line **only on a state change** (`restarted`,
`extension-missing`, `recovered`) and nothing while healthy, so it can run every 10
minutes without spamming. With Hermes:

```
cronjob(action='create', name='bsk browser watchdog', schedule='*/10 * * * *',
        no_agent=True, script='bsk-browser-watch.sh', deliver='<your channel>')
```

## Pitfalls worth knowing before you start

1. **Editing the installed skill pauses its updates.** `bsk doctor` then warns
   `automatic updates paused … local changes detected`. Keep local notes outside the
   managed skill, or own the source with
   `bsk install-skill --harness <id> --source <your-dir> --force`.
2. **`--headless=new` is mandatory** — the legacy headless mode never registers MV3
   extensions, so `bsk doctor` reports `0 browsers connected` forever. Add `--no-sandbox`
   in containers.
3. **Playwright's path moved:** newer revisions ship `chrome-linux64/chrome`, older ones
   `chrome-linux/chrome`.
4. **`pkill -f "user-data-dir=<path>"` kills your own shell** (the pattern is in the
   command line you are running). Use `pgrep -f 'user-data-di[r]=…'` or kill by PID.
5. **Some agent hosts spawn non-login shells** with a sanitized `PATH`, so `bsk` is not
   found even after install — always keep the absolute path handy, and pass the same
   `BSK_HOME`/`BSK_AUTO_START` on every call.
6. **The extension is online only while the browser runs**; keep the process detached
   (`setsid`) or in a supervisor. Reopening the browser reconnects automatically.
7. **Never delete `~/.bsk/daemon.lock`** (a held file-handle lock) and never restart a
   shared daemon as a "fix" — `lock is already held by another process` means a daemon is
   correctly running.
8. **`bsk doctor` is not the finish line.** An uninstalled skill shows `N/A` (not a
   failure), and only `extension connected` gates sessions — always finish with a real
   `start → observe → stop` round-trip that returns `@eN` refs.

## 中文速览

BrowserSkill 默认要求"人已在浏览器里装好扩展"，无显示器的服务器上跑不通。本仓库给出闭环做法：
从 Chrome 商店取 CRX → 解包 → 用 `--headless=new --load-extension` 把一个 **headless Chromium**
拉起，扩展就会像桌面浏览器一样拨号本地守护进程（`ws://127.0.0.1:52800`），agent 即可用 `bsk`
CLI 操作它。附带一个"健康则静默、掉了自动拉起、绝不重启已有守护进程"的值守脚本，可按 10 分钟
跑 cron。**注意：这个浏览器是全新 profile、没有登录态**，只能证明链路可用/给 agent 一个匿名浏览器；
要用用户自己的登录态，请走 BrowserSkill 的 server/remote 模式。

## License

MIT © 2026 Caoran1314. BrowserSkill itself is Tencent's — see its own repository and
license.
