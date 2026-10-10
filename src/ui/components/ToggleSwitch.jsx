import { createElement as h, useId } from 'react';

/**
 * ToggleSwitch — the app's on/off control (tray, login item, EQ, visualizer).
 *
 * The old version put its label in a `title` attribute on a <label> whose only
 * child input had no accessible name, so screen readers announced an unlabelled
 * checkbox. This wires a real label association and keeps the exact class names
 * and inner element order the stylesheet depends on.
 */
const SYMBOL_X = h('svg', { viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 4 },
  h('path', { d: 'M6 6l12 12M18 6L6 18' }));

const SYMBOL_O = h('svg', { viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 4 },
  h('circle', { cx: 12, cy: 12, r: 7 }));

export function ToggleSwitch({ checked, onChange, disabled, label, id }) {
  const autoId = useId();
  const inputId = id || `fp-toggle-${autoId}`;

  return h(
    'label',
    { className: 'fp-toggle', htmlFor: inputId, title: label },
    h('input', {
      id: inputId,
      type: 'checkbox',
      checked,
      disabled,
      'aria-label': label,
      onChange: (e) => onChange?.(e.target.checked),
    }),
    h('span', { className: 'fp-toggle-track', 'aria-hidden': 'true' }),
    h('span', { className: 'fp-toggle-symbol fp-toggle-symbol--x', 'aria-hidden': 'true' }, SYMBOL_X),
    h('span', { className: 'fp-toggle-symbol fp-toggle-symbol--o', 'aria-hidden': 'true' }, SYMBOL_O),
    h('span', { className: 'fp-toggle-thumb', 'aria-hidden': 'true' }),
  );
}
