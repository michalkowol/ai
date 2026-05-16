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
ai --java 21         # Build the image with a specific Java version (default: 25)
ai --java 21 path/   # Combine with any tool/path
```

The given path is mounted as `/workspace` inside the container. Git worktrees
are detected and their common git dir is mounted automatically.

The `--java` flag selects the `eclipse-temurin:<version>` base image and tags
the built image as `ai:java<version>`, so multiple Java versions are cached
independently.

## Layout

```
.
├── Dockerfile         # Temurin (configurable via --java) + Claude + Cursor + Docker CLI
├── ai                 # Launcher script
├── claude/            # Per-tool config mounted into the container
├── cursor/
├── common/
│   ├── commands/      # Shared slash commands
│   ├── skills/        # Shared skills
│   └── rules/         # Shared coding rules
└── config/
```

## License

MIT
