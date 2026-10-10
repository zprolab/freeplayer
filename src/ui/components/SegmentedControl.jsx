import { createElement as h } from 'react';

/**
 * SegmentedControl — mutually exclusive options (visualizer mode, import mode,
 * analysis quality, UI mode).
 *
 * The old version conveyed the selection only through a CSS class, so assistive
 * tech saw a row of identical buttons. This exposes it as a radiogroup with
 * roving tabindex and arrow-key navigation, while emitting the SAME class names
 * so the existing stylesheet keeps applying unchanged.
 */
export function SegmentedControl({ options = [], value, onChange, disabled, ariaLabel }) {
  const move = (delta) => {
    if (disabled || !options.length) return;
    const current = options.findIndex((o) => o.value === value);
    const next = (current + delta + options.length) % options.length;
    onChange?.(options[next].value);
  };

  const onKeyDown = (e) => {
    if (e.key === 'ArrowRight' || e.key === 'ArrowDown') { e.preventDefault(); move(1); }
    else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
  };

  return h(
    'div',
    {
      className: `seg-control${disabled ? ' seg-control--disabled' : ''}`,
      role: 'radiogroup',
      'aria-label': ariaLabel,
      onKeyDown,
    },
    options.map((opt) => {
      const active = opt.value === value;
      return h(
        'button',
        {
          key: opt.value,
          type: 'button',
          role: 'radio',
          'aria-checked': active,
          // Roving tabindex: one tab stop for the whole group.
          tabIndex: active ? 0 : -1,
          className: `seg-control-btn${active ? ' seg-control-btn--active' : ''}`,
          disabled,
          title: opt.title,
          onClick: () => onChange?.(opt.value),
        },
        opt.label,
      );
    }),
  );
}
