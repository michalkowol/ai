Create a single git commit for the current changes.

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Git Safety Protocol

- NEVER update the git config.
- NEVER skip hooks (`--no-verify`, `--no-gpg-sign`, etc.) unless the user explicitly requests it.
- CRITICAL: ALWAYS create NEW commits. NEVER use `git commit --amend`, unless the user explicitly requests it.
- Do not commit files that likely contain secrets (`.env`, `credentials.json`, etc.). Warn the user if they specifically request to commit those files.
- If there are no changes to commit (no untracked files and no modifications), do not create an empty commit.
- Never use git commands with the `-i` flag (like `git rebase -i` or `git add -i`) since they require interactive input which is not supported.
- Never push to remote.
- NEVER add AI/tool attribution to commits. The commit message body must contain ONLY the human-authored message — no footers, no trailers, no co-author lines, no generation notices. Specifically forbidden (non-exhaustive):
  - any `Co-Authored-By:` line referring to an AI assistant or its vendor — including but not limited to Claude, Anthropic, Sonnet, Haiku, Opus, ChatGPT, GPT, OpenAI, Codex, Cursor, Copilot, Gemini, Google, Devin, Aider, or any `noreply@` address of such vendors (`@anthropic.com`, `@openai.com`, `@cursor.sh`, `@cursor.com`, `@github.com` bot accounts, etc.)
  - generation/tooling notices such as `Generated with Claude Code`, `Generated with [Claude Code](...)`, `Made with Claude`, `Generated with Cursor`, `Written with Codex`, `via GitHub Copilot`, or any analogous credit
  - the robot emoji line (`🤖 ...`) or "sparkles" line (`✨ ...`) commonly paired with the above
- Do NOT pass `--author`, `--trailer`, or `-c user.*` flags to `git commit` to inject such attribution.
- Use the existing local `git config user.name` / `user.email` as-is. Do not override the author identity to point at an AI tool.

## Your task

Based on the above changes, create a single git commit:

1. Analyze all changes (staged and unstaged) and draft a commit message:
   - Look at the recent commits above to follow this repository's commit message style.
   - Summarize the nature of the changes (new feature, enhancement, bug fix, refactoring, test, docs, etc.).
   - Ensure the message accurately reflects the changes and their purpose (i.e. "add" means a wholly new feature, "update" means an enhancement to an existing feature, "fix" means a bug fix, etc.).
   - Write the message as one sentence, present simple tense, max 15 words, in English. Do not add a dot at the end.

2. Stage relevant files with `git add` (do not use `git add -A` if it would include files that likely contain secrets) and create the commit using HEREDOC syntax:

```
git commit -m "$(cat <<'EOF'
Commit message here
EOF
)"
```

3. Run `git status` after the commit to confirm success.

Only respond with the commit message, no additional text.
