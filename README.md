# ai

Run Claude Code or Cursor Agent inside a sandboxed Docker container with your
own shared commands, skills, and rules mounted in.

## Why

Keep AI coding assistants isolated from the host while reusing a single set of
prompts, slash commands, and configuration across both tools.

## Requirements

- Docker
- A clone of this repo at `~/dev/ai`

## Usage

```bash
./ai                 # Claude Code (default), current directory
./ai --claude path/  # Claude Code in a specific directory
./ai --cursor path/  # Cursor Agent
./ai --bash path/    # Plain bash shell in the container
```

The given path is mounted as `/workspace` inside the container. Git worktrees
are detected and their common git dir is mounted automatically.

## Layout

```
.
├── Dockerfile         # Temurin 21 + Claude + Cursor + Docker CLI
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
