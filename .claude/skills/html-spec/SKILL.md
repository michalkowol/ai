---
name: html-spec
description: Use when planning a change before implementation, or when the user asks for a plan, spec, design decisions or a "grill" in an HTML file - run the whole planning phase inside .agents/docs/specs/YYYY-MM-DD-short-name.html, where the user answers questions in the browser and pastes a generated prompt back into the session
---

# HTML Spec

The planning phase happens in an HTML file instead of in the chat. The file holds the context, the facts, the open questions, the decision log and a prompt the user copies back into the session. It stays in the repo as a history of the decisions.

The result is a spec (what and why), not a step-by-step plan. It holds no tasks, steps or progress. Work tracked outside the implementation is referenced with `ticket` on a decision.

This skill only plans. It never implements in the same turn. The implementation starts when the user pastes the final prompt.

## Files

- Spec: `.agents/docs/specs/YYYY-MM-DD-short-name.html`. The date is the creation date and never changes. `short-name` is a kebab-case English slug, even when the session is in another language.
- Index: `.agents/docs/INDEX.md`.
- Global style and components: `.agents/docs/specs/assets/style.css` and `.agents/docs/specs/assets/global-components.js`.
- Project components: `.agents/docs/specs/assets/local-components.js`.
- Template: `template.html` in this skill directory. Start every spec from it.

This skill was installed into the project by `/mk:html-spec-init` from [michalkowol/ai-tools](https://github.com/michalkowol/ai-tools). The project structure (`.agents/docs/specs/`, `.agents/docs/specs/assets/` with `style.css`, `global-components.js` and `local-components.js`, `.agents/docs/INDEX.md`) is created by the init. If any of it is missing, stop and ask the user to run `/mk:html-spec-init` instead of creating it here. The plugin is public:

```
/plugin marketplace add michalkowol/ai-tools
/plugin install mk@michalkowol
```

Do not edit this skill in the project, change it in ai-tools and re-run the init.

## Workflow

### 0. Gather facts and pick the path

Gather facts yourself before asking anything: read the code, configs, docs, run read-only commands, use a sub-agent for wide searches. Never ask the user for something you can look up.

Then build the decision tree and count the decisions:

- **1-2 decisions, no dependent branches:** a draft round trip is not worth it. Use the quick path below.
- **More than 2 decisions, or decisions that open further questions:** use the draft workflow (steps 1-3).

### Quick path

1. Ask the questions in the session (with the question tool if available): options, a recommended option first, the trade-off in one sentence.
2. Create the spec from `template.html` straight away with `status="decided"`, in English: Context, Facts and Out of scope filled in, no Open questions section, Prompt at the end (final order).
3. Record every answer as a `<spec-decision>` exactly as in step 2 below: all options with `chosen` on the picked ones, the user's note translated to English, the rationale.
4. Add the row to `.agents/docs/INDEX.md` with status `decided`.
5. Give the user the implementation prompt (the same text the `<spec-prompt>` generates).

If an answer opens new questions and the total goes above 2, switch to the draft workflow: create the spec as `draft`, record the decisions made so far and put the new questions into Open questions.

### 1. Create the spec (draft)

1. Facts are gathered in step 0.
2. Copy `template.html` to `.agents/docs/specs/YYYY-MM-DD-short-name.html` and replace the example content. Keep the `<link>` and `<script>` tags unchanged.
3. Fill in `<spec-header status="draft">`, Context, Facts (each with its source) and Out of scope.
4. Write round 1 into Open questions (rules below).
5. Add a row to `.agents/docs/INDEX.md` with status `draft`.
6. Tell the user the file path and ask them to open it, answer, and paste the prompt from the Prompt section under the questions.

### 2. Process a round

The user pastes a prompt that starts with `/html-spec Round N answers for <file>`.

1. For every answered question add a `<spec-decision>` to the Decision log with round and `from="Qn"`. Number decisions `D1, D2, ...` continuously across rounds. The decision is the history, so keep everything the user saw and wrote:
   - the question as `<p class="q">`;
   - **all** `<spec-option>` elements of the question, unchanged (value, label, description, `recommended`), with `chosen` added to the picked ones. Add the `other` option only if it was picked;
   - the user's note as `<p class="note">`, word for word, in the language it was written in until the spec is finalized;
   - the rationale as `<p class="why">`, based on the option description and the note.

   A note never replaces the chosen option, it refines it: `A` with a note means "A, adjusted by the note". Apply both. If the note contradicts the chosen option or leaves it ambiguous, do not guess, ask a follow-up question in the next round.

   ```html
   <spec-decision did="D2" round="2" from="Q2">
     <p class="q">Keep offset pagination as a fallback?</p>
     <spec-option value="A" label="Yes, behind a query parameter" recommended>Safer rollout.</spec-option>
     <spec-option value="B" label="No, remove it in the same change" chosen>Less code, but no way back.</spec-option>
     <p class="note">Both clients deploy on the same day.</p>
     <p class="why">A fallback only adds code to delete later.</p>
   </spec-decision>
   ```
2. Remove the answered `<spec-question>` elements. Open questions only hold the current round, the history lives in the Decision log.
3. If an answer changes an earlier decision, add a new decision and link them. Never delete decisions.
   - The whole decision changes: set `superseded-by="Dn"` on the old one.
   - Only a part changes (e.g. one detail of a note): set `amended-by="Dn"` on the old one and `amends="Dm"` on the new one. The old decision stays active.
4. A question that ends without a decision still becomes a `<spec-decision>` with the next `Dn` number, its options without `chosen`, and `outcome`:
   - `deferred`: we come back to it later;
   - `dropped`: the question no longer makes sense;
   - `out-of-scope`: not part of this spec (also add it to Out of scope).

   Every `Qn` leaves a trace in the Decision log, nothing disappears.
5. Move new facts to Facts. Move things the user excluded to Out of scope.
6. If the answers open new questions, write the next round. Otherwise finalize.

### 3. Finalize

When no open questions are left:

1. If the session was in a language other than English, translate the whole file to English in place, including the users' notes in the Decision log and the alternatives that were not chosen. Keep the meaning, do not add sentences. The audience is engineers and agents.
2. Remove the empty Open questions section and move the Prompt section to the end, so the page starts with Context.
3. Find the decisions that need work outside this implementation (another team, a separate task, something that takes long). Ask the user for a ticket key or a link for each of them and set `ticket` on the decision. If the user asks, create the tickets (e.g. through Jira MCP). The spec is not a task tracker: it holds no tasks, owners or progress, only the reference to where the work is tracked.
4. Set `status="decided"` in `<spec-header>` and in `INDEX.md`.
5. The `<spec-prompt>` switches to the implementation prompt by itself. Tell the user to copy it into a new session or this one.

### 4. After implementation

Whoever implements the spec sets `status="implemented"` in the file and in `INDEX.md`. Do not change decisions at this point. If the implementation had to deviate, add a new decision that supersedes the old one.

## Questions

Follow the grilling method:

- Put as many questions as possible into one round: every question whose prerequisites are settled.
- If you can predict a branch, add the dependent question now with `show-if="Qn=B"` (or `Qn=B|C`). It appears only when that answer is picked. Only unpredictable follow-ups go to the next round.
- Every question has a recommended option, marked `recommended`, which is preselected. Put it first.
- 2-4 options per question. The label is short, the description gives the trade-off in one or two sentences.
- An "Other" option and a note field are added automatically. Use `no-other` only when other answers make no sense.
- Use `multiple` for non-exclusive choices.
- Ask about decisions only. Facts go to the Facts section with a source.
- When a spec covers several areas, give questions a `topic` (short label, e.g. `topic="Monorepo"`). The decision keeps the question's topic. It is shown as a pill.
- Number questions `Q1, Q2, ...` continuously across rounds, never reuse a number.

## INDEX.md

```markdown
# Docs index

## Specs

| Date | Title | Status | File |
|------|-------|--------|------|
| 2026-11-18 | Cursor pagination for orders API | draft | [2026-11-18-orders-cursor-pagination.html](specs/2026-11-18-orders-cursor-pagination.html) |
```

Newest first. Keep the title in sync with the `<h1>` and the status in sync with `<spec-header>`.

## Structure, not styling

A spec contains structure and content only. No `<style>` blocks, no `style=""` attributes, no inline scripts. Look and behaviour come from:

- `assets/style.css` and `assets/global-components.js` (global, installed by the init)
- `assets/local-components.js` (project-specific)

The `assets/` folder sits next to the specs, so `.agents/docs/specs/` holds only specs. All three are linked with relative paths, so a spec opens straight from the repo (`file://`) without a server or internet access. Never edit `style.css` or `global-components.js` in the project: they are owned by the plugin and replaced when the init is re-run. Project-specific needs go to `local-components.js`.

Every spec declares the spec format it was written for with `<meta name="html-spec" content="N">` (already in `template.html`). The init uses it to migrate old specs when the format changes. Keep the number from the template, do not change it by hand.

### Page skeleton

While the spec is a `draft`, Open questions and Prompt come right after `<spec-header>`, so the user answers and copies the prompt without scrolling, and reads the rest only when needed. When the spec is finalized, Open questions is removed, Prompt moves to the end and the page keeps the reference order: Context, Facts, Out of scope, Decision log, Prompt.

Conventions inside the sections:

- Every fact ends with its source in `<cite>`: `<li>12 switches in 7 files. <cite>lines 6-34</cite></li>`. The style adds the "Source:" prefix, do not write it. Facts may be grouped with `<h3>`.
- References to decisions and questions are explicit links: `<a href="#D6">D6</a>`. Decisions get their `id` automatically. Plain "D6" in text is not linked.

```html
<main>
  <spec-header date="YYYY-MM-DD" status="draft"> <h1>…</h1> <p>…</p> </spec-header>
  <section id="questions"> <h2>Open questions</h2> <spec-question>… </section>  <!-- draft only -->
  <section id="prompt"> <h2>Prompt</h2> <spec-prompt file="…"></spec-prompt> </section>   <!-- draft position -->
  <section id="context"> <h2>Context</h2> … </section>
  <section id="facts"> <h2>Facts</h2> <ul><li>… <cite>source</cite></li></ul> </section>
  <section id="out-of-scope"> <h2>Out of scope</h2> <ul>…</ul> </section>
  <section id="decisions"> <h2>Decision log</h2> <spec-decision>… </section>
  <!-- after finalizing, Prompt moves here -->
</main>
```

Add other sections (diagrams, tables, code samples) when the content needs them, using plain HTML and the classes below.

### style.css

Tokens (CSS variables):

| Token | Value | Use |
|-------|-------|-----|
| `--ivory` | `#FAF9F5` | page background |
| `--white` | `#FFFFFF` | surfaces, inputs |
| `--gray-150` | `#F0EEE6` | subtle fill, inline code |
| `--gray-300` | `#D1CFC5` | borders |
| `--gray-500` | `#87867F` | muted text |
| `--gray-700` | `#3D3D3A` | body text |
| `--slate` | `#141413` | headings, code background, primary button |
| `--clay` | `#D97757` | accent: links, recommended, decided |
| `--oat` | `#E3DACC` | soft tags |
| `--olive` | `#788C5D` | positive: active decisions, implemented |
| `--serif` / `--sans` / `--mono` | system stacks | headings and quotes / body / code and labels |

Styled elements: `h1`-`h3` (serif), `p`, `ul`, `ol`, `code`, `pre` (dark code block), `blockquote` (clay rule), `table` / `th` / `td`, `hr`, `a`, `cite` (muted, "Source:" prefix), and `main` (760px column) with `main > section` spacing.

Classes:

| Class | Element | Use |
|-------|---------|-----|
| `.eyebrow` | any | small uppercase muted label |
| `.muted` | any | muted text |
| `.pill` | `span` | neutral rounded mono label |
| `.tag` | `span` | soft oat tag; `.tag.accent` clay, `.tag.positive` olive |
| `.btn` | `button` | secondary button; `.btn.primary` slate, `.btn.accent` clay |
| `.field` | `input`, `textarea` | form field |

### global-components.js

Light DOM custom elements, so `style.css` styles them directly. Answers are saved in `localStorage` under `html-spec:<path>`, so a page reload keeps them.

`<spec-header date="YYYY-MM-DD" status="draft|decided|implemented">`
: Children: `<h1>` title and an optional `<p>` summary. Renders the date and a status tag.

`<spec-question qid="Q1" round="1" [multiple] [show-if="Q1=A|B"] [no-other] [topic="…"]>`
: Children: `<h3>` question, optional `<p>` context, then `<spec-option>` elements. Renders radios (checkboxes with `multiple`), an "Other" option and a note field. With `show-if` it is hidden until the referenced question has one of the listed values. Hidden questions are left out of the prompt.

`<spec-option value="A" label="Short label" [recommended]>Description</spec-option>`
: One option. `recommended` is preselected and tagged.

`<spec-decision did="D1" round="1" [from="Q1"] [topic="…"] [ticket="DARCH-123|https://…"] [superseded-by="D3"] [amended-by="D4"] [amends="D2"] [outcome="deferred|dropped|out-of-scope"]>`
: Children: `<p class="q">` question, every `<spec-option>` of the question with `chosen` on the picked ones, optional `<p class="note">` user's note, `<p class="why">` rationale. Renders the chosen options with a check mark and the alternatives muted below them. Gets `id="D1"` for links. With `superseded-by` it is struck through and links to the newer decision. `amended-by` / `amends` show linked pills and keep the decision active. With `outcome` it shows the outcome pill and is not an active decision. `ticket` holds one Jira key (shown as a tag) or one URL, e.g. another team's ticket or a Slack thread (shown as a link); set it only for decisions whose work is tracked outside this implementation. The older form with `<p class="choice">` instead of options still renders.

`<spec-prompt file=".agents/docs/specs/….html">`
: Textarea with Copy and Reset answers buttons. The text is generated from the page:
  - open questions present: `/html-spec Round N answers for <file>` and one `Qn: A — Label` line per visible question (several picks joined with `; `, "Other" as plain `other`), with notes;
  - no questions, status `draft`: `/html-spec Finalize <file>`;
  - status `decided` or `implemented`: implementation prompt with active decisions (with notes, amendments and tickets) and a "Not decided" block (decisions with `outcome`).

## local-components.js

Each project may define its own components in `.agents/docs/specs/assets/local-components.js`. Every spec loads it with `<script defer src="assets/local-components.js">`.

- Rule of three: extract markup into a local component only after the same pattern appears at least 3 times across the project's specs. Until then, repeat the plain HTML.
- Before writing repeated markup, check the existing specs and `local-components.js`. Reuse a component if one exists.
- Prefix local elements with the project name or `local-` (e.g. `<local-endpoint>`), never `spec-`.
- Local components use the classes and tokens from `style.css`. If one needs extra CSS, it injects a single `<style>` tag from the script.
- If a local component looks useful beyond this project, suggest moving it to `global-components.js` in [michalkowol/ai-tools](https://github.com/michalkowol/ai-tools). The user decides. After the change in the plugin, re-running the init brings it to every project.
- For a sweep across all specs, use the `html-spec-extract` skill.
