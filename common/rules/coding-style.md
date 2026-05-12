---
description: Core coding style - minimal comments, English logs, no emojis
alwaysApply: true
---

# Coding Style

- Avoid adding comments to code. Only keep comments that explain non-obvious logic or public API contracts.
- When adding log messages (console.log, logger.info, logger.error, etc.), always write them in English.
- Do not use emojis unless explicitly asked to do so.
- In log messages, use bracket notation for context: `"Failed to do something [key={}, other={}]"`.
- When logging exceptions, pass the exception as the last argument (to include the stacktrace). Do not use `e.getMessage()` as a format parameter.
