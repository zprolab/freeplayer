import { createElement as h } from 'react';

/**
 * Button — the single control surface for actions.
 *
 * Replaces the eight hand-rolled `className="btn btn-*"` variations and the
 * `.btn-lg` / `.btn-icon` copies. Two things it fixes beyond consolidation:
 *   - a real disabled state (previously nothing styled `:disabled`, so disabled
 *     buttons looked enabled)
 *   - one focus treatment (`:focus-visible`), which the app had almost nowhere
 *
 * `variant`/`size` map to the class names the existing stylesheets already use,
 * so this is a drop-in replacement during the per-screen migration.
 *
 * Written with createElement rather than JSX on purpose: the design-system
 * primitives are the one place worth unit-testing at the element level, and the
 * test environment has no JSX transform or DOM. Keeping these files JSX-free
 * lets their structure be verified without adding jsdom.
 */
export function Button({
  children,
  variant = 'primary',
  size = 'md',
  type = 'button',
  className = '',
  ...rest
}) {
  // Only design-system class names are emitted now: the styles/buttons.css rules
  // they used to mirror are deleted, so carrying `btn btn-primary` would leave
  // class names in the DOM with no definition anywhere.
  const classes = ['fp-btn', `fp-btn--${variant}`, `fp-btn--${size}`, className]
    .filter(Boolean).join(' ');

  return h('button', { type, className: classes, ...rest }, children);
}

/**
 * IconButton — square, icon-only actions (close, transport, row actions).
 * The "close" affordance previously existed at 24, 28 and 32px depending on
 * which sheet defined it.
 */
export function IconButton({ children, size = 'md', type = 'button', className = '', label, ...rest }) {
  const classes = ['fp-icon-btn', `fp-icon-btn--${size}`, className]
    .filter(Boolean).join(' ');

  return h('button', {
    type,
    className: classes,
    'aria-label': label,
    title: label,
    ...rest,
  }, children);
}
