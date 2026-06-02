---
description: Efficient digest of recent Slack activity across channels (optional time window, threads, DMs)
argument-hint: "[#channel1, #channel2, DM] [time window] [lang:<language>]"
---

Make a digest of Slack activity based on $ARGUMENTS.

For the logged-in user, use Slack's `from:me` / `to:me` modifiers — do **not** hardcode an ID. When you need the user's own `user_id` (e.g. to spot @-mentions in step 2d), use the one the `slack_search_public_and_private` tool states in its own description. Timezone is **Europe/Warsaw**.

Parse $ARGUMENTS into:
- **lang** — a `lang:<language>` token anywhere in the args (e.g. `lang:en`, `lang:pl`, `lang:polish`). Generate the **entire digest in this language** (labels and bullets). Default: English.
- **time window** — an optional phrase (e.g. "today", "yesterday", "last 7 days", "2026-06-01"). Default: last 24h.
- **targets** — comma-separated channel names (strip leading `#` and whitespace). The literal token `DM`/`DMs` is a special target (see step 5).

**If no channel targets are given, run the "everything" mode in step 2.**

## 1. Resolve the time window to timestamps

Run one Bash call to derive both epoch seconds (for reads) and `YYYY-MM-DD` dates (for search modifiers) in Europe/Warsaw, e.g.:

```bash
TZ=Europe/Warsaw date -d 'yesterday 00:00' +%s          # oldest (epoch)
TZ=Europe/Warsaw date -d 'today 00:00' +%s              # latest (epoch)
TZ=Europe/Warsaw date -d 'yesterday 00:00' +%F          # oldest (YYYY-MM-DD)
```

Pass `oldest`/`latest` to every read, and `after:`/`before:`/`on:` to every search. This is what makes time windows cheap and exact — never fetch everything and filter by eye.

## 2. Everything mode (no channel targets given)

When the user passes no channels (e.g. `/slack-digest`, or only `lang:` / a time window):

a. **Channels the user was active in.** Call `slack_search_public_and_private` with `query: "from:me after:<date>"`, `sort: "timestamp"`, `include_context: false`, `response_format: "concise"`. Note: Slack's `after:` is **exclusive** of the date, so pass the day *before* `oldest`, then rely on the precise epoch `oldest`/`latest` in step 4 to trim the window. Page through (follow the cursor) until results leave the window, collecting the distinct channel / DM names.

b. **DMs others sent you.** Call the same search with `query: "to:me after:<date>"`. This reliably returns incoming DM messages (questions / things awaiting your reply). Group by sender.

c. Use the channels from (a) as the target list and run steps 3-4 on them.

d. **Channel @-mentions — best-effort, local only.** Slack search **cannot** find channel mentions by the raw `<@USER_ID>` token (verified: it returns empty / junk), and `to:me` only covers DMs. So do **not** issue a mention search. Instead, from the channels already read in step 4, flag messages from *other* people that @-mention you (match your own `user_id` — see the note at the top), or replies from others in threads you started. State plainly that mentions in channels you did **not** engage are not covered, and point the user to Slack's own **Activity** view for a complete mentions list.

Keep this efficient: concise format, no context, parallel batches.

## 3. Resolve channels (one parallel batch)

For named targets, call `slack_search_channels` for **all** of them in a single message (parallel tool calls). Always pass `channel_types: "public_channel,private_channel"` — many work channels are private and won't be found with the default. Note each channel ID. If a name resolves to nothing, report it and continue with the rest.

## 4. Read channels (one parallel batch)

Call `slack_read_channel` for every resolved channel in a single message (parallel), with:
- `oldest` / `latest` from step 1
- `limit: 50`
- `response_format: "concise"`

Do not request context-heavy formats here. Broad reads must stay small.

## 5. Read threads — but only the ones that matter

A channel read shows only thread parents plus a reply count. Read a thread (`slack_read_thread` with `message_ts`) only when it is **both relevant and information-dense**:
- the parent body is empty / just a link but has replies (the substance is inside), or
- it has many replies (≳5) on a topic worth summarizing.

Skip chit-chat and single-emoji threads. Batch all the thread reads you decide to do into one parallel message. Use `response_format: "concise"`.

## 6. DM target (only if `DM`/`DMs` is among the targets)

DMs are not found via `slack_search_channels`. Use `slack_search_public_and_private`:
- `query: "on:YYYY-MM-DD"` (or `after:`/`before:` for ranges) matching the window
- `channel_types: "im,mpim"`
- `sort: "timestamp"`, `include_context: false`, `response_format: "concise"`

Group results by conversation partner and summarize each thread of discussion, not individual lines.

## 7. Token-safety (important)

`slack_search_public_and_private` with context is huge and will blow the tool-output token limit. Always set `include_context: false` and `response_format: "concise"`. If a result still overflows and gets written to a file, do **not** read the file back — re-issue the same call with a narrower window / smaller `limit`.

## 8. Output

Render the digest in the **lang** language (translate the labels below into it):

```
*Slack digest — <window, e.g. yesterday 2026-06-01>*

*Addressed to you*   (everything mode: incoming DMs via `to:me`, plus best-effort channel mentions from step 2d)
- ...   (if channel mentions can't be established reliably, say so and point to Slack's Activity view)

*#channel-1*
- ...
*#channel-2*
- ...
```

Rules:
- 3-5 bullets per target, max. Focus on **decisions, open questions awaiting an answer, action items, deploys/incidents, and anything addressed to the user**.
- For each PR/link mentioned, keep the PR number / short label so it stays traceable.
- A channel that is quiet in the window → say so, and note the last visible message timestamp.
- End with a one-line "needs your attention" highlight.
