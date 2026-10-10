import { createElement as h } from 'react';

/**
 * TextField / Select — form primitives.
 *
 * Thin wrappers over the class names the app already uses (`.edit-input`,
 * `.search-input`, `.plugin-select`), so adopting them changes no pixels while
 * the design system takes ownership of the control radius, text colour and
 * focus ring. Screens previously repeated `className="edit-input"` by hand in
 * half a dozen places with slightly different attributes each time.
 */
export function TextField({ className = 'edit-input', mono = false, ...rest }) {
  return h('input', {
    type: 'text',
    className: `${className}${mono ? ' mono' : ''}`.trim(),
    ...rest,
  });
}

export function Select({ children, className = 'plugin-select', ...rest }) {
  return h('select', { className, ...rest }, children);
}
