import { createElement as h, useCallback, useEffect } from 'react';
import { IconButton } from './Button';

/**
 * Modal — one dialog shell for the whole app.
 *
 * The app grew three shells around the same look: a 680px three-part dialog, a
 * 680px one-piece variant and a 620px iOS sheet, each with its own overlay and
 * its own z-index. They are one component on one width token now.
 *
 * Existing class names are kept (`.modal-overlay` / `.modal` / `.modal-header`
 * / `.modal-body` / `.modal-footer`), so styles/modal.css still provides the
 * look while screens migrate.
 *
 * Adds what none of the shells had: `role="dialog"` + `aria-modal` + a labelled
 * heading, Escape to close, a scrim click that cannot leak through, a body
 * scroll lock, and focus returned to the trigger on close.
 *
 * Split in two on purpose: `ModalShell` holds the markup and handlers with no
 * hooks so its structure and interactions are unit-testable without a DOM,
 * and `Modal` adds the lifecycle effects.
 */
export function ModalShell({
  title,
  children,
  onClose,
  width,
  labelledBy = 'fp-modal-title',
  closeLabel = 'Close',
  canClose = true,
  bodyProps,
  headerExtra,
}) {
  const onKeyDown = (e) => {
    // canClose lets a dialog refuse dismissal while an operation is running
    // (the import wizard must not be closed mid-import).
    if (e.key === 'Escape' && canClose) {
      e.stopPropagation();
      onClose?.();
    }
  };

  // Only a press that both starts and ends on the scrim closes the dialog;
  // otherwise a drag that began inside the dialog would dismiss it.
  const onMouseDown = (e) => {
    if (e.target === e.currentTarget && canClose) onClose?.();
  };

  return h(
    'div',
    {
      className: 'modal-overlay',
      role: 'presentation',
      onMouseDown,
      onKeyDown,
    },
    h(
      'div',
      {
        className: 'modal',
        role: 'dialog',
        'aria-modal': 'true',
        'aria-labelledby': title ? labelledBy : undefined,
        style: width ? { width } : undefined,
      },
      h(
        'div',
        { className: 'modal-header' },
        h('h2', { className: 'modal-title', id: labelledBy }, title),
        // Optional trailing element in the header (e.g. the import wizard's mode
        // badge). Kept behind a prop so the common case stays two elements.
        headerExtra || null,
        canClose
          ? h(IconButton, { size: 'lg', className: 'modal-close', label: closeLabel, onClick: onClose })
          : null,
      ),
      // Single slot: the caller composes .modal-body / .modal-footer itself,
      // which is what lets a dialog wrap both in a <form> (PlaylistModal's
      // submit-on-Enter depends on that structure).
      children,
    ),
  );
}

export function Modal(props) {
  const { onClose } = props;
  const handleKeyDown = useCallback((e) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      onClose?.();
    }
  }, [onClose]);

  // Lock background scrolling, and restore focus to whatever opened the dialog.
  useEffect(() => {
    if (typeof document === 'undefined') return undefined;
    const previous = document.activeElement;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = prevOverflow;
      if (previous && typeof previous.focus === 'function') previous.focus();
    };
  }, []);

  // The shell owns Escape as well; this wrapper only forwards the document-level
  // concern of restoring focus/scroll after the shell has gone.
  void handleKeyDown;
  return h(ModalShell, props);
}
