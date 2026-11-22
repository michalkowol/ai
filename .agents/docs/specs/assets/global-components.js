/*
 * html-spec global components
 * html-spec format 1
 *
 * Copied into .agents/docs/specs/assets/ by /mk:html-spec-init from michalkowol/ai-tools.
 * Do not edit in the project: changes are made in the plugin and installed by re-running the init.
 *
 * Light DOM custom elements (no shadow DOM), styled by style.css:
 *   <spec-header date status>                     title, date, status
 *   <spec-question qid round [multiple] [show-if] [no-other] [topic]>
 *     <spec-option value label [recommended]>     one answer option
 *   <spec-decision did round [from] [topic] [ticket] [superseded-by] [amended-by] [amends] [outcome]>
 *     <spec-option value label [recommended] [chosen]>  all options, chosen marked
 *   <spec-prompt file>                            prompt to paste back into the session
 *
 * Load with <script defer src="..."> so all markup is parsed before upgrade.
 */
(() => {
  const STORAGE_KEY = `html-spec:${location.pathname}`;
  const STATUS_TAG = { draft: '', decided: 'accent', implemented: 'positive' };

  const h = (tag, attrs = {}, ...children) => {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null) continue;
      if (k === 'class') el.className = v;
      else if (k in el && typeof v !== 'string') el[k] = v;
      else if (v !== false) el.setAttribute(k, v === true ? '' : v);
    }
    for (const c of children.flat()) {
      if (c != null && c !== false) el.append(c);
    }
    return el;
  };

  const loadState = () => {
    try { return JSON.parse(localStorage.getItem(STORAGE_KEY)) || {}; } catch { return {}; }
  };
  const saveState = (state) => {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch { /* storage unavailable */ }
  };

  const OUTCOMES = ['deferred', 'dropped', 'out-of-scope'];
  const link = (id) => h('a', { href: `#${id}` }, id);
  const ticketRef = (value) => {
    if (/^https?:\/\//.test(value)) {
      try {
        const host = new URL(value).hostname.replace(/^www\./, '');
        return h('a', { class: 'pill ticket', href: value, target: '_blank', rel: 'noopener' }, host);
      } catch { /* malformed URL: render as plain ticket text */ }
    }
    return h('span', { class: 'tag ticket' }, value);
  };
  const topicPill = (el) => (el.getAttribute('topic') ? h('span', { class: 'pill topic' }, el.getAttribute('topic')) : null);

  const parseCondition = (expr) => {
    const m = /^\s*([\w-]+)\s*=\s*([\w|-]+)\s*$/.exec(expr || '');
    return m ? { qid: m[1], values: m[2].split('|') } : null;
  };

  class SpecHeader extends HTMLElement {
    connectedCallback() {
      if (this._rendered) return;
      this._rendered = true;
      const status = this.getAttribute('status') || 'draft';
      const date = this.getAttribute('date') || '';
      this.prepend(h('div', { class: 'meta' },
        h('span', { class: 'eyebrow' }, date ? `Spec · ${date}` : 'Spec'),
        h('span', { class: `tag ${STATUS_TAG[status] ?? ''}`.trim() }, status),
      ));
    }
  }

  class SpecOption extends HTMLElement {}

  class SpecQuestion extends HTMLElement {
    connectedCallback() {
      if (this._rendered) return;
      this._rendered = true;
      const qid = this.qid;
      const multiple = this.hasAttribute('multiple');
      const type = multiple ? 'checkbox' : 'radio';
      const saved = loadState()[qid];

      if (!this.hasAttribute('no-other') && !this.querySelector('spec-option[value="other"]')) {
        this.append(h('spec-option', { value: 'other', label: 'Other' }, 'Describe it in the note below.'));
      }

      const head = h('div', { class: 'head' },
        h('span', { class: 'tag' }, qid),
        h('span', { class: 'eyebrow' }, `Round ${this.getAttribute('round') || 1}`),
      );
      const cond = parseCondition(this.getAttribute('show-if'));
      if (cond) head.append(h('span', { class: 'pill condition' }, `if ${cond.qid} = ${cond.values.join(' or ')}`));
      head.append(topicPill(this) || '');
      this.prepend(head);

      for (const opt of this.options) {
        const value = opt.getAttribute('value');
        const desc = [...opt.childNodes];
        const checked = saved ? saved.values.includes(value) : opt.hasAttribute('recommended');
        opt.replaceChildren(h('label', {},
          h('input', { type, name: qid, value, checked }),
          h('span', {},
            h('span', { class: 'label' },
              h('span', { class: 'value' }, value),
              opt.getAttribute('label') || '',
              opt.hasAttribute('recommended') ? h('span', { class: 'tag accent' }, 'recommended') : null,
            ),
            desc.length ? h('span', { class: 'desc' }, ...desc) : null,
          ),
        ));
      }

      this._note = h('textarea', { class: 'field', placeholder: 'Note (optional, any language). It is applied together with the selected option, e.g. A + this note.' });
      this._note.value = saved?.note || '';
      this._hint = h('p', { class: 'note-hint' });
      this.append(this._note, this._hint);
      this._updateHint();

      this.addEventListener('change', () => this._persist());
      this.addEventListener('input', () => this._persist());
    }

    get qid() { return this.getAttribute('qid'); }
    get options() { return [...this.querySelectorAll(':scope > spec-option')]; }

    get answer() {
      const picked = this.options.filter((o) => o.querySelector('input')?.checked);
      return {
        values: picked.map((o) => o.getAttribute('value')),
        labels: picked.map((o) => o.getAttribute('label') || ''),
        note: this._note?.value.trim() || '',
      };
    }

    _updateHint() {
      const { values, labels, note } = this.answer;
      const picked = values.filter((v) => v !== 'other').map((v, i) => `${v} — ${labels[values.indexOf(v)]}`);
      this._hint.hidden = !note;
      this._hint.textContent = !note ? ''
        : picked.length ? `This note applies together with ${picked.join(', ')}.`
        : 'This note is your answer.';
    }

    _persist() {
      this._updateHint();
      const state = loadState();
      const { values, note } = this.answer;
      state[this.qid] = { values, note };
      saveState(state);
      update();
    }
  }

  class SpecDecision extends HTMLElement {
    connectedCallback() {
      if (this._rendered) return;
      this._rendered = true;
      const did = this.getAttribute('did');
      if (did && !this.id) this.id = did;
      const from = this.getAttribute('from');
      const by = this.getAttribute('superseded-by');
      const amendedBy = this.getAttribute('amended-by');
      const amends = this.getAttribute('amends');
      const outcome = this.outcome;
      const meta = [`Round ${this.getAttribute('round') || 1}`, from ? `from ${from}` : null].filter(Boolean).join(' · ');
      this.prepend(h('div', { class: 'head' },
        h('span', { class: this.active ? 'tag positive' : 'tag' }, did || 'D?'),
        h('span', { class: 'eyebrow' }, meta),
        outcome ? h('span', { class: 'pill outcome' }, outcome) : null,
        by ? h('span', { class: 'pill' }, 'superseded by ', link(by)) : null,
        amendedBy ? h('span', { class: 'pill' }, 'amended by ', ...amendedBy.split(/[\s,]+/).flatMap((id, i) => (i ? [', ', link(id)] : [link(id)]))) : null,
        amends ? h('span', { class: 'pill' }, 'amends ', link(amends)) : null,
        topicPill(this),
        this.getAttribute('ticket') ? ticketRef(this.getAttribute('ticket').trim()) : null,
      ));

      // Options keep the alternatives that were not chosen, for the history.
      const options = this.options;
      if (options.length) {
        const list = h('div', { class: 'options' });
        options[0].before(list);
        for (const opt of options) {
          const chosen = opt.hasAttribute('chosen');
          const desc = [...opt.childNodes];
          opt.replaceChildren(
            h('span', { class: 'mark' }, chosen ? '✓' : ''),
            h('span', {},
              h('span', { class: 'label' },
                h('span', { class: 'value' }, opt.getAttribute('value') || ''),
                opt.getAttribute('label') || '',
                opt.hasAttribute('recommended') ? h('span', { class: 'tag' }, 'recommended') : null,
              ),
              desc.length ? h('span', { class: 'desc' }, ...desc) : null,
            ),
          );
          list.append(opt);
        }
      }
    }

    get options() { return [...this.querySelectorAll(':scope > spec-option, :scope > .options > spec-option')]; }
    get outcome() {
      const o = this.getAttribute('outcome');
      return OUTCOMES.includes(o) ? o : null;
    }
    get active() { return !this.hasAttribute('superseded-by') && !this.outcome; }
    get summary() {
      const q = this.querySelector('.q')?.textContent.trim() || '';
      const chosen = this.options.filter((o) => o.hasAttribute('chosen')).map((o) => o.getAttribute('label') || o.getAttribute('value'));
      const c = this.querySelector('.choice')?.textContent.trim() || chosen.join('; ');
      const note = this.querySelector('.note')?.textContent.trim();
      if (this.outcome) {
        const why = this.querySelector('.why')?.textContent.trim();
        const ticket = this.getAttribute('ticket');
        return `${this.getAttribute('did')}: ${q} → ${this.outcome}${why ? ` (${why})` : ''}${ticket ? ` [ticket ${ticket}]` : ''}`;
      }
      const amended = this.getAttribute('amended-by');
      const ticket = this.getAttribute('ticket');
      return `${this.getAttribute('did')}: ${q} → ${c}${note ? ` (note: ${note})` : ''}${amended ? ` [amended by ${amended}]` : ''}${ticket ? ` [ticket ${ticket}]` : ''}`;
    }
  }

  class SpecPrompt extends HTMLElement {
    connectedCallback() {
      if (this._rendered) return;
      this._rendered = true;
      this._mode = h('span', { class: 'eyebrow' });
      this._text = h('textarea', { class: 'field', spellcheck: false });
      const copy = h('button', { class: 'btn primary', type: 'button' }, 'Copy');
      copy.addEventListener('click', () => this._copy(copy));
      const reset = h('button', { class: 'btn', type: 'button' }, 'Reset answers');
      reset.addEventListener('click', () => {
        if (!confirm('Clear all answers saved in this browser for this spec?')) return;
        try { localStorage.removeItem(STORAGE_KEY); } catch { /* storage unavailable */ }
        location.reload();
      });
      this.append(
        h('div', { class: 'head' }, this._mode, h('span', {}, reset, ' ', copy)),
        this._text,
      );
      update();
    }

    render() {
      const file = this.getAttribute('file') || location.pathname.split('/').pop();
      const status = document.querySelector('spec-header')?.getAttribute('status') || 'draft';
      const questions = [...document.querySelectorAll('spec-question')];

      if (questions.length) {
        const round = Math.max(...questions.map((q) => Number(q.getAttribute('round')) || 1));
        const lines = questions.filter((q) => !q.hidden).map((q) => {
          const { values, labels, note } = q.answer;
          const answer = !values.length ? '(no answer)'
            : values.map((v, i) => (v === 'other' ? v : `${v} — ${labels[i]}`)).join('; ');
          return `${q.qid}: ${answer}${note ? `\n    Note: ${note}` : ''}`;
        });
        this._mode.textContent = `Round ${round} answers`;
        this._text.value = [
          `/html-spec Round ${round} answers for ${file}`,
          '',
          ...lines,
          '',
          'Each note applies together with the chosen option(s). Record these answers in the spec, then add the next round or finalize it.',
        ].join('\n');
        return;
      }

      if (status === 'draft') {
        this._mode.textContent = 'Finalize';
        this._text.value = [
          `/html-spec Finalize ${file}`,
          '',
          'No open questions are left. Translate the spec to English if needed, set the status to decided and update .agents/docs/INDEX.md.',
        ].join('\n');
        return;
      }

      const all = [...document.querySelectorAll('spec-decision')];
      const decisions = all.filter((d) => d.active);
      const undecided = all.filter((d) => d.outcome && !d.hasAttribute('superseded-by'));
      this._mode.textContent = 'Implementation prompt';
      this._text.value = [
        `Implement the spec ${file}.`,
        'Read the whole file first. Follow the decisions and respect Out of scope.',
        '',
        'Decisions:',
        ...decisions.map((d) => `- ${d.summary}`),
        ...(undecided.length ? ['', 'Not decided (do not implement):', ...undecided.map((d) => `- ${d.summary}`)] : []),
        '',
        'When done, set the spec status to implemented in the file and in .agents/docs/INDEX.md.',
      ].join('\n');
    }

    async _copy(button) {
      try {
        await navigator.clipboard.writeText(this._text.value);
      } catch {
        this._text.select();
        document.execCommand('copy');
      }
      const label = button.textContent;
      button.textContent = 'Copied';
      setTimeout(() => { button.textContent = label; }, 1200);
    }
  }

  function applyConditions() {
    const questions = [...document.querySelectorAll('spec-question')];
    const byId = new Map(questions.map((q) => [q.qid, q]));
    // Iterate so chained conditions (Q5 depends on Q3, Q3 on Q1) settle.
    for (let pass = 0; pass < questions.length + 1; pass++) {
      let changed = false;
      for (const q of questions) {
        const cond = parseCondition(q.getAttribute('show-if'));
        if (!cond) continue;
        const parent = byId.get(cond.qid);
        const visible = !!parent && !parent.hidden && parent.answer.values.some((v) => cond.values.includes(v));
        if (q.hidden === visible) { q.hidden = !visible; changed = true; }
      }
      if (!changed) break;
    }
  }

  function update() {
    applyConditions();
    for (const p of document.querySelectorAll('spec-prompt')) {
      if (p._rendered) p.render();
    }
  }

  customElements.define('spec-header', SpecHeader);
  customElements.define('spec-option', SpecOption);
  customElements.define('spec-question', SpecQuestion);
  customElements.define('spec-decision', SpecDecision);
  customElements.define('spec-prompt', SpecPrompt);

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', update);
  else update();
})();
