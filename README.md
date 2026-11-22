# ai

Run Claude Code or Cursor Agent inside a sandboxed Docker container.

Slash commands, skills and hooks live in [michalkowol/ai-tools](https://github.com/michalkowol/ai-tools), a Claude Code plugin marketplace. Install it once in a session started with `ai`, and `claude/.claude/` keeps it for every later run:

```
/plugin marketplace add michalkowol/ai-tools
/plugin install mk@michalkowol
```

Cursor Agent also reads the Claude Code plugins kept in `claude/.claude/`, so `ai --cursor` gets the same commands, skills and hooks. Cursor honors the guard hook's deny decisions but ignores its ask decisions, so commands such as `gh pr create` run there without confirmation.

## Why

Keep AI coding assistants isolated from the host while reusing a single set of commands, skills and hooks across both tools.

## Requirements

- Docker

## Setup

```bash
git clone https://github.com/michalkowol/ai.git
cd ai
./ai
```

You can clone the repo anywhere — the launcher resolves its own location. For
convenience, symlink it onto your `PATH`:

```bash
ln -s "$(pwd)/ai" ~/.local/bin/ai
```

## Usage

```bash
ai                      # Claude Code (default), current directory
ai --claude path/       # Claude Code in a specific directory
ai --cursor path/       # Cursor Agent
ai --bash path/         # Plain bash shell in the container
ai --model sonnet       # Pick the model (default: opus)
ai --without-dashboard  # Do not start the sessions dashboard
ai --model sonnet path/ # Combine with any tool/path
ai --update             # Update Claude Code to its latest version (rebuilds only its layers)
ai --update-all         # Rebuild the whole image from scratch with fresh base images
```

The given path is mounted as `/workspace` inside the container. Git worktrees
are detected and their common git dir is mounted automatically.

Cursor Agent is installed only in a separate `ai-cursor` image (the `cursor` stage of the Dockerfile),
built the first time you run `ai --cursor`. Claude Code and `--bash` use the `ai` image without it.

The `--model` flag picks the model the agent runs with. Claude Code defaults to
`opus`; pass e.g. `--model sonnet` to override. Cursor Agent uses its own model
names (`gpt-5`, `sonnet-4-thinking`, …), so the flag is only forwarded there
when given explicitly. It is not supported with `--bash`.

## Toolchains

The image ships with [mise](https://mise.jdx.dev) and these preinstalled runtimes:

| Tool | Versions | Global default |
| --- | --- | --- |
| Node.js | `lts/jod` (22), `lts/lithium` (26) | `lts/lithium` |
| Python | latest 3.x | latest 3.x |
| Java (Temurin) | 11, 21, 25 | 25 |

Pick a version per project with a `mise.toml` in the repo (or `mise use java@temurin-21`
inside the container). mise shims are on `PATH`, so the choice also applies to
non-interactive commands. Other versions can be added with `mise install`, but they live in
the container and are gone once it exits.

### Dependency caches

Downloaded dependencies are shared with the host, so they are not fetched again on every run:

- `~/.m2` is mounted read-write.
- `~/.gradle` is mounted read-only and used as Gradle's read-only dependency cache, because Gradle's
  cache locks do not work across the host and containers. New dependencies go to the container's own cache.
- `~/.npm` is mounted read-write. The npm cache is content-addressed and safe for concurrent use.

## Dashboard

Every `ai` run starts a single `ai-dashboard` container serving
http://localhost:8787: live and recently ended Claude Code sessions, what each
one is doing right now and which ones wait for input. It refreshes every 3 s.
Click the **Notifications** button to allow browser notifications when a session needs input or finishes a
turn; the label always shows the current state (`Notifications on` / `Notifications off`).

It installs as a PWA, with the Claude mark as its icon: in Chrome pick
**Install** from the address bar, in Safari **File → Add to Dock**. The
installed app runs in its own window and keeps the notifications.

- a card pulses while its session waits for you, click anywhere to acknowledge and stop the pulse
- **Flash** and **Sound** each cycle through three states on click, off → on → on (loop) → off, and the
  label always shows the current one. **Flash on** flashes the whole page red once, **Flash on (loop)** keeps
  flashing until acknowledged. **Sound on** pings the Nostromo sonar (two low pings) once, **Sound on (loop)**
  repeats it every 6 s. The two are independent and both are remembered
- both follow the same trigger as the notifications: any session that needs input or has just finished its
  turn, so a session you have just opened or resumed with `ai` stays quiet until its first turn ends. A click
  anywhere on the page dismisses them, the next session that needs you brings them back. The browser keeps the
  sound muted until you have clicked the page once
- **Ntfy** pushes the same alerts to [ntfy.sh](https://ntfy.sh), so they reach your phone: switch it on, type a
  topic into the field next to the button and subscribe to that topic in the ntfy app. Switching it on with a
  topic already set sends a test push. The topic is the only secret, anyone who knows it can read and publish
  to it, so pick something unguessable. Pushes go out only while a dashboard tab is open
- the **Compact view** button trims each card down to status, title, the branch/model/effort line, what it does now,
  elapsed, cost and tokens, dropping the session id; the choice is remembered
- the **Ended in the last 24 h** tile carries the summed cost of those sessions (`~$3.75`), taking the higher
  of the recorded and the estimated cost of each one
- live cards show an estimated cost and token count (`~$1.20`, `~8.6M`) summed from the token usage in the
  transcript, because Claude Code records its own cost only when a session exits or compacts its context; the card
  shows whichever of the two is higher, as both are lower bounds. Subagent calls never land in the transcript, so
  sessions that lean on subagents read low. Ended sessions show the exact cost
- the theme follows the operating system, the **Dark mode** / **Light mode** button overrides it
- `ai --without-dashboard` skips it, `AI_DASHBOARD_PORT=9000 ai` changes the port
- `docker restart ai-dashboard` after editing `dashboard/`, `docker rm -f ai-dashboard` stops it
- the service worker goes to the network first and only caches the app shell, so a reload
  always picks up an edited `dashboard/` instead of a stale copy
- each container gets a private session registry in `claude/.claude/ai-runs/<run-id>/`,
  removed when the container exits

## herdr

`ai` runs inside [herdr](https://herdr.dev) panes on the host for persistence and working/blocked/idle tracking. Since herdr only sees `docker`, `ai` sets `HERDR_AGENT=claude`/`cursor` on `docker run` (host-only; `--bash` skips it).

- no `herdr integration install` needed, the container has its own `~/.claude`
- after a herdr restart, resume with `ai --resume <session-id>` (id on the dashboard card)
- keep the herdr socket out of the container: its API runs arbitrary host commands

## GitHub CLI

`gh` comes from Ubuntu's package repository, so its version follows the Ubuntu release
rather than tracking upstream releases.

Give it a **dedicated token** — not your own.

### Create the token

Use a **classic** token, not fine-grained. A fine-grained token is scoped to a single resource
owner, so it cannot span more than one organization.

At [github.com/settings/tokens/new](https://github.com/settings/tokens/new?scopes=repo,read:org&description=ai-container)
— that link preselects both scopes below.

| Scope | What it buys |
| --- | --- |
| `repo` | the only way to reach pull requests and issues in private repos — classic tokens have no narrower pull-request scope. Tick the parent box; the children come with it |
| `read:org` | resolves org and team membership. Needed because a review request often targets a **team** rather than you personally, and those PRs are invisible without it |

### Hand the token to the container

Keep it in `~/.config/ai/settings.env` (or `$XDG_CONFIG_HOME/ai/settings.env`) on the host, outside this repo, so it is never committed:

```bash
mkdir -p ~/.config/ai
printf 'GH_TOKEN=ghp_...\n' > ~/.config/ai/settings.env
chmod 600 ~/.config/ai/settings.env
```

## Browser (Playwright MCP)

The image ships with [Playwright MCP](https://github.com/microsoft/playwright-mcp) and a headless Chromium,
so the agent can drive a browser inside the container. Google Chrome has no arm64 Linux build, so it uses
Playwright's Chromium. Register it once inside the container. It is stored in `claude/.claude.json`, so later runs keep it:

```bash
claude mcp add --scope user playwright -- playwright-mcp --headless --isolated --browser chromium
```

- `--headless` is required: the container has no display.
- `--isolated` keeps the browser profile in memory, so every session starts clean.

The browser runs in the container, so it reaches a dev server started there at `localhost`, and host apps at
`host.docker.internal`. Screenshots and downloads stay in the container file system unless saved under `/workspace`.

The system libraries Chromium needs are installed too, so Playwright tests in a project can run headless as well.
Browsers built for a different Playwright version than the one in the image are downloaded with
`npx playwright install chromium` and live in the container until it exits.

### Visible browser on the host

To watch the browser, add a second server, `playwright-host`, that runs on the host and is reached over HTTP.
Both stay registered, so you pick one per task, e.g. "use playwright-host". Start it on the host when you need it:

```bash
npx @playwright/mcp@latest --port 8931 --host 0.0.0.0 --isolated --allowed-hosts host.docker.internal:8931
```

- `--host 0.0.0.0` is required: by default the server listens only on `localhost`, which the container cannot reach
  (ECONNREFUSED). It also exposes the server to your local network, so stop it when you are done.
- `--allowed-hosts` is required: the server only accepts `Host: localhost` by default and answers the container with 403.

Register it once inside the container:

```bash
claude mcp add --scope user --transport http playwright-host http://host.docker.internal:8931/mcp
```

While the host server is not running, Claude reports `playwright-host` as failed to connect at startup. That is
expected and does not affect `playwright`.

That browser runs on the host, so it reaches host apps at `localhost`. A dev server started inside the
container is not visible to it unless you publish its port. The browser and the MCP server run with your
host permissions, and file uploads and downloads use the host file system, so do not leave the server running.

If Claude keeps failing with `SDK auth failed: Dynamic Client Registration rejected`, it saw an error once
(e.g. the 403 above) and cached the server as needing OAuth. Playwright MCP needs none. Quit Claude, then
remove the `playwright-host|…` entry under `mcpOAuth` in `claude/.claude/.credentials.json` and the `playwright-host`
key in `claude/.claude/mcp-needs-auth-cache.json`, and start `ai` again.

## Layout

```
.
├── Dockerfile         # Ubuntu + mise (Node, Python, Java) + Playwright MCP + Chromium + Claude + Docker CLI + gh; Cursor in its own stage
├── ai                 # Launcher script
├── dashboard/         # Sessions dashboard: server.py + index.html + PWA manifest, service worker, icons
├── claude/            # Per-tool config mounted into the container
├── cursor/
└── config/
    └── claude/        # managed-settings.json -> /etc/claude-code/
```

## License

MIT
