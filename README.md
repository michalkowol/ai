# ai

Run Claude Code or Cursor Agent inside a sandboxed Docker container with your
own shared commands, skills, and rules mounted in.

## Why

Keep AI coding assistants isolated from the host while reusing a single set of
prompts, slash commands, and configuration across both tools.

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
ai --java 21            # Build the Java image with a specific version (default: 25)
ai --node jod           # Build the Node.js image with a specific tag
ai --model sonnet       # Pick the model (default: opus)
ai --without-dashboard  # Do not start the sessions dashboard
ai --java 21 path/      # Combine with any tool/path
```

The given path is mounted as `/workspace` inside the container. Git worktrees
are detected and their common git dir is mounted automatically.

The `--java` flag selects the `eclipse-temurin:<version>` base image and tags
the built image as `ai:java<version>`. The `--node` flag selects the
`node:<tag>` base image (e.g. `jod` for Node.js 22 LTS) and tags it as
`ai:node<tag>`. The two flags are mutually exclusive; each variant is cached
independently.

The `--model` flag picks the model the agent runs with. Claude Code defaults to
`opus`; pass e.g. `--model sonnet` to override. Cursor Agent uses its own model
names (`gpt-5`, `sonnet-4-thinking`, …), so the flag is only forwarded there
when given explicitly. It is not supported with `--bash`.

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

## GitHub CLI

`gh` comes from the base image's package repository, so its version follows the base you build
(`--java` or `--node`) rather than tracking upstream releases.

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

Keep it in `~/.ai/settings.env` on the host, outside this repo, so it is never committed:

```bash
mkdir -p ~/.ai
printf 'GH_TOKEN=ghp_...\n' > ~/.ai/settings.env
chmod 600 ~/.ai/settings.env
```

## Layout

```
.
├── Dockerfile         # Configurable base (via --java / --node) + Claude + Cursor + Docker CLI + gh
├── ai                 # Launcher script
├── dashboard/         # Sessions dashboard: server.py + index.html + PWA manifest, service worker, icons
├── claude/            # Per-tool config mounted into the container
├── cursor/
├── common/
│   ├── commands/      # Shared slash commands
│   ├── skills/        # Shared skills
│   └── rules/         # Shared coding rules
└── config/
    └── claude/        # managed-settings.json -> /etc/claude-code/
```

## License

MIT
