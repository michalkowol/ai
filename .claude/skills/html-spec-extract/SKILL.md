---
name: html-spec-extract
description: Use periodically, or when the user asks to clean up specs or extract shared components - scans .agents/docs/specs/*.html for markup repeated at least 3 times, proposes local components and, after approval, adds them to assets/local-components.js and replaces the markup in all specs
---

# HTML Spec Extract

Keeps specs created with `html-spec` free of repeated markup by applying the rule of three across all specs of a project.

## Steps

1. Read every `.agents/docs/specs/*.html`, `local-components.js` and the `global-components.js` API described in the `html-spec` skill.
2. Find markup patterns that appear at least 3 times across the specs: the same element structure with different content (e.g. an endpoint table row, an API example block, a risk card). Ignore patterns already covered by a global `spec-*` or an existing local component.
3. Show the candidates to the user, one entry each:
   - proposed element name (`local-…`) and attributes / children,
   - where it appears (file and section),
   - before / after markup of one occurrence.
4. Wait for approval. The user may accept, rename or reject each candidate.
5. For each accepted candidate:
   - add the component to `.agents/docs/specs/assets/local-components.js` (light DOM custom element, classes and tokens from `style.css`, extra CSS only through one injected `<style>` tag);
   - replace the markup in all specs, including `decided` and `implemented` ones. Change structure only, keep every word of content and every decision as it was.
6. If a component looks useful outside this project, suggest moving it to `global-components.js` in the ai-tools repo. Do not move it without approval. Never edit `.agents/docs/specs/assets/global-components.js` or `style.css` here: they are owned by the plugin and replaced by `/mk:html-spec-init`.
7. Report: components added, files changed, candidates rejected.

## Rules

- Fewer than 3 occurrences is not a candidate, even if it looks reusable.
- Never change the meaning, the language or the decisions of a spec.
- Keep components backwards compatible: renaming an attribute means updating every spec that uses it in the same change.
