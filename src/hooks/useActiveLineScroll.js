import { useEffect, useRef } from 'react';

/**
 * Smoothly scrolls the active lyrics line into view whenever it changes.
 * `selector` must match the active line's class inside `listRef`.
 */
export function useActiveLineScroll(listRef, activeIndex, selector, enabled = true) {
  const prevActiveRef = useRef(-1);

  useEffect(() => {
    if (!enabled) return;
    if (activeIndex !== prevActiveRef.current && listRef.current) {
      const el = listRef.current.querySelector(selector);
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
      prevActiveRef.current = activeIndex;
    }
  }, [activeIndex, enabled, listRef, selector]);
}
