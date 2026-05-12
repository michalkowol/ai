Make sure the current changes are saved as a git checkpoint commit.

Steps:

1. Run `git status` to see if there are any uncommitted changes (staged, unstaged, or untracked).
2. If the working tree is clean, report "Nothing to checkpoint - working tree is clean" and stop.
3. Otherwise:
   - Run `git diff` and `git diff --staged` to understand what changed.
   - Stage all changes with `git add -A`.
   - Create a commit with message format: `<short summary>`
     - Summary must be one sentence, present simple tense, max 15 words, in English.
   - Run `git status` after the commit to confirm success.

Rules:
- Never push to remote.
- Never amend an existing commit - always create a new one.
- Never skip hooks (no `--no-verify`).
- Do not commit files that likely contain secrets (`.env`, `credentials.json`, etc.) - warn instead.
