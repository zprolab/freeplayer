import { describe, it, expect, vi } from 'vitest';

// Same lightweight react harness used by the other hook/component tests.
vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal();
  let idCounter = 0;
  return {
    ...actual,
    useId: () => `test-${++idCounter}`,
  };
});

import { Button, IconButton } from '../src/ui/components/Button';
import { SegmentedControl } from '../src/ui/components/SegmentedControl';
import { ToggleSwitch } from '../src/ui/components/ToggleSwitch';
import { ModalShell } from '../src/ui/components/Modal';
import { TextField, Select } from '../src/ui/components/Field';

// The design system emits React elements; walking them as plain objects is
// enough to assert the class contract and the accessibility attributes without
// pulling in a DOM renderer.
function propsOf(el) {
  return el?.props || {};
}
function childrenOf(el) {
  const c = el?.props?.children;
  return Array.isArray(c) ? c.flat(Infinity).filter(Boolean) : (c ? [c] : []);
}

describe('Button', () => {
  it('emits only design-system class names', () => {
    // The legacy `btn`/`btn-primary` rules are deleted, so emitting those names
    // would put classes in the DOM that resolve to nothing.
    const cls = propsOf(Button({ children: 'Save', variant: 'primary' })).className;
    expect(cls).toContain('fp-btn');
    expect(cls).toContain('fp-btn--primary');
    expect(cls).toContain('fp-btn--md');
    const tokens = cls.split(/\s+/);
    // Exact class match — `fp-btn` contains "btn" as a substring, so a regex
    // would false-positive here.
    expect(tokens).not.toContain('btn');
    expect(tokens).not.toContain('btn-primary');
  });

  it('maps the large size to its token class', () => {
    const cls = propsOf(Button({ children: 'Go', size: 'lg' })).className;
    expect(cls).toContain('fp-btn--lg');
    expect(cls).not.toContain('btn-lg');
  });

  it('defaults to type=button so it cannot submit an enclosing form', () => {
    expect(propsOf(Button({ children: 'x' })).type).toBe('button');
  });

  it('passes disabled through, which nothing used to style', () => {
    const el = Button({ children: 'x', disabled: true });
    expect(propsOf(el).disabled).toBe(true);
  });
});

describe('IconButton', () => {
  it('always carries an accessible name', () => {
    const el = IconButton({ children: 'x', label: 'Close dialog' });
    const props = propsOf(el);
    expect(props['aria-label']).toBe('Close dialog');
    expect(props.className).toContain('fp-icon-btn');
    expect(props.className.split(/\s+/)).not.toContain('btn-icon');
  });
});

describe('SegmentedControl', () => {
  const options = [
    { value: 'a', label: 'A' },
    { value: 'b', label: 'B' },
    { value: 'c', label: 'C' },
  ];

  it('exposes the selection to assistive tech (radiogroup + aria-checked)', () => {
    const el = SegmentedControl({ options, value: 'b', onChange: () => {} });
    expect(propsOf(el).role).toBe('radiogroup');
    const radios = childrenOf(el);
    expect(radios.map((r) => propsOf(r)['aria-checked'])).toEqual([false, true, false]);
    expect(radios.map((r) => propsOf(r).role)).toEqual(['radio', 'radio', 'radio']);
  });

  it('keeps one tab stop for the group via roving tabindex', () => {
    const el = SegmentedControl({ options, value: 'c', onChange: () => {} });
    expect(childrenOf(el).map((r) => propsOf(r).tabIndex)).toEqual([-1, -1, 0]);
  });

  it('moves the selection with arrow keys, wrapping at the ends', () => {
    const onChange = vi.fn();
    const el = SegmentedControl({ options, value: 'c', onChange });
    propsOf(el).onKeyDown({ key: 'ArrowRight', preventDefault: () => {} });
    expect(onChange).toHaveBeenCalledWith('a');
    onChange.mockClear();
    const el2 = SegmentedControl({ options, value: 'a', onChange });
    propsOf(el2).onKeyDown({ key: 'ArrowLeft', preventDefault: () => {} });
    expect(onChange).toHaveBeenCalledWith('c');
  });

  it('still emits the legacy class names', () => {
    const el = SegmentedControl({ options, value: 'a', onChange: () => {} });
    expect(propsOf(el).className).toContain('seg-control');
    expect(propsOf(childrenOf(el)[0]).className).toContain('seg-control-btn--active');
  });

  it('does not navigate while disabled', () => {
    const onChange = vi.fn();
    const el = SegmentedControl({ options, value: 'a', onChange, disabled: true });
    propsOf(el).onKeyDown({ key: 'ArrowRight', preventDefault: () => {} });
    expect(onChange).not.toHaveBeenCalled();
    expect(propsOf(el).className).toContain('seg-control--disabled');
  });
});

describe('ToggleSwitch', () => {
  it('gives the checkbox a real accessible name and label association', () => {
    const el = ToggleSwitch({ checked: false, onChange: () => {}, label: 'Close to Tray' });
    const input = childrenOf(el).find((c) => propsOf(c).type === 'checkbox');
    expect(propsOf(input)['aria-label']).toBe('Close to Tray');
    expect(propsOf(input).id).toBeTruthy();
    expect(propsOf(el).htmlFor).toBe(propsOf(input).id);
  });

  it('keeps the track/symbol/thumb structure the stylesheet targets', () => {
    const el = ToggleSwitch({ checked: true, onChange: () => {}, label: 'x' });
    const classes = childrenOf(el).map((c) => propsOf(c).className);
    expect(classes).toContain('fp-toggle-track');
    expect(classes).toContain('fp-toggle-thumb');
    expect(classes.filter((c) => c?.startsWith('fp-toggle-symbol'))).toHaveLength(2);
  });

  it('reports the toggled value', () => {
    const onChange = vi.fn();
    const el = ToggleSwitch({ checked: false, onChange, label: 'x' });
    const input = childrenOf(el).find((c) => propsOf(c).type === 'checkbox');
    propsOf(input).onChange({ target: { checked: true } });
    expect(onChange).toHaveBeenCalledWith(true);
  });
});

describe('ModalShell', () => {
  it('exposes a dialog role, modality and a labelled heading', () => {
    const overlay = ModalShell({ title: 'Edit Track', onClose: () => {} });
    const dialog = childrenOf(overlay)[0];
    expect(propsOf(dialog).role).toBe('dialog');
    expect(propsOf(dialog)['aria-modal']).toBe('true');
    const header = childrenOf(dialog)[0];
    const heading = childrenOf(header)[0];
    expect(propsOf(heading).id).toBe(propsOf(dialog)['aria-labelledby']);
    expect(propsOf(dialog)['aria-labelledby']).toBeTruthy();
  });

  it('closes on Escape and ignores clicks that did not start on the scrim', () => {
    const onClose = vi.fn();
    const overlay = ModalShell({ title: 'x', onClose });
    propsOf(overlay).onKeyDown({ key: 'Escape', stopPropagation: () => {} });
    expect(onClose).toHaveBeenCalledTimes(1);

    // A click originating inside the dialog must not dismiss it.
    const inside = {};
    propsOf(overlay).onMouseDown({ target: inside, currentTarget: overlay });
    expect(onClose).toHaveBeenCalledTimes(1);
    propsOf(overlay).onMouseDown({ target: overlay, currentTarget: overlay });
    expect(onClose).toHaveBeenCalledTimes(2);
  });

  it('renders the caller-composed content as-is', () => {
    // Single slot: the caller builds .modal-body (and .modal-footer, or a form
    // wrapping both) so the shell does not dictate the inner structure.
    const dialog = childrenOf(ModalShell({ title: 'x', onClose: () => {}, children: 'body' }))[0];
    const classes = childrenOf(dialog).map((c) => propsOf(c).className);
    expect(classes[0]).toBe('modal-header');
    expect(childrenOf(dialog)[1]).toBe('body');
  });

  it('gives the close control an accessible name', () => {
    const dialog = childrenOf(ModalShell({ title: 'x', onClose: () => {} }))[0];
    const header = childrenOf(dialog)[0];
    const close = childrenOf(header)[1];
    // The header renders <IconButton …/>, so assert on its props (the element is
    // created by our own call, which is how the DOM-free harness inspects it).
    expect(propsOf(close).label || propsOf(close)['aria-label']).toBe('Close');
  });
});

describe('form primitives', () => {
  it('TextField keeps the legacy class and can opt into mono', () => {
    expect(propsOf(TextField({})).className).toBe('edit-input');
    expect(propsOf(TextField({ mono: true })).className).toBe('edit-input mono');
    expect(propsOf(TextField({ type: 'number' })).type).toBe('number');
  });

  it('Select keeps the legacy class', () => {
    expect(propsOf(Select({ children: 'x' })).className).toBe('plugin-select');
  });
});
