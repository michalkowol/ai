Based on the current git changes, generate:

1. A git branch command with a suggested branch name
2. A commit message

Rules:
- Ask for the ticket number if not provided (format: EDEN-XXXX)
- Branch name format: `TICKET-NUMBER-short-description` (max 4 words, lowercase, hyphen-separated)
- Commit message format: `TICKET-NUMBER Commit message`
- Commit message must be one sentence in present simple tense, max 20 words, in English

Output format (exactly two lines, no additional text):
```
git switch -c TICKET-NUMBER-short-description && \
github "TICKET-NUMBER Commit message here"
```

Example:
```
git switch -c EDEN-6353-add-email-validation && \
github "EDEN-6353 Add validation for user email input field"
```
