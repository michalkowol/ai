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
ai                   # Claude Code (default), current directory
ai --claude path/    # Claude Code in a specific directory
ai --cursor path/    # Cursor Agent
ai --bash path/      # Plain bash shell in the container
ai --java 21         # Build the Java image with a specific version (default: 25)
ai --node jod        # Build the Node.js image with a specific tag
ai --model sonnet    # Pick the model (default: opus)
ai --java 21 path/   # Combine with any tool/path
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

## GitHub CLI

`gh` comes from the base image's package repository, so its version follows the base you build
(`--java` or `--node`) rather than tracking upstream releases.

Give it a **dedicated token** — not your own. The token's own scopes are the only boundary that
still holds if the agent is ever talked around the rules below.

### Create the token

At [github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new):

- **Resource owner** — your account, or the organization that owns the repos. For an organization,
  fine-grained PATs have to be enabled there and the token approved by an admin.
- **Repository access** — *Only select repositories*, never *All repositories*.
- **Expiration** — keep it short, 30–90 days.
- **Account permissions** — leave every entry at *No access*.

Under **Repository permissions**, set these six and leave everything else at *No access*:

| Permission | Value | What it buys |
| --- | --- | --- |
| Metadata | Read-only | mandatory, preselected |
| Contents | Read-only | clone, file reads, `gh pr diff`, `gh pr checkout`. Read-only is what makes GitHub itself refuse pushes and releases |
| Pull requests | Read and write | `gh pr view/list/diff/checks`, plus comments and reviews — each one still gated by an approval prompt |
| Issues | Read and write | `gh issue view/list`, plus comments |
| Actions | Read-only | `gh run list`, `gh run view --log` |
| Commit statuses | Read-only | `gh pr checks` |

For an agent that may never write anything, set Pull requests and Issues to Read-only as well; the
approval prompts then have nothing left to approve.

The entries worth refusing deliberately:

| Permission | Why not |
| --- | --- |
| Administration | repo deletion, rename, visibility, collaborators, branch protection |
| Secrets, Variables, Agent secrets, Agent variables, Dependabot secrets, Codespaces secrets | secret exfiltration |
| Workflows | lets the agent edit `.github/workflows`, i.e. run arbitrary code with CI's own privileges |
| Codespaces, Codespaces lifecycle admin, Codespaces metadata | spins up billable compute |
| Deployments, Environments, Merge queues, Pages, Webhooks, Custom properties | no allowed command needs them |
| Code scanning, Secret scanning, Dependabot alerts, Repository security advisories, License compliance alerts | vulnerability detail; grant Read-only only if you want the agent triaging it |
| Agent tasks, Artifact metadata, Attestations, Code quality, Copilot agent settings, Discussions | not needed here |

GitHub's UI no longer offers a `Checks` permission — `Commit statuses` together with `Actions` covers
reading CI results.

### Hand the token to the container

Keep it in `~/.ai/settings.env` on the host, outside this repo, so it is never committed:

```bash
mkdir -p ~/.ai
printf 'GH_TOKEN=github_pat_...\n' > ~/.ai/settings.env
chmod 600 ~/.ai/settings.env
```

No quotes around the value: Docker's `--env-file` passes the line verbatim, quotes included.

The launcher hands the whole file to `docker run --env-file` whenever it exists, so any other
variable you put there reaches the container too — one `KEY=value` per line, `#` comments allowed,
no shell expansion. Nothing is mounted and your own `~/.config/gh` is never shared, so the container
holds no credential beyond what this file carries.

Your git identity travels separately, as `-e` arguments the launcher derives from the host. Docker
gives `-e` precedence over `--env-file` whatever the argument order, so a `GIT_AUTHOR_NAME` or
`GIT_AUTHOR_EMAIL` line in this file has no effect.

Verify from inside the container:

```bash
ai --bash
gh auth status
```

### What the agent may do

Claude Code runs without permission prompts (`--dangerously-skip-permissions`), so the scope is a
default-deny allowlist instead:

| Command | Result |
| --- | --- |
| Reads: `gh pr view`, `gh issue list`, `gh run view`, `gh search …`, `gh api` without write flags | runs |
| Writes: `gh pr comment`, `gh pr review`, `gh issue create`, `gh release create`, `gh workflow run`, … | asks every time |
| Everything else: `gh repo delete`, `gh secret`, `gh extension`, `gh api -X POST`, `git push`, unknown subcommands | denied |

- `common/hooks/gh-guard.sh` holds the allowlist and runs as a `PreToolUse` hook on every Bash call.
  A `gh` command it does not recognize is denied, as is any `git push`. It defers on everything else,
  so the permission rules decide. Without `jq` it denies rather than waving commands through.
- `config/claude/managed-settings.json` mounts read-only at `/etc/claude-code/managed-settings.json`.
  It carries the `ask` rules — the one mechanism that still prompts in bypass mode — plus a `deny`
  backstop for the destructive commands. Managed settings outrank every other settings file, and the
  mount is read-only, so the agent cannot lift its own restrictions.

To widen the scope, add the `<command> <verb>` line to `ALLOWED` in `common/hooks/gh-guard.sh`. If it
writes anything, also add a matching `Bash(gh …:*)` entry to the `ask` list in
`config/claude/managed-settings.json`, otherwise it will run without a prompt.

None of this covers `ai --cursor`: Cursor Agent runs with `--force` and has no policy here, so the
token's own scopes are the only limit there.

### What the token refuses by design

Not misconfiguration — these follow from the read-only scopes above:

| Command | Why it fails |
| --- | --- |
| `git push` | blocked by the guard before it runs, and refused by GitHub if it ever got that far |
| `gh pr create` | needs the branch pushed first, so open pull requests yourself |
| `gh release create`, `gh release upload` | need Contents: Read and write |
| `gh repo create`, `gh repo fork` | account-level permission, not a repository one |
| `gh workflow run`, `gh run rerun`, `gh run cancel` | need Actions: Read and write; with Actions: Read-only the agent asks for approval and then gets a 403. Raise Actions if you want it triggering CI |

These are guardrails against mistakes, not a sandbox. The container has passwordless `sudo`,
`GH_TOKEN` is readable from the environment, and the allowlist only sees commands it can parse — a
`bash -c "gh …"` or a script that calls the API itself is not covered. The token's own scopes are the
boundary that actually holds.

## Layout

```
.
├── Dockerfile         # Configurable base (via --java / --node) + Claude + Cursor + Docker CLI + gh
├── ai                 # Launcher script
├── claude/            # Per-tool config mounted into the container
├── cursor/
├── common/
│   ├── commands/      # Shared slash commands
│   ├── skills/        # Shared skills
│   ├── rules/         # Shared coding rules
│   └── hooks/         # gh-guard.sh — the GitHub CLI allowlist
└── config/
    └── claude/        # managed-settings.json -> /etc/claude-code/
```

## License

MIT
