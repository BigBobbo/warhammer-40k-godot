// Tiny DOM helpers for the army builder — no framework, just h().

/**
 * h('div.cls#id', {onclick, title, ...attrs}, ...children)
 * Children: strings, numbers, Nodes, arrays, or null/undefined (skipped).
 */
export function h(tag, props = {}, ...children) {
  const [name, ...classesAndId] = tag.split(/(?=[.#])/);
  const el = document.createElement(name || 'div');
  for (const part of classesAndId) {
    if (part.startsWith('.')) el.classList.add(part.slice(1));
    else if (part.startsWith('#')) el.id = part.slice(1);
  }
  if (props) {
    for (const [k, v] of Object.entries(props)) {
      if (v === null || v === undefined || v === false) continue;
      if (k.startsWith('on') && typeof v === 'function') {
        el.addEventListener(k.slice(2).toLowerCase(), v);
      } else if (k === 'dataset') {
        Object.assign(el.dataset, v);
      } else if (k === 'value') {
        el.value = v;
      } else if (k === 'checked' || k === 'disabled' || k === 'selected' || k === 'open') {
        el[k] = !!v;
      } else {
        el.setAttribute(k, v === true ? '' : String(v));
      }
    }
  }
  append(el, children);
  return el;
}

function append(el, child) {
  if (child === null || child === undefined || child === false) return;
  if (Array.isArray(child)) {
    for (const c of child) append(el, c);
  } else if (child instanceof Node) {
    el.appendChild(child);
  } else {
    el.appendChild(document.createTextNode(String(child)));
  }
}

export function clear(el) {
  while (el.firstChild) el.removeChild(el.firstChild);
  return el;
}

/** <select> from [{value, label, disabled?}], with change handler. */
export function select(options, current, onChange, props = {}) {
  return h('select', { ...props, onchange: (e) => onChange(e.target.value) },
    options.map(o => h('option', {
      value: o.value,
      selected: String(o.value) === String(current),
      disabled: o.disabled,
    }, o.label)));
}

/** [-] count [+] stepper. */
export function stepper(count, min, max, onSet, props = {}) {
  return h('span.stepper', props,
    h('button.step-btn', { onclick: () => onSet(count - 1), disabled: count <= min }, '−'),
    h('span.step-count', {}, String(count)),
    h('button.step-btn', { onclick: () => onSet(count + 1), disabled: count >= max }, '+'),
  );
}

/** Download a text file client-side. */
export function downloadFile(filename, text, mime = 'application/json') {
  const blob = new Blob([text], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

/** Modal scaffolding: showModal(title, bodyNode, footerNodes) -> closes on X/backdrop. */
export function showModal(title, body, footer = []) {
  closeModal();
  const backdrop = h('div.modal-backdrop', {
    onclick: (e) => { if (e.target === backdrop) closeModal(); },
  },
    h('div.modal', {},
      h('div.modal-header', {},
        h('h2', {}, title),
        h('button.modal-close', { onclick: closeModal, title: 'Close' }, '×')),
      h('div.modal-body', {}, body),
      footer.length ? h('div.modal-footer', {}, footer) : null,
    ));
  document.body.appendChild(backdrop);
  return backdrop;
}

export function closeModal() {
  document.querySelectorAll('.modal-backdrop').forEach(el => el.remove());
}
